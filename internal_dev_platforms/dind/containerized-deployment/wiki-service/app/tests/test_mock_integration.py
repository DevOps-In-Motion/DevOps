"""
Additional API tests against PostgreSQL (validation, edge cases).
"""
import os
import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
import sys
from pathlib import Path
import asyncpg

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))

os.environ.setdefault(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/wiki",
)

from app.main import app

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
    """Inject test pool into app so endpoints use test DB."""
    import app.main as main_module
    main_module.db.pool = pg_pool
    async with pg_pool.acquire() as conn:
        await conn.execute("TRUNCATE posts, users RESTART IDENTITY CASCADE")
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


pytestmark = pytest.mark.asyncio


async def test_get_user_not_found(client):
    response = await client.get("/users/999")
    assert response.status_code == 404
    assert response.json()["detail"] == "User not found"


async def test_get_post_not_found(client):
    response = await client.get("/posts/999")
    assert response.status_code == 404
    assert response.json()["detail"] == "Post not found"


async def test_create_user_validation(client):
    response = await client.post("/users", json={})
    assert response.status_code == 422


async def test_create_user_with_extra_field(client):
    response = await client.post(
        "/users",
        json={"name": "Alice", "extra": "ignored"},
    )
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Alice"
    assert "id" in data


async def test_create_post_validation_missing_user_id(client):
    response = await client.post("/posts", json={"content": "Hello"})
    assert response.status_code == 422


async def test_create_post_validation_missing_content(client):
    create_user = await client.post("/users", json={"name": "Author"})
    user_id = create_user.json()["id"]
    response = await client.post("/posts", json={"user_id": user_id})
    assert response.status_code == 422


async def test_create_post_user_not_found(client):
    response = await client.post(
        "/posts",
        json={"user_id": 99999, "content": "Orphan"},
    )
    assert response.status_code == 404
    assert response.json()["detail"] == "User not found"


async def test_get_user_success(client):
    create_response = await client.post("/users", json={"name": "Bob"})
    user_id = create_response.json()["id"]
    response = await client.get(f"/users/{user_id}")
    assert response.status_code == 200
    data = response.json()
    assert data["id"] == user_id
    assert data["name"] == "Bob"
    assert "created_time" in data


async def test_get_post_success(client):
    create_user = await client.post("/users", json={"name": "Author"})
    user_id = create_user.json()["id"]
    create_post = await client.post(
        "/posts",
        json={"user_id": user_id, "content": "Post content"},
    )
    post_id = create_post.json()["post_id"]
    response = await client.get(f"/posts/{post_id}")
    assert response.status_code == 200
    data = response.json()
    assert data["post_id"] == post_id
    assert data["content"] == "Post content"
    assert data["user_id"] == user_id
    assert "created_time" in data


async def test_create_user_success(client):
    response = await client.post("/users", json={"name": "New User"})
    assert response.status_code == 201
    data = response.json()
    assert "id" in data
    assert data["name"] == "New User"
    assert "created_time" in data


async def test_create_post_success(client):
    create_user = await client.post("/users", json={"name": "Poster"})
    user_id = create_user.json()["id"]
    response = await client.post(
        "/posts",
        json={"user_id": user_id, "content": "New post"},
    )
    assert response.status_code == 201
    data = response.json()
    assert "post_id" in data
    assert data["content"] == "New post"
    assert data["user_id"] == user_id
    assert "created_time" in data


async def test_metrics_returns_text(client):
    response = await client.get("/metrics")
    assert response.status_code == 200
    assert len(response.text) > 0
