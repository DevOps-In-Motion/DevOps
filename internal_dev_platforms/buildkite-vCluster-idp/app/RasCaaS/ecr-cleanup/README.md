# Standalone CronJob image that deletes aged tags from ECR `uat-temp`.
# Not part of the RaSCaaS IDP pod or image.
#
# Build/push (also done by `.github/workflows/rascaas-build.yml`):
#   docker build -t "$ECR/rascaas-uat-ecr-cleanup:latest" .
#   docker push "$ECR/rascaas-uat-ecr-cleanup:latest"
#
# Helm: set `uatTempEcrCleanup.image` to that URI (see helm/_values/qa-install-values.yaml).
