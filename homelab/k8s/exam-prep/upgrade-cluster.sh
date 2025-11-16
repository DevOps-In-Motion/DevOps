### --- Steps to upgrade
## https://kubernetes.io/docs/tasks/administer-cluster/cluster-upgrade/

# --- At a high level, the steps you perform are:
#   - Upgrade the control plane
#   - Upgrade the nodes in your cluster
#   - Upgrade clients such as kubectl
#   - Adjust manifests and other resources based on the API changes that accompany the new Kubernetes version


### ----- Control Plane ----- ###

# see current versions
kubectl get node
kubectl version

# kubeadm upgrade -h
# check version
kubeadm version
# upgrade if needed
sudo apt-get install -y kubeadm
# check which versions of each service we can upgrade
kubeadm upgrade plan
kubectl drain controlplane --ignore-daemonsets
# upgrade the controlplane
sudo kubeadm upgrade apply 1.33.5
# allow scheduling 
kubectl uncordon controlplane

# upgrade kubelet and kubectl
apt-get install kubectl=1.33.3-1.1 kubelet=1.33.3-1.1
service kubelet restart




### ----- Node A ----- ###

ssh root@nodea
# do the same things as above
./kubeadm-upgrade

apt-get install kubeadm=1.33.3-1.1
kubeadm upgrade node

# can be a different version for you
apt-get install kubelet=1.33.3-1.1

service kubelet restart

# You should manually update the control plane following this sequence:

#  #  etcd (all instances)
#  #  kube-apiserver (all control plane hosts)
#  #  kube-controller-manager
#  #  kube-scheduler
#  #  cloud controller manager, if you use one

### ----- ETCD Upgrade - Manual way ----- ###
# https://github.com/etcd-io/etcd/releases
# backup ETCD
ETCDCTL_API=3 etcdctl snapshot save <backup-file> \
  --endpoints=<etcd-endpoint> \
  --cert=<path-to-cert> \
  --key=<path-to-key> \
  --cacert=<path-to-cacert>

# Download new ETCD release
sudo chmod +x download-etcd.sh && ./download-etcd.sh
sudo systemctl stop etcd  # For systemd-based systems
sudo mv /path/to/new/etcd /usr/local/bin/
sudo mv /path/to/new/etcdctl /usr/local/bin/
sudo systemctl start etcd

etcdctl version
etcdctl endpoint status --write-out=table
kubectl logs -n kube-system etcd-<node-name>


### ----- Kube-API Server ----- ###
sudo kubeadm upgrade apply <new-version>








# Once you have upgraded the cluster, remember to install the latest version of kubectl.