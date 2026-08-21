# RaSCaaS GitHub Actions

| Workflow | Purpose |
|----------|---------|
| [`uat-deploy.yml`](uat-deploy.yml) | UAT entrypoint (`workflow_dispatch` only): build variance → temp ECR → vCluster → Helm full stack |
| [`rascaas-build.yml`](rascaas-build.yml) | Build/push IDP image and `rascaas-uat-ecr-cleanup` (`workflow_dispatch` only) |

Helpers: [`../../workflows/rascaas/`](../../workflows/rascaas/). Project overview: [`../../README.md`](../../README.md).
