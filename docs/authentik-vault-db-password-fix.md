# Fixing Authentik Database Authentication via Vault

**Date:** 2026-02-27

## The Problem

Authentik would not load after the `authentik-db` Database manifest was deleted and recreated. The app stayed in a `Progressing` state indefinitely, silently failing to connect to Postgres.

## Root Cause

A password mismatch between two independently managed systems:

| System | Password source | Value |
|---|---|---|
| CNPG `authentik` role | `cnpg-authentik-user` Kubernetes secret (Vault-managed) | `cZtqwu8slQgd` (example) |
| Authentik helm chart | Hardcoded in `authentik-helm.yaml` | `authentikpassword` |

The CNPG cluster manages the `authentik` Postgres role via `cnpg-prod-cluster.yaml:66`:

```yaml
- name: authentik
  ensure: present
  login: true
  superuser: true
  passwordSecret:
    name: cnpg-authentik-user
```

The `cnpg-authentik-user` secret is populated by the Vault Secrets Operator (VSO) from the Vault path `cloudnativepg/prod/authentik` (see `apps/cnpg-cluster/prod/secrets/vault-static-secrets.yaml`). Vault is the source of truth for the password.

Meanwhile, the Authentik helm chart had the password hardcoded:

```yaml
postgresql:
  password: authentikpassword  # wrong — not what Vault/CNPG uses
```

When the Database manifest was recreated, CNPG re-applied the Vault-managed password to the `authentik` role. Authentik never knew the real password and could not authenticate.

## Why It Seemed Like "Caching"

It wasn't caching. The DB role password was always being set from Vault. Authentik was always using the hardcoded value. They simply never matched — and deleting/recreating the DB manifest made no difference to either side.

## The Fix

### 1. Sync the Vault secret into the `authentik` namespace

The `cnpg-authentik-user` secret lives in the `cnpg-prod-cluster` namespace. Authentik runs in the `authentik` namespace and cannot reference cross-namespace secrets directly.

Created `apps/authentik/vault-secret.yaml` with a `VaultConnection`, `VaultAuth`, and `VaultStaticSecret` that pulls the same Vault path (`cloudnativepg/prod/authentik`) and creates a `authentik-db-credentials` secret in the `authentik` namespace.

Created `registry/authentik-secrets.yaml` — a new ArgoCD Application (sync-wave `-1`) pointing at `apps/authentik/` so it deploys before the authentik helm chart.

### 2. Remove the hardcoded password from the helm chart

The authentik helm chart (`registry/helm/authentik/authentik-helm.yaml`) does not natively support `existingSecret` for the postgresql password. Instead, authentik reads its config from environment variables using a double-underscore naming convention (`AUTHENTIK_POSTGRESQL__PASSWORD`).

Changed `authentik.postgresql.password` to `""` and added a `global.env` block:

```yaml
global:
  env:
    - name: AUTHENTIK_POSTGRESQL__PASSWORD
      valueFrom:
        secretKeyRef:
          name: authentik-db-credentials
          key: password
```

The `global.env` key applies to all authentik components (server and worker). The env var overrides whatever the chart's own templated value would produce.

## Sync Order (ArgoCD Waves)

```
wave -1: authentik-secrets  →  VSO creates authentik-db-credentials secret
wave  0: authentik           →  helm chart deploys; pods find the secret ready
```

The sync-wave annotation on `authentik-secrets.yaml` ensures the secret exists before the Authentik pods try to start.

## Verification

After pushing, confirm the secret syncs in the authentik namespace:

```bash
kubectl get vaultstaticsecret -n authentik
kubectl get secret authentik-db-credentials -n authentik -o jsonpath='{.data.password}' | base64 -d
```

The decoded value should match what's in Vault at `cloudnativepg/prod/authentik`.

Then confirm Authentik connects:

```bash
kubectl logs -n authentik -l app.kubernetes.io/name=authentik-server --tail=50
```

Look for successful database migration/connection lines rather than `password authentication failed`.

## Lessons Learned

- **Hardcoded secrets in helm values are a liability.** Even if they worked initially, they silently diverge as Vault becomes the source of truth. Use `valueFrom.secretKeyRef` with VSO-synced secrets from the start.
- **Namespace boundaries require explicit secret replication.** Vault manages a single secret path, but VSO must create a `VaultStaticSecret` per namespace that needs access. The same Vault path can be referenced by multiple `VaultStaticSecret` resources in different namespaces.
- **The authentik helm chart has no `existingSecret` for postgresql.** Use `global.env` with `AUTHENTIK_POSTGRESQL__PASSWORD` as the env var name (double underscores map to nested config keys).
- **Deleting and recreating the Database manifest only affects the database object, not the role password.** The role password is managed by the CNPG `managed.roles` block on the Cluster resource, not the Database resource.
