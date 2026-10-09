<div align="center">

<p>Wife approved HomeOps driven by Kubernetes and GitOps using ArgoCD</p>

<p align="center">
  <a href="https://github.com/k8s-at-home" alt="Image used with permission from k8s-at-home"><img width="300" alt="Image used with permission from k8s-at-home" src="misc/homeops-logo.png" /></a>
</p>

<p align="center">
    <a href="https://talos.dev"><img alt="talos" src="https://img.shields.io/badge/talos-v1.14.2-orange?logo=talos&logoColor=white&style=flat-square"></a>
    <a href="https://github.com/mrpbennett/home-ops/commits/master"><img alt="GitHub Last Commit" src="https://img.shields.io/github/last-commit/mrpbennett/home-ops?logo=git&logoColor=white&color=purple&style=flat-square"></a>
    <a href="https://discord.gg/home-operations"><img alt="Home Operations Discord" src="https://img.shields.io/badge/discord-chat-7289DA.svg?logo=discord&logoColor=white&maxAge=60&style=flat-square"></a>
</p>

### My Home Operations Repository :octocat:

_... managed with ArgoCD, Renovate and GitHub Actions_ 🤖

</div>

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f4a1/512.gif" alt="💡" width="20" height="20"> Overview

This is a mono repository for my home infrastructure and Kubernetes nodes. I try to adhere to Infrastructure as Code (IaC) and GitOps practices using tools like [Kubernetes](https://kubernetes.io/), [ArgoCD](https://argoproj.github.io/cd/), [Renovate](https://github.com/renovatebot/renovate) and [GitHub Actions](https://github.com/features/actions).

I have a HA setup running 3 Dell OptiPlex 7060 Micros (6-core, 16GB) with [Talos Linux](https://talos.dev), all acting as control planes that also accept workloads.

## The purpose here is to learn Kubernetes, while practising GitOps

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f331/512.gif" alt="🌱" width="20" height="20"> Kubernetes

### Installation

My Kubernetes environment is deployed with [Talos Linux](https://talos.dev), with [MetalLB](https://metallb.universe.tf/) providing `LoadBalancer` support.

### GitOps

[ArgoCD](https://argoproj.github.io/cd/) watches the `kubernetes` directory (see structure below) and changes the cluster to match the state of this Git repository. A single root application, `kubernetes/argo-root.yaml`, syncs every [ApplicationSet](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/) in `kubernetes/appsets/`. Each ApplicationSet generates the Application that deploys one app, following the [app of apps pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/#app-of-apps-pattern).

### Cluster Naming

Clusters use short, Dorset-themed names rather than encoding distro or environment info into the directory name. This keeps paths concise and avoids churn if the underlying distro changes.

| Cluster      | Environment | Description              |
| ------------ | ----------- | ------------------------ |
| **portland** | Production  | Primary workload cluster |

### Directories

This Git repository contains the following directories:

```sh
📁 kubernetes
├── argo-root.yaml                        # root app: syncs everything in appsets/
├── 📁 appsets                            # one ApplicationSet per app
│   ├── 📁 argocd-helm                    # Argo CD manages itself
│   ├── 📁 atuin                          # manifest app -> clusters/portland/apps/atuin
│   ├── 📁 CLUSTER                        # deploys clusters/portland/CLUSTER
│   ├── 📁 vault-helm                     # Helm app, values inline
│   └── ...
└── 📁 clusters
    └── 📁 portland                       # production cluster
        ├── 📁 apps                       # plain manifests for non-Helm apps
        │   └── 📁 app
        │       ├── deployment.yaml
        │       ├── service.yaml
        │       └── ...
        └── 📁 CLUSTER                    # cluster-wide manifests
            ├── 📁 cluster-role-bindings
            ├── 📁 gateway-api            # GatewayClass, shared Gateway, wildcard cert
            ├── 📁 namespaces
            └── 📁 secrets                # VaultStaticSecrets, synced from Vault
📁 terraform
└── 📁 vault                              # Vault config + secrets as code (see its README)
```

Each ApplicationSet deploys one app in one of two ways:

- **Helm apps** (`*-helm`) name the chart directly. Their values live inline in the ApplicationSet under `helm.valuesObject`, so there are no separate `values.yaml` files.
- **Manifest apps** point at a directory of plain manifests:

```yml
source:
  repoURL: "https://github.com/mrpbennett/home-ops.git"
  path: "kubernetes/clusters/{{.cluster}}/apps/{{.app_name}}"
```

The `cluster` generator value (`portland`) picks both the folder under `clusters/` and the Argo CD destination cluster.

### Bootstrapping a new cluster

Argo CD manages itself through [`appset-helm-argocd.yaml`](./kubernetes/appsets/argocd-helm/appset-helm-argocd.yaml), so on a fresh cluster it's installed once with Helm, using the **same chart version, release name and values** as that appset. Argo CD then takes over the existing resources when the appset syncs.

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

- **The release name must be `argocd`** to match the generated Application, so Argo CD takes over the existing resources instead of duplicating them.
- **`httproute` is disabled only for the first install**, because the HTTPRoute resource type doesn't exist until Envoy Gateway installs it. Argo CD adds the HTTPRoute afterwards.
- **After step 4, never run `helm upgrade`.** Upgrade Argo CD by changing the appset in git.
- **`configs.clusterCredentials`** in the appset registers this cluster as `portland`, the destination every appset targets.
- **Expect sync errors at first.** Apps retry until the resource types and namespaces they depend on exist, so the cluster converges in about 5–15 minutes.
- **Vault needs manual steps.** It starts sealed, so initialise and unseal it, then apply the Terraform; until then, the apps that need its secrets wait.

The Vault steps, and how sync ordering works, are in [`terraform/vault/README.md`](./terraform/vault/README.md).

## Tech stack

| Name                                                           | Description                                                  |
| -------------------------------------------------------------- | ------------------------------------------------------------ |
| [ArgoCD](https://argoproj.github.io/cd)                        | GitOps tool built to deploy applications to Kubernetes       |
| [Argo Workflows](https://argoproj.github.io/workflows)         | Workflow management to help with CronWorkflows               |
| [Cert Manager](https://cert-manager.io)                        | Certificate management                                       |
| [Docker Registry](https://docker.com/)                         | Private container registry                                   |
| [Envoy Gateway](https://gateway.envoyproxy.io/)                | API Gateway                                                  |
| [Grafana](https://grafana.com)                                 | Observability platform                                       |
| [Helm](https://helm.sh)                                        | The package manager for Kubernetes                           |
| [Talos Linux](https://talos.dev)                               | Kubernetes OS                                                |
| [Keycloak](https://www.keycloak.org/) | OIDC provider |
| [Kubernetes](https://kubernetes.io)                            | Container-orchestration system, the backbone of this project |
| [Loki](https://grafana.com/oss/loki/)                          | Log aggregation system                                       |
| [ExternalDNS](https://github.com/kubernetes-sigs/external-dns) | External DNS server configuration                            |
| [NGINX](https://www.nginx.com)                                 | Kubernetes Ingress Controller                                |
| [MetalLB](https://metallb.universe.tf/)                        | Kubernetes load balancer                                     |
| [Prometheus](https://prometheus.io)                            | Systems monitoring and alerting toolkit                      |
| [SeaweedFS](https://github.com/seaweedfs/seaweedfs)            | Data Warehouse Object Storage                                |
| [Trino](https://trino.io/)                                     | Fast distributed SQL query engine                            |
| [Tailscale](https://tailscale.com/docs/kubernetes-operator) | Secure connectivity |

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f30e/512.gif" alt="🌎" width="20" height="20"> DNS

In my cluster there is one instance of [ExternalDNS](https://github.com/kubernetes-sigs/external-dns) running. This syncs to a LXCPi5 running [Adguard Home](https://github.com/AdguardTeam/Adguardhome) for syncing local DNS records. This setup allows me to create dns records with valid certification via cert-manager and cloudflares API.

---

## 🔧 Hardware

| Device          | Count | CPU    | OS Disk Size | Data Disk Size | Ram  | Operating System | Purpose                         |
| --------------- | ----- | ------ | ------------ | -------------- | ---- | ---------------- | ------------------------------- |
| Dell 7060 micro | 3     | 6-core | 1TB NVMe     | -              | 16GB | Talos Linux      | Control planes that run workloads |
| Dell 7060 micro | 1     | -      | 256GB SSD    | 1TB NVMe       | 16GB | Proxmox          | Hypervisor                      |

---

## ⭐ Stargazers

<div align="center">

[![Star History Chart](https://api.star-history.com/svg?repos=mrpbennett/home-ops&type=Date)](https://star-history.com/#mrpbennett/home-ops&Date)

</div>

---

## 🤝 Gratitude and Thanks

Thanks to all the people who donate their time to the [Home Operations](https://discord.gg/home-operations) Discord community. Be sure to check out [kubesearch.dev](https://kubesearch.dev/) for ideas on how to deploy applications or get ideas on what you may deploy.
