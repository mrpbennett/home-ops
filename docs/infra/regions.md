# 70LD Cloud — Naming Convention

## Overview

Names follow Google Cloud's model: a resource's identity is its path through the things that contain it, so the leaf name stays short. Placement and ownership live in the path and in labels, never repeated in the name. The domain is `70ld.dev` throughout; renaming the cloud means changing it in one place.

1. **Cloud** — `70LD Cloud`, the whole estate.
2. **Region** — a physical site with its own power and uplink (`uk-southwest1`).
3. **Zone** — an independent failure domain inside a region (`uk-southwest1-a`).
4. **Project** — the unit that owns resources and scopes their names (`ld-prod`).
5. **Resource** — an instance (`cp-01`), a cluster (`main`), a subnet (`k8s`) or a bucket (`ld-prod-longhorn`).

Guiding rules: names are short and unique within their parent; the parent supplies the context; numbers are never reused; nothing claims resilience the hardware doesn't have.

## How GCP names things

This convention copies the parts of Google Cloud's that fit a home estate.

**Regions** are `<geography>-<compass><n>`, such as `europe-west2` (London), `europe-west1` (Belgium) and `us-central1` (Iowa). A region names a broad area, not a city, and the number only separates regions in the same compass area. The city is metadata.

**Zones** are the region plus a letter: `europe-west2-a`, `-b`, `-c`. A zone is a failure domain inside a region, with independent power, cooling and networking. The letter carries no meaning (`-a` is not the "edge" zone); workloads spread across zones for resilience, not for role.

**Projects** own resources and scope their names. A project ID is globally unique, 6–30 characters, lowercase letters, digits and hyphens, starts with a letter and never changes.

**Resource names** are unique within their parent, not globally:

| Level | Rule | Example |
| --- | --- | --- |
| Project ID | Globally unique, 6–30 chars, starts with a letter, immutable | `my-homelab-123456` |
| Instance, cluster | Unique within the project; 1–63 chars, RFC 1035 label, starts with a letter, no trailing hyphen | `web-1`, `prod-cluster` |
| Network | Unique within the project; global | `prod-vpc` |
| Subnet | Unique within the project and region | `prod-subnet-london` |
| Full resource path | Unique everywhere, built from the parents | `projects/my-homelab/zones/europe-west2-a/instances/web-1` |

- **The zone is not in the instance name.** The path carries it, and so does internal DNS (`web-1.europe-west2-a.c.my-homelab.internal`). Moving a VM never forces a rename.
- **Names are immutable.** An instance can't be renamed, only recreated, which is why numbers are never reused.
- **Labels carry everything else:** environment, team, hardware. Names stay short and labels are queryable.
- **Kubeconfig contexts** are `gke_<project>_<location>_<cluster>`, so two clusters can both be called `main` without clashing.

## Regions

Regions follow `<country>-<compass><n>`, as in `europe-west2`. The compass point is the part of the country, and the number separates regions in the same part. The county or city goes in the region's `display_name`, not the ID.

| Region | Display name | Meaning | Status |
| --- | --- | --- | --- |
| `uk-southwest1` | Dorset (Poole) | Home site | Active |
| `uk-southwest2` | Dorset (second site) | A second site in the same part of the country (family house, office) | Reserved |
| `uk-southeast1` | London | London VPS or colo | Reserved |

- A region is a distinct physical location with its own power and uplink.
- The number increments only for a second site in the same compass area.
- Roles such as DR or edge never appear in a region name; they are labels on whichever region plays that role.

## Zones

Zones follow `<region>-<letter>`, and home has exactly one today: `uk-southwest1-a`.

A zone is an independent failure domain inside a region, meaning separate power and/or network path. Everything in the rack shares one circuit and one uplink, so it is one zone. Add `uk-southwest1-b` only when that stops being true, e.g. a second rack on its own circuit, UPS and switch. Zones are never mapped to towns or to roles.

Zones never appear in instance names. They live in the resource path, in DNS and in node labels, so moving a machine never renames it.

## Projects

A project owns a set of resources and gives their short names a scope. Project IDs start with a letter because they feed hostnames, and hostnames must.

