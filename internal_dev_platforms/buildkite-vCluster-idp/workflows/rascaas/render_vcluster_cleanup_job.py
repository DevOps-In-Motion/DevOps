#!/usr/bin/env python3
"""Render a Kubernetes Job that waits for TTL then deletes a vCluster + ephemeral DNS."""

from __future__ import annotations

import argparse
from pathlib import Path
from string import Template


_JOB = Template("""apiVersion: batch/v1
kind: Job
metadata:
  name: $job_name
  namespace: $job_namespace
  labels:
    app.kubernetes.io/part-of: rascaas-uat
    app.kubernetes.io/component: vcluster-cleanup
spec:
  ttlSecondsAfterFinished: 86400
  backoffLimit: 2
  activeDeadlineSeconds: $active_deadline
  template:
    metadata:
      labels:
        app.kubernetes.io/part-of: rascaas-uat
        app.kubernetes.io/component: vcluster-cleanup
$sa_annotation
    spec:
$sa_name
      restartPolicy: Never
      containers:
        - name: cleanup
          image: $cleanup_image
          imagePullPolicy: IfNotPresent
          env:
            - name: TTL_SECONDS
              value: "$ttl_seconds"
            - name: VCLUSTER_NAME
              value: "$vcluster_name"
            - name: VCLUSTER_HOST_NAMESPACE
              value: "$vcluster_host_namespace"
            - name: HELM_RELEASE
              value: "$helm_release"
            - name: HELM_NAMESPACE
              value: "$helm_namespace"
            - name: UAT_DNS_ZONE_ID
              value: "$uat_dns_zone_id"
            - name: UAT_DNS_ZONE
              value: "$uat_dns_zone"
            - name: UAT_ALB_DNS
              value: "$uat_alb_dns"
            - name: UAT_ALB_HOSTED_ZONE_ID
              value: "$uat_alb_hosted_zone_id"
            - name: UAT_PUBLIC_HOSTNAME
              value: "$uat_public_hostname"
            - name: AWS_DEFAULT_REGION
              value: "$aws_region"
            - name: VCLUSTER_CLI_VERSION
              value: "$vcluster_cli_version"
          command:
            - /bin/sh
            - -ec
          args:
            - |
              set -euo pipefail
              echo "UAT cleanup: sleeping $${TTL_SECONDS}s then removing vCluster $${VCLUSTER_NAME}..."
              sleep "$${TTL_SECONDS}"

              if [ -n "$${UAT_PUBLIC_HOSTNAME}" ] && [ -n "$${UAT_DNS_ZONE_ID}" ]; then
                echo "Deleting ephemeral DNS $${UAT_PUBLIC_HOSTNAME}..."
                if command -v aws >/dev/null 2>&1; then
                  ALIAS="dualstack.$${UAT_ALB_DNS}."
                  case "$${UAT_ALB_DNS}" in dualstack.*) ALIAS="$${UAT_ALB_DNS}." ;; esac
                  CHANGE=$$(cat <<EOF
              {
                "Comment": "RaSCaaS UAT TTL cleanup delete $${UAT_PUBLIC_HOSTNAME}",
                "Changes": [{
                  "Action": "DELETE",
                  "ResourceRecordSet": {
                    "Name": "$${UAT_PUBLIC_HOSTNAME}.",
                    "Type": "A",
                    "AliasTarget": {
                      "HostedZoneId": "$${UAT_ALB_HOSTED_ZONE_ID}",
                      "DNSName": "$${ALIAS}",
                      "EvaluateTargetHealth": false
                    }
                  }
                }]
              }
              EOF
              )
                  aws route53 change-resource-record-sets \\
                    --hosted-zone-id "$${UAT_DNS_ZONE_ID}" \\
                    --change-batch "$${CHANGE}" \\
                    && echo "DNS delete ok" \\
                    || echo "DNS delete skipped/failed (record may already be gone; check IRSA)" >&2
                else
                  echo "aws CLI not in image — skip DNS delete for $${UAT_PUBLIC_HOSTNAME}" >&2
                fi
              fi

              if [ -f /vcluster-kubeconfig/config ]; then
                echo "Uninstalling Helm release $${HELM_RELEASE} in $${HELM_NAMESPACE} (inside vCluster)..."
                export KUBECONFIG=/vcluster-kubeconfig/config
                if command -v helm >/dev/null 2>&1; then
                  helm uninstall "$${HELM_RELEASE}" -n "$${HELM_NAMESPACE}" --wait --timeout 15m || true
                else
                  echo "helm not available in image; continuing with vCluster delete" >&2
                fi
              fi
              echo "Deleting vCluster $${VCLUSTER_NAME} on host namespace $${VCLUSTER_HOST_NAMESPACE}..."
              export KUBECONFIG=/host-kubeconfig/config
              if ! command -v vcluster >/dev/null 2>&1; then
                echo "Installing vcluster CLI $${VCLUSTER_CLI_VERSION}..."
                curl -fsSL -o /tmp/vcluster \\
                  "https://github.com/loft-sh/vcluster/releases/download/$${VCLUSTER_CLI_VERSION}/vcluster-linux-amd64"
                chmod +x /tmp/vcluster
                VCLUSTER_BIN=/tmp/vcluster
              else
                VCLUSTER_BIN=vcluster
              fi
              "$${VCLUSTER_BIN}" delete "$${VCLUSTER_NAME}" -n "$${VCLUSTER_HOST_NAMESPACE}" --force
          volumeMounts:
            - name: host-kubeconfig
              mountPath: /host-kubeconfig
              readOnly: true
            - name: vcluster-kubeconfig
              mountPath: /vcluster-kubeconfig
              readOnly: true
      volumes:
        - name: host-kubeconfig
          secret:
            secretName: $host_kubeconfig_secret
        - name: vcluster-kubeconfig
          secret:
            secretName: $vcluster_kubeconfig_secret
            optional: true
""")


