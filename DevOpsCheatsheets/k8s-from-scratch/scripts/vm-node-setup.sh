#!/bin/bash
set -euo pipefail

sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg



# Keeps the swap off during reboot
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true
sudo apt-get update -y

# Modules required by Kubernetes + kube-proxy IPVS mode
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
sudo modprobe ip_vs
sudo modprobe ip_vs_rr
sudo modprobe ip_vs_wrr
sudo modprobe ip_vs_sh
sudo modprobe nf_conntrack

# Sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo swapoff -a
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true

# Userspace tools for kube-proxy IPVS mode
sudo apt-get install -y ipset ipvsadm



### CRI-O Runtime Installation

CRIO_VERSION="v1.36"
KUBERNETES_VERSION="v1.36"

# Install CRI-O Runtime
sudo apt-get update -y
sudo apt-get install -y software-properties-common curl apt-transport-https ca-certificates gnupg

sudo install -m 0755 -d /etc/apt/keyrings

# Add CRI-O apt repository
curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/Release.key |
  sudo gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/ /" |
  sudo tee /etc/apt/sources.list.d/cri-o.list

sudo apt-get update -y
sudo apt-get install -y cri-o

# Prefer Calico's network name once the CNI conflist is installed (avoids
# CRI-O sticking on "no CNI configuration file" after Calico lands).
sudo mkdir -p /etc/crio/crio.conf.d
cat <<EOF | sudo tee /etc/crio/crio.conf.d/20-cni-default.conf
[crio.network]
cni_default_network = "k8s-pod-network"
network_dir = "/etc/cni/net.d/"
plugin_dirs = ["/opt/cni/bin/"]
EOF

sudo systemctl daemon-reload
sudo systemctl enable crio --now
sudo systemctl start crio.service


### Crictl Installation
CRICTL_VERSION="v1.36.0"

# Detect architecture automatically (amd64 or arm64)
CRICTL_ARCH=$(dpkg --print-architecture)

# Install crictl
curl -LO "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-${CRICTL_ARCH}.tar.gz"
sudo tar zxvf "crictl-${CRICTL_VERSION}-linux-${CRICTL_ARCH}.tar.gz" -C /usr/local/bin
rm -f "crictl-${CRICTL_VERSION}-linux-${CRICTL_ARCH}.tar.gz"

# Configure crictl to use CRI-O socket
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/crio/crio.sock
image-endpoint: unix:///run/crio/crio.sock
timeout: 10
debug: false
EOF

### Install Kubeadm & Kubelet & Kubectl on all Nodes Installation

# Apply sysctl params without reboot
sudo sysctl --system

# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo systemctl enable --now kubelet

sudo apt-get install -y jq


apt-cache madison kubeadm | tac


KUBERNETES_INSTALL_VERSION="1.36.2-2.1"
sudo apt-get install -y kubelet="$KUBERNETES_INSTALL_VERSION" kubectl="$KUBERNETES_INSTALL_VERSION" kubeadm="$KUBERNETES_INSTALL_VERSION"



# Pin kubelet to the Vagrant host-only NIC (eth1 / 192.168.56.0/24).
# eth0 is VirtualBox NAT (10.0.2.15 on every VM) and breaks Calico + Service routing.
local_ip="$(ip --json addr show eth1 2>/dev/null | jq -r '.[0].addr_info[]? | select(.family == "inet") | .local' | head -1 || true)"
if [[ -z "${local_ip}" || "${local_ip}" == "null" ]]; then
  local_ip="$(ip -4 -o addr show scope global | awk '/192\.168\.56\./ {print $4}' | cut -d/ -f1 | head -1 || true)"
fi
if [[ -z "${local_ip}" ]]; then
  echo "error: no host-only IP on eth1 / 192.168.56.0/24 — check Vagrant private_network" >&2
  exit 1
fi

cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS=--node-ip=${local_ip}
EOF
echo "kubelet --node-ip=${local_ip}"

