#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# setup.sh – Install all prerequisites via Homebrew
#
# Run once on a fresh machine before using start-cluster.sh.
# Safe to re-run; Homebrew skips already-installed packages.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[setup]${NC} $*"; }
warn()  { echo -e "${YELLOW}[setup]${NC} $*"; }
error() { echo -e "${RED}[setup]${NC} $*" >&2; exit 1; }

# ── Homebrew ──────────────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  error "Homebrew is not installed. Visit https://brew.sh and install it first."
fi
info "Homebrew found at $(brew --prefix)"

# ── Packages ──────────────────────────────────────────────────────────────────
PACKAGES=(
  colima          # macOS container runtime (Docker + Kubernetes via Lima VMs)
  docker          # Docker CLI (colima provides the daemon)
  k3d             # k3s-in-Docker multi-node cluster manager
  kubectl         # Kubernetes CLI
  helm            # Kubernetes package manager (optional but handy)
)

info "Installing / upgrading required packages..."
for pkg in "${PACKAGES[@]}"; do
  if brew list --formula "$pkg" &>/dev/null; then
    warn "$pkg already installed – skipping"
  else
    info "Installing $pkg..."
    brew install "$pkg"
  fi
done

# ── Version report ────────────────────────────────────────────────────────────
echo ""
info "Installed versions:"
colima  version 2>/dev/null | head -1 || true
docker  --version           || true
k3d     version             | head -1 || true
kubectl version --client --short 2>/dev/null || kubectl version --client || true
helm    version --short     || true

echo ""
info "Setup complete! Run 'make start' (or scripts/start-cluster.sh) to bring up the cluster."
