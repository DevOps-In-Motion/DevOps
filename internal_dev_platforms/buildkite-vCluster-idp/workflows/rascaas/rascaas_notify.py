#!/usr/bin/env python3
"""Post milestone / failure lines to RaSCaaS FastAPI (optional — no-op if unset).

Env (set from workflow_dispatch inputs):
  RASCAAS_DEPLOYMENT_ID
  RASCAAS_CALLBACK_URL   — e.g. https://rascaas.qa.kovrai.com/api/runner/events
  RASCAAS_CALLBACK_TOKEN
  RASCAAS_TRACE_ID       — optional deploy-scoped trace id

Never fails the job: network/HTTP errors print a warning and exit 0.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

MAX_TAIL_LINES = 50
MAX_LINE_LEN = 4000
RETRIES = 3


def _env(name: str) -> str:
    return (os.environ.get(name) or "").strip()


def _truncate(line: str) -> str:
    line = line.rstrip("\n")
    if len(line) > MAX_LINE_LEN:
        return line[: MAX_LINE_LEN - 1] + "…"
    return line


def main() -> int:
    parser = argparse.ArgumentParser(description="Notify RaSCaaS of workflow progress")
    parser.add_argument("--line", action="append", default=[], help="Log line (repeatable)")
    parser.add_argument(
        "--from-file",
        default="",
        help="Append last N lines from this file (failure tails)",
    )
    parser.add_argument("--tail", type=int, default=MAX_TAIL_LINES)
    parser.add_argument(
        "--level",
        default="info",
        choices=("info", "warn", "warning", "error"),
    )
    parser.add_argument(
        "--phase",
        default="",
        choices=("", "provisioning", "syncing", "ready", "failed"),
    )
    parser.add_argument("--message", default="", help="Optional phase message")
    parser.add_argument("--run-id", type=int, default=0)
    parser.add_argument("--run-url", default="")
    args = parser.parse_args()

    deployment_id = _env("RASCAAS_DEPLOYMENT_ID")
    url = _env("RASCAAS_CALLBACK_URL")
    token = _env("RASCAAS_CALLBACK_TOKEN")
    trace_id = _env("RASCAAS_TRACE_ID")
    if not deployment_id or not url or not token:
        print("rascaas_notify: callback unset — skipping", file=sys.stderr)
        return 0

    lines: list[str] = [_truncate(x) for x in args.line if x and x.strip()]
    if args.from_file and os.path.isfile(args.from_file):
        try:
            with open(args.from_file, encoding="utf-8", errors="replace") as fh:
                file_lines = fh.read().splitlines()
            for raw in file_lines[-max(1, args.tail) :]:
                t = _truncate(raw)
                if t:
                    lines.append(t)
        except OSError as exc:
            print(f"rascaas_notify: could not read {args.from_file}: {exc}", file=sys.stderr)

    if not lines:
        lines = ["(empty notify)"]

    payload: dict = {
        "deployment_id": deployment_id,
        "lines": lines[:100],
        "level": args.level,
    }
    if trace_id:
        payload["trace_id"] = trace_id
    if args.phase:
        payload["phase"] = args.phase
    if args.message:
        payload["message"] = args.message
    if args.run_id:
        payload["run_id"] = args.run_id
    elif _env("GITHUB_RUN_ID").isdigit():
        payload["run_id"] = int(_env("GITHUB_RUN_ID"))

    run_url = (args.run_url or "").strip()
    if not run_url:
        # GitHub Actions always sets these — every notify gets a workflow link
        # even when the step omits --run-id / --run-url.
        rid = payload.get("run_id") or _env("GITHUB_RUN_ID")
        server = _env("GITHUB_SERVER_URL") or "https://github.com"
        repo = _env("GITHUB_REPOSITORY")
        if rid and repo:
            run_url = f"{server.rstrip('/')}/{repo}/actions/runs/{rid}"
    if run_url:
        payload["run_url"] = run_url

    body = json.dumps(payload).encode("utf-8")
    if len(body) > 64 * 1024:
        payload["lines"] = lines[:20]
        body = json.dumps(payload).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
            "User-Agent": "rascaas-notify/1.0",
            **({"X-Trace-Id": trace_id} if trace_id else {}),
        },
    )

    last_err = ""
    for attempt in range(1, RETRIES + 1):
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                resp.read()
                print(f"rascaas_notify: ok status={resp.status} lines={len(payload['lines'])}")
                return 0
        except urllib.error.HTTPError as exc:
            last_err = f"HTTP {exc.code}: {exc.read()[:200]!r}"
        except Exception as exc:  # noqa: BLE001 — never fail the job
            last_err = str(exc)
        print(f"rascaas_notify: attempt {attempt}/{RETRIES} failed: {last_err}", file=sys.stderr)

    print(f"rascaas_notify: giving up ({last_err})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
