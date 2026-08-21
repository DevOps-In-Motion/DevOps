"""Delete aged UAT variance images from the dedicated temp ECR repository.

Standalone CronJob image — not part of the RaSCaaS IDP.

Retention uses calendar days (UTC midnight today minus RETENTION_DAYS), not a
rolling hour window. Only ECR_UAT_TEMP_REPO is touched.

Env:
  ECR_UAT_TEMP_REPO  — repository name (default: uat-temp)
  AWS_REGION         — region for the ECR API
  RETENTION_DAYS     — calendar days to keep (default: 14)
  DRY_RUN            — if "1"/"true", log deletions without calling BatchDeleteImage
"""

from __future__ import annotations

import logging
import os
import sys
from datetime import date, datetime, timedelta, timezone
from typing import Any

import boto3
from botocore.exceptions import ClientError

LOG = logging.getLogger("ecr_temp_cleanup")


def _env_bool(name: str, default: bool = False) -> bool:
    raw = os.environ.get(name, "").strip().lower()
    if not raw:
        return default
    return raw in ("1", "true", "yes", "on")


def calendar_cutoff_utc(retention_days: int, *, today: date | None = None) -> datetime:
    """Images pushed strictly before this instant are eligible for deletion."""
    day = today or datetime.now(timezone.utc).date()
    cutoff_date = day - timedelta(days=retention_days)
    return datetime(cutoff_date.year, cutoff_date.month, cutoff_date.day, tzinfo=timezone.utc)


def _as_aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def list_stale_image_ids(
    client: Any,
    repository: str,
    cutoff: datetime,
) -> list[dict[str, str]]:
    """Return unique imageDigest ids pushed before cutoff."""
    stale: dict[str, dict[str, str]] = {}
    paginator = client.get_paginator("describe_images")
    for page in paginator.paginate(repositoryName=repository, filter={"tagStatus": "ANY"}):
        for detail in page.get("imageDetails") or []:
            digest = detail.get("imageDigest")
            pushed = detail.get("imagePushedAt")
            if not digest or pushed is None:
                continue
            if _as_aware_utc(pushed) < cutoff:
                stale[digest] = {"imageDigest": digest}
    return list(stale.values())


def delete_images(
    client: Any,
    repository: str,
    image_ids: list[dict[str, str]],
    *,
    dry_run: bool,
) -> int:
    if not image_ids:
        return 0
    deleted = 0
    # BatchDeleteImage accepts at most 100 ids per call.
    for i in range(0, len(image_ids), 100):
        chunk = image_ids[i : i + 100]
        digests = [item["imageDigest"] for item in chunk]
        if dry_run:
            LOG.info("DRY_RUN would delete %d image(s): %s", len(chunk), ", ".join(digests))
            deleted += len(chunk)
            continue
        resp = client.batch_delete_image(repositoryName=repository, imageIds=chunk)
        failures = resp.get("failures") or []
        for fail in failures:
            LOG.error(
                "Failed to delete %s: %s %s",
                fail.get("imageId"),
                fail.get("failureCode"),
                fail.get("failureReason"),
            )
        ok = len(resp.get("imageIds") or [])
        deleted += ok
        LOG.info("Deleted %d image(s) in batch (%d failure(s))", ok, len(failures))
    return deleted


def main() -> int:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stdout,
    )
    repository = os.environ.get("ECR_UAT_TEMP_REPO", "uat-temp").strip()
    region = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION") or "us-west-2"
    retention_days = int(os.environ.get("RETENTION_DAYS", "14"))
    dry_run = _env_bool("DRY_RUN", False)

    if retention_days < 1:
        LOG.error("RETENTION_DAYS must be >= 1, got %s", retention_days)
        return 2

    cutoff = calendar_cutoff_utc(retention_days)
    LOG.info(
        "Scanning ECR repo=%s region=%s retention_days=%d cutoff_utc=%s dry_run=%s",
        repository,
        region,
        retention_days,
        cutoff.isoformat(),
        dry_run,
    )

    client = boto3.client("ecr", region_name=region)
    try:
        client.describe_repositories(repositoryNames=[repository])
    except ClientError as exc:
        code = (exc.response.get("Error") or {}).get("Code", "")
        if code == "RepositoryNotFoundException":
            LOG.warning("Repository %s not found — nothing to clean", repository)
            return 0
        LOG.exception("Failed to describe repository %s", repository)
        return 1

    try:
        stale = list_stale_image_ids(client, repository, cutoff)
    except ClientError:
        LOG.exception("Failed to list images in %s", repository)
        return 1

    LOG.info("Found %d stale image digest(s)", len(stale))
    try:
        deleted = delete_images(client, repository, stale, dry_run=dry_run)
    except ClientError:
        LOG.exception("Failed to delete images from %s", repository)
        return 1

    LOG.info("Cleanup finished: eligible=%d processed=%d", len(stale), deleted)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
