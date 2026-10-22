# Fixing Vault 403 Permission Denied for CloudNativePG Backups

**Date:** 2026-02-26

## The Problem

The CloudNativePG dev cluster's `VaultStaticSecret` was failing to sync with a 403 error:

```
Failed to read Vault secret: Error making API request.
URL: GET http://vault.vault.svc.cluster.local:8200/v1/kv/data/rustfs/cloudnativepg-dev-backup
Code: 403. Errors: * permission denied
```

The CNPG cluster couldn't start because it depended on S3 backup credentials that were supposed to be synced from Vault into a Kubernetes secret.

## Root Causes

Digging into the Vault Secrets Operator (VSO) controller logs revealed three distinct issues:

### 1. Quoted wildcard in namespace binding

The `vso-role` Kubernetes auth role had `bound_service_account_namespaces` set to `"*"` (a literal string with quotes) instead of `*` (the actual wildcard). This meant no namespace actually matched, and the VSO login was rejected with `namespace not authorized`.

### 2. Wrong policy name on the auth role

The role's `token_policies` was set to `["rustfs"]` -- a policy that didn't exist. The actual policy was named `rustfs-read`. Even if login succeeded, the token would have had no permissions.

### 3. Missing secret in Vault

The `VaultStaticSecret` was configured to read from `rustfs/cloudnativepg-dev-backup`, but that secret path didn't exist in Vault. Only `rustfs/cloudnativepg` had been created previously.

## The Fix

We used Terraform to declaratively manage the Vault configuration and bring it into a correct state.

### Step 1: Import existing Vault resources into Terraform state

Since the KV engine, Kubernetes auth, policy, and role already existed in Vault (configured via the UI), we imported them so Terraform could manage them without recreating from scratch:

```bash
terraform import vault_mount.kv kv
terraform import vault_auth_backend.kubernetes kubernetes
terraform import vault_policy.rustfs_read rustfs-read
terraform import vault_kubernetes_auth_backend_role.vso_role auth/kubernetes/role/vso-role
terraform import vault_kubernetes_auth_backend_config.config auth/kubernetes/config
```

### Step 2: Apply the correct configuration

`terraform apply` then reconciled the differences:

- **Fixed** `bound_service_account_namespaces` from `"*"` to `*`
- **Fixed** `token_policies` from `rustfs` to `rustfs-read`
- **Created** the missing secret at `rustfs/cloudnativepg-dev-backup`
- **Set** the `rustfs-read` policy content to allow reads on `kv/data/rustfs/*`

### Step 3: Restart the VSO controller

The VSO controller was caching the failed auth state and had stopped retrying. A rollout restart cleared the cache:

```bash
kubectl rollout restart deployment -n vault-secrets-operator vault-secrets-operator-controller-manager
```

## Result

After the restart, the `VaultStaticSecret` immediately synced:

```
NAME                                    SYNCED   HEALTHY   READY
vault-rustfs-cloudnativepg-dev-backup   True     True      True
```

The CNPG dev cluster came up healthy with its backup credentials in place.

## Lessons Learned

- **Check the operator logs, not just the resource status.** The `describe` output showed a generic "permission denied" on the secret read, but the actual VSO logs revealed the real error was `namespace not authorized` on the login step -- a completely different issue.
- **Vault UI can introduce subtle quoting issues.** Setting a wildcard `*` in the UI resulted in a literal `"*"` string. Terraform caught and fixed this.
- **Use Terraform for Vault configuration.** Managing Vault through IaC makes misconfigurations visible in `terraform plan` and reproducible across environments. The `terraform import` workflow lets you adopt existing manual config without recreating it.
- **VSO caches auth failures aggressively.** If you fix the Vault-side config, you may need to restart the VSO controller to pick up the changes.
