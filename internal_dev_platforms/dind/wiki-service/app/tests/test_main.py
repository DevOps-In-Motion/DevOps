"""
API tests against PostgreSQL.
Uses asyncpg to prepare the DB; app must use the same DATABASE_URL (PG only).
"""
import os
import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
import sys
from pathlib import Path
import asyncpg

# Project root
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))

# Set test DB before app imports (app uses DATABASE_URL for PG)
os.environ.setdefault(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/wiki",
)

from app.main import app

# DDL matching app (PG only)
CREATE_USERS = """
    CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        name VARCHAR NOT NULL,
        created_time TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
"""
CREATE_POSTS = """
    CREATE TABLE IF NOT EXISTS posts (
        id SERIAL PRIMARY KEY,
        content TEXT NOT NULL,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        created_time TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
"""


@pytest_asyncio.fixture
async def pg_pool():
    """Create PG pool and ensure users/posts tables exist."""
    url = os.environ["DATABASE_URL"]
    try:
        pool = await asyncpg.create_pool(url, min_size=1, max_size=5)
    except Exception as e:
        pytest.skip(f"PostgreSQL not available: {e}")
    async with pool.acquire() as conn:
        await conn.execute(CREATE_USERS)
        await conn.execute(CREATE_POSTS)
    yield pool
    await pool.close()


@pytest_asyncio.fixture
async def client(pg_pool):
    """Async HTTP client; DB tables already created by pg_pool. Inject test pool into app."""
    import app.main as main_module
    main_module.db.pool = pg_pool
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


@pytest_asyncio.fixture
async def client_with_clean_db(pg_pool):
    """Client with empty users/posts tables before each test. Inject test pool into app."""
    import app.main as main_module
    main_module.db.pool = pg_pool
    async with pg_pool.acquire() as conn:
        await conn.execute("TRUNCATE posts, users RESTART IDENTITY CASCADE")
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


@pytest.mark.asyncio
async def test_health(client):
    response = await client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "service" in data


@pytest.mark.asyncio
async def test_root(client):
    response = await client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["message"] == "User and Post API"
    assert "endpoints" in data


@pytest.mark.asyncio
async def test_create_user(client_with_clean_db):
    response = await client_with_clean_db.post("/users", json={"name": "Test User"})
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Test User"
    assert data["id"] is not None
    assert "created_time" in data


@pytest.mark.asyncio
async def test_get_user(client_with_clean_db):
    create_response = await client_with_clean_db.post("/users", json={"name": "Find Me"})
    user_id = create_response.json()["id"]
    response = await client_with_clean_db.get(f"/users/{user_id}")
    assert response.status_code == 200
    data = response.json()
    assert data["id"] == user_id
    assert data["name"] == "Find Me"
    assert "created_time" in data


@pytest.mark.asyncio
async def test_get_user_not_found(client_with_clean_db):
    response = await client_with_clean_db.get("/users/99999")
    assert response.status_code == 404
    assert response.json()["detail"] == "User not found"


@pytest.mark.asyncio
async def test_create_post(client_with_clean_db):
    create_user = await client_with_clean_db.post("/users", json={"name": "Post Author"})
    user_id = create_user.json()["id"]
    response = await client_with_clean_db.post(
        "/posts",
        json={"user_id": user_id, "content": "Hello world"},
    )
    assert response.status_code == 201
    data = response.json()
    assert data["content"] == "Hello world"
    assert data["user_id"] == user_id
    assert data["post_id"] is not None
    assert "created_time" in data


@pytest.mark.asyncio
async def test_create_post_user_not_found(client_with_clean_db):
    response = await client_with_clean_db.post(
        "/posts",
        json={"user_id": 99999, "content": "Orphan post"},
    )
    assert response.status_code == 404
    assert response.json()["detail"] == "User not found"


@pytest.mark.asyncio
async def test_get_post(client_with_clean_db):
    create_user = await client_with_clean_db.post("/users", json={"name": "Author"})
    user_id = create_user.json()["id"]
    create_post = await client_with_clean_db.post(
        "/posts",
        json={"user_id": user_id, "content": "My post content"},
    )
    post_id = create_post.json()["post_id"]
    response = await client_with_clean_db.get(f"/posts/{post_id}")
    assert response.status_code == 200
    data = response.json()
    assert data["post_id"] == post_id
    assert data["content"] == "My post content"
    assert data["user_id"] == user_id
    assert "created_time" in data


@pytest.mark.asyncio
async def test_get_post_not_found(client_with_clean_db):
    response = await client_with_clean_db.get("/posts/99999")
    assert response.status_code == 404
    assert response.json()["detail"] == "Post not found"


@pytest.mark.asyncio
async def test_metrics(client):
    response = await client.get("/metrics")
    assert response.status_code == 200
    assert "text/plain" in response.headers.get("content-type", "")
