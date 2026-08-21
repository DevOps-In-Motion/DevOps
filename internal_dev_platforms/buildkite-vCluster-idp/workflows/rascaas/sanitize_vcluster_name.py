#!/usr/bin/env python3
"""Sanitize repo + branch into DNS-1123: tmp-<reponame>-<branch>.

That string is both the host namespace and the vCluster Helm release name
(one virtual cluster per namespace — required by vCluster ≥0.25).
"""
from __future__ import annotations

import argparse
import re
import sys


def _slug(part: str) -> str:
    raw = (part or "").strip()
    slug = raw.lower().replace("/", "-").replace("_", "-")
    slug = re.sub(r"[^a-z0-9-]+", "-", slug)
    slug = re.sub(r"-+", "-", slug).strip("-")
    return slug


def sanitize_vcluster_name(
    branch: str,
    *,
    repo: str = "",
    prefix: str = "tmp-",
    max_len: int = 63,
) -> str:
    """Build tmp-<reponame>-<branch> (repo may be owner/name; only the name is used)."""
    branch_slug = _slug(branch)
    if not branch_slug:
        raise ValueError("branch is empty or sanitizes to empty")

    repo_raw = (repo or "").strip()
    # owner/name → name only
    if "/" in repo_raw:
        repo_raw = repo_raw.rsplit("/", 1)[-1]
    repo_slug = _slug(repo_raw)

    if repo_slug:
        name = f"{prefix}{repo_slug}-{branch_slug}"
    else:
        name = f"{prefix}{branch_slug}"

    if len(name) > max_len:
        name = name[:max_len].rstrip("-")
    if not re.fullmatch(r"[a-z0-9]([-a-z0-9]*[a-z0-9])?", name):
        raise ValueError(f"invalid vCluster/namespace name after sanitize: {name!r}")
    return name


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("branch", help="Git branch name from RaSCaaS UI")
    parser.add_argument(
        "--repo",
        default="",
        help="Variance repo (owner/name or name); used as tmp-<reponame>-…",
    )
    parser.add_argument(
        "--prefix",
        default="tmp-",
        help="Name/namespace prefix (default tmp-)",
    )
    parser.add_argument("--max-len", type=int, default=63)
    args = parser.parse_args()
    try:
        print(
            sanitize_vcluster_name(
                args.branch,
                repo=args.repo,
                prefix=args.prefix,
                max_len=args.max_len,
            )
        )
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
