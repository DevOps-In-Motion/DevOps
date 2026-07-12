from fastapi import Request, HTTPException, status
from dataclasses import dataclass, field
from urllib.parse import urlparse, urlunparse
import httpx
import jwt
import logging

from app.config import settings

logger = logging.getLogger(__name__)


@dataclass
class User:
    sub: str
    email: str
    name: str
    groups: list[str] = field(default_factory=list)


def _oidc_discovery_url() -> str:
    """OpenID discovery document URL (may use internal Docker hostname)."""
    base = (settings.oidc_discovery_url or settings.oidc_issuer_url).rstrip("/")
    return f"{base}/.well-known/openid-configuration"


def _rewrite_jwks_for_internal_fetch(jwks_uri: str) -> str:
    """
    Keycloak often advertises jwks_uri with localhost (KC_HOSTNAME) while the app
    must fetch JWKS via the Docker service name (e.g. keycloak:8080).
    """
    discovery_base = (settings.oidc_discovery_url or "").rstrip("/")
    issuer_base = settings.oidc_issuer_url.rstrip("/")
    if not discovery_base or discovery_base == issuer_base:
        return jwks_uri

    d = urlparse(discovery_base)
    j = urlparse(jwks_uri)
    if not d.hostname or not j.hostname:
        return jwks_uri
    if d.hostname == j.hostname and d.port == j.port:
        return jwks_uri
    return urlunparse(j._replace(netloc=d.netloc))


async def _resolve_jwks_uri() -> str:
    if settings.oidc_jwks_url:
        return settings.oidc_jwks_url
    async with httpx.AsyncClient() as client:
        r = await client.get(_oidc_discovery_url())
        r.raise_for_status()
        jwks_uri = r.json()["jwks_uri"]
    return _rewrite_jwks_for_internal_fetch(jwks_uri)


def _extract_bearer_token(request: Request) -> str | None:
    """Read OIDC access token from oauth2-proxy or Authorization header."""
    for header in (
        "X-Forwarded-Access-Token",
        "X-Auth-Request-Access-Token",
    ):
        raw = request.headers.get(header)
        if raw:
            raw = raw.strip()
            if raw.lower().startswith("bearer "):
                return raw[7:].strip()
            return raw

    auth = request.headers.get("Authorization")
    if auth and auth.lower().startswith("bearer "):
        return auth[7:].strip()
    return None


def _user_from_proxy_headers(request: Request) -> User | None:
    """Identity from oauth2-proxy (session already validated at the proxy)."""
    if not settings.trust_oauth2_proxy_identity:
        return None

    email = (
        request.headers.get("X-Auth-Request-Email")
        or request.headers.get("X-Forwarded-Email")
        or ""
    )
    name = (
        request.headers.get("X-Auth-Request-User")
        or request.headers.get("X-Forwarded-User")
        or request.headers.get("X-Auth-Request-Preferred-Username")
        or request.headers.get("X-Forwarded-Preferred-Username")
        or ""
    )
    if not email and not name:
        return None

    groups_raw = (
        request.headers.get("X-Auth-Request-Groups")
        or request.headers.get("X-Forwarded-Groups")
        or ""
    )
    groups = [g.strip() for g in groups_raw.split(",") if g.strip()]

    sub = request.headers.get("X-Auth-Request-User-Id") or email or name
    return User(
        sub=sub,
        email=email,
        name=name or email,
        groups=groups,
    )


async def _user_from_jwt(token: str) -> User:
    jwks_uri = await _resolve_jwks_uri()
    jwks_client = jwt.PyJWKClient(jwks_uri)
    signing_key = jwks_client.get_signing_key_from_jwt(token)
    payload = jwt.decode(
        token,
        signing_key.key,
        algorithms=["RS256"],
        issuer=settings.oidc_issuer_url,
        options={"verify_aud": False},
    )
    azp = payload.get("azp")
    aud = payload.get("aud")
    if isinstance(aud, str):
        aud = [aud]
    if azp != settings.oidc_client_id and settings.oidc_client_id not in (aud or []):
        raise jwt.InvalidTokenError("Token not issued for this client")
    return User(
        sub=payload["sub"],
        email=payload.get("email", ""),
        name=payload.get("name", payload.get("preferred_username", "")),
        groups=payload.get("groups", []),
    )


async def get_current_user(request: Request) -> User:
    """
    Authenticate via oauth2-proxy:
    1. Trust proxy identity headers when enabled (local compose; avoids JWKS localhost issues).
    2. Validate X-Forwarded-Access-Token when present.
    3. Development mock user when ENVIRONMENT=development.
    """
    if settings.trust_oauth2_proxy_identity:
        proxy_user = _user_from_proxy_headers(request)
        if proxy_user:
            return proxy_user

    token = _extract_bearer_token(request)
    if token:
        try:
            return await _user_from_jwt(token)
        except jwt.ExpiredSignatureError:
            raise HTTPException(status_code=401, detail="Token expired")
        except jwt.InvalidTokenError as e:
            logger.warning("Invalid access token: %s", e)
            proxy_user = _user_from_proxy_headers(request)
            if proxy_user:
                return proxy_user
            raise HTTPException(status_code=401, detail=f"Invalid token: {e}")
        except Exception as e:
            logger.warning("JWT validation failed: %s", e)
            proxy_user = _user_from_proxy_headers(request)
            if proxy_user:
                return proxy_user
            raise HTTPException(status_code=401, detail="Token validation failed") from e

    if settings.environment == "development":
        return User(sub="dev", email="dev@example.com", name="Dev User", groups=["admins"])

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=(
            "Not authenticated. Open http://localhost:4180 (oauth2-proxy), sign in, "
            "and do not use http://localhost:8000 for the UI."
        ),
    )
