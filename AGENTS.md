# AGENTS.md

Guidance for AI agents working in this repo (`home-ops`): a GitOps monorepo for a three-node Talos Linux Kubernetes cluster called **portland**. Cluster facts below were captured on 2026-10-10 and will drift. Verify with `kubectl` before relying on them.

## Cluster access: Portland only

**You only have access to the `portland` Kubernetes context.**

- Pass `--context portland` on every `kubectl`, `helm`, and `argocd` call. Don't rely on the current-context.
- `~/.kube/config` also holds other contexts (`dm-ma2-*`, `et-*`, `plat-ma2-*`). They are unrelated to this repo. **Never use them** without explicit permission from the user.
- Don't run `kubectl config use-context`.
- If a task seems to need another cluster, stop and ask.
- Stay in the directory where the session started. Use absolute paths and don't `cd` elsewhere.

## GitOps rules

- Argo CD is the source of truth. The root app `kubernetes/argo-root.yaml` syncs every ApplicationSet in `kubernetes/appsets/`, with `prune` and `selfHeal` on. Manual `kubectl apply/edit/patch` changes get reverted, so make changes in git.
- Never run `helm upgrade` on Argo CD. Change `kubernetes/appsets/argocd-helm/appset-helm-argocd.yaml` instead.
- Prefer read-only cluster operations (`get`, `describe`, `logs`, `top`). Ask before anything destructive or mutating (delete, scale, patch, drain, `talosctl` writes).
- **Git:** you may stage changes and draft commit messages and PR descriptions. Do not `git commit`, `git push`, or `gh pr create` until the user explicitly approves that action.
- Renovate (`renovate.json`) bumps chart and image versions via PRs. The `K8s Workflow` (`.github/workflows/k8s.yaml`) runs yamlfmt and a kubescape scan on `kubernetes/**`.
- Run `yamlfmt` (`.yamlfmt`) and `yamllint` (`.yamllint`) rather than hand-formatting YAML.

## Nodes

Three identical Dell OptiPlex 7060 Micro machines. All are **control-plane nodes with no taints**, so they also run workloads.

| Node        | IP          | Role          | CPU     | RAM   | Allocatable (CPU / RAM) | OS disk  |
| ----------- | ----------- | ------------- | ------- | ----- | ----------------------- | -------- |
| `kube-cp-1` | 192.168.7.1 | control-plane | 6 cores | ~16GB | 5950m / ~14.5GiB        | 1TB NVMe |
| `kube-cp-2` | 192.168.7.2 | control-plane | 6 cores | ~16GB | 5950m / ~14.5GiB        | 1TB NVMe |
| `kube-cp-3` | 192.168.7.3 | control-plane | 6 cores | ~16GB | 5950m / ~14.5GiB        | 1TB NVMe |

- Each node: amd64, 110 pod limit, about 997GB ephemeral storage.
- OS: Talos Linux v1.14.2, kernel 6.18.54-talos, containerd 2.3.6.
- Kubernetes: v1.37.1.
- Talos extensions (`servers/talos-cluster/schematic.yaml`): `iscsi-tools` and `util-linux-tools` (needed by Longhorn), and `intel-ucode`.
- Talos config: `servers/talos-cluster/` (`controlplane.yaml`, `patches/all-nodes.yaml`, per-node `patches/kube-cp-N.yaml`). Ansible inventory: `ansible/inventory.yaml`.
- **Capacity is tight.** At the last check, node memory use was 54–64% and CPU 18–25%. Mind resource requests and limits when adding workloads. Trino was recently reduced for this reason (see git log).
- 3x Raspberry Pi 5 (LXC) runs AdGuard Home for local DNS.

## Networking

- **MetalLB** pool `portland-pool`: `192.168.7.10–192.168.7.110`.
- **Envoy Gateway** is the primary ingress, using Gateway API. The shared `Gateway` `envoy-shared-gateway` (ns `envoy-gateway-system`, class `envoy-gatewayclass`) listens on 443 for `*.70ld.dev` at `192.168.7.13`. The wildcard TLS secret is `wildcard-70ld-tls`. Routes from all namespaces are allowed.
- **ingress-nginx** (`192.168.7.69`) still runs alongside it.
- **cert-manager** issues certificates through the `letsencrypt-cloudflare-dns-issuer` ClusterIssuer.
- **ExternalDNS** syncs records to AdGuard Home on the Pi.
- **Tailscale** operator provides remote connectivity.

Domain is `70ld.dev`. HTTPRoutes exist for `argocd`, `chartdb`, `registry`, `headlamp`, `homepage`, `keycloak`, `longhorn`, and `trino`.

Fixed LoadBalancer IPs:

| IP             | Service                                                    |
| -------------- | ---------------------------------------------------------- |
| 192.168.7.10   | Prometheus (`monitoring`)                                  |
| 192.168.7.11   | Envoy Gateway control plane                                |
| 192.168.7.12   | Vault (`vault`, 8200/8201)                                 |
| 192.168.7.13   | Shared Envoy Gateway (443)                                 |
| 192.168.7.14   | Argo CD server                                             |
| 192.168.7.15   | `ubuntu-vm` SSH (KubeVirt)                                 |
| 192.168.7.69   | ingress-nginx controller                                   |
| 192.168.7.80   | Postgres read-write (`cnpg-prod-cluster`, 5432)            |
| 192.168.7.81   | Trino (8080)                                               |
| 192.168.7.99   | pgAdmin (5050)                                             |

