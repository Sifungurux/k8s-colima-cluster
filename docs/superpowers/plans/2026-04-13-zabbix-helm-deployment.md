# Zabbix Helm Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy a full Zabbix stack (server, web frontend, proxy, agent, PostgreSQL) to the local `zabbix` k3d cluster using the `zabbix-community/helm-zabbix` chart, driven by Makefile targets.

**Architecture:** Direct Helm install with a `values.yaml` for component config and a gitignored `secrets.yaml` for credentials. Three Makefile targets handle install/upgrade, teardown, and status. No ingress — access via `kubectl port-forward`.

**Tech Stack:** Helm 3, `zabbix-community/helm-zabbix` chart, PostgreSQL 16 (bundled subchart), Zabbix 7.0 LTS (ubuntu image), kubectl, GNU Make.

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `helmfiles/zabbix/values.yaml` | Create | All chart values — components, DB, agent mode |
| `helmfiles/zabbix/secrets.yaml` | Create | DB password (gitignored, never committed) |
| `helmfiles/zabbix/secrets.yaml.example` | Create | Template for secrets.yaml — committed |
| `.gitignore` | Modify | Add `helmfiles/zabbix/secrets.yaml` |
| `Makefile` | Modify | Add `zabbix-install`, `zabbix-uninstall`, `zabbix-status` targets |

---

## Task 1: Scaffold helmfiles/zabbix/ and gitignore secrets

**Files:**
- Create: `helmfiles/zabbix/` (directory)
- Modify: `.gitignore`

- [ ] **Step 1: Add secrets.yaml to .gitignore**

Open `.gitignore` and add:

```
.DS_Store
helmfiles/zabbix/secrets.yaml
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore zabbix secrets file"
```

---

## Task 2: Write helmfiles/zabbix/values.yaml

**Files:**
- Create: `helmfiles/zabbix/values.yaml`

- [ ] **Step 1: Create the values file**

Create `helmfiles/zabbix/values.yaml` with this content:

```yaml
# Zabbix Helm Chart Values
# Chart: zabbix-community/helm-zabbix
# Docs:  https://github.com/zabbix-community/helm-zabbix
#
# Credentials go in secrets.yaml (gitignored). Required keys:
#   postgresAccess.password

# Zabbix version — 7.0 LTS
zabbixImageTag: ubuntu-7.0.16

# ── Database access ─────────────────────────────────────────────────────────
# password is set in secrets.yaml
postgresAccess:
  user: "zabbix"
  database: "zabbix"

# ── PostgreSQL (bundled subchart) ────────────────────────────────────────────
postgresql:
  enabled: true
  image:
    repository: postgres
    tag: "16"
  persistence:
    enabled: true
    storageSize: 5Gi

# ── Zabbix Server ────────────────────────────────────────────────────────────
zabbixServer:
  enabled: true
  replicaCount: 1

# ── Zabbix Web Frontend ──────────────────────────────────────────────────────
zabbixWeb:
  enabled: true
  replicaCount: 1
  # port 8080 is the chart default for the container

# ── Zabbix Proxy (active mode) ───────────────────────────────────────────────
zabbixProxy:
  enabled: true
  replicaCount: 1
  ZBX_PROXYMODE: 0                      # 0 = active, 1 = passive
  ZBX_HOSTNAME: zabbix-proxy
  ZBX_SERVER_HOST: zabbix-zabbix-server # <release>-zabbix-server (ClusterIP service)
  ZBX_SERVER_PORT: 10051

# ── Zabbix Agent (DaemonSet — one agent per node) ────────────────────────────
zabbixAgent:
  enabled: true
  runAsSidecar: false
  runAsDaemonSet: true
  ZBX_SERVER_HOST: 0.0.0.0/0
  ZBX_PASSIVE_ALLOW: true
  ZBX_ACTIVE_ALLOW: false
```

- [ ] **Step 2: Commit**

```bash
git add helmfiles/zabbix/values.yaml
git commit -m "feat: add Zabbix Helm values"
```

---

## Task 3: Write secrets files

**Files:**
- Create: `helmfiles/zabbix/secrets.yaml` (gitignored)
- Create: `helmfiles/zabbix/secrets.yaml.example` (committed)

