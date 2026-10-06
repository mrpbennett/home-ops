# Vault (Terraform)

`vault-setup.tf` is the source of truth for everything in Vault that the cluster depends on:

- the `kv` (KV v2) secrets engine
- Kubernetes auth plus the `vso-role` role used by the Vault Secrets Operator (VSO)
- one read policy per app
- the secrets themselves, with values supplied from `../terraform.tfvars`

**Manage Vault by editing this file, not the Vault UI or CLI.** If you add or change a secret here and run `terraform apply`, the change is recorded in code, it's repeatable, and a new cluster gets an identical Vault. Changes made by hand in the UI aren't tracked, are lost when the cluster is rebuilt, and are overwritten the next time Terraform applies.

## How it connects to the cluster

```
terraform.tfvars ──► vault-setup.tf ──► Vault kv/<path>
                                              │  (policy allows read, vso-role holds the policy)
                                              ▼
       kubernetes/clusters/portland/CLUSTER/secrets/<app>/*.yaml   (VaultStaticSecret)
                                              │  VSO syncs it every 60s
                                              ▼
                              Kubernetes Secret ──► app (envFrom / secretKeyRef / mounted file)
```

- The VaultConnection and VaultAuth (`vault-auth`) are in `kubernetes/clusters/portland/CLUSTER/secrets/vault-connection.yaml`.
- Every VaultStaticSecret points at `vault-secrets-operator/vault-auth`.
- The **keys in each secret's `data_json` must match exactly what the app reads**, because VSO copies them into the Kubernetes Secret unchanged.

| Vault path | Kubernetes Secret (namespace) | Keys |
| --- | --- | --- |
| `alertmanager/discord` | `alertmanager-discord` (monitoring) | `alertmanager-critical`, `alertmanager-warning` (mounted as files) |
| `atuin/config` | `atuin-secret` (atuin) | `ATUIN_*` (envFrom) |
| `cloudnativepg/cnpg-cluster-user` | `cnpg-cluster-user` (cnpg-prod-cluster) | `username`, `password` (basic-auth) |
| `cloudnativepg/backup` | `cloudnativepg-backup-secret` (cnpg-prod-cluster) | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |
| `external-dns/adguard` | `adguard-configuration` (external-dns) | `url`, `user`, `password` |
| `headlamp` | `headlamp-oidc` (headlamp) | `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`, `OIDC_ISSUER_URL`, `OIDC_SCOPES` |
| `pgadmin/config` | `pgadmin-credentials` (pgadmin) | `email`, `password` |
| `seaweedfs/loki` | `seaweedfs-loki` (logging) | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (envFrom) |
| `trino` | `trino-secrets` (trino) | `TRINO_*` (envFrom, read as `${ENV:...}` in the Trino config) |

## Prerequisites

- Terraform. `mise install` in this directory installs it via `mise.toml`.
- Vault deployed by Argo CD (`kubernetes/appsets/vault-helm`) and reachable at the provider `address` in `vault-setup.tf`, currently `http://192.168.7.11:8200`. Update it if the Vault LoadBalancer IP changes.
- A Vault token with admin rights, passed as an environment variable so it never lands in a file:

  ```sh
  export TF_VAR_vault_token=<root-or-admin-token>
  ```

- Values in `../terraform.tfvars`. This file is gitignored and **never committed**. Every variable declared in `vault-setup.tf` needs a value; replace any `"CHANGEME"` placeholder before applying, or that text becomes the real secret.

## Day-to-day changes

**Change a secret value:** edit `../terraform.tfvars`, then `plan` and `apply`. VSO picks up the new version within `refreshAfter` (60s). Trino restarts automatically through `rolloutRestartTargets`; other apps may need a manual restart if they read the secret only at startup.

**Add a secret for a new app:**

1. Add a `vault_policy` that grants `read` on `kv/data/<app>/*`. Use the exact path instead of `/*` if the secret sits at `kv/<app>`.
2. Add the policy name to `token_policies` on `vault_kubernetes_auth_backend_role.vso_role`.
3. Add a `vault_kv_secret_v2` with `name = "<app>/<secret>"` and `data_json` keys matching what the app reads.
4. Declare a `variable` for each value (`sensitive = true` for anything secret).
5. Add the values to `../terraform.tfvars`.
6. Add a `VaultStaticSecret` under `kubernetes/clusters/portland/CLUSTER/secrets/<app>/`, with `vaultAuthRef: vault-secrets-operator/vault-auth`, `mount: kv`, `type: kv-v2`, the matching `path`, and the app's namespace.
7. `plan` and `apply`, then commit the `.tf` and manifest changes. Don't commit the tfvars.

## Things not to commit

`*.tfvars`, `*.tfstate*` and plan files (`tfplan`, `*.tfplan`). A saved plan file contains every input variable's value, including `vault_token`, in plain text. Use `terraform plan` without `-out`, or delete the plan file after applying it.
