from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    github_app_id: str = "0"
    github_client_id: str = ""  # optional; used as JWT iss when set (else github_app_id)
    github_installation_id: str = "0"
    github_private_key: str = ""  # PEM contents; empty = mock GitHub API in dev
    # GitHub platform repo (owner/repo) where uat-deploy.yml runs. Local path: platform-testing/; GitHub name: platform.
    # Production: kovr-ai/platform. variance_repo input = UI-selected service. Empty = legacy dispatch on selected repo.
    github_dispatch_repo: str = ""
    # Branch/tag of the *platform* repo that contains uat-deploy.yml (not the variance service branch).
    github_dispatch_ref: str = "main"

    oidc_issuer_url: str = "https://idp.example.com"
    # Optional: reach IdP from inside Docker (e.g. keycloak:8080 instead of localhost)
    oidc_discovery_url: str = ""
    # Optional: JWKS URL reachable from the app pod (overrides discovery; avoids localhost in Keycloak metadata)
    oidc_jwks_url: str = ""
    oidc_client_id: str = "platform-ui"
    # Trust X-Auth-Request-* / X-Forwarded-* from oauth2-proxy when access token header is absent.
    trust_oauth2_proxy_identity: bool = False
    # Full IdP logout URL for oauth2-proxy ?rd= (e.g. Cognito /logout?client_id=…&logout_uri=…).
    # Empty → sign out only clears the proxy cookie and returns to /.
    oidc_logout_url: str = ""

    app_base_url: str = "http://localhost:8000"
    environment: str = "development"

    # Logging — LOG_FORMAT defaults to json in production, text otherwise.
    log_level: str = "INFO"
    log_format: str = ""  # json | text | empty=auto

    # Shared secret for GitHub Actions → POST /api/runner/events (bypass oauth2).
    runner_callback_token: str = ""

    app_version: str = "0.3.1"
    helm_chart_version: str = "0.3.1"
    default_workflow: str = "uat-deploy.yml"

    # SQLite path (PVC mount in cluster). Default under /tmp for local docker.
    sqlite_path: str = "/data/rascaas.db"
    # Legacy shared host ns; new envs use dedicated ns = release = tmp-<repo>-<branch>.
    vcluster_host_namespace: str = "vcluster"

    # After a deletion event (POST /api/runner/deleted), wait this many seconds
    # then re-check the cluster to confirm the vCluster is actually gone. Still
    # live → deployment stays active; gone → marked deleted (hidden).
    delete_verify_delay_s: int = 180

    # Redis deployment locks (traditional SET NX EX). Empty host/url → locks disabled.
    # Prefer REDIS_URL; else REDIS_HOST + REDIS_PASSWORD (+ REDIS_PORT / REDIS_DB).
    redis_url: str = ""
    redis_host: str = ""
    redis_port: int = 6379
    redis_db: int = 0
    redis_password: str = ""
    # Live env hold after phase=ready (default 8 days).
    deploy_lock_ttl_s: int = 691_200
    # In-flight hold from deploy start until ready/fail (default 2 hours).
    deploy_inflight_lock_ttl_s: int = 7_200

    class Config:
        env_file = ".env"

    @property
    def resolved_log_format(self) -> str:
        if self.log_format.strip():
            return self.log_format.strip().lower()
        return "json" if self.environment.lower() in {"production", "prod", "qa"} else "text"


@lru_cache()
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
