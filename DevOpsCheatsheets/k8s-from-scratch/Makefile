# k8s-from-scratch — admin vs nginx-deployer
#
#   make up && make admin && make app && make browse
#   make share   # optional ngrok public URL

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

ROOT  := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
CP    := controlplane
ADMIN := /vagrant/scripts/admin
NGINX := /vagrant/scripts/nginx
K8S_A := /vagrant/k8s/admin

VSSH := cd "$(ROOT)" && vagrant ssh $(CP) -c

.DEFAULT_GOAL := help

.PHONY: help admin app up context wait-nodes cni label-nodes metrics \
	ns-rbac platform-tls user cert-manager metallb gateway-api \
	check-nginx browse share oidc-render oidc-rbac oidc-policy \
	status context-host deployer-context destroy down

help:
	@echo "Bring-up (in order):"
	@echo "  make up               boot VMs + kubeadm join"
	@echo "  make admin            platform + RBAC + nginx-deployer identity"
	@echo "  make deployer-context merge/switch to nginx-deployer on Mac"
	@echo "  make app              deploy app AS nginx-deployer (not admin)"
	@echo "  make browse           https://localhost:8443/ (Vagrant SSH -L -> Gateway)"
	@echo ""
	@echo "Also:"
	@echo "  make context-host     merge admin kubeconfig on Mac (optional)"
	@echo "  make status           nodes + nginx-app resources"
	@echo "  make check-nginx      in-cluster nginx checks"
	@echo "  make share            optional: ngrok public HTTPS URL (needs ngrok auth)"
	@echo "  make oidc-render      optional: render kubeadm ClusterConfiguration OIDC"
	@echo "  make oidc-rbac        optional: apply OIDC group RBAC (needs placeholders)"
	@echo "  make oidc-policy      optional: Gatekeeper constraints (Gatekeeper required)"
	@echo "  make destroy"

admin: context cni wait-nodes label-nodes metrics cert-manager metallb gateway-api platform-tls ns-rbac user
	@echo ""
	@echo "=== Admin complete ==="
	@echo "Traffic: client → Gateway → HTTPRoute → Service → Pods"
	@echo ""
	@echo "  1) make deployer-context"
	@echo "  2) make app"
	@echo "  3) make browse"
	@echo "       # https://localhost:8443/ via Vagrant SSH tunnel → Gateway"
	@echo "  4) make share   # optional — ngrok public URL"
	@echo ""

app:
	@echo "==> Deploying app with nginx-deployer identity (not admin)"
	$(VSSH) 'bash $(NGINX)/apply-app.sh'

up:
	# Drop stale join artifacts (synced folder survives vagrant destroy).
	rm -f "$(ROOT)/join-command.sh" "$(ROOT)/join-ready"
	cd "$(ROOT)" && vagrant up

context:
	$(VSSH) 'kubectl cluster-info && kubectl get nodes'

context-host:
	bash "$(ROOT)/scripts/admin/get-context.sh"

cni: context
	$(VSSH) 'bash $(ADMIN)/install-cni.sh'
	# Operator must be up before Installation CR is useful (recreate race).
	$(VSSH) 'kubectl -n tigera-operator wait --for=condition=Available deploy --all --timeout=300s'
	$(VSSH) 'kubectl apply -f $(K8S_A)/calico-installation.yaml'
	$(VSSH) 'sudo mkdir -p /etc/crio/crio.conf.d; printf "%s\n" "[crio.network]" "cni_default_network = \"k8s-pod-network\"" "network_dir = \"/etc/cni/net.d/\"" "plugin_dirs = [\"/opt/cni/bin/\"]" | sudo tee /etc/crio/crio.conf.d/20-cni-default.conf >/dev/null; sudo systemctl restart crio; sleep 2; sudo systemctl restart kubelet'

wait-nodes: context
	$(VSSH) 'kubectl wait --for=condition=Ready nodes --all --timeout=600s'
	$(VSSH) 'kubectl get nodes -o wide'

label-nodes: wait-nodes
	$(VSSH) 'bash $(ADMIN)/label-nodes.sh'

