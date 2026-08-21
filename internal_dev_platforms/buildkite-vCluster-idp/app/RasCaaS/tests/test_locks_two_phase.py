"""Two-phase lock smoke tests (in-memory fake Redis — no cluster / starlette needed)."""

from __future__ import annotations

import asyncio
import logging
import sys
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

# locks.py → logging_config → starlette; stub logger for bare python3.
_fake_log = types.ModuleType("app.logging_config")
_fake_log.get_logger = lambda name: logging.getLogger(name)  # type: ignore[attr-defined]
sys.modules["app.logging_config"] = _fake_log

from app.locks import DeploymentLockStore, inflight_key, live_key  # noqa: E402


class _FakeRedis:
    def __init__(self) -> None:
        self.kv: dict[str, str] = {}

    async def get(self, key: str):
        return self.kv.get(key)

    async def set(self, key: str, value: str, nx: bool = False, ex: int | None = None):
        if nx and key in self.kv:
            return False
        self.kv[key] = value
        return True

    async def delete(self, *keys: str) -> int:
        n = 0
        for k in keys:
            if k in self.kv:
                del self.kv[k]
                n += 1
        return n

    async def eval(self, script: str, numkeys: int, *args):
        key = args[0]
        if "expire" in script.lower() or "EXPIRE" in script:
            token = args[1]
            if self.kv.get(key) == token:
                return 1
            return 0
        token = args[1]
        if self.kv.get(key) == token:
            del self.kv[key]
            return 1
        return 0

    async def aclose(self) -> None:
        return None


async def _run() -> None:
    r = _FakeRedis()
    store = DeploymentLockStore(r, live_ttl_s=100, inflight_ttl_s=10, enabled=True)
    name = "tmp-ai-workers-main"

    a = await store.try_acquire_inflight(name, "dep-a")
    assert a.acquired and a.kind == "inflight"
    assert r.kv[inflight_key(name)] == "dep-a"
    assert live_key(name) not in r.kv

    b = await store.try_acquire_inflight(name, "dep-b")
    assert not b.acquired and b.kind == "inflight" and b.holder == "dep-a"

    await store.release_inflight(name, "dep-a")
    assert inflight_key(name) not in r.kv

    c = await store.try_acquire_inflight(name, "dep-c")
    assert c.acquired
    ready = await store.create_from_ready(name, "dep-c")
    assert ready.acquired and ready.kind == "live"
    assert inflight_key(name) not in r.kv
    assert r.kv[live_key(name)] == "dep-c"

    # Fail must not clear live held by another token
    d = await store.try_acquire_inflight(name, "dep-d")
    assert not d.acquired and d.kind == "live" and d.holder == "dep-c"
    await store.release_inflight(name, "dep-d")
    assert r.kv[live_key(name)] == "dep-c"

    await store.release_live(name, "dep-c")
    assert live_key(name) not in r.kv

    # Force clears both then takes inflight
    await store.try_acquire_inflight(name, "x")
    await store.create_from_ready(name, "x")
    f = await store.force_acquire_inflight(name, "y")
    assert f.acquired
    assert r.kv[inflight_key(name)] == "y"
    assert live_key(name) not in r.kv

    print("locks two-phase: ok")


if __name__ == "__main__":
    asyncio.run(_run())
