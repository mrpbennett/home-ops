# 70LD Cloud — Naming Convention

## Overview

Every resource is named Cloud → Region → Zone → Cluster → Node/Service, and each level exists only when it represents something real. The domain is `70ld.dev` throughout; renaming the cloud means changing it in one place.

1. **Cloud** — `70LD Cloud`, the whole estate.
2. **Region** — a physical site with its own power and uplink (`uk-dor-1`).
3. **Zone** — an independent failure domain inside a region (`uk-dor-1a`).
4. **Cluster** — a Kubernetes cluster scoped to one region (`uk-dor-1-prod-01`).
5. **Node / service** — a machine (`dor1-cp-01`) or an endpoint (`grafana.int.70ld.dev`).

Guiding rules: placement lives in labels, not names; numbers are never reused; nothing claims resilience the hardware doesn't have.

## Regions

Regions follow `<country>-<area>-<n>`; `uk-dor-1` is the only active one today.

| Region | Meaning | Status |
| --- | --- | --- |
| `uk-dor-1` | Home site, Poole | Active |
| `uk-dor-2` | A second Dorset site (family house, office) | Reserved |
| `uk-lon-1` | London VPS or colo | Reserved |

- A region is a distinct physical location with its own power and uplink.
- The number increments only for a second site in the same area.
- Roles such as DR or edge never appear in a region name; they are labels on whichever region plays that role.

## Zones

Zones follow `<region><letter>`, and home has exactly one today: `uk-dor-1a`.

A zone is an independent failure domain inside a region, meaning separate power and/or network path. Everything in the rack shares one circuit and one uplink, so it is one zone. Add `uk-dor-1b` only when that stops being true, e.g. a second rack on its own circuit, UPS and switch.

Zones never appear in hostnames. They live in node labels and the inventory, so moving a machine never renames it.

## Hostnames

Hostnames follow `<site>-<role>-<nn>`, e.g. `dor1-cp-01`.

The site token is the short form of the region (`dor1`, `lon1`, `fsn1`). It keeps names unique across the tailnet, since Tailscale MagicDNS needs unique machine names, while staying short enough to type into `talosctl`.

| Role | Use |
| --- | --- |
| `cp` | Kubernetes control plane |
| `wk` | Kubernetes worker |
| `nas` | Storage appliance |
| `gw` / `fw` | Router / firewall |
| `sw` / `ap` | Switch / access point |
| `dns` | Standalone DNS (e.g. AdGuard) |
| `mon` | Monitoring host |
| `bkp` | Backup target |
| `hv` | Hypervisor (reserved, for if Proxmox arrives) |
| `edge` | Single-purpose remote node |

- Numbers are two digits, unique per role per region, and never reused. A retired `dor1-wk-02` stays retired.
- Hardware model, cluster and environment go in labels, not the name. A Pi in the dev cluster is just `dor1-cp-04` with `env=dev`.
- Lowercase and hyphens only; no pet names.

## Clusters

Clusters follow `<region>-<env>-<nn>`: production is `uk-dor-1-prod-01` (Talos on the 7060s, ArgoCD) and dev is `uk-dor-1-dev-01` (k3s on the Pis).

Environments are `prod`, `stage`, `dev`, `lab` (break it freely) and `edge`. The `-nn` suffix lets a replacement cluster run alongside the old one during a migration, then take over.

Every node carries these labels:

```yaml
topology.kubernetes.io/region: uk-dor-1
topology.kubernetes.io/zone: uk-dor-1a
70ld.dev/cluster: uk-dor-1-prod-01
70ld.dev/hardware: m720q
70ld.dev/role: primary        # or dr, edge
```

## IP addressing

Each region gets its own block and each cluster a pair of /16s from a separate block, so nothing overlaps when sites are routed together over Tailscale subnet routers. The home site uses a /22 of `192.168.x` split into four /24s; later regions use /16s from `10.x`.

| Block | Allocation |
| --- | --- |
| `192.168.4.0/22` | `uk-dor-1` |
| `10.71.0.0/16` | `uk-dor-2` (reserved) |
| `10.72.0.0/16` | `uk-lon-1` (reserved) |
| `10.73–10.99` | Future regions |
| `10.100.0.0/14` | Cluster pod and service ranges |

| Cluster | Pod CIDR | Service CIDR |
| --- | --- | --- |
| `uk-dor-1-prod-01` | `10.100.0.0/16` | `10.101.0.0/16` |
| `uk-dor-1-dev-01` | `10.102.0.0/16` | `10.103.0.0/16` |

Set these explicitly in the Talos and k3s configs. The defaults (Talos 10.244/10.96, k3s 10.42/10.43) collide as soon as there are two clusters of the same kind.

### VLANs

Each network is a /24 (`255.255.255.0`) inside the region's `192.168.4.0/22`. The third octet no longer matches the VLAN ID.

| VLAN | Name | Subnet | Contents |
| --- | --- | --- | --- |
| 50 | `general` | `192.168.4.0/24` | General computing, gateway |
| 60 | `iot` | `192.168.5.0/24` | IoT devices |
| 20 | `servers` | `192.168.6.0/24` | Servers, Raspberry Pis, NAS |
| 30 | `k8s` | `192.168.7.0/24` | Prod Kubernetes nodes and LB pool |

