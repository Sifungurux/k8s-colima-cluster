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
COLIMA_PROFILE  ?= k8s
CLUSTER_NAME    ?= dev-cluster
SCRIPTS_DIR     := scripts

export COLIMA_PROFILE
export CLUSTER_NAME

# ── Phony targets ─────────────────────────────────────────────────────────────
.PHONY: help setup start stop delete restart reset status logs kubeconfig clean

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