| Project | Owns |
| --- | --- |
| `ld-prod` | The production cluster, its machines, storage appliance and buckets |
| `ld-dev` | The Raspberry Pi dev cluster and its machines |
| `ld-net` | The network, DNS, gateway and other shared plumbing |

Add a project when a set of resources needs its own owner, lifecycle or blast radius, not for every new service.

## Instances and hostnames

An instance's resource name is `<role>-<nn>`, unique within its project: `cp-01`, `nas-01`. Its OS hostname, Kubernetes node name and Tailscale name are `<project>-<name>`: `ld-prod-cp-01`.

The project prefix is added only to the hostname. Tailscale MagicDNS needs unique machine names, and `ld-prod` and `ld-dev` would otherwise both have a `cp-01`.

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

- Numbers are two digits, unique per role per project, and never reused. A retired `wk-02` stays retired.
- Hardware model, cluster and environment go in labels, not the name.
- Lowercase and hyphens only, starting with a letter; no pet names.

## Clusters

A cluster's name is unique within its project and region, and is just `main`, as in `prod-cluster`. The project says it is production and the region says where.

| Cluster path | Distro | Nodes |
| --- | --- | --- |
| `ld-prod/uk-southwest1/main` | Talos, Argo CD | The Dell 7060s |
| `ld-dev/uk-southwest1/main` | k3s | The Raspberry Pis |

A replacement cluster runs alongside the old one during a migration (`main-02`), then takes over.

Kubeconfig contexts are `<project>_<region>_<cluster>`, e.g. `ld-prod_uk-southwest1_main`.

Every node carries these labels:

```yaml
topology.kubernetes.io/region: uk-southwest1
topology.kubernetes.io/zone: uk-southwest1-a
70ld.dev/project: ld-prod
70ld.dev/cluster: main
70ld.dev/hardware: optiplex-7060
70ld.dev/role: primary        # or dr, edge
```

## Networks

GCP separates a global network from regional subnets, and so do we. The network `home-vpc` belongs to `ld-net`; each subnet belongs to one region. Subnets are named by purpose, never by the device that implements them, and are unique within the region.

| VLAN | Subnet | CIDR | Contents |
| --- | --- | --- | --- |
| 50 | `general` | `192.168.4.0/24` | General computing, gateway |
| 60 | `iot` | `192.168.5.0/24` | IoT devices |
| 20 | `servers` | `192.168.6.0/24` | Servers, Raspberry Pis, NAS |
| 30 | `k8s` | `192.168.7.0/24` | Prod Kubernetes nodes and LB pool |

A subnet's full path is `projects/ld-net/regions/uk-southwest1/subnetworks/k8s`.

## IP addressing

Each region gets its own block and each cluster a pair of /16s from a separate block, so nothing overlaps when sites are routed together over Tailscale subnet routers. The home site uses a /22 of `192.168.x` split into four /24s; later regions use /16s from `10.x`.

| Block | Allocation |
| --- | --- |
| `192.168.4.0/22` | `uk-southwest1` |
| `10.71.0.0/16` | `uk-southwest2` (reserved) |
| `10.72.0.0/16` | `uk-southeast1` (reserved) |
| `10.73–10.99` | Future regions |
| `10.100.0.0/14` | Cluster pod and service ranges |

| Cluster | Pod CIDR | Service CIDR |
| --- | --- | --- |
| `ld-prod/main` | `10.100.0.0/16` | `10.101.0.0/16` |
| `ld-dev/main` | `10.102.0.0/16` | `10.103.0.0/16` |

Set these explicitly in the Talos and k3s configs. The defaults (Talos 10.244/10.96, k3s 10.42/10.43) collide as soon as there are two clusters of the same kind.

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

Public services sit at the apex; everything private sits under `int.70ld.dev`. Private names follow GCP's internal DNS, which puts the zone and project in the name.

| Namespace | Pattern | Example |
| --- | --- | --- |
| Public services | `<service>.70ld.dev` | `photos.70ld.dev` |
| Internal services | `<service>.int.70ld.dev` | `grafana.int.70ld.dev` |
| Instances | `<name>.<zone>.<project>.int.70ld.dev` | `cp-01.uk-southwest1-a.ld-prod.int.70ld.dev` |
| Per-region endpoints | `<service>.<region>.int.70ld.dev` | `ingress.uk-southwest1.int.70ld.dev` |
| Per-cluster endpoints | `<service>.<cluster>.<project>.int.70ld.dev` | `api.main.ld-prod.int.70ld.dev` |

