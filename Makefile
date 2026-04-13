# ──────────────────────────────────────────────────────────────────────────────
# Makefile – k8s-colima-cluster
#
# Targets
#   make setup     Install prerequisites via Homebrew
#   make start     Start Colima + create/resume the k3d cluster
#   make stop      Suspend the cluster and stop Colima
#   make delete    Permanently delete the cluster (preserves Colima)
#   make restart   stop → start
#   make reset     Fully delete and recreate the cluster
#   make status    Show current state of Colima and the cluster
#   make logs      Tail k3d node container logs
#   make kubeconfig  Print the kubeconfig merge command
#   make clean     stop --delete + remove generated files
# ──────────────────────────────────────────────────────────────────────────────

SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

# ── Configuration (override via env or CLI) ───────────────────────────────────
# Set CLUSTER=<name> to use a different cluster config from config/<name>/
# e.g. CLUSTER=staging make start
CLUSTER         ?= dev-cluster
COLIMA_PROFILE  ?= $(CLUSTER)
CLUSTER_NAME    ?= $(CLUSTER)
SCRIPTS_DIR     := scripts

export COLIMA_PROFILE
export CLUSTER_NAME

# ── Phony targets ─────────────────────────────────────────────────────────────
.PHONY: help setup start stop delete restart reset status logs kubeconfig clean flux-bootstrap flux-status flux-reconcile zabbix-install zabbix-uninstall zabbix-status

help: ## Show this help message
	@echo ""
	@echo "  k8s-colima-cluster – 1 control-plane + 2 worker nodes via k3d on Colima"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@echo ""

setup: ## Install prerequisites (colima, docker, k3d, kubectl, helm)
	@bash $(SCRIPTS_DIR)/setup.sh

start: ## Start Colima and bring up the cluster
	@bash $(SCRIPTS_DIR)/start-cluster.sh

stop: ## Suspend the cluster and stop Colima (state preserved)
	@bash $(SCRIPTS_DIR)/stop-cluster.sh

delete: ## Delete the cluster permanently (Colima keeps running)
	@bash $(SCRIPTS_DIR)/stop-cluster.sh --delete --keep-colima

restart: stop start ## Full stop then start

reset: ## Delete and recreate the cluster from scratch
	@bash $(SCRIPTS_DIR)/start-cluster.sh --reset

status: ## Show Colima + cluster + node status
	@bash $(SCRIPTS_DIR)/status.sh

logs: ## Tail logs from all k3d node containers
	@docker --host "unix://$${HOME}/.colima/$(COLIMA_PROFILE)/docker.sock" \
		logs -f $$(docker --host "unix://$${HOME}/.colima/$(COLIMA_PROFILE)/docker.sock" \
			ps --filter "name=k3d-$(CLUSTER_NAME)" -q) 2>&1 | head -200 || \
		echo "No running k3d containers found."

kubeconfig: ## Print command to export the kubeconfig for this cluster
	@echo "export KUBECONFIG=\$$(k3d kubeconfig write $(CLUSTER_NAME))"

clean: ## Delete the cluster and remove any generated artifacts
	@bash $(SCRIPTS_DIR)/stop-cluster.sh --delete
	@rm -f /tmp/k3d-$(CLUSTER_NAME).yaml
	@echo "Clean complete."

# ── Flux GitOps ───────────────────────────────────────────────────────────────
FLUX_GITOPS_DIR ?= $(HOME)/development/k8s-fleet
GITHUB_USER     ?= $(shell git -C $(FLUX_GITOPS_DIR) remote get-url origin 2>/dev/null | sed 's|.*github.com[:/]\([^/]*\)/.*|\1|')

flux-bootstrap: ## Bootstrap Flux onto the cluster (GITHUB_USER=<user> make flux-bootstrap)
	@GITHUB_USER="$(GITHUB_USER)" CLUSTER="$(CLUSTER_NAME)" CLUSTER_CONTEXT="k3d-$(CLUSTER_NAME)" \
		bash $(FLUX_GITOPS_DIR)/bootstrap/bootstrap.sh

flux-status: ## Show status of all Flux resources
	@flux get all -A

flux-reconcile: ## Force Flux to reconcile all kustomizations now
	@flux reconcile kustomization infrastructure --timeout=2m
	@flux reconcile kustomization apps --timeout=2m

# ── Zabbix ────────────────────────────────────────────────────────────────────
ZABBIX_NAMESPACE ?= zabbix
ZABBIX_RELEASE   ?= zabbix
ZABBIX_VALUES    := helmfiles/zabbix/values.yaml
ZABBIX_SECRETS   := helmfiles/zabbix/secrets.yaml

zabbix-install: ## Install or upgrade the Zabbix Helm release
	@helm repo add zabbix-community https://zabbix-community.github.io/helm-zabbix 2>/dev/null || true
	@helm repo update zabbix-community
	@kubectl create namespace $(ZABBIX_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@helm upgrade --install $(ZABBIX_RELEASE) zabbix-community/zabbix \
		--namespace $(ZABBIX_NAMESPACE) \
		--values $(ZABBIX_VALUES) \
		--values $(ZABBIX_SECRETS) \
		--wait --timeout 5m
	@echo "[zabbix] Patching 'Zabbix server' host agent interface port (chart bug: initialises to 10052 instead of 10050)..."
	@kubectl exec -n $(ZABBIX_NAMESPACE) $(ZABBIX_RELEASE)-postgresql-0 -- \
		psql -U zabbix -d zabbix -c \
		"UPDATE interface SET port='10050' WHERE hostid=(SELECT hostid FROM hosts WHERE host='Zabbix server') AND type=1;" \
		2>/dev/null && echo "[zabbix] Interface port corrected." || echo "[zabbix] WARN: could not patch interface port — fix manually in frontend."

zabbix-uninstall: ## Uninstall Zabbix and delete the namespace
	@helm uninstall $(ZABBIX_RELEASE) --namespace $(ZABBIX_NAMESPACE) || true
	@kubectl delete namespace $(ZABBIX_NAMESPACE) --ignore-not-found

zabbix-status: ## Show Zabbix pods, services, and port-forward command
	@echo ""
	@echo "Pods:"
	@kubectl get pods -n $(ZABBIX_NAMESPACE)
	@echo ""
	@echo "Services:"
	@kubectl get svc -n $(ZABBIX_NAMESPACE)
	@echo ""
	@echo "To access the Zabbix frontend:"
	@echo "  kubectl port-forward svc/$(ZABBIX_RELEASE)-zabbix-web 8888:80 -n $(ZABBIX_NAMESPACE)"
	@echo "  Then open: http://localhost:8888"
	@echo "  Default credentials: Admin / zabbix"
