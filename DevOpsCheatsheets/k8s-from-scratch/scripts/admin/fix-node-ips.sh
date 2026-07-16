#!/usr/bin/env bash
# Admin (from Mac): fix VirtualBox NAT node IPs → host-only 192.168.56.x
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

pin_node_ip() {
  local vm="$1" ip="$2"
  echo "==> ${vm}: kubelet --node-ip=${ip}"
  vagrant ssh "${vm}" -c "echo 'KUBELET_EXTRA_ARGS=--node-ip=${ip}' | sudo tee /etc/default/kubelet >/dev/null && sudo systemctl restart kubelet"
}

pin_node_ip controlplane 192.168.56.101
pin_node_ip worker1 192.168.56.102
if vagrant ssh worker2 -c 'ip -4 addr show eth1 2>/dev/null | grep -q 192.168.56'; then
  pin_node_ip worker2 192.168.56.103
else
  echo "==> worker2: no 192.168.56.x on eth1 yet — run: vagrant reload worker2 --provision"
fi

echo "==> Apply Calico Installation"
vagrant ssh controlplane -c 'kubectl apply -f /vagrant/k8s/admin/calico-installation.yaml'
vagrant ssh controlplane -c 'kubectl delete node vagrant --ignore-not-found'

echo "==> Restart CRI-O + kubelet on controlplane"
vagrant ssh controlplane -c 'sudo mkdir -p /etc/crio/crio.conf.d
printf "%s\n" "[crio.network]" "cni_default_network = \"k8s-pod-network\"" "network_dir = \"/etc/cni/net.d/\"" "plugin_dirs = [\"/opt/cni/bin/\"]" | sudo tee /etc/crio/crio.conf.d/20-cni-default.conf >/dev/null
sudo chmod 644 /etc/cni/net.d/*.conflist /etc/cni/net.d/calico-kubeconfig 2>/dev/null || true
sudo systemctl restart crio; sleep 2; sudo systemctl restart kubelet'

vagrant ssh controlplane -c 'kubectl wait --for=condition=Ready nodes --all --timeout=300s || kubectl get nodes -o wide'
vagrant ssh controlplane -c 'kubectl -n cert-manager rollout restart deploy/cert-manager deploy/cert-manager-cainjector deploy/cert-manager-webhook || true'
echo "Done (admin). nginx-deployer can run: make app"
