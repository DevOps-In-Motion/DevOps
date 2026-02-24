# GKE high availability
gcloud container node-pools update <NODE_POOL_NAME> \
  --region=<REGION> \
  --cluster=<CLUSTER_NAME> \
  --enable-autoscaling \
  --min-nodes=<MIN_NODES> \
  --max-nodes=<MAX_NODES>
