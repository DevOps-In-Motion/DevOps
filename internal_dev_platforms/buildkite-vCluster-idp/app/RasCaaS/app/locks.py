"""Two-phase Redis locks for RaSCaaS UAT environments.

Keys (token = ``deployment_id``):
  * ``rascaas:inflight:<tmp-name>`` — short TTL while build/create/helm runs
  * ``rascaas:lock:<tmp-name>``     — 8d live hold only after phase=ready

Order of operations (SQLite stays the attempt history):
  1. Deploy start → acquire **inflight** (blocked if live or another inflight).
  2. SQLite create + supersede priors (failed rows kept for Failed tab).
  3. Dispatch GHA. Dispatch failure → phase=failed + release **inflight**.
  4. Runner phase=failed → phase=failed + release **inflight** (never touch live).
  5. Runner phase=ready → drop inflight, set/refresh **live** 8d.
  6. Teardown confirmed → release **live**.
  7. Force → clear both keys, then acquire inflight.
  8. Heal: live key held by a non-ready row (legacy acquire-at-start) → clear live.
  9. Orphan: SQLite ready + no host vCluster → mark deleted + release live.
 10. Superseded/deleted rows ignore lock side-effects (zombie GHA).

When Redis is unset the store is a no-op; SQLite inflight checks remain.
"""

from __future__ import annotations

from dataclasses import dataclass

from app.logging_config import get_logger

log = get_logger("rascaas.locks")

LIVE_KEY_PREFIX = "rascaas:lock:"
INFLIGHT_KEY_PREFIX = "rascaas:inflight:"

# Compare-and-delete: only the holder may unlock.
_RELEASE_LUA = """
if redis.call("get", KEYS[1]) == ARGV[1] then
  return redis.call("del", KEYS[1])
end
return 0
"""

_REFRESH_LUA = """
if redis.call("get", KEYS[1]) == ARGV[1] then
  return redis.call("expire", KEYS[1], ARGV[2])
end
return 0
"""


def live_key(vcluster_name: str) -> str:
    name = (vcluster_name or "").strip()
    if not name:
        raise ValueError("vcluster_name required for lock key")
    return f"{LIVE_KEY_PREFIX}{name}"


def inflight_key(vcluster_name: str) -> str:
    name = (vcluster_name or "").strip()
    if not name:
        raise ValueError("vcluster_name required for lock key")
    return f"{INFLIGHT_KEY_PREFIX}{name}"


# Back-compat alias used by older call sites / docs.
def lock_key(vcluster_name: str) -> str:
    return live_key(vcluster_name)


@dataclass(frozen=True)
class LockAcquireResult:
    acquired: bool
    key: str
    token: str
    holder: str | None = None
    kind: str = ""  # "inflight" | "live" | ""


