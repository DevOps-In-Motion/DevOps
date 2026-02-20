# Allow running as python main.py from this directory (app/) or from wiki-service/
import sys
from pathlib import Path
if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from fastapi import FastAPI, HTTPException, Response
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST, REGISTRY
from app.database import Database
from app.schemas import UserCreate, UserResponse, PostCreate, PostResponse
from app.metrics import users_created_total, posts_created_total

app = FastAPI(title="User and Post API",
              version="0.1.0")

db = Database()


@app.on_event("startup")
async def startup():
    """Initialize database on startup; retry so we wait for Postgres (e.g. in k8s)."""
    import asyncio
    for attempt in range(30):
        try:
            await db.connect()
            await db.create_tables()
            return
        except Exception as e:
            if attempt == 3:
                raise
            await asyncio.sleep(1)


@app.on_event("shutdown")
async def shutdown():
    """Close database connection on shutdown"""
    await db.disconnect()


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy", "service": "User and Post API"}


@app.get("/users/{user_id}", response_model=UserResponse)
async def get_user(user_id: int):
    """Get a specific user by ID"""
    user = await db.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return UserResponse(
        id=user["id"],
        name=user["name"],
        created_time=user["created_time"],
    )


@app.post("/users", response_model=UserResponse, status_code=201)
async def create_user(user: UserCreate):
    """Create a new user"""
    user_id = await db.create_user(user.name)
    users_created_total.inc()  # count before get_user so we don't miss on later failure
    created = await db.get_user(user_id)
    return UserResponse(
        id=created["id"],
        name=created["name"],
        created_time=created["created_time"],
    )


@app.get("/posts/{post_id}", response_model=PostResponse)
async def get_post(post_id: int):
    """Get a specific post by ID"""
    post = await db.get_post(post_id)
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")
    return PostResponse(
        post_id=post["id"],
        content=post["content"],
        user_id=post["user_id"],
        created_time=post["created_time"],
    )


@app.post("/posts", response_model=PostResponse, status_code=201)
async def create_post(post: PostCreate):
    """Create a new post under a given user"""
    user = await db.get_user(post.user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    post_id = await db.create_post(post.user_id, post.content)
    posts_created_total.inc()  # count before get_post so we don't miss on later failure
    created = await db.get_post(post_id)
    return PostResponse(
        post_id=created["id"],
        content=created["content"],
        user_id=created["user_id"],
        created_time=created["created_time"],
    )


@app.get("/")
async def root():
    """Root endpoint with API information."""
    return {
        "message": "User and Post API",
        "endpoints": {
            "status": "healthy",
            "POST /users": "Create a new user",
            "POST /posts": "Create a new post",
            "GET /users/{id}": "Get user by ID",
            "GET /posts/{id}": "Get post by ID",
            "GET /metrics": "Prometheus metrics"
        }
    }


@app.get("/metrics")
async def metrics():
    """
    Prometheus metrics endpoint. Uses default REGISTRY so users_created_total and posts_created_total are included.
    """
    return Response(content=generate_latest(REGISTRY), media_type=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    import os
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=int(os.environ.get("PORT", "8000")),
        reload=True,
    )
