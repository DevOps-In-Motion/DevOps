import os
import asyncpg
from typing import List, Optional, Dict


class Database:
    def __init__(self):
        self.pool: Optional[asyncpg.Pool] = None
        self.db_url = os.getenv(
            "DATABASE_URL",
            "postgresql://postgres:postgres@localhost:5432/wiki"
        )

    async def connect(self):
        """Create connection pool"""
        self.pool = await asyncpg.create_pool(self.db_url, min_size=1, max_size=10)

    async def disconnect(self):
        """Close connection pool"""
        if self.pool:
            await self.pool.close()

    async def create_tables(self):
        """Create tables for User and Post models if they don't exist"""
        async with self.pool.acquire() as conn:
            # Create users table
            await conn.execute("""
                CREATE TABLE IF NOT EXISTS users (
                    id SERIAL PRIMARY KEY,
                    name VARCHAR NOT NULL,
                    created_time TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
            """)
            # Create posts table
            await conn.execute("""
                CREATE TABLE IF NOT EXISTS posts (
                    id SERIAL PRIMARY KEY,
                    content TEXT NOT NULL,
                    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    created_time TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
            """)

    # --- Pool-based methods (for tests / direct PG use) ---

    async def create_user(self, name: str) -> int:
        """Create a user, return new user id."""
        async with self.pool.acquire() as conn:
            row = await conn.fetchrow(
                "INSERT INTO users (name) VALUES ($1) RETURNING id",
                name,
            )
            return row["id"]

    async def get_user(self, user_id: int) -> Optional[Dict]:
        """Get user by id, return dict or None."""
        async with self.pool.acquire() as conn:
            row = await conn.fetchrow(
                "SELECT id, name, created_time FROM users WHERE id = $1",
                user_id,
            )
            return dict(row) if row else None

    async def get_all_users(self) -> List[Dict]:
        """Get all users."""
        async with self.pool.acquire() as conn:
            rows = await conn.fetch(
                "SELECT id, name, created_time FROM users ORDER BY id"
            )
            return [dict(r) for r in rows]

    async def update_user(self, user_id: int, name: str) -> bool:
        """Update user name. Returns True if a row was updated."""
        async with self.pool.acquire() as conn:
            result = await conn.execute(
                "UPDATE users SET name = $1 WHERE id = $2",
                name,
                user_id,
            )
            return result == "UPDATE 1"

    async def delete_user(self, user_id: int) -> bool:
        """Delete user. Returns True if a row was deleted."""
        async with self.pool.acquire() as conn:
            result = await conn.execute("DELETE FROM users WHERE id = $1", user_id)
            return result == "DELETE 1"

    async def create_post(self, user_id: int, content: str) -> int:
        """Create a post, return new post id."""
        async with self.pool.acquire() as conn:
            row = await conn.fetchrow(
                "INSERT INTO posts (user_id, content) VALUES ($1, $2) RETURNING id",
                user_id,
                content,
            )
            return row["id"]

    async def get_post(self, post_id: int) -> Optional[Dict]:
        """Get post by id, return dict or None."""
        async with self.pool.acquire() as conn:
            row = await conn.fetchrow(
                "SELECT id, content, user_id, created_time FROM posts WHERE id = $1",
                post_id,
            )
            return dict(row) if row else None

    async def get_all_posts(self) -> List[Dict]:
        """Get all posts."""
        async with self.pool.acquire() as conn:
            rows = await conn.fetch(
                "SELECT id, content, user_id, created_time FROM posts ORDER BY id"
            )
            return [dict(r) for r in rows]

    async def update_post(self, post_id: int, content: str) -> bool:
        """Update post content. Returns True if a row was updated."""
        async with self.pool.acquire() as conn:
            result = await conn.execute(
                "UPDATE posts SET content = $1 WHERE id = $2",
                content,
                post_id,
            )
            return result == "UPDATE 1"

    async def delete_post(self, post_id: int) -> bool:
        """Delete post. Returns True if a row was deleted."""
        async with self.pool.acquire() as conn:
            result = await conn.execute("DELETE FROM posts WHERE id = $1", post_id)
            return result == "DELETE 1"


# SQLAlchemy Base for ORM models (e.g. models.py); app uses Database (PG) for CRUD.
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass
