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
|---|---|---|
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

## First-time setup on a new cluster

### Bootstrap Argo CD

Argo CD manages itself through `kubernetes/appsets/argocd-helm/appset-helm-argocd.yaml`, but something has to install it the first time. Install it once with Helm, using **the same chart version, release name and values as that appset**. Argo CD then takes over the existing resources when the appset syncs.

Run these from the repo root, with `kubectl` pointing at the new cluster:

```sh
APPSET=kubernetes/appsets/argocd-helm/appset-helm-argocd.yaml

# 1. Install Argo CD with the appset's own values and chart version
yq '.spec.template.spec.sources[0].helm.valuesObject' $APPSET > /tmp/argocd-values.yaml
helm install argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version "$(yq '.spec.template.spec.sources[0].targetRevision' $APPSET)" \
  -n argocd --create-namespace \
  -f /tmp/argocd-values.yaml \
  --set server.httproute.enabled=false   # Gateway API CRDs don't exist yet

# 2. Log in. There's no LoadBalancer IP until MetalLB is running, so port-forward
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl -n argocd port-forward svc/argocd-server 8080:80   # http://localhost:8080, user admin

# 3. Hand everything over to GitOps
kubectl apply -f kubernetes/argo-root.yaml

# 4. Once the "argocd" Application shows Synced, delete Helm's record of the release
kubectl -n argocd delete secret -l owner=helm,name=argocd
```

Why it's done this way:

- **The release name must be `argocd`.** It has to match the Application the appset generates, so Helm and Argo CD produce identical resource names and `app.kubernetes.io/instance` labels. Argo CD then takes over the existing resources instead of creating duplicates.
- **`httproute` is disabled only for the first install.** The HTTPRoute resource type doesn't exist until Envoy Gateway installs the Gateway API CRDs, and `helm install` would fail without it. Argo CD adds the HTTPRoute later, once those CRDs exist.
- **Step 4 makes Argo CD the only owner.** After it, never run `helm upgrade` on this release. Upgrade Argo CD by changing `targetRevision` and the values in the appset and committing.
- **`configs.clusterCredentials`** in the appset values registers this cluster in Argo CD as **`portland`**, the destination every appset targets. A fresh Argo CD only knows the cluster as `in-cluster`; without this, every generated Application fails with "cluster not found".
- **The `argocd` Application has no finalizer**, so deleting it never removes Argo CD itself.

Argo CD gets its `192.168.7.10` address once MetalLB is up. SSO via Keycloak works once Keycloak is running; until then, log in as `admin`.

**Recreate any Argo CD API tokens.** The new install signs tokens with a new key, so old tokens stop working. Generate a new token for Homepage with `argocd account generate-token --account homepage`.

### What happens when you apply `argo-root.yaml`

`kubernetes/argo-root.yaml` (the `registry` app) only syncs the ApplicationSets in `kubernetes/appsets/`. Each ApplicationSet then generates its own Application, and those sync independently and in parallel. They aren't part of the root app's sync, so **sync waves can't order one app against another**. A `sync-wave` annotation only orders resources inside a single app.

Instead of a fixed order, every app is set up to **keep retrying until whatever it depends on exists**:

- **`retry.limit: -1`** on every appset: retry forever, with backoff up to 5 minutes. With the old limit of 5, an app that started before its dependencies gave up and stayed failed until the next commit.
- **`SkipDryRunOnMissingResource=true`** on apps that use resource types installed by another app. Without it, Argo CD rejects the whole sync up front if any resource type is missing. With it, Argo applies everything it can, and the rest succeeds on a later retry.

  | App | Uses | Provided by |
  |---|---|---|
  | `cluster-resources` (`CLUSTER/`) | VaultConnection, VaultAuth, VaultStaticSecret | vault-secrets-operator |
  | `cluster-resources` (`CLUSTER/`) | Gateway, GatewayClass | envoy-gateway |
  | `cluster-resources` (`CLUSTER/`) | Certificate | cert-manager |
  | cnpg-cluster | Cluster, Database, ScheduledBackup | cnpg-operator |
  | cnpg-cluster | PodMonitor | kube-prometheus |
  | chartdb, homepage, keycloak, argocd, headlamp | HTTPRoute | envoy-gateway |
  | longhorn, trino | HTTPRoute, ServiceMonitor | envoy-gateway, kube-prometheus |
  | ingress-nginx, external-dns | ServiceMonitor | kube-prometheus |

  If you add an app that uses one of these resource types, add `SkipDryRunOnMissingResource=true` to its `syncOptions`.

- **Namespaces** are created by each app's own appset (`CreateNamespace=true`), not by `CLUSTER/namespaces/`. The VaultStaticSecrets in `CLUSTER/secrets/` live in those app namespaces, so they fail until the app has created its namespace, then succeed on the next retry. VSO also keeps retrying a VaultStaticSecret on its own, so it doesn't matter whether VaultAuth or Vault itself is ready first.

**Expect this on first boot:** many apps will show sync errors and retry for about 5–15 minutes before everything converges. That's normal. Look into an app only if it's still failing after that, or if its error isn't about a missing resource type or namespace.

Some things retrying can't fix:

- Vault starts sealed, and its secrets don't exist until you've run Terraform (steps 1–2 below). Until then, the VaultStaticSecrets stay unhealthy, and any app that needs one of their Secrets waits.

### Steps

1. **Let Argo CD deploy Vault**, then initialise and unseal it (once per new Vault):

   ```sh
   kubectl exec -n vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1
   kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key>
   ```

   Store the unseal key and root token in your password manager. No auto-unseal is configured, so Vault **comes back sealed whenever the pod restarts** and has to be unsealed again.

2. **Apply the Terraform:**

   ```sh
   cd terraform/vault
   export TF_VAR_vault_token=<root-token>
   terraform init
   terraform plan  -var-file=../terraform.tfvars
   terraform apply -var-file=../terraform.tfvars
   ```

3. **Check the sync.** Once VSO and the `cluster-resources` app are running, each VaultStaticSecret should report healthy:

   ```sh
   kubectl get vaultstaticsecrets -A
   kubectl describe vaultstaticsecret <name> -n <namespace>   # look for 403 / path errors
   ```

> **State:** state is local (`terraform.tfstate`, gitignored) and contains every secret value in plain text. Keep it somewhere safe and don't commit it. For a brand-new Vault, starting with no state is correct. To manage a Vault that already holds these resources without state, either `terraform import` them first or `apply` will fail with "already exists" errors.

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