## Storage

- **Longhorn** is the storage backend. It uses one filesystem disk per node at `/var/lib/longhorn/`.
- StorageClasses: `longhorn` (default, Delete reclaim), `longhorn-kubevirt`, `longhorn-static`. All allow volume expansion.
- The `docker-registry` app and Loki also use Longhorn volumes.
- Backups: Velero and SeaweedFS ApplicationSets exist but are **commented out** (disabled).

## Secrets

- **HashiCorp Vault** is deployed in the cluster. Its config and secrets are managed as code in `terraform/vault/` (see its `README.md`).
- **Vault Secrets Operator** syncs secrets into the cluster as `VaultStaticSecret` resources, in `kubernetes/clusters/portland/CLUSTER/secrets/`.
- Never commit secret values. Don't print secrets from the cluster or from `terraform.tfstate*`.

## What's running

Namespaces and their Argo CD applications (all `Synced/Healthy` at last check, except `airflow`, which was `OutOfSync` and has a local uncommitted change).

| Area          | App (namespace)                             | How it's deployed                    |
| ------------- | ------------------------------------------- | ------------------------------------ |
| GitOps        | Argo CD (`argocd`)                          | Helm, self-managed, v3.5.3           |
| Ingress / LB  | Envoy Gateway (`envoy-gateway-system`)      | Helm `gateway-helm` v1.9.1           |
|               | ingress-nginx (`ingress-nginx`)             | Helm 4.11.1                          |
|               | MetalLB (`metallb-system`)                  | Manifests                            |
|               | Tailscale (`tailscale`)                     | Manifests                            |
|               | ExternalDNS (`external-dns`)                | Helm 1.22.0                          |
| Certificates  | cert-manager (`cert-manager`)               | Helm 1.19.1                          |
| Storage       | Longhorn (`longhorn-system`)                | Helm 1.12.1                          |
| Secrets       | Vault (`vault`)                             | Helm 0.32.0                          |
|               | Vault Secrets Operator                      | Helm 1.3.0                           |
| Database      | CloudNativePG operator (`cnpg-system`)      | Manifests                            |
|               | `cnpg-prod-cluster`: 3 instances, PG 18.4, 8Gi on Longhorn | Manifests             |
|               | pgAdmin (`pgadmin`)                         | Manifests                            |
| Observability | kube-prometheus-stack (`monitoring`)        | Helm 79.4.1                          |
|               | Alertmanager config and rules (`monitoring`) | Manifests                           |
|               | Loki and Alloy (`logging`)                  | Helm 7.3.0 and 1.13.0                |
| Data          | Trino (`trino`)                             | Helm 1.42.2                          |
|               | Airflow (`airflow`)                         | Helm 1.22.0                          |
| Identity      | Keycloak (`keycloak`)                       | Manifests, OIDC provider             |
| Virtualization | KubeVirt (`kubevirt`), CDI (`cdi`)         | Manifests                            |
|               | `ubuntu-vm` (`kubevirt-vms`), 1 core, 2Gi   | Manifests                            |
| Apps / UI     | Headlamp (`headlamp`)                       | Helm 0.45.0, OIDC login              |
|               | Homepage (`homepage`)                       | Manifests                            |
|               | ChartDB (`chartdb`)                         | Manifests                            |
|               | Atuin (`atuin`)                             | Manifests                            |
|               | Docker registry (`docker-registry`)         | Manifests                            |
| Other         | Minecraft server (manifests in `apps/minecraft-server`; no appset) | Manifests     |

Other namespaces: `cron-jobs`, `dev` (created by `CLUSTER/namespaces`), `kubelet-serving-cert-approver`.

## Repo layout

```
kubernetes/
  argo-root.yaml            # root app-of-apps
  appsets/<app>/            # one ApplicationSet per app
  clusters/portland/
    apps/<app>/             # plain manifests for non-Helm apps
    CLUSTER/                # cluster-wide: namespaces, gateway-api, secrets, role bindings
terraform/vault/            # Vault config as code
servers/talos-cluster/      # Talos machine config, patches, image schematic
ansible/                    # inventory for the nodes
docker/                     # Minecraft images
docs/                       # plans, fixes, learnings
```

### Adding or changing an app

- **Helm apps** (`appsets/<name>-helm/appset-helm-<name>.yaml`): the chart, version, and values are inline under `helm.valuesObject`. There are no separate `values.yaml` files.
- **Manifest apps** (`appsets/<name>/appset-<name>.yaml`): the ApplicationSet points at `kubernetes/clusters/portland/apps/<name>`. Add the plain manifests there.
- Cluster-wide resources go in `kubernetes/clusters/portland/CLUSTER/`.
- See `README.md` for the generator and bootstrap details. Past incident write-ups are in `docs/` (`kubevirt-*.md`, `vault-cnpg-403-fix.md`, `authentik-vault-db-password-fix.md`, `plans/`).

## Debugging checklist

Check the simple causes first:

1. `kubectl --context portland get applications -n argocd` for sync and health.
2. `kubectl --context portland get pods -A | grep -v Running` for failing pods.
3. `kubectl --context portland get events -A --sort-by=.lastTimestamp` for scheduling, PVC, and probe errors.
4. `kubectl --context portland top nodes` for resource pressure. Memory is the likely constraint.
5. Check that you're in the right repo and that any local binary or config is current.