def render_job(**kwargs: str | int) -> str:
    role = str(kwargs.pop("route53_role_arn", "") or "").strip()
    parts: list[str] = []
    if role:
        parts.append(
            f"""apiVersion: v1
kind: ServiceAccount
metadata:
  name: rascaas-uat-route53
  namespace: {kwargs['job_namespace']}
  labels:
    app.kubernetes.io/part-of: rascaas-uat
  annotations:
    eks.amazonaws.com/role-arn: {role}
---
"""
        )
        kwargs["sa_annotation"] = ""
        kwargs["sa_name"] = "      serviceAccountName: rascaas-uat-route53\n"
    else:
        kwargs["sa_annotation"] = ""
        kwargs["sa_name"] = ""
    parts.append(_JOB.substitute(kwargs))
    return "".join(parts)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--job-name", required=True)
    parser.add_argument("--job-namespace", required=True)
    parser.add_argument("--ttl-seconds", type=int, required=True)
    parser.add_argument("--vcluster-name", required=True)
    parser.add_argument("--vcluster-host-namespace", required=True)
    parser.add_argument("--helm-release", required=True)
    parser.add_argument("--helm-namespace", required=True)
    parser.add_argument("--host-kubeconfig-secret", required=True)
    parser.add_argument("--vcluster-kubeconfig-secret", required=True)
    parser.add_argument(
        "--cleanup-image",
        default="public.ecr.aws/aws-cli/aws-cli:2.15.17",
        help="Image with aws CLI (and curl) for DNS delete + vcluster download",
    )
    parser.add_argument("--vcluster-cli-version", default="v0.22.1")
    parser.add_argument("--uat-dns-zone-id", default="")
    parser.add_argument("--uat-dns-zone", default="uat.example.com")
    parser.add_argument("--uat-alb-dns", default="")
    parser.add_argument("--uat-alb-hosted-zone-id", default="Z1H1FL5HABSF5")
    parser.add_argument("--uat-public-hostname", default="")
    parser.add_argument("--aws-region", default="us-west-2")
    parser.add_argument(
        "--route53-role-arn",
        default="",
        help="Optional IRSA role ARN for Route53 delete (annotates Job pod)",
    )
    parser.add_argument("--output", type=Path, default=Path("-"))
    args = parser.parse_args()

    doc = render_job(
        job_name=args.job_name,
        job_namespace=args.job_namespace,
        ttl_seconds=args.ttl_seconds,
        active_deadline=args.ttl_seconds + 3600,
        vcluster_name=args.vcluster_name,
        vcluster_host_namespace=args.vcluster_host_namespace,
        helm_release=args.helm_release,
        helm_namespace=args.helm_namespace,
        host_kubeconfig_secret=args.host_kubeconfig_secret,
        vcluster_kubeconfig_secret=args.vcluster_kubeconfig_secret,
        cleanup_image=args.cleanup_image,
        vcluster_cli_version=args.vcluster_cli_version,
        uat_dns_zone_id=args.uat_dns_zone_id,
        uat_dns_zone=args.uat_dns_zone,
        uat_alb_dns=args.uat_alb_dns,
        uat_alb_hosted_zone_id=args.uat_alb_hosted_zone_id,
        uat_public_hostname=args.uat_public_hostname,
        aws_region=args.aws_region,
        route53_role_arn=args.route53_role_arn,
    )
    if str(args.output) == "-":
        print(doc)
    else:
        args.output.write_text(doc)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