class DeploymentLockStore:
    """Async Redis lock store. Safe to call when ``client`` is None (no-op)."""

    def __init__(
        self,
        client,  # redis.asyncio.Redis | None
        *,
        live_ttl_s: int = 691_200,
        inflight_ttl_s: int = 7_200,
        enabled: bool = True,
    ) -> None:
        self._client = client
        self.ttl_s = int(live_ttl_s)  # back-compat attribute name
        self.live_ttl_s = int(live_ttl_s)
        self.inflight_ttl_s = int(inflight_ttl_s)
        self.enabled = enabled and client is not None

    @property
    def configured(self) -> bool:
        return self.enabled

    async def close(self) -> None:
        if self._client is not None:
            await self._client.aclose()

    async def _get(self, key: str) -> str | None:
        if not self.enabled:
            return None
        val = await self._client.get(key)
        if isinstance(val, bytes):
            return val.decode()
        return val

    async def _release_key(self, key: str, token: str, *, event: str, vcluster: str) -> bool:
        if not self.enabled:
            return True
        result = await self._client.eval(_RELEASE_LUA, 1, key, token)
        released = bool(result)
        log.info(
            "%s key=%s token=%s released=%s",
            event,
            key,
            token,
            released,
            extra={
                "event": event if released else f"{event}_noop",
                "vcluster": vcluster,
                "token": token,
            },
        )
        return released

    async def get_live_holder(self, vcluster_name: str) -> str | None:
        return await self._get(live_key(vcluster_name))

    async def get_inflight_holder(self, vcluster_name: str) -> str | None:
        return await self._get(inflight_key(vcluster_name))

    async def get_holder(self, vcluster_name: str) -> str | None:
        """Prefer live holder, else inflight (for status / legacy callers)."""
        return (await self.get_live_holder(vcluster_name)) or (
            await self.get_inflight_holder(vcluster_name)
        )

    async def is_locked(self, vcluster_name: str) -> str | None:
        return await self.get_holder(vcluster_name)

    async def try_acquire_inflight(self, vcluster_name: str, token: str) -> LockAcquireResult:
        """Acquire short-lived inflight lock. Fails if live or another inflight is held."""
        token = (token or "").strip()
        if not token:
            raise ValueError("lock token required")
        ikey = inflight_key(vcluster_name)
        lkey = live_key(vcluster_name)

        if not self.enabled:
            return LockAcquireResult(acquired=True, key=ikey, token=token, kind="inflight")

        live_holder = await self._get(lkey)
        if live_holder:
            log.warning(
                "inflight denied — live lock held key=%s holder=%s requester=%s",
                lkey,
                live_holder,
                token,
                extra={
                    "event": "lock_denied_live",
                    "vcluster": vcluster_name,
                    "holder": live_holder,
                    "token": token,
                },
            )
            return LockAcquireResult(
                acquired=False, key=lkey, token=token, holder=live_holder, kind="live"
            )

        ok = await self._client.set(ikey, token, nx=True, ex=self.inflight_ttl_s)
        if ok:
            log.info(
                "inflight acquired key=%s token=%s ttl=%ss",
                ikey,
                token,
                self.inflight_ttl_s,
                extra={
                    "event": "lock_inflight_acquired",
                    "vcluster": vcluster_name,
                    "token": token,
                },
            )
            return LockAcquireResult(acquired=True, key=ikey, token=token, kind="inflight")

        holder = await self._get(ikey)
        log.warning(
            "inflight denied key=%s holder=%s requester=%s",
            ikey,
            holder,
            token,
            extra={
                "event": "lock_inflight_denied",
                "vcluster": vcluster_name,
                "holder": holder,
                "token": token,
            },
        )
        return LockAcquireResult(
            acquired=False, key=ikey, token=token, holder=holder, kind="inflight"
        )

    async def try_acquire(self, vcluster_name: str, token: str) -> LockAcquireResult:
        """Back-compat: begin-deploy = acquire inflight."""
        return await self.try_acquire_inflight(vcluster_name, token)

    async def force_acquire_inflight(self, vcluster_name: str, token: str) -> LockAcquireResult:
        """Force redeploy: clear live + inflight, then take inflight."""
        token = (token or "").strip()
        if not token:
            raise ValueError("lock token required")
        await self.clear_for_force(vcluster_name)
        if not self.enabled:
            return LockAcquireResult(
                acquired=True, key=inflight_key(vcluster_name), token=token, kind="inflight"
            )
        ikey = inflight_key(vcluster_name)
        await self._client.set(ikey, token, ex=self.inflight_ttl_s)
        log.warning(
            "inflight force-acquired key=%s token=%s ttl=%ss",
            ikey,
            token,
            self.inflight_ttl_s,
            extra={
                "event": "lock_inflight_force_acquired",
                "vcluster": vcluster_name,
                "token": token,
            },
        )
        return LockAcquireResult(acquired=True, key=ikey, token=token, kind="inflight")

    async def force_acquire(self, vcluster_name: str, token: str) -> LockAcquireResult:
        return await self.force_acquire_inflight(vcluster_name, token)

    async def release_inflight(self, vcluster_name: str, token: str) -> bool:
        if not (vcluster_name or "").strip() or not (token or "").strip():
            return False
        return await self._release_key(
            inflight_key(vcluster_name),
            token,
            event="lock_inflight_released",
            vcluster=vcluster_name,
        )

    async def release_live(self, vcluster_name: str, token: str) -> bool:
        if not (vcluster_name or "").strip() or not (token or "").strip():
            return False
        return await self._release_key(
            live_key(vcluster_name),
            token,
            event="lock_live_released",
            vcluster=vcluster_name,
        )

    async def release(self, vcluster_name: str, token: str) -> bool:
        """Release inflight and/or live if this token holds them (fail / orphan paths)."""
        a = await self.release_inflight(vcluster_name, token)
        b = await self.release_live(vcluster_name, token)
        return a or b

    async def clear_for_force(self, vcluster_name: str) -> bool:
        if not (vcluster_name or "").strip():
            return False
        if not self.enabled:
            return True
        d1 = await self._client.delete(live_key(vcluster_name))
        d2 = await self._client.delete(inflight_key(vcluster_name))
        log.warning(
            "locks force-cleared vcluster=%s live_del=%s inflight_del=%s",
            vcluster_name,
            d1,
            d2,
            extra={"event": "lock_force_cleared", "vcluster": vcluster_name},
        )
        return bool(d1 or d2)

    async def heal_stale_live_key(self, vcluster_name: str) -> bool:
        """Delete live key unconditionally (caller verified holder is not a ready env)."""
        if not self.enabled:
            return True
        key = live_key(vcluster_name)
        deleted = await self._client.delete(key)
        if deleted:
            log.warning(
                "stale live key healed key=%s",
                key,
                extra={"event": "lock_live_healed", "vcluster": vcluster_name},
            )
        return bool(deleted)

    async def steal_inflight(self, vcluster_name: str, token: str) -> LockAcquireResult:
        """Overwrite inflight only (live must already be clear)."""
        token = (token or "").strip()
        if not token:
            raise ValueError("lock token required")
        ikey = inflight_key(vcluster_name)
        if not self.enabled:
            return LockAcquireResult(acquired=True, key=ikey, token=token, kind="inflight")
        prev = await self._get(ikey)
        await self._client.set(ikey, token, ex=self.inflight_ttl_s)
        log.warning(
            "inflight stolen key=%s prev=%s token=%s",
            ikey,
            prev,
            token,
            extra={
                "event": "lock_inflight_stolen",
                "vcluster": vcluster_name,
                "prev_holder": prev,
                "token": token,
            },
        )
        return LockAcquireResult(acquired=True, key=ikey, token=token, holder=prev, kind="inflight")

    async def create_from_ready(self, vcluster_name: str, token: str) -> LockAcquireResult:
        """Promote: drop our inflight, set/refresh live 8d. Never overwrite foreign live."""
        token = (token or "").strip()
        if not token:
            raise ValueError("lock token required")
        lkey = live_key(vcluster_name)

        if not self.enabled:
            return LockAcquireResult(acquired=True, key=lkey, token=token, kind="live")

        await self.release_inflight(vcluster_name, token)

        holder = await self._get(lkey)
        if holder == token:
            await self._client.eval(_REFRESH_LUA, 1, lkey, token, str(self.live_ttl_s))
            log.info(
                "live lock refreshed on ready key=%s token=%s ttl=%ss",
                lkey,
                token,
                self.live_ttl_s,
                extra={
                    "event": "lock_live_refreshed",
                    "vcluster": vcluster_name,
                    "token": token,
                },
            )
            return LockAcquireResult(acquired=True, key=lkey, token=token, kind="live")

        if holder is None:
            ok = await self._client.set(lkey, token, nx=True, ex=self.live_ttl_s)
            if ok:
                log.info(
                    "live lock acquired on ready key=%s token=%s ttl=%ss",
                    lkey,
                    token,
                    self.live_ttl_s,
                    extra={
                        "event": "lock_live_acquired_ready",
                        "vcluster": vcluster_name,
                        "token": token,
                    },
                )
                return LockAcquireResult(acquired=True, key=lkey, token=token, kind="live")
            holder = await self._get(lkey)

        log.warning(
            "live lock ready skipped — foreign holder key=%s holder=%s ready_token=%s",
            lkey,
            holder,
            token,
            extra={
                "event": "lock_live_ready_foreign",
                "vcluster": vcluster_name,
                "holder": holder,
                "token": token,
            },
        )
        return LockAcquireResult(
            acquired=False, key=lkey, token=token, holder=holder, kind="live"
        )


