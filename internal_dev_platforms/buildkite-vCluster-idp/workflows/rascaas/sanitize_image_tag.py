#!/usr/bin/env python3
"""Sanitize a git branch into an ECR/docker tag fragment (DNS-ish, lowercase)."""
from __future__ import annotations

import argparse
import re
import sys


def sanitize_tag_fragment(branch: str, *, max_len: int = 80) -> str:
    raw = (branch or "").strip()
    if not raw:
        raise ValueError("branch is empty")
    slug = raw.lower().replace("/", "-").replace("_", "-")
    slug = re.sub(r"[^a-z0-9.-]+", "-", slug)
    slug = re.sub(r"-+", "-", slug).strip("-.")
    if not slug:
        raise ValueError(f"branch {branch!r} sanitizes to empty")
    if len(slug) > max_len:
        slug = slug[:max_len].rstrip("-.")
    return slug


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("branch", help="Git branch name")
    parser.add_argument("--max-len", type=int, default=80)
    args = parser.parse_args()
    try:
        print(sanitize_tag_fragment(args.branch, max_len=args.max_len))
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
