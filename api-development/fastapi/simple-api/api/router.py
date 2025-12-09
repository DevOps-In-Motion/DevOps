from fastapi import APIRouter
from fastapi import (Response,
                     HTTPException)
from schemas.item import ItemCreate
from api.v1.endpoints import users, items, auth

router = APIRouter()

# Include all endpoint routers
api_router.include_router(
    auth.router,
    prefix="/auth",
    tags=["Authentication"]
)

api_router.include_router(
    users.router,
    prefix="/users",
    tags=["Users"]
)

api_router.include_router(
    items.router,
    prefix="/items",
    tags=["Items"]
)

@router.get("/health")
async def health_check():
    return Response(status_code=200, content="OK")

@router.get("/items/{item_id}")
async def read_item(item_id: int):
  if item_id <0:
    raise HTTPException(status_code=400, detail="Item ID must be positive")
  if type(item_id) != int:
    raise HTTPException(status_code=400, detail="Item ID must be an integer")
  return {"item_id": item_id}

@router.post("/items")
async def create_item(item: ItemCreate):
  return {"item": item}

@router.post("/users/", response_model=User)
async def create_user(user: UserCreate):
  return {"user": user}

@router.get("/users/{user_id}", response_model=User)
async def read_user(user_id: int):
  return {"user_id": user_id}

@router.put("/users/{user_id}", response_model=User)
async def update_user(user_id: int, user: UserUpdate):
  return {"user_id": user_id, "user": user}

@router.delete("/users/{user_id}", response_model=User)
async def delete_user(user_id: int):
  return {"user_id": user_id}