- [ ] **Step 1: Create secrets.yaml.example**

Create `helmfiles/zabbix/secrets.yaml.example`:

```yaml
# Copy this file to secrets.yaml and fill in values before running make zabbix-install.
# secrets.yaml is gitignored and must never be committed.
postgresAccess:
  password: "changeme"
```

- [ ] **Step 2: Create secrets.yaml**

Create `helmfiles/zabbix/secrets.yaml` (will not be committed):

```yaml
postgresAccess:
  password: "zabbix-local"
```

- [ ] **Step 3: Commit the example file**

```bash
git add helmfiles/zabbix/secrets.yaml.example
git commit -m "feat: add secrets.yaml example template"
```

---

## Task 4: Add Makefile targets

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Add Zabbix variables and targets to Makefile**

Append to `Makefile` after the `# ── Flux GitOps` section:

```makefile
# ── Zabbix ────────────────────────────────────────────────────────────────────
ZABBIX_NAMESPACE ?= zabbix
ZABBIX_RELEASE   ?= zabbix
ZABBIX_VALUES    := helmfiles/zabbix/values.yaml
ZABBIX_SECRETS   := helmfiles/zabbix/secrets.yaml

.PHONY: zabbix-install zabbix-uninstall zabbix-status

zabbix-install: ## Install or upgrade the Zabbix Helm release
	@helm repo add zabbix-community https://zabbix-community.github.io/helm-zabbix 2>/dev/null || true
	@helm repo update zabbix-community
	@kubectl create namespace $(ZABBIX_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@helm upgrade --install $(ZABBIX_RELEASE) zabbix-community/zabbix \
		--namespace $(ZABBIX_NAMESPACE) \
		--values $(ZABBIX_VALUES) \
		--values $(ZABBIX_SECRETS) \
		--wait --timeout 5m

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
	@echo "  kubectl port-forward svc/$(ZABBIX_RELEASE)-zabbix-web 8888:8080 -n $(ZABBIX_NAMESPACE)"
	@echo "  Then open: http://localhost:8888"
	@echo "  Default credentials: Admin / zabbix"
```

Also add `zabbix-install zabbix-uninstall zabbix-status` to the existing `.PHONY` line.

- [ ] **Step 2: Commit**

```bash
git add Makefile
git commit -m "feat: add zabbix Makefile targets"
```

---

## Task 5: Install and verify

**Prerequisites:** The `zabbix` k3d cluster must be running (`CLUSTER=zabbix make start`).

- [ ] **Step 1: Confirm cluster context**

```bash
kubectl config current-context
```

Expected output: `k3d-zabbix`

- [ ] **Step 2: Run install**

```bash
CLUSTER=zabbix make zabbix-install
```

Expected: Helm waits for all pods to be ready (up to 5 minutes). Watch for any ImagePullBackOff or CrashLoopBackOff.

- [ ] **Step 3: Check status**

```bash
CLUSTER=zabbix make zabbix-status
```

Expected: All pods in `Running` or `Completed` state. Services listed include `zabbix-zabbix-web`.

- [ ] **Step 4: Open the frontend**

```bash
kubectl port-forward svc/zabbix-zabbix-web 8888:8080 -n zabbix
```

Open `http://localhost:8888` in a browser. Log in with `Admin` / `zabbix`.

- [ ] **Step 5: Verify proxy registered**

In the Zabbix frontend: Administration → Proxies. The `zabbix-proxy` entry should appear with status "Active".

---

## Known things to check if it fails

- **ImagePullBackOff on arm64:** Zabbix official images are multi-arch. If pulls fail, check `kubectl describe pod <pod> -n zabbix` for the exact error.
- **PostgreSQL PVC pending:** k3d uses the local-path provisioner by default — PVCs should bind automatically. If stuck, run `kubectl get pvc -n zabbix`.
- **Proxy not connecting:** The `ZBX_SERVER_HOST: zabbix-zabbix-server` must match the actual server service name. Verify with `kubectl get svc -n zabbix`.
- **Helm timeout:** If `--wait` times out, run `kubectl get pods -n zabbix` to see what's still starting and check logs with `kubectl logs <pod> -n zabbix`.
