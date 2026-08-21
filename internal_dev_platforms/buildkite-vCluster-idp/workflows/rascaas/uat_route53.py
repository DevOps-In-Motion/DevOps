#!/usr/bin/env python3
"""Ephemeral Route53 A-alias records for RaSCaaS UAT envs under uat.example.com.

Each vCluster gets ``{tmp-<repo>-<branch>}.uat.example.com`` → dualstack.<shared ALB>.
Identity is one namespace + one Helm release named ``tmp-<repo>-<branch>``.

Requires:
  - ACM ``*.uat.example.com`` for HTTPS (apex cert alone is not enough for subdomains)
  - IAM ``route53:ChangeResourceRecordSets`` on the UAT hosted zone
  - Host HTTPRoute / ingress so the ALB actually serves that hostname into the vCluster
"""

from __future__ import annotations

import argparse
import json
import os
import sys


DEFAULT_ZONE_NAME = "uat.example.com"
DEFAULT_ZONE_ID = "YOUR_ROUTE53_ZONE_ID"
DEFAULT_ALB_DNS = "YOUR_ALB_DNS.us-west-2.elb.amazonaws.com"
DEFAULT_ALB_ZONE_ID = "Z1H1FL5HABSF5"  # us-west-2 ELB regional HZ


def public_hostname(vcluster_name: str, zone_name: str = DEFAULT_ZONE_NAME) -> str:
    name = (vcluster_name or "").strip().strip(".")
    zone = (zone_name or DEFAULT_ZONE_NAME).strip().strip(".")
    if not name:
        raise ValueError("vcluster_name required")
    if len(name) > 63:
        raise ValueError(f"DNS label too long ({len(name)} > 63): {name}")
    return f"{name}.{zone}"


def _dualstack_alb(alb_dns: str) -> str:
    host = (alb_dns or "").strip().rstrip(".")
    if not host:
        raise ValueError("alb_dns required")
    if host.startswith("dualstack."):
        return f"{host}."
    return f"dualstack.{host}."


def _change_batch(
    *,
    action: str,
    fqdn: str,
    alb_dns: str,
    alb_zone_id: str,
) -> dict:
    return {
        "Comment": f"RaSCaaS UAT ephemeral {action} {fqdn}",
        "Changes": [
            {
                "Action": action,
                "ResourceRecordSet": {
                    "Name": fqdn if fqdn.endswith(".") else f"{fqdn}.",
                    "Type": "A",
                    "AliasTarget": {
                        "HostedZoneId": alb_zone_id,
                        "DNSName": _dualstack_alb(alb_dns),
                        "EvaluateTargetHealth": False,
                    },
                },
            }
        ],
    }


def _client(region: str):
    try:
        import boto3
    except ImportError as exc:
        raise SystemExit("boto3 required for uat_route53.py (pip install boto3)") from exc
    return boto3.client("route53", region_name=region)


def upsert(
    *,
    vcluster_name: str,
    zone_id: str,
    zone_name: str,
    alb_dns: str,
    alb_zone_id: str,
    region: str,
    dry_run: bool,
) -> str:
    fqdn = public_hostname(vcluster_name, zone_name)
    batch = _change_batch(
        action="UPSERT",
        fqdn=fqdn,
        alb_dns=alb_dns,
        alb_zone_id=alb_zone_id,
    )
    print(json.dumps(batch, indent=2))
    if dry_run:
        print(f"dry-run: would UPSERT {fqdn} → {_dualstack_alb(alb_dns)}")
        return fqdn
    resp = _client(region).change_resource_record_sets(
        HostedZoneId=zone_id,
        ChangeBatch=batch,
    )
    print(f"UPSERT ok {fqdn} id={resp['ChangeInfo']['Id']}")
    return fqdn


def delete(
    *,
    vcluster_name: str,
    zone_id: str,
    zone_name: str,
    alb_dns: str,
    alb_zone_id: str,
    region: str,
    dry_run: bool,
) -> str:
    fqdn = public_hostname(vcluster_name, zone_name)
    batch = _change_batch(
        action="DELETE",
        fqdn=fqdn,
        alb_dns=alb_dns,
        alb_zone_id=alb_zone_id,
    )
    print(json.dumps(batch, indent=2))
    if dry_run:
        print(f"dry-run: would DELETE {fqdn}")
        return fqdn
    try:
        resp = _client(region).change_resource_record_sets(
            HostedZoneId=zone_id,
            ChangeBatch=batch,
        )
        print(f"DELETE ok {fqdn} id={resp['ChangeInfo']['Id']}")
    except Exception as exc:  # noqa: BLE001 — idempotent cleanup
        msg = str(exc)
        if "not found" in msg.lower() or "NoSuchHostedZone" in msg:
            print(f"DELETE noop (missing): {fqdn}")
        else:
            # DELETE requires exact match; if record missing, AWS returns InvalidChangeBatch
            if "InvalidChangeBatch" in msg or "not exist" in msg.lower():
                print(f"DELETE noop (absent): {fqdn}")
            else:
                raise
    return fqdn


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("action", choices=("upsert", "delete", "hostname"))
    p.add_argument("--vcluster-name", required=True)
    p.add_argument("--zone-id", default=os.environ.get("UAT_DNS_ZONE_ID", DEFAULT_ZONE_ID))
    p.add_argument("--zone-name", default=os.environ.get("UAT_DNS_ZONE", DEFAULT_ZONE_NAME))
    p.add_argument("--alb-dns", default=os.environ.get("UAT_ALB_DNS", DEFAULT_ALB_DNS))
    p.add_argument(
        "--alb-zone-id",
        default=os.environ.get("UAT_ALB_HOSTED_ZONE_ID", DEFAULT_ALB_ZONE_ID),
    )
    p.add_argument("--region", default=os.environ.get("AWS_REGION", "us-west-2"))
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    if args.action == "hostname":
        print(public_hostname(args.vcluster_name, args.zone_name))
        return 0

    fn = upsert if args.action == "upsert" else delete
    fqdn = fn(
        vcluster_name=args.vcluster_name,
        zone_id=args.zone_id,
        zone_name=args.zone_name,
        alb_dns=args.alb_dns,
        alb_zone_id=args.alb_zone_id,
        region=args.region,
        dry_run=args.dry_run,
    )
    # Always emit for GHA step outputs / cleanup env.
    print(f"hostname={fqdn}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
