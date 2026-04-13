# Zabbix Helm Deployment Design

**Date:** 2026-04-13  
**Cluster:** `zabbix` (Colima + k3d, Apple Silicon, VZ hypervisor)  
**Goal:** Evaluate the best approach to deploying and maintaining a full Zabbix stack in Kubernetes.

---

## Context

This is a research/exploratory deployment on the local `zabbix` k3d cluster. The aim is to get a full Zabbix stack running, poke at it, and determine what works before committing to a production approach. Findings will inform how Zabbix is eventually deployed on real infrastructure.

---

## Approach

Direct Helm with Makefile targets. Fast iteration — change a value, re-run `make zabbix-install`. No extra tooling (no Flux, no Helmfile). Maps cleanly to a Flux `HelmRelease` later once the config is settled.

**Chart:** `zabbix-community/helm-zabbix`  
The most mature community chart. Bundles PostgreSQL as a Bitnami subchart — no separate DB chart needed. Supports all Zabbix components.

---

## Components

| Component | Enabled | Mode |
|---|---|---|
| `zabbixServer` | Yes | 1 replica |
| `zabbixWeb` | Yes | 1 replica (Nginx) |
| `zabbixProxy` | Yes | 1 replica, active mode |
| `zabbixAgent` | Yes | DaemonSet |
| `postgresql` | Yes | Bitnami subchart, 1 replica, 5Gi PVC |

**Database:** PostgreSQL (recommended for Zabbix — better performance, TimescaleDB support).

---

## Repository Structure

```
k8s-colima-cluster/
└── helmfiles/
    └── zabbix/
        ├── values.yaml     # component config, DB settings, resource limits
        └── secrets.yaml    # DB passwords + Zabbix admin credentials (gitignored)
```

All resources deployed to the `zabbix` namespace.

---

## Access

No ingress controller — port-forward only for this exploratory phase. The `zabbix` k3d cluster maps `8080→80` on agent nodes; this can be used for ingress later if needed.

`make zabbix-status` prints the port-forward command for the web frontend.

---

## Makefile Targets

| Target | Description |
|---|---|
| `make zabbix-install` | Add Helm repo + `helm upgrade --install` (idempotent) |
| `make zabbix-uninstall` | `helm uninstall` + delete namespace |
| `make zabbix-status` | Pod/service overview + port-forward command |

Variables (overridable via env):

| Variable | Default |
|---|---|
| `ZABBIX_NAMESPACE` | `zabbix` |
| `ZABBIX_RELEASE` | `zabbix` |

---

## Credentials

`helmfiles/zabbix/secrets.yaml` is gitignored. Required keys documented as comments in `values.yaml`. If the file is missing, `helm upgrade --install` fails with a clear error.

---

## Out of Scope (for now)

- Ingress controller — add once config is stable
- Flux HelmRelease — graduate to this after exploration
- HA / multiple replicas — single replicas for exploration
- TimescaleDB extension — can be enabled later on PostgreSQL
