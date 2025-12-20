# Multi-Tenant Kubernetes SRE Runbook — Copy/Paste Reference

################################################################################
# SECTION 1: Cluster Upgrade (Kubernetes/EKS Control Plane & Node Groups)
################################################################################

# 1. Set your kubeconfig
export KUBECONFIG="/path/to/your/kubeconfig"

# 2. Check current control plane and node version
kubectl version --short
kubectl get nodes -o wide

# 3. (EKS only) List managed node groups (requires eksctl)
eksctl get nodegroup --kubeconfig "$KUBECONFIG"

# 4. Review cluster health before making changes
kubectl get cs                    # For Kubernetes API health (if enabled)
kubectl get componentstatuses     # Deprecated but may still be present
kubectl get pods -A | grep -v Running
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# 5. (DRY RUN) Examine what's currently running
kubectl get deploy,sts,ds -A
kubectl get job,cronjob -A

# 6. Review planned upgrades:
#   - Ensure your cloud provider supports your target version.
#   - Know your current control plane and node versions.
#   - Read the cloud provider's release notes for deprecations and requirements.

# 7. Initiate the Cluster Upgrade (EKS example—do not run blindly):
#     (Double check version compatibility, IAM permissions, and backups first.)
eksctl upgrade cluster --name <your-eks-cluster> --approve
# OR via AWS Console: navigate to "EKS Clusters > Update"

# 8. Node Group Upgrade (EKS example):
eksctl upgrade nodegroup --cluster <your-eks-cluster> --name <nodegroup> --kubernetes-version <target-version>

# 9. Upgrade Monitoring:
kubectl get nodes -o wide
kubectl get events -A | grep -i "upgrade"
kubectl get pods -A | grep -v Running
kubectl get deployment -A

# 10. Clean up old nodegroups if using rolling node upgrades (EKS managed):
# (After migrations/cordoning are proven successful)
# eksctl delete nodegroup ...

################################################################################
# SECTION 2: Rollback Kubernetes Deployment to Previous Revision
################################################################################

# 1. List revision history of your deployment:
kubectl -n <namespace> rollout history deployment/<deployment-name>

# 2. Identify the revision to which you want to rollback
# (Output from previous command will show revision numbers)

# 3. Rollback to previous or specific revision:
#   - Latest previous revision:
kubectl -n <namespace> rollout undo deployment/<deployment-name>
#   - To specific revision (number):
kubectl -n <namespace> rollout undo deployment/<deployment-name> --to-revision=<revisionNumber>

# 4. Monitor rollout status for progress and errors:
kubectl -n <namespace> rollout status deployment/<deployment-name>
kubectl -n <namespace> get pods -o wide

# 5. (Optional) Troubleshoot failed rollout:
kubectl -n <namespace> describe deployment <deployment-name>
kubectl -n <namespace> get events | tail -20

################################################################################
# SECTION 3: Pod Debugging Procedure
################################################################################

# 1. Describe the pod for conditions/events:
kubectl -n <namespace> describe pod <pod-name>

# 2. Get recent logs (last 100 lines):
kubectl -n <namespace> logs <pod-name> --tail=100

# 3. If the pod is restarting, see the previous container logs:
kubectl -n <namespace> logs <pod-name> --previous

# 4. Exec into the pod shell (if the container has /bin/sh):
kubectl -n <namespace> exec -it <pod-name> -- sh

# 5. For /bin/bash (if sh not available):
kubectl -n <namespace> exec -it <pod-name> -- bash

# 6. List events in the namespace, sorted by most recent:
kubectl -n <namespace> get events --sort-by='.lastTimestamp' | tail -20

# 7. List pod conditions and container statuses directly:
kubectl -n <namespace> get pod <pod-name> -o jsonpath='{.status.containerStatuses}'

################################################################################
# SECTION 4: RBAC — Check Effective Permissions for Users or Service Accounts
################################################################################

# 1. List what a ServiceAccount can do in a namespace:
kubectl -n <namespace> auth can-i --as=system:serviceaccount:<namespace>:<serviceaccount-name> --list

# 2. List permissions for a user (as known to Kubernetes API):
kubectl -n <namespace> auth can-i --as=<username> --list

# 3. Interactively check if ServiceAccount or User can perform a specific action:
# (e.g., create pods)
kubectl -n <namespace> auth can-i create pods --as=system:serviceaccount:<namespace>:<serviceaccount-name>
kubectl -n <namespace> auth can-i delete deployments --as=<username>

# 4. Debug RBAC for a request (show allowed/denied, and role source):
kubectl auth can-i --as=<username> get pods -n <namespace> --verbose

# 5. List all Roles and RoleBindings in the namespace:
kubectl -n <namespace> get roles,rolebindings

################################################################################
# SECTION 5: Safety, Advanced, and Pre-Flight Checks
################################################################################

# 1. Confirm kubeconfig context is what you expect:
kubectl config current-context
kubectl config get-contexts

# 2. View resource usage (CPU/memory) by namespace or node:
kubectl top pod -A
kubectl top node

# 3. Cordon/Drain nodes before disruptive upgrades:
kubectl drain <node> --ignore-daemonsets --delete-local-data
kubectl cordon <node>

# 4. Backup etcd (for control plane upgrades, if self-managed clusters only):
# (Adjust paths and authentication as sane to your setup!)
ETCDCTL_API=3 etcdctl snapshot save snapshot.db --endpoints=https://127.0.0.1:2379 --cacert=<ca.pem> --cert=<cert.pem> --key=<key.pem>

################################################################################
# END OF RUNBOOK
################################################################################

# NOTE:
# - Replace all <placeholders> above with your actual cluster, namespace, deployment, pod etc.
# - All commands are intended to be copied, one at a time, with necessary context/variable substitution and safety in mind.
# - Read and adapt for your own environment, especially during upgrades and rollbacks, as some steps are provider- or environment-specific.
