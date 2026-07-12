#!/bin/bash
set -euo pipefail

cat <<EOF | sudo tee kubeadm.config
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "192.168.56.101"
  bindPort: 6443
nodeRegistration:
  name: "controlplane"

---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: "v1.36.0"
controlPlaneEndpoint: "192.168.56.101:6443"
apiServer:
  extraArgs:
    - name: "enable-admission-plugins"
      value: "NodeRestriction"
    - name: "audit-log-path"
      value: "/var/log/kubernetes/audit.log"
controllerManager:
  extraArgs:
    - name: "node-cidr-mask-size"
      value: "24"
scheduler:
  extraArgs:
    - name: "leader-elect"
      value: "true"
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
  dnsDomain: "cluster.local"

---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: "systemd"
syncFrequency: "1m"

---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "ipvs"
conntrack:
  maxPerCore: 32768
  min: 131072
  tcpCloseWaitTimeout: "1h"
  tcpEstablishedTimeout: "24h"

EOF

CONTROL_PLANE_IP="192.168.56.101"


# Only init if this node hasn't already been initialized
if [ ! -f /etc/kubernetes/admin.conf ]; then
  echo "Running kubeadm init..."
  sudo kubeadm init --config ~/kubeadm.config
else
  echo "kubeadm already initialized, skipping init."
fi

# Set up kubeconfig for the vagrant user
mkdir -p /home/vagrant/.kube
sudo cp -f /etc/kubernetes/admin.conf /home/vagrant/.kube/config
sudo chown vagrant:vagrant /home/vagrant/.kube/config

kubectl get po -n kube-system
kubectl get --raw='/readyz?verbose'
kubectl cluster-info 
# Taint the control plane node so that pods can be scheduled on it
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# Always regenerate a fresh join command and share it via the synced folder
# (tokens expire after 24h, so regenerating on every provision run is safer
# than reusing a possibly-stale one)
sudo kubeadm token create --print-join-command | sudo tee join-command.sh
sudo chmod +x join-command.sh
sudo ./join-command.sh