VLANs are named by purpose, never by the device that implements them.

### Host layout within every subnet

| Range | Use |
| --- | --- |
| `.1` | Gateway |
| `.2–.9` | Network gear |
| `.10–.99` | Static hosts |
| `.100–.199` | DHCP |
| `.200–.239` | LoadBalancer pool (MetalLB / Cilium LB-IPAM) |
| `.240–.254` | VIPs (Kubernetes API, ingress) |

## DNS

Public services sit at the apex; everything private sits under `int.70ld.dev`.

| Namespace | Pattern | Example |
| --- | --- | --- |
| Public services | `<service>.70ld.dev` | `photos.70ld.dev` |
| Internal services | `<service>.int.70ld.dev` | `grafana.int.70ld.dev` |
| Hosts | `<host>.int.70ld.dev` | `dor1-cp-01.int.70ld.dev` |
| Per-region endpoints | `<service>.<region>.int.70ld.dev` | `ingress.uk-dor-1.int.70ld.dev` |
| Per-cluster endpoints | `<service>.<cluster>.int.70ld.dev` | `api.uk-dor-1-prod-01.int.70ld.dev` |

- `int` rather than `home`, so names stay accurate once a VPS joins.
- One wildcard cert for `*.int.70ld.dev`, so internal hostnames never appear in Certificate Transparency logs.
- Split-horizon DNS for anything resolving differently inside and out; private names are never published publicly.
- Inside clusters, keep `cluster.local`.

## Kubernetes objects

Objects are named after what they are, and a namespace means the same thing in every cluster.

- **Namespaces** by function: `platform`, `networking`, `observability`, `storage`, `identity`, `media`, `photos`, `games`, `home-automation`.
- **Workloads** after the app (`immich-server`), never in hostname style.
- **ArgoCD Applications** as `<app>-<cluster>`, e.g. `immich-uk-dor-1-prod-01`, generated by an ApplicationSet over the cluster list so adding a cluster is one line.
- **Labels** use the standard `app.kubernetes.io/*` set with `part-of: 70ld-cloud`.

## Storage, backups and access

Buckets carry the cluster they serve; shares and tags carry purpose.

- **S3 buckets** on the NAS: `<cluster>-<purpose>`, e.g. `uk-dor-1-prod-01-longhorn`, `uk-dor-1-prod-01-velero`, `uk-dor-1-prod-01-cnpg`. Region-wide buckets drop the cluster: `uk-dor-1-archive`.
- **NAS shares** by purpose, never by user: `media`, `photos`, `backups`.
- **Tailscale tags**: `tag:uk-dor-1`, `tag:k8s`, `tag:prod`, `tag:infra`. ACLs are written against tags, never machine names.

## Git layout and inventory

`inventory.yaml` at the repo root is the single source of truth for every host, IP, role and zone; everything else follows the naming above.

```
70ld-cloud/
  inventory.yaml            # every host, IP, role, zone
  regions/
    uk-dor-1/
      network/              # VLANs, IPAM, DNS records
  clusters/
    uk-dor-1-prod-01/
      talos/
      apps/
    uk-dor-1-dev-01/
  apps/                     # shared app bases, overlaid per cluster
```

The cluster folder names match the ArgoCD cluster names, so ApplicationSet paths can be derived from them.

## Growth scenarios

Every likely addition slots in without renaming anything that already exists.

| You add… | What changes |
| --- | --- |
| A London VPS for ingress | Region `uk-lon-1`, host `lon1-edge-01`, subnet `10.72.0.0/16`, label `role=edge` |
| A second cluster at home | `uk-dor-1-stage-01`, next pod/service pair from `10.100.0.0/14`, new folder in `clusters/` |
| A prod rebuild | `uk-dor-1-prod-02` alongside `-01`; migrate, then retire `-01` |
| Offsite DR at a relative's | Region `uk-dor-2` labelled `role=dr`; buckets replicate from `uk-dor-1-*` |
| A second rack on its own circuit | Zone `uk-dor-1b`; existing hostnames unchanged |
| A hypervisor | `dor1-hv-01`; its VMs follow the normal role scheme |

## Quick reference

| Resource | Standard |
| --- | --- |
| Region | `uk-dor-1` |
| Zone | `uk-dor-1a` |
| Cluster | `uk-dor-1-prod-01` |
| Host | `dor1-cp-01` |
| Host FQDN | `dor1-cp-01.int.70ld.dev` |
| Region network | `192.168.4.0/22` (general `.4`, iot `.5`, servers `.6`, k8s `.7`) |
| Pod / service CIDR | `10.100.0.0/16` / `10.101.0.0/16` |
| Internal service | `grafana.int.70ld.dev` |
| Public service | `photos.70ld.dev` |
| Bucket | `uk-dor-1-prod-01-velero` |
| ArgoCD app | `immich-uk-dor-1-prod-01` |
