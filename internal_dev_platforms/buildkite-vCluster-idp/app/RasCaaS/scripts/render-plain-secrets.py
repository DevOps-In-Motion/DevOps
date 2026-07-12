#!/usr/bin/env python3
"""Render helm/_crds/secrets/plain-secrets.yaml from RasCaaS/.env."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / ".env"
OUT_PATH = ROOT / "helm/_crds/secrets/plain-secrets.yaml"


def load_env(path: Path) -> dict[str, str]:
    env: dict[str, str] = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        env[key.strip()] = value.strip()
    return env


def format_pem(raw: str) -> str:
    text = raw.strip().replace("\\n", "\n")
    if "\n" in text and text.count("\n") >= 2:
        return text if text.endswith("\n") else text + "\n"
    match = re.search(
        r"-----BEGIN ([^-]+)-----(.+)-----END \1-----",
        text.replace("\n", ""),
        re.DOTALL,
    )
    if not match:
        return text if text.endswith("\n") else text + "\n"
    body = re.sub(r"\s+", "", match.group(2))
    wrapped = "\n".join(body[i : i + 64] for i in range(0, len(body), 64))
    return f"-----BEGIN {match.group(1)}-----\n{wrapped}\n-----END {match.group(1)}-----\n"


def main() -> int:
    if not ENV_PATH.is_file():
        print(f"Missing {ENV_PATH}", file=sys.stderr)
        return 1
    env = load_env(ENV_PATH)
    required = ("GITHUB_PRIVATE_KEY", "OAUTH2_PROXY_CLIENT_SECRET", "OAUTH2_PROXY_COOKIE_SECRET")
    missing = [k for k in required if not env.get(k)]
    if missing:
        print(f"Missing in .env: {', '.join(missing)}", file=sys.stderr)
        return 1

    pem = format_pem(env["GITHUB_PRIVATE_KEY"])
    client = env["OAUTH2_PROXY_CLIENT_SECRET"]
    cookie = env["OAUTH2_PROXY_COOKIE_SECRET"]
    if len(cookie) not in (16, 24, 32):
        print(f"OAUTH2_PROXY_COOKIE_SECRET must be 16, 24, or 32 bytes, got {len(cookie)}", file=sys.stderr)
        return 1

    indented_pem = "\n".join(f"    {line}" for line in pem.splitlines())
    content = f"""# Generated from .env — gitignored. Re-run: python3 scripts/render-plain-secrets.py
# Apply: kubectl apply -f helm/_crds/secrets/plain-secrets.yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: fastapi-secrets
  namespace: rascaas
  labels:
    app.kubernetes.io/part-of: rascaas
    app.kubernetes.io/component: secrets
type: Opaque
stringData:
  github-private-key: |
{indented_pem}
---
apiVersion: v1
kind: Secret
metadata:
  name: oauth2proxy-secret
  namespace: rascaas
  labels:
    app.kubernetes.io/part-of: rascaas
    app.kubernetes.io/component: secrets
type: Opaque
stringData:
  client-secret: {client}
  cookie-secret: {cookie}
"""
    OUT_PATH.write_text(content)
    print(f"Wrote {OUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
