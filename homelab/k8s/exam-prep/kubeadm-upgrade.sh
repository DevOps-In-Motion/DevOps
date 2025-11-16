
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