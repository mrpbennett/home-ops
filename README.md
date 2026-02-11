<div align="center">

<p>Wife approved HomeOps driven by Kubernetes and GitOps using ArgoCD</p>

<p align="center">
  <a href="https://github.com/k8s-at-home" alt="Image used with permission from k8s-at-home"><img alt="Image used with permission from k8s-at-home" src="https://avatars.githubusercontent.com/u/61287648" /></a>
</p>

<p align="center">
    <a href="[https://talos.dev/](https://talos.dev)"><img alt="talos" src="https://img.shields.io/badge/talos-v1.34.1-orange?logo=talos&logoColor=white&style=flat-square"></a>
    <a href="https://github.com/mrpbennett/home-ops/commits/master"><img alt="GitHub Last Commit" src="https://img.shields.io/github/last-commit/mrpbennett/home-ops?logo=git&logoColor=white&color=purple&style=flat-square"></a>
    <a href="https://discord.gg/home-operations"><img alt="Home Operations Discord" src="https://img.shields.io/badge/discord-chat-7289DA.svg?logo=discord&logoColor=white&maxAge=60&style=flat-square"></a>
</p>

### My Home Operations Repository :octocat:

_... managed with ArgoCD, Renovate and GitHub Actions_ 🤖

</div>

---

## 📖 Overview

This is a mono repository for my home infrastructure and Kubernetes node. I try to adhere to Infrastructure as Code (IaC) and GitOps practices using tools like [Kubernetes](https://kubernetes.io/), [ArgoCD](https://argoproj.github.io/cd/), [Renovate](https://github.com/renovatebot/renovate) and [GitHub Actions](https://github.com/features/actions).

I have a HA setup running 3 Raspberry Pi5 8GB as control planes with a further 2x Lenovo M720q as worker nodes running K3s.

## The purpose here is to learn Kubernetes, while practising GitOps

## ⛵ Kubernetes

### Installation

My Kubernetes enviroment is deployed with [Talos](https://talos.dev). With [MetalLB](https://metallb.universe.tf/) providing `LoadBalancer` support.

#### System Requirements

| Role          | Memory | Cores | System Disk |
| ------------- | ------ | ----- | ----------- |
| Control Plane | 6 GiB  | 4     | 250 Gb      |
| Worker Nodes  | 32 GiB | 6     | 1 TB        |

### GitOps

[ArgoCD](https://argoproj.github.io/cd/) watches the cluster in my kubernetes directory (see structure below) and makes the changes to my cluster based on the state of my Git repository. The way ArgoCD works for me here is it will search through `kubernetes/registry...`. Then deploy apps using the [apps of apps pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/#app-of-apps-pattern).

### Directories

This Git repository contains the following directories under [kubernetes](./kubernetes). I have the `apps` directory that stores all the application manifests for deployed apps. The registry directory is where I store all my `Application` type manifests for deployed apps. I also have a `cluster` directory for all cluster wide manifests.

All Helm deployment `values.yaml` are contained within the Application under the `helm.valuesObject`

```sh
📁 kubernetes
├── 📁 apps                           # application directory
│   └── 📁 app
│       ├── config-map.yaml
│       ├── ingress.yaml
│       └── stateful-set.yaml
├── argo-root.yaml
├── 📁 cluster                        # cluster wide manifests
│   ├── 📁 cluster-role-bindings
│   ├── 📁 cron-workflows
│   ├── 📁 cronjobs
│   ├── 📁 ingress
│   ├── 📁 namespaces
│   ├── 📁 secrets
│   ├── 📁 users
│   └── 📁 workflows
├── 📁 registry                       # registry for application deployments
│   ├── argo-workflows.yaml
│   ├── 📁 helm                       # helm deployments
│   │   └── trino-helm.yaml

```

My `argo-root.yaml` argocd application checks for changes in `./kubernetes/<cluster>/registry` for new `Application` manifests. That manifest then checks in the `apps` directory, then deploys the app like the below:

```yml
source:
  repoURL: "https://github.com/mrpbennett/home-ops.git"
  path: kubernetes/apps/nginx
```

## Tech stack

<table>
    <tr>
        <th>Name</th>
        <th>Description</th>
    </tr>
    <tr>
        <td><a href="https://airflow.apache.org/">Apache Airflow</a></td>
        <td>Workflow Orchestration</td>
    </tr>
    <tr>
        <td><a href="https://argoproj.github.io/cd">ArgoCD</a></td>
        <td>GitOps tool built to deploy applications to Kubernetes</td>
    </tr>
    <tr>
        <td><a href="https://argoproj.github.io/workflows">Argo Workflows</a></td>
        <td>Workflow management to help with CronWorkflows</td>
    </tr>
    <tr>
        <td><a href="https://cert-manager.io">cert-manager</a></td>
        <td>Certificate management</td>
    </tr>
    <tr>
        <td><a href="https://docker.com/">Docker Registry</a></td>
        <td>Private container registry</td>
    </tr>
    <tr>
        <td><a href="https://grafana.com">Grafana</a></td>
        <td>Observability platform</td>
    </tr>
    <tr>
        <td><a href="https://helm.sh">Helm</a></td>
        <td>The package manager for Kubernetes</td>
    </tr>
    <tr>
        <td><a href="https://kubernetes.io">Kubernetes</a></td>
        <td>Container-orchestration system, the backbone of this project</td>
    </tr>
    <tr>
        <td><a href="https://grafana.com/oss/loki/">Loki</a></td>
        <td>Log aggregation system</td>
    </tr>
    <tr>
        <td><a href="https://www.nginx.com">NGINX</a></td>
        <td>Kubernetes Ingress Controller</td>
    </tr>
    <tr>
        <td><a href="https://metallb.universe.tf/">MetalLB</a></td>
        <td>Kubernetes load balancer</td>
    </tr>
    <tr>
        <td><a href="https://prometheus.io">Prometheus</a></td>
        <td>Systems monitoring and alerting toolkit</td>
    </tr>
    <tr>
        <td><a href="https://trino.io/">Trino</a></td>
        <td>Fast distributed SQL query engine</td>
    </tr>
    <tr>
        <td><a href="https://talos.dev">Talos OS</a></td>
        <td>Talos OS</td>
    </tr>
</table>

---

## 🔧 Hardware

| Device                        | Count | Disk Sizes               | Ram  | Operating System  | Purpose          |
| ----------------------------- | ----- | ------------------------ | ---- | ----------------- | ---------------- |
| Raspberry Pi5                 | 3     | 250GB NVMe               | 8GB  | Raspberry Pi ARM64  | Microservices    |
| Dell 7060 micro | 3     | 1TB NVMe                 | 32GB | Talos OS | Control Planes as workers       |


---

## ⭐ Stargazers

<div align="center">
  
[![Star History Chart](https://api.star-history.com/svg?repos=mrpbennett/home-ops&type=Date)](https://star-history.com/#mrpbennett/home-ops&Date)
  
</div>

---

## 🤝 Gratitude and Thanks

Thanks to all the people who donate their time to the [Home Operations](https://discord.gg/home-operations) Discord community. Be sure to check out [kubesearch.dev](https://kubesearch.dev/) for ideas on how to deploy applications or get ideas on what you may deploy.
