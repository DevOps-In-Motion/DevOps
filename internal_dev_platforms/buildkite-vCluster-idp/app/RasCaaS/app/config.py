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

    oidc_issuer_url: str = "https://idp.example.com"
    # Optional: reach IdP from inside Docker (e.g. keycloak:8080 instead of localhost)
    oidc_discovery_url: str = ""
    # Optional: JWKS URL reachable from the app pod (overrides discovery; avoids localhost in Keycloak metadata)
    oidc_jwks_url: str = ""
    oidc_client_id: str = "platform-ui"
    # Trust X-Auth-Request-* / X-Forwarded-* from oauth2-proxy when access token header is absent.
    trust_oauth2_proxy_identity: bool = False

    app_base_url: str = "http://localhost:8000"
    environment: str = "development"

    app_version: str = "0.1.0"
    helm_chart_version: str = "0.1.0"
    default_workflow: str = "uat-deploy.yml"

    class Config:
        env_file = ".env"


@lru_cache()
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
