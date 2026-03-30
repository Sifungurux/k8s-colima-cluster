#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# status.sh – Show the current state of Colima and the k3d cluster
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

COLIMA_PROFILE="${COLIMA_PROFILE:-k8s}"
CLUSTER_NAME="${CLUSTER_NAME:-dev-cluster}"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }
ok()      { echo -e "  ${GREEN}✔${NC} $*"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $*"; }
fail()    { echo -e "  ${RED}✘${NC} $*"; }

echo ""
echo -e "${CYAN}k8s-colima-cluster status${NC}"
echo "  Profile : ${COLIMA_PROFILE}"
echo "  Cluster : ${CLUSTER_NAME}"

# ── Colima ────────────────────────────────────────────────────────────────────
section "Colima"
if colima status "${COLIMA_PROFILE}" 2>/dev/null | grep -q "Running"; then
  ok "Colima is running"
  colima status "${COLIMA_PROFILE}" 2>/dev/null | grep -E "cpu|memory|disk|runtime" | sed 's/^/    /'
else
  fail "Colima is NOT running (start with: make start)"
fi

# ── Docker socket ─────────────────────────────────────────────────────────────
section "Docker"
DOCKER_HOST="unix://${HOME}/.colima/${COLIMA_PROFILE}/docker.sock"
if DOCKER_HOST="${DOCKER_HOST}" docker info &>/dev/null; then
  ok "Docker daemon reachable at ${DOCKER_HOST}"
  echo "    Server version: $(DOCKER_HOST="${DOCKER_HOST}" docker info --format '{{.ServerVersion}}' 2>/dev/null)"
else
  fail "Docker daemon NOT reachable (is Colima running?)"
fi

# ── k3d cluster ───────────────────────────────────────────────────────────────
section "k3d cluster"
if ! command -v k3d &>/dev/null; then
  fail "k3d not found – run scripts/setup.sh"
elif k3d cluster list 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
  CLUSTER_STATE=$(k3d cluster list 2>/dev/null | awk -v name="${CLUSTER_NAME}" '$1==name {print $4}')
  if [[ "${CLUSTER_STATE}" == *"running"* ]] || k3d cluster list 2>/dev/null | grep "${CLUSTER_NAME}" | grep -q "3/3"; then
    ok "Cluster '${CLUSTER_NAME}' exists"
  else
    warn "Cluster '${CLUSTER_NAME}' exists but may not be fully running"
  fi
  k3d cluster list 2>/dev/null | grep -E "NAME|${CLUSTER_NAME}" | sed 's/^/    /'
else
  fail "Cluster '${CLUSTER_NAME}' not found (create with: make start)"
fi

# ── Kubernetes nodes ──────────────────────────────────────────────────────────
section "Kubernetes nodes"
KUBECONFIG_CONTEXT="k3d-${CLUSTER_NAME}"
if kubectl config get-contexts "${KUBECONFIG_CONTEXT}" &>/dev/null; then
  if kubectl --context="${KUBECONFIG_CONTEXT}" get nodes &>/dev/null; then
    ok "API server reachable"
    echo ""
    kubectl --context="${KUBECONFIG_CONTEXT}" get nodes -o wide 2>/dev/null | sed 's/^/    /'
  else
    fail "API server not reachable (cluster may be stopped)"
  fi
else
  fail "kubeconfig context '${KUBECONFIG_CONTEXT}' not found"
fi

# ── Pods summary ──────────────────────────────────────────────────────────────
section "Pods (all namespaces)"
kubectl --context="${KUBECONFIG_CONTEXT}" get pods -A 2>/dev/null | sed 's/^/    /' || warn "Could not list pods"

echo ""