- `int` rather than `home`, so names stay accurate once a VPS joins.
- One wildcard cert for `*.int.70ld.dev`, so internal hostnames never appear in Certificate Transparency logs.
- Split-horizon DNS for anything resolving differently inside and out; private names are never published publicly.
- Inside clusters, keep `cluster.local`.

## Kubernetes objects

Objects are named after what they are, and a namespace means the same thing in every cluster.

- **Namespaces** by function: `platform`, `networking`, `observability`, `storage`, `identity`, `media`, `photos`, `games`, `home-automation`.
- **Workloads** after the app (`immich-server`), never in hostname style.
- **Argo CD Applications** as `<app>-<project>`, e.g. `immich-ld-prod`, generated by an ApplicationSet over the project list so adding a cluster is one line.
- **Labels** use the standard `app.kubernetes.io/*` set with `part-of: 70ld-cloud`.

## Storage, backups and access

Buckets carry the project that owns them, as GCP buckets do, and shares and tags carry purpose.

- **S3 buckets** on the NAS: `<project>-<purpose>`, e.g. `ld-prod-longhorn`, `ld-prod-velero`, `ld-prod-cnpg-backup`. Bucket names are globally unique in GCP, so the project prefix plays that role here.
- **NAS shares** by purpose, never by user: `media`, `photos`, `backups`.
- **Tailscale tags**: `tag:uk-southwest1`, `tag:k8s`, `tag:prod`, `tag:infra`. ACLs are written against tags, never machine names.

## Git layout and inventory

`inventory.yaml` is the single source of truth for every region, project, instance and subnet. A resource's path is derived from it, never stored twice.

```
70ld-cloud/
  inventory.yaml
  projects/
    ld-prod/
      clusters/
        main/
          talos/
          apps/
    ld-dev/
      clusters/main/
    ld-net/
      network/              # VLANs, IPAM, DNS records
  apps/                     # shared app bases, overlaid per cluster
```

Project and cluster folder names match the inventory, so ApplicationSet paths can be derived from them.

## Growth scenarios

Every likely addition slots in without renaming anything that already exists.

| You add… | What changes |
| --- | --- |
| A London VPS for ingress | Region `uk-southeast1`, instance `edge-01` in `ld-prod`, subnet from `10.72.0.0/16`, label `role=edge` |
| A second cluster at home | `ld-stage` project with cluster `main`, next pod/service pair from `10.100.0.0/14` |
| A prod rebuild | `main-02` in `ld-prod`; migrate, then retire `main` |
| Offsite DR at a relative's | Region `uk-southwest2` labelled `role=dr`; buckets replicate from `ld-prod-*` |
| A second rack on its own circuit | Zone `uk-southwest1-b`; existing instance names unchanged |
| A hypervisor | `hv-01` in `ld-prod`; its VMs follow the normal role scheme |

## Quick reference

| Resource | Standard |
| --- | --- |
| Region | `uk-southwest1` |
| Zone | `uk-southwest1-a` |
| Project | `ld-prod` |
| Instance | `cp-01` |
| Hostname / Tailscale name | `ld-prod-cp-01` |
| Instance path | `projects/ld-prod/zones/uk-southwest1-a/instances/cp-01` |
| Cluster | `main` (context `ld-prod_uk-southwest1_main`) |
| Instance DNS | `cp-01.uk-southwest1-a.ld-prod.int.70ld.dev` |
| Network / subnet | `home-vpc` / `k8s` |
| Region network | `192.168.4.0/22` (general `.4`, iot `.5`, servers `.6`, k8s `.7`) |
| Pod / service CIDR | `10.100.0.0/16` / `10.101.0.0/16` |
| Internal service | `grafana.int.70ld.dev` |
| Public service | `photos.70ld.dev` |
| Bucket | `ld-prod-velero` |
| Argo CD app | `immich-ld-prod` |
