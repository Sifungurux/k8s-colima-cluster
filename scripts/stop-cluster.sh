#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# stop-cluster.sh – Stop (or delete) the k3d cluster and optionally Colima
#
# Usage:
#   ./scripts/stop-cluster.sh              # suspend cluster + stop Colima
#   ./scripts/stop-cluster.sh --delete     # permanently delete the cluster
#   ./scripts/stop-cluster.sh --delete --keep-colima  # delete cluster only
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

COLIMA_PROFILE="${COLIMA_PROFILE:-k8s}"
CLUSTER_NAME="${CLUSTER_NAME:-dev-cluster}"

YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${GREEN}[stop]${NC} $*"; }
warn()    { echo -e "${YELLOW}[stop]${NC} $*"; }
section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

DELETE=false
KEEP_COLIMA=false

for arg in "$@"; do
  case "$arg" in
    --delete)       DELETE=true ;;
    --keep-colima)  KEEP_COLIMA=true ;;
  esac
done

# ── 1. Handle cluster ─────────────────────────────────────────────────────────
section "k3d cluster (${CLUSTER_NAME})"

if ! k3d cluster list 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
  warn "No cluster named '${CLUSTER_NAME}' found – nothing to stop."
else
  if $DELETE; then
    warn "Deleting cluster '${CLUSTER_NAME}' (this removes all data)..."
    k3d cluster delete "${CLUSTER_NAME}"
    info "Cluster deleted."
  else
    info "Stopping cluster '${CLUSTER_NAME}' (state is preserved)..."
    k3d cluster stop "${CLUSTER_NAME}"
    info "Cluster stopped. Use 'make start' to resume."
  fi
fi

# ── 2. Handle Colima ──────────────────────────────────────────────────────────
section "Colima (profile: ${COLIMA_PROFILE})"

if $KEEP_COLIMA; then
  warn "Leaving Colima running (--keep-colima specified)."
else
  colima_status() { colima status "${COLIMA_PROFILE}" 2>&1 || true; }
  if colima_status | grep -q "Running"; then
    info "Stopping Colima profile '${COLIMA_PROFILE}'..."
    colima stop "${COLIMA_PROFILE}"
    info "Colima stopped."
  else
    warn "Colima profile '${COLIMA_PROFILE}' is not running."
  fi
fi

echo ""
info "Done. Run 'make start' to bring everything back up."
