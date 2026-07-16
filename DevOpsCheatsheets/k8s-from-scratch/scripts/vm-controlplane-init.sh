#!/bin/bash
set -euo pipefail

# Drop any stale join artifacts from a previous cluster (synced folder survives destroy).
sudo rm -f /vagrant/join-command.sh /vagrant/join-ready

# apiserver audit log path requires the directory to exist before kubeadm init.
sudo mkdir -p /var/log/kubernetes

# --- OIDC (IdP-agnostic): load placeholders; bake into ClusterConfiguration ---
# Source of truth is kubeadm ClusterConfiguration apiServer.extraArgs — not
# hand-edited static Pod manifests. Values survive destroy/recreate with this script.
OIDC_ENV="/vagrant/k8s/oidc/placeholders.env"
if [[ ! -f "${OIDC_ENV}" ]]; then
  OIDC_ENV="/vagrant/k8s/oidc/placeholders.env.example"
fi
# shellcheck disable=SC1090
set -a
source "${OIDC_ENV}"
set +a

: "${OIDC_ISSUER_URL:=https://oidc.example.invalid/realms/REPLACE_ME}"
: "${OIDC_CLIENT_ID:=kubernetes}"
: "${OIDC_USERNAME_CLAIM:=email}"
: "${OIDC_GROUPS_CLAIM:=groups}"
: "${OIDC_USERNAME_PREFIX:=oidc:}"
: "${OIDC_GROUPS_PREFIX:=oidc:}"
: "${OIDC_CA_FILE:=/etc/kubernetes/pki/oidc-ca.crt}"

# Placeholder CA so --oidc-ca-file exists before a real IdP is plugged in.
if [[ ! -f "${OIDC_CA_FILE}" ]]; then
  sudo mkdir -p "$(dirname "${OIDC_CA_FILE}")"
  if [[ -f /vagrant/k8s/oidc/apiserver/generated/oidc-ca.crt ]]; then
    sudo cp /vagrant/k8s/oidc/apiserver/generated/oidc-ca.crt "${OIDC_CA_FILE}"
  else
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
      -subj "/CN=oidc-placeholder-ca" \
      -keyout /tmp/oidc-ca.key \
      -out /tmp/oidc-ca.crt 2>/dev/null
    sudo mv /tmp/oidc-ca.crt "${OIDC_CA_FILE}"
    rm -f /tmp/oidc-ca.key
  fi
  sudo chmod 644 "${OIDC_CA_FILE}"
fi

# Write config to a fixed path. Vagrant shell provisions often run as root;
# a bare "kubeadm.config" / "~/kubeadm.config" land in different homes and break init.
KUBEADM_CONFIG="/home/vagrant/kubeadm.config"

cat <<EOF | tee "${KUBEADM_CONFIG}"
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "192.168.56.101"
  bindPort: 6443
nodeRegistration:
  name: "controlplane"
  kubeletExtraArgs:
    - name: node-ip
      value: "192.168.56.101"

---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: "v1.36.2"
controlPlaneEndpoint: "192.168.56.101:6443"
apiServer:
  extraArgs:
    - name: "enable-admission-plugins"
      value: "NodeRestriction"
    - name: "audit-log-path"
      value: "/var/log/kubernetes/audit.log"
    - name: "oidc-issuer-url"
      value: "${OIDC_ISSUER_URL}"
    - name: "oidc-client-id"
      value: "${OIDC_CLIENT_ID}"
    - name: "oidc-username-claim"
      value: "${OIDC_USERNAME_CLAIM}"
    - name: "oidc-groups-claim"
      value: "${OIDC_GROUPS_CLAIM}"
    - name: "oidc-username-prefix"
      value: "${OIDC_USERNAME_PREFIX}"
    - name: "oidc-groups-prefix"
      value: "${OIDC_GROUPS_PREFIX}"
    - name: "oidc-ca-file"
      value: "${OIDC_CA_FILE}"
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
chown vagrant:vagrant "${KUBEADM_CONFIG}"

# Only init if this node hasn't already been initialized
if [ ! -f /etc/kubernetes/admin.conf ]; then
  echo "Running kubeadm init..."
  kubeadm init --config "${KUBEADM_CONFIG}"
else
  echo "kubeadm already initialized, skipping init."
fi

# Set up kubeconfig for the vagrant user (and for this provision, often running as root)
mkdir -p /home/vagrant/.kube
cp -f /etc/kubernetes/admin.conf /home/vagrant/.kube/config
chown vagrant:vagrant /home/vagrant/.kube/config
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl get po -n kube-system
kubectl get --raw='/readyz?verbose'
kubectl cluster-info
# Allow scheduling on the control plane in this lab
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

# Fresh join command for workers (do NOT run join on this node).
# Atomic write + join-ready flag so workers never pick up a stale/partial file.
kubeadm token create --print-join-command | tee /vagrant/join-command.sh.tmp >/dev/null
chmod +x /vagrant/join-command.sh.tmp
mv -f /vagrant/join-command.sh.tmp /vagrant/join-command.sh
echo "ready $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee /vagrant/join-ready >/dev/null
echo "Wrote /vagrant/join-command.sh for workers"
