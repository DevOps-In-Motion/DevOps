# k8s-from-scratch — ordered cluster bring-up
#
# Cluster kubectl/helm commands run ON the controlplane VM via:
#   vagrant ssh controlplane -c '...'
# Repo is mounted at /vagrant inside every VM.
#
#   make help
#   make up && make all

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
CP   := controlplane

# Run a single shell command on the controlplane (cwd is the Vagrant project).
# Usage: $(call ssh_cp,kubectl get nodes)
ssh_cp = cd "$(ROOT)" && vagrant ssh $(CP) -c $(1)

.DEFAULT_GOAL := help

.PHONY: help all up context cni wait-nodes label-nodes metrics \
	ns-rbac user-key user-csr user-cert user-context user \
	cert-manager taint nginx ssl status context-host destroy down

help:
	@echo "Targets (run kubectl/helm on $(CP) via vagrant ssh -c):"
	@echo "  make up              1. vagrant up (controlplane + workers)"
	@echo "  make context         2. verify kubectl on controlplane"
	@echo "  make cni             3. Calico / Tigera + Installation"
	@echo "  make wait-nodes      4. wait until nodes are Ready"
	@echo "  make label-nodes     5. label worker1/worker2"
	@echo "  make metrics         6. metrics-server + dnsutils"
	@echo "  make ns-rbac         7. nginx-app Namespace / Role / RoleBinding"
	@echo "  make user            8. nginx-deployer cert + context (on VM)"
	@echo "  make cert-manager    9. Helm install cert-manager (on VM)"
	@echo "  make taint          10. taint workers for nginx HA"
	@echo "  make nginx          11. nginx Deployment + Service"
	@echo "  make ssl            12. ClusterIssuers, Certificate, Ingress"
	@echo "  make all             steps 2–12 (VMs already up)"
	@echo "  make status          nodes / nginx / cert-manager"
	@echo "  make context-host    optional: merge admin.conf into host ~/.kube"
	@echo "  make destroy         vagrant destroy -f"

all: context cni wait-nodes label-nodes metrics ns-rbac cert-manager taint nginx ssl
	@echo "Lab stack applied. Optional: make user"

# ---------------------------------------------------------------------------
# 1–2
# ---------------------------------------------------------------------------

up:
	cd "$(ROOT)" && vagrant up

context:
	$(call ssh_cp,'kubectl cluster-info && kubectl get nodes')

# Optional: pull admin kubeconfig onto the Mac for local kubectl
context-host:
	bash "$(ROOT)/scripts/get-context.sh"

# ---------------------------------------------------------------------------
# 3–6  Platform (CNI before anything that needs Ready nodes)
# ---------------------------------------------------------------------------

cni: context
	$(call ssh_cp,'bash /vagrant/scripts/install-cni.sh')
	$(call ssh_cp,'kubectl apply -f /vagrant/k8s/calico-installation.yaml')
	$(call ssh_cp,'kubectl -n tigera-operator wait --for=condition=Available deploy --all --timeout=300s || true')

wait-nodes: context
	$(call ssh_cp,'kubectl wait --for=condition=Ready nodes --all --timeout=600s')
	$(call ssh_cp,'kubectl get nodes -o wide')

label-nodes: wait-nodes
	$(call ssh_cp,'bash /vagrant/scripts/label-nodes.sh')

metrics: wait-nodes
	$(call ssh_cp,'bash /vagrant/scripts/install-metrics-server.sh')

# ---------------------------------------------------------------------------
# 7–8  App RBAC / deployer user (artifacts land in /vagrant/scripts)
# ---------------------------------------------------------------------------

ns-rbac: wait-nodes
	$(call ssh_cp,'kubectl apply -f /vagrant/k8s/nginx-ns-rolebinding.yaml')

user-key:
	$(call ssh_cp,'bash /vagrant/scripts/create-key-developer.sh')

user-csr: user-key
	$(call ssh_cp,'bash /vagrant/scripts/create-csr.sh')

user-cert: user-csr
	$(call ssh_cp,'bash /vagrant/scripts/post-csr.sh')

user-context: user-cert
	$(call ssh_cp,'bash /vagrant/scripts/add-user-context.sh')

user: ns-rbac user-context
	@echo "On controlplane: kubectl config use-context nginx-deployer-context"

# ---------------------------------------------------------------------------
# 9–12  cert-manager → taints → nginx → TLS ingress
# ---------------------------------------------------------------------------

cert-manager: wait-nodes
	$(call ssh_cp,'bash /vagrant/scripts/install-cert-manager.sh')

taint: wait-nodes
	$(call ssh_cp,'bash /vagrant/scripts/taint-nodes-ha.sh')

nginx: ns-rbac taint
	$(call ssh_cp,'kubectl apply -f /vagrant/k8s/nginx-webserver.yaml')
	$(call ssh_cp,'kubectl -n nginx-app rollout status deploy/nginx --timeout=180s')

ssl: cert-manager nginx
	$(call ssh_cp,'kubectl apply -f /vagrant/k8s/nginx-ssl-ing.yaml')
	$(call ssh_cp,'kubectl -n nginx-app get certificate,ingress,secret nginx-tls || true')

# ---------------------------------------------------------------------------
# Ops
# ---------------------------------------------------------------------------

status:
	-$(call ssh_cp,'kubectl get nodes -o wide')
	-$(call ssh_cp,'kubectl -n nginx-app get deploy,pods,svc,ingress,certificate -o wide')
	-$(call ssh_cp,'kubectl -n cert-manager get pods')
	-$(call ssh_cp,'helm list -n cert-manager || true')

destroy down:
	cd "$(ROOT)" && vagrant destroy -f
