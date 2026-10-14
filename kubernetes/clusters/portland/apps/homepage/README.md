# Homepage dashboard

[Homepage](https://gethomepage.dev) for the `portland` cluster, served at `https://homepage.70ld.dev`.
Everything is config in one ConfigMap (`config-map.yaml`); Argo CD syncs this directory
(`kubernetes/appsets/homepage`). The `.md` file is ignored by Argo (it only reads yaml/json).

_Written 2026-10-14 after the dashboard overhaul. Re-verify against the cluster before relying on it._

## Layout

Two tabs, set in `settings.yaml` under `layout:` (group name → tab). Groups render in the
order they appear in `services.yaml`, so reorder there, not in `layout:`.

| Tab | Groups |
| --- | --- |
| **Overview** | Cluster Pulse, Needs Attention, Nodes, Shortcuts (bookmarks) |
| **Services** | Platform, Observability, Security, Data, Storage, Infra |

Group names in `layout:` must match `services.yaml` / `bookmarks.yaml` exactly, or the group
silently disappears.

### Overview

- **Cluster Pulse** – four stat tiles (no links), live from Prometheus:
  Workloads (running / unhealthy pods, restarts 1h, unavailable deployments),
  Alerts & Sync (critical / warning alerts, Argo apps out of sync / degraded),
  Capacity (CPU %, memory %, pod slots %, network in),
  Storage & Certs (Longhorn used %, degraded volumes, days to cert expiry, certs not ready).
- **Needs Attention** – the log/alert glance:
  Active Alerts (Alertmanager, Watchdog and InfoInhibitor filtered out),
  Errors by Namespace and Errors by Pod (top 5 by count of `error|fatal|panic` log lines in
  the last 15 minutes, queried from Loki).
- **Nodes** – `kube-cp-1/2/3`: CPU, memory, temp, network in, plus an ICMP ping dot.
- **Shortcuts** – GitHub repo, PRs, Actions, Grafana Explore, Talos docs.

### Services

Link cards for every app. In-cluster apps have:

- a **site dot** (`siteMonitor`) that probes the in-cluster Service URL directly, so it reflects
  the app and not DNS or the gateway;
- a **pod dot** (`namespace` + blank `podSelector`); click it for pod CPU / memory.

Widgets: Argo CD (app counts), Prometheus (targets), Registry (repo count), Vault (sealed /
initialized / version), PGAdmin card (CloudNativePG instances, connections, lag, size),
Longhorn card (healthy / degraded volumes, used, capacity), AdGuard (queries, blocked, ...).
The top bar has a greeting, the cluster-wide Kubernetes widget (node stats are hidden because
the Nodes group shows them), Longhorn totals and a clock.

Not deployed, so not shown: Airflow (commented out in `services.yaml`). Proxmox was removed.

## Data sources

All in-cluster, no auth, tested via `kubectl get --raw .../proxy/...`:

| Used for | URL |
| --- | --- |
| Stat tiles, node cards, Postgres/Longhorn cards | `http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090` |
| Active Alerts | `http://kube-prometheus-stack-alertmanager.monitoring.svc.cluster.local:9093/api/v2/alerts?...` |
| Error panels, Loki card | `http://loki-gateway.logging.svc.cluster.local/loki/api/v1/...` (no tenant header needed) |
| Longhorn info widget | `http://longhorn-frontend.longhorn-system.svc.cluster.local` (set under `providers:`) |
| Vault card | `http://vault.vault.svc.cluster.local:8200/v1/sys/health?...` |

Not available (checked, no metrics or endpoint): nginx / Envoy request rates, Velero backup age,
KubeVirt VM counts, etcd, Trino `/v1/cluster`. Don't build cards on those without fixing the
scrape first.

The Loki and Alertmanager URLs are URL-encoded and wrapped with `\` line continuations in the
ConfigMap (yamllint line limit). They parse back to the exact strings that were tested.

## Secrets

Credentials are not in git. The config uses `{{HOMEPAGE_VAR_*}}` placeholders that Homepage
fills from environment variables:

```
terraform.tfvars -> terraform/vault (kv/homepage) -> VaultStaticSecret homepage-secrets
  (CLUSTER/secrets/homepage/vault-secrets.yaml) -> Secret -> envFrom (optional) on the Deployment
```

| Variable | Used by |
| --- | --- |
| `HOMEPAGE_VAR_ADGUARD_USERNAME` / `_PASSWORD` | AdGuard widget |
| `HOMEPAGE_VAR_ARGOCD_KEY` | Argo CD widget |

Terraform input variables are `HOMEPAGE_ADGUARD_USERNAME`, `HOMEPAGE_ADGUARD_PASSWORD`,
`HOMEPAGE_ARGOCD_KEY`. `envFrom` is `optional: true`, so the page still loads if the secret
isn't synced; only those two widgets show errors.

**The old AdGuard password and Argo CD JWT were committed in plaintext and are in git history.
Rotate both** and put the new values in `terraform.tfvars` before `terraform apply`.

## Applying changes

1. Edit `config-map.yaml`, then run `yamlfmt` and `yamllint` (repo configs).
2. Commit and push; Argo re-checks git roughly every 3 minutes
   (hard refresh: annotate the `homepage` Application with `argocd.argoproj.io/refresh=hard`).
3. **Restart the pod.** The config files are `subPath` mounts, which Kubernetes never updates in
   place, so a ConfigMap-only change is not picked up until the pod restarts:
   `kubectl --context portland -n homepage rollout restart deploy/homepage`
4. Hard-refresh the browser (Ctrl+Shift+R); `custom.css` is cached.

## Styling

`custom.css` is deliberately minimal: thin card borders, small uppercase group headers, no
shadows or gradients, bigger numbers on the four Cluster Pulse tiles, and red/amber/green tints
on stat blocks. The tile and node selectors use `li.service[data-name="..."]`, so **renaming a
service in `services.yaml` requires updating `custom.css`** (the four tile names and the
`kube-cp` prefix).

The image is `ghcr.io/gethomepage/homepage:latest` with `imagePullPolicy: Always`, and the CSS
depends on Homepage's markup. If styling breaks after a restart, an upstream change is the
first suspect; consider pinning a tag.

## Not verified at the time of writing

The page was validated (YAML parses, every PromQL query returns data, every Loki/Alertmanager
URL returns data, CSS is served by the pod) but **not looked at in a browser**. Things to check
in screenshots:

- **Threshold tints.** Stat blocks should turn red/amber/green via `highlight:` rules, keyed by
  the metric `label`. The Homepage docs don't say what key `prometheusmetric` uses; if blocks
  are never tinted, the key is wrong (or the rules need `field` names) and the CSS is fine.
- **Status dots.** `ping` dots (the three nodes, TrueNAS, WDCloud) use ICMP from the pod. If
  they're red while the hosts are up, switch them to `siteMonitor`.
- **Vault card.** `Sealed` / `Initialized` are shown as raw text (`false` / `true`) on purpose,
  avoiding a boolean `remap` whose behaviour I couldn't confirm.
- **Dynamic lists** (Active Alerts, Errors by ...) render empty when there is nothing to show.
  Active Alerts is expected to be empty when healthy.
- **Header.** Greeting, cluster widget, Longhorn totals and clock should all appear; the
  Longhorn info widget needs the `providers.longhorn` URL to work.
- **Unauthenticated widgets** show an error until the Vault values are applied: AdGuard, Argo CD.

## Known noise in the error panels

At the last check the panels were dominated by two real, unrelated problems, so the top
entries will look the same until they're fixed:

- Loki logs `failed to lookup SRV records` for `loki-chunks-cache` / `loki-results-cache`
  (memcached services that don't exist).
- `csi-nfs-controller` can't find the VolumeSnapshot CRDs (`volumesnapshotclasses`,
  `volumesnapshotcontents`).

Also at last check: the `velero` Argo app was `OutOfSync` (this shows up in the Alerts & Sync
tile).

## Ideas not done

- Gitea, Proxmox and Grafana widgets (each needs a token added to the Vault secret).
- Auto-discovery from HTTPRoute annotations instead of hand-written URLs.
- A weather widget (needs coordinates).
- Pinning the image version.