metrics: wait-nodes
	$(VSSH) 'bash $(ADMIN)/install-metrics-server.sh'

cert-manager: wait-nodes
	$(VSSH) 'bash $(ADMIN)/install-cert-manager.sh'

metallb: wait-nodes
	$(VSSH) 'bash $(ADMIN)/install-metallb.sh'

gateway-api: wait-nodes metallb
	$(VSSH) 'bash $(ADMIN)/install-gateway-api.sh'

platform-tls: cert-manager gateway-api
	$(VSSH) 'kubectl -n cert-manager wait --for=condition=Available deploy/cert-manager-webhook --timeout=300s'
	$(VSSH) 'kubectl apply -f $(K8S_A)/cluster-issuers.yaml'
	$(VSSH) 'kubectl -n cert-manager wait --for=condition=Ready certificate/lab-root-ca --timeout=180s'
	$(VSSH) 'kubectl get clusterissuer,gatewayclass'

ns-rbac: wait-nodes
	$(VSSH) 'kubectl apply -f $(K8S_A)/nginx-ns-rolebinding.yaml'

user: ns-rbac
	$(VSSH) 'bash $(ADMIN)/issue-deployer.sh'
	@echo "Issued scripts/nginx/nginx-deployer.kubeconfig"

deployer-context:
	bash "$(ROOT)/scripts/admin/add-user-context.sh"

check-nginx:
	$(VSSH) 'bash $(NGINX)/check-nginx.sh'

browse:
	bash "$(ROOT)/scripts/nginx/browse.sh"

# Optional: public HTTPS link via ngrok (requires `ngrok` + authtoken on the Mac).
share:
	bash "$(ROOT)/scripts/nginx/share.sh"

# Optional OIDC (IdP-agnostic). Flags survive recreate via kubeadm init config.
oidc-render:
	bash "$(ROOT)/k8s/oidc/apiserver/render-kubeadm-oidc.sh"

oidc-rbac:
	bash "$(ROOT)/k8s/oidc/rbac/apply-rbac.sh"

oidc-policy:
	bash "$(ROOT)/k8s/oidc/policy/apply-policy.sh"

status:
	-$(VSSH) 'kubectl get nodes -o wide'
	-$(VSSH) 'kubectl -n nginx-app get deploy,pods,svc,gateway,httproute -o wide'
	-$(VSSH) 'kubectl get gatewayclass'

destroy down:
	# Drop host-side tunnel + deployer identity (new CA after recreate).
	@if [[ -f "$(ROOT)/scripts/nginx/.browse-ssh.pid" ]]; then \
		kill "$$(cat "$(ROOT)/scripts/nginx/.browse-ssh.pid" 2>/dev/null)" 2>/dev/null || true; \
	fi
	@if [[ -f "$(ROOT)/scripts/nginx/.ngrok.pid" ]]; then \
		kill "$$(cat "$(ROOT)/scripts/nginx/.ngrok.pid" 2>/dev/null)" 2>/dev/null || true; \
	fi
	rm -f "$(ROOT)/scripts/nginx/.browse-ssh.pid" \
		"$(ROOT)/scripts/nginx/.vagrant-worker1-ssh" \
		"$(ROOT)/scripts/nginx/.ngrok.pid" \
		"$(ROOT)/scripts/nginx/.ngrok.log" \
		"$(ROOT)/scripts/nginx/.ngrok-url" \
		"$(ROOT)/scripts/nginx/nginx-deployer.kubeconfig" \
		"$(ROOT)/scripts/nginx/nginx-deployer.key" \
		"$(ROOT)/scripts/nginx/nginx-deployer.crt" \
		"$(ROOT)/scripts/nginx/nginx-deployer.csr" \
		"$(ROOT)/scripts/nginx/cluster-ca.crt" \
		"$(ROOT)/scripts/nginx/lab-root-ca.crt" \
		"$(ROOT)/join-command.sh" "$(ROOT)/join-ready"
	cd "$(ROOT)" && vagrant destroy -f
	@echo "Destroyed. Recreate: make up && make admin && make deployer-context && make app && make browse"
