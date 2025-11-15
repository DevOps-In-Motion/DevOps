kubectl create clusterrolebinding kubiya-service-account-access \
  --clusterrole=cluster-admin \
  --serviceaccount=kubiya:kubiya-service-account


# enable tasks_v2_enabled feature flag