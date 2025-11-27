### ----- Env Setup ----- ###
export  KUBE_EDITOR='nano'
alias k=kubectl


### ----- Monitoring Containers ----- ###
kubectl top pods


### ----- Cheat codes ----- ###
# change an env for deployment
## https://weaviate.io/blog/gomemlimit-a-game-changer-for-high-memory-applications
kubectl set env deployment/<your-deployment-name> GOMEMLIMIT="$(kubectl get deployment <your-deployment-name> -o=jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}')"
kubectl set env deployment/memhog GOMEMLIMIT=460MiB

