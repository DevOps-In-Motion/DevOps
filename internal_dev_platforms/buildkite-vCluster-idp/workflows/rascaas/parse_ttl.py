#!/usr/bin/env python3
"""Parse RaSCaaS TTL strings (e.g. 72h, 3d, 30m) to seconds. Empty → 0."""
from __future__ import annotations

import re
import sys

_UNITS = {
    "m": 60,
    "min": 60,
    "mins": 60,
    "minute": 60,
    "minutes": 60,
    "h": 3600,
    "hr": 3600,
    "hrs": 3600,
    "hour": 3600,
    "hours": 3600,
    "d": 86400,
    "day": 86400,
    "days": 86400,
}

_PATTERN = re.compile(
    r"^\s*(\d+)\s*([a-zA-Z]+)\s*$",
)


def parse_ttl(value: str) -> int:
    text = (value or "").strip()
    if not text:
        return 0
    compact = re.sub(r"\s+", "", text.lower())
    match = _PATTERN.match(compact) or _PATTERN.match(text.lower())
    if not match:
        raise ValueError(
            f"invalid TTL {value!r}; use forms like 72h, 3d, 30m (empty skips cleanup job)"
        )
    amount = int(match.group(1))
    unit = match.group(2).lower()
    if unit not in _UNITS:
        raise ValueError(f"unknown TTL unit {unit!r} in {value!r}")
    if amount <= 0:
        raise ValueError(f"TTL must be positive, got {value!r}")
    return amount * _UNITS[unit]


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: parse_ttl.py <ttl>", file=sys.stderr)
        return 2
    try:
        print(parse_ttl(sys.argv[1]))
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