_lock_store: DeploymentLockStore | None = None


def get_lock_store() -> DeploymentLockStore:
    global _lock_store
    if _lock_store is None:
        _lock_store = DeploymentLockStore(None, enabled=False)
    return _lock_store


def set_lock_store(store: DeploymentLockStore | None) -> None:
    global _lock_store
    _lock_store = store


async def init_lock_store_from_settings(settings) -> DeploymentLockStore:
    live_ttl = int(getattr(settings, "deploy_lock_ttl_s", 691_200) or 691_200)
    inflight_ttl = int(getattr(settings, "deploy_inflight_lock_ttl_s", 7_200) or 7_200)
    url = (getattr(settings, "redis_url", "") or "").strip()
    host = (getattr(settings, "redis_host", "") or "").strip()
    password = (getattr(settings, "redis_password", "") or "").strip()
    port = int(getattr(settings, "redis_port", 6379) or 6379)
    db = int(getattr(settings, "redis_db", 0) or 0)

    if not url and not host:
        store = DeploymentLockStore(
            None, live_ttl_s=live_ttl, inflight_ttl_s=inflight_ttl, enabled=False
        )
        set_lock_store(store)
        log.warning(
            "Redis not configured — deployment locks disabled (set REDIS_URL or REDIS_HOST)",
            extra={"event": "lock_store_disabled"},
        )
        return store

    try:
        from redis.asyncio import Redis
    except ImportError as exc:
        raise RuntimeError("redis package required for deployment locks") from exc

    if url:
        client = Redis.from_url(url, decode_responses=True)
    else:
        client = Redis(
            host=host,
            port=port,
            db=db,
            password=password or None,
            decode_responses=True,
        )

    await client.ping()
    store = DeploymentLockStore(
        client, live_ttl_s=live_ttl, inflight_ttl_s=inflight_ttl, enabled=True
    )
    set_lock_store(store)
    log.info(
        "deployment lock store ready live_ttl=%ss inflight_ttl=%ss redis=%s",
        live_ttl,
        inflight_ttl,
        url or f"{host}:{port}/{db}",
        extra={
            "event": "lock_store_ready",
            "live_ttl_s": live_ttl,
            "inflight_ttl_s": inflight_ttl,
        },
    )
    return store
