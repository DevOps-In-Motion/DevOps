"""
PostgreSQL integration tests using the Database class (same pattern as working example).
"""
import os
import pytest
import pytest_asyncio
import asyncpg
import sys
from pathlib import Path

# Add parent directory to path to import app modules
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))

os.environ.setdefault(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/wiki",
)

from app.database import Database

# Mark all tests in this file as async
pytestmark = pytest.mark.asyncio


@pytest_asyncio.fixture
async def db():
    """Database fixture that handles connection and cleanup."""
    database = Database()
    await database.connect()
    await database.create_tables()
    yield database
    # Cleanup: drop all test data
    if database.pool is not None:
        async with database.pool.acquire() as conn:
            await conn.execute("TRUNCATE posts, users RESTART IDENTITY CASCADE")
        await database.disconnect()


async def test_database_connection(db):
    """Test database pool connection."""
    assert db.pool is not None
    assert db.pool.get_size() > 0


async def test_create_tables(db):
    """Test table creation."""
    async with db.pool.acquire() as conn:
        users_ok = await conn.fetchval(
            """
            SELECT EXISTS (
                SELECT FROM information_schema.tables
                WHERE table_name = 'users'
            )
            """
        )
        posts_ok = await conn.fetchval(
            """
            SELECT EXISTS (
                SELECT FROM information_schema.tables
                WHERE table_name = 'posts'
            )
            """
        )
    assert users_ok is True
    assert posts_ok is True


async def test_create_user(db):
    """Test creating a new user."""
    user_id = await db.create_user("Test User")
    assert user_id > 0

    user = await db.get_user(user_id)
    assert user is not None
    assert user["name"] == "Test User"
    assert "created_time" in user


async def test_get_user(db):
    """Test retrieving a user."""
    user_id = await db.create_user("Find Me")

    user = await db.get_user(user_id)
    assert user is not None
    assert user["id"] == user_id
    assert user["name"] == "Find Me"


async def test_get_user_not_found(db):
    """Test retrieving a user that doesn't exist."""
    user = await db.get_user(99999)
    assert user is None


async def test_get_all_users(db):
    """Test retrieving all users."""
    await db.create_user("User 1")
    await db.create_user("User 2")
    await db.create_user("User 3")

    users = await db.get_all_users()
    assert len(users) >= 3

    for user in users:
        assert "id" in user
        assert "name" in user
        assert "created_time" in user


async def test_update_user(db):
    """Test updating a user."""
    user_id = await db.create_user("Original")

    updated = await db.update_user(user_id, "Updated")
    assert updated is True

    user = await db.get_user(user_id)
    assert user["name"] == "Updated"


async def test_update_user_not_found(db):
    """Test updating a user that doesn't exist."""
    updated = await db.update_user(99999, "Name")
    assert updated is False


async def test_delete_user(db):
    """Test deleting a user."""
    user_id = await db.create_user("Delete Me")

    user = await db.get_user(user_id)
    assert user is not None

    deleted = await db.delete_user(user_id)
    assert deleted is True

    user = await db.get_user(user_id)
    assert user is None


async def test_delete_user_not_found(db):
    """Test deleting a user that doesn't exist."""
    deleted = await db.delete_user(99999)
    assert deleted is False


async def test_create_post(db):
    """Test creating a new post."""
    user_id = await db.create_user("Author")
    post_id = await db.create_post(user_id, "First post")
    assert post_id > 0

    post = await db.get_post(post_id)
    assert post is not None
    assert post["content"] == "First post"
    assert post["user_id"] == user_id
    assert "created_time" in post


async def test_get_post(db):
    """Test retrieving a post."""
    user_id = await db.create_user("Author")
    post_id = await db.create_post(user_id, "Find this post")

    post = await db.get_post(post_id)
    assert post is not None
    assert post["id"] == post_id
    assert post["content"] == "Find this post"
    assert post["user_id"] == user_id


async def test_get_post_not_found(db):
    """Test retrieving a post that doesn't exist."""
    post = await db.get_post(99999)
    assert post is None


async def test_get_all_posts(db):
    """Test retrieving all posts."""
    user_id = await db.create_user("Author")
    await db.create_post(user_id, "Post 1")
    await db.create_post(user_id, "Post 2")
    await db.create_post(user_id, "Post 3")

    posts = await db.get_all_posts()
    assert len(posts) >= 3

    for post in posts:
        assert "id" in post
        assert "content" in post
        assert "user_id" in post
        assert "created_time" in post


async def test_update_post(db):
    """Test updating a post."""
    user_id = await db.create_user("Author")
    post_id = await db.create_post(user_id, "Original content")

    updated = await db.update_post(post_id, "Updated content")
    assert updated is True

    post = await db.get_post(post_id)
    assert post["content"] == "Updated content"


async def test_update_post_not_found(db):
    """Test updating a post that doesn't exist."""
    updated = await db.update_post(99999, "Content")
    assert updated is False


async def test_delete_post(db):
    """Test deleting a post."""
    user_id = await db.create_user("Author")
    post_id = await db.create_post(user_id, "Delete me")

    post = await db.get_post(post_id)
    assert post is not None

    deleted = await db.delete_post(post_id)
    assert deleted is True

    post = await db.get_post(post_id)
    assert post is None


async def test_delete_post_not_found(db):
    """Test deleting a post that doesn't exist."""
    deleted = await db.delete_post(99999)
    assert deleted is False


async def test_create_post_invalid_user_raises(db):
    """Creating a post for non-existent user raises ForeignKeyViolationError."""
    with pytest.raises(asyncpg.ForeignKeyViolationError):
        await db.create_post(99999, "Orphan post")


async def test_user_can_have_multiple_posts(db):
    """One user, multiple posts."""
    user_id = await db.create_user("Author")
    await db.create_post(user_id, "Post 0")
    await db.create_post(user_id, "Post 1")
    await db.create_post(user_id, "Post 2")

    posts = await db.get_all_posts()
    user_posts = [p for p in posts if p["user_id"] == user_id]
    assert len(user_posts) == 3


async def test_crud_operations(db):
    """Test full CRUD cycle for user and post."""
    # Create user
    user_id = await db.create_user("CRUD User")
    assert user_id > 0

    user = await db.get_user(user_id)
    assert user["name"] == "CRUD User"

    # Create post
    post_id = await db.create_post(user_id, "CRUD post content")
    assert post_id > 0

    post = await db.get_post(post_id)
    assert post["content"] == "CRUD post content"
    assert post["user_id"] == user_id

    # Update post
    updated = await db.update_post(post_id, "Updated content")
    assert updated is True
    post = await db.get_post(post_id)
    assert post["content"] == "Updated content"

    # Delete post
    deleted = await db.delete_post(post_id)
    assert deleted is True
    assert await db.get_post(post_id) is None

    # Delete user
    deleted = await db.delete_user(user_id)
    assert deleted is True
    assert await db.get_user(user_id) is None
