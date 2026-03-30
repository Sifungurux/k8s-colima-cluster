#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# start-cluster.sh – Start Colima (Docker runtime) then bring up the k3d cluster
#
# Usage:
#   ./scripts/start-cluster.sh            # use defaults
#   ./scripts/start-cluster.sh --reset    # delete any existing cluster first
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

COLIMA_PROFILE="${COLIMA_PROFILE:-k8s}"
CLUSTER_NAME="${CLUSTER_NAME:-dev-cluster}"
COLIMA_CONFIG="${PROJECT_ROOT}/config/colima.yaml"
K3D_CONFIG="${PROJECT_ROOT}/config/k3d-cluster.yaml"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${GREEN}[start]${NC} $*"; }
warn()    { echo -e "${YELLOW}[start]${NC} $*"; }
section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }
error()   { echo -e "${RED}[start]${NC} $*" >&2; exit 1; }

RESET=false
for arg in "$@"; do
  [[ "$arg" == "--reset" ]] && RESET=true
done

# ── 1. Pre-flight checks ──────────────────────────────────────────────────────
section "Pre-flight checks"
command -v colima  &>/dev/null || error "colima not found. Run scripts/setup.sh first."
command -v docker  &>/dev/null || error "docker not found. Run scripts/setup.sh first."
command -v k3d     &>/dev/null || error "k3d not found. Run scripts/setup.sh first."
command -v kubectl &>/dev/null || error "kubectl not found. Run scripts/setup.sh first."
info "All prerequisites found."

# ── 2. Start Colima ───────────────────────────────────────────────────────────
section "Colima (profile: ${COLIMA_PROFILE})"

colima_status() { colima status "${COLIMA_PROFILE}" 2>&1 || true; }

if colima_status | grep -q "Running"; then
  info "Colima profile '${COLIMA_PROFILE}' is already running."
else
  # Colima reads its config from ~/.colima/<profile>/colima.yaml
  # Copy our project config there before first start (non-destructive: skip if already exists)
  COLIMA_PROFILE_DIR="${HOME}/.colima/${COLIMA_PROFILE}"
  mkdir -p "${COLIMA_PROFILE_DIR}"
  if [ ! -f "${COLIMA_PROFILE_DIR}/colima.yaml" ]; then
    info "Installing Colima config to ${COLIMA_PROFILE_DIR}/colima.yaml"
    cp "${COLIMA_CONFIG}" "${COLIMA_PROFILE_DIR}/colima.yaml"
  else
    warn "Config already exists at ${COLIMA_PROFILE_DIR}/colima.yaml – leaving it unchanged."
    warn "To apply project config changes, delete that file and re-run."
  fi

  info "Starting Colima with profile '${COLIMA_PROFILE}'..."
  colima start "${COLIMA_PROFILE}" --edit=false
  info "Colima started."
fi

# Point Docker CLI at Colima's socket
export DOCKER_HOST="unix://${HOME}/.colima/${COLIMA_PROFILE}/docker.sock"
info "DOCKER_HOST=${DOCKER_HOST}"

# Quick sanity check
docker info --format '{{.ServerVersion}}' &>/dev/null \
  || error "Cannot reach Docker daemon at ${DOCKER_HOST}"
info "Docker daemon reachable ($(docker info --format '{{.ServerVersion}}'))."

# ── 3. Optionally delete existing cluster ─────────────────────────────────────
if $RESET; then
  section "Resetting existing cluster"
  if k3d cluster list | grep -q "${CLUSTER_NAME}"; then
    warn "Deleting existing cluster '${CLUSTER_NAME}'..."
    k3d cluster delete "${CLUSTER_NAME}"
  else
    warn "No existing cluster named '${CLUSTER_NAME}' – nothing to delete."
  fi
fi

# ── 4. Create k3d cluster ─────────────────────────────────────────────────────
section "k3d cluster (${CLUSTER_NAME})"

if k3d cluster list 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
  info "Cluster '${CLUSTER_NAME}' already exists."
  info "Starting it if stopped..."
  k3d cluster start "${CLUSTER_NAME}" 2>/dev/null || true
else
  info "Creating cluster '${CLUSTER_NAME}' (1 server + 2 agents)..."
  # Resolve absolute path for the manifests volume – Docker does not accept relative paths
  MANIFESTS_DIR="$(cd "${PROJECT_ROOT}/manifests" && pwd)"
  DOCKER_HOST="${DOCKER_HOST}" k3d cluster create \
    --config "${K3D_CONFIG}" \
    --volume "${MANIFESTS_DIR}:/var/lib/rancher/k3s/server/manifests/custom@all"
  info "Cluster created."
fi

# ── 5. Verify cluster ─────────────────────────────────────────────────────────
section "Cluster verification"

KUBECONFIG_CONTEXT="k3d-${CLUSTER_NAME}"
info "Switching kubectl context to '${KUBECONFIG_CONTEXT}'..."
kubectl config use-context "${KUBECONFIG_CONTEXT}" 2>/dev/null \
  || warn "Could not switch context – it may already be set."

info "Waiting for all nodes to be Ready..."
kubectl wait node --all --for=condition=Ready --timeout=120s

echo ""
info "Node overview:"
kubectl get nodes -o wide

echo ""
info "System pods:"
kubectl get pods -n kube-system

echo ""
echo -e "${GREEN}✔  Cluster '${CLUSTER_NAME}' is up and healthy!${NC}"
echo ""
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo "  make status"
