<div align="center">

<p>Wife approved HomeOps driven by Kubernetes and GitOps using ArgoCD</p>

<p align="center">
  <a href="https://github.com/k8s-at-home" alt="Image used with permission from k8s-at-home"><img alt="Image used with permission from k8s-at-home" src="https://avatars.githubusercontent.com/u/61287648" /></a>
</p>

<p align="center">
    <a href="[https://talos.dev/](https://k3s.io/)"><img alt="k3s" src="https://img.shields.io/badge/k3s-v1.29.5-yellow?logo=kubernetes&logoColor=white&style=flat-square"></a>
    <a href="https://github.com/mrpbennett/home-ops/commits/master"><img alt="GitHub Last Commit" src="https://img.shields.io/github/last-commit/mrpbennett/home-ops?logo=git&logoColor=white&color=purple&style=flat-square"></a>
    <a href="https://discord.gg/home-operations"><img alt="Home Operations Discord" src="https://img.shields.io/badge/discord-chat-7289DA.svg?logo=discord&logoColor=white&maxAge=60&style=flat-square"></a>
</p>

### My Home Operations Repository :octocat:

_... managed with ArgoCD, Renovate and GitHub Actions_ 🤖

</div>

---

## 📖 Overview

This is a mono repository for my home infrastructure and Kubernetes cluster. I try to adhere to Infrastructure as Code (IaC) and GitOps practices using tools like [Ansible](https://www.ansible.com/), [Terraform](https://www.terraform.io/), [Kubernetes](https://kubernetes.io/), [ArgoCD](https://argoproj.github.io/cd/), [Renovate](https://github.com/renovatebot/renovate) and [GitHub Actions](https://github.com/features/actions).

## The purpose here is to learn Kubernetes, while practising GitOps

## ⛵ Kubernetes

### Installation

My Kubernetes cluster is deployed with [K3s](https://www.k3s.io) and [KubeVIP](https://kube-vip.io/). This is a high availability cluster, running inside Proxmox.

#### System Requirements

| Role          | Memory | Cores | System Disk | Storage Disk |
| ------------- | ------ | ----- | ----------- | ------------ |
| Control Plane | 6 GiB  | 4     | 50 GiB      | 100 Gib      |
| Node          | 4 Gib  | 2     | 50 GiB      | 100 Gib      |

### GitOps

[ArgoCD](https://argoproj.github.io/cd/) watches the cluster in my kubernetes directory (see structure below) and makes the changes to my cluster based on the state of my Git repository. The way ArgoCD works for me here is it will search through `kubernetes/registry...`. Then deploy apps using the [apps of apps pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/#app-of-apps-pattern).

### Directories

This Git repository contains the following directories under [kubernetes](./kubernetes). I have the `apps` directory that stores all the application manifests for deployed apps. The registry directory is where I store all my `Application` type manifests for deployed apps. I also have a `cluster` directory for all cluster wide manifests as well as a `workflows` directory for all CronWorkflow via ArgoCD.

All Helm deployment `values.yaml` are contained within the Application under the `helm.valuesObject`

```sh
📁 kubernetes                          # root folder for all kubernetes manifests
├── 📁 apps                            # application directory deployed by ArgoCD
│   └── 📁 application
│       ├── deployment.yaml
│       ├── ingress.yaml
│       ├── namespace.yaml
│       └── service.yaml
├── argo-root.yaml
├── 📁 cluster                          # directory for cluster wide manifests
│   ├── cj-namespace.yaml
│   └── cluster-role-binding.yaml
├── 📁 registry                         # folder to hold all argo applications
│   ├── 📁 helm                         # folder for all helm deployments
│   │   └── application-helm.yaml
│   └── application.yaml
└── 📁 workflows                        # # directory for all argo cron workflows
    ├── 📁 jobs
    │   └── cron-workflow.yaml
    └── namespace.yaml
```

My `argo-root.yaml` argocd application checks for changes in `./kubernetes/registry` for new `Application` manifests. That manifest then checks in the `apps` directory, then deploys the app like the below:

```yml
source:
  repoURL: 'https://github.com/mrpbennett/home-ops.git'
  path: kubernetes/apps/nginx
```

## Tech stack

<table>
    <tr>
        <th>Logo</th>
        <th>Name</th>
        <th>Description</th>
    </tr>
    <tr>
        <td><img width="32" src="https://simpleicons.org/icons/ansible.svg"></td>
        <td><a href="https://www.ansible.com">Ansible</a></td>
        <td>Automate provisioning and configuration</td>
    </tr>
    <tr>
        <td><img width="32" src="https://avatars.githubusercontent.com/u/30269780"></td>
        <td><a href="https://argoproj.github.io/cd">ArgoCD</a></td>
        <td>GitOps tool built to deploy applications to Kubernetes</td>
    </tr>
    <tr>
        <td><img width="32" src="https://github.com/jetstack/cert-manager/raw/master/logo/logo.png"></td>
        <td><a href="https://cert-manager.io">cert-manager</a></td>
        <td>Cloud native certificate management - TBA</td>
    </tr>
    <tr>
        <td><img width="32" src="https://github.com/walkxcode/dashboard-icons/blob/main/png/cloudflare.png?raw=true"></td>
        <td><a href="https://www.cloudflare.com/en-gb/">Cloudflare</a></td>
        <td>Domain and network tunnel</td>
    </tr>
    <tr>
        <td><img width="32" src="https://www.docker.com/wp-content/uploads/2022/03/Moby-logo.png"></td>
        <td><a href="https://www.docker.com">Docker Registry</a></td>
        <td>Private container registry</td>
    </tr>
    <tr>
        <td><img width="32" src="https://grafana.com/static/img/menu/grafana2.svg"></td>
        <td><a href="https://grafana.com">Grafana</a></td>
        <td>Observability platform</td>
    </tr>
    <tr>
        <td><img width="32" src="https://helm.sh/img/helm.svg"></td>
        <td><a href="https://helm.sh">Helm</a></td>
        <td>The package manager for Kubernetes</td>
    </tr>
    <tr>
        <td><img width="32" src="https://avatars.githubusercontent.com/u/13629408"></td>
        <td><a href="https://kubernetes.io">Kubernetes</a></td>
        <td>Container-orchestration system, the backbone of this project</td>
    </tr>
    <tr>
        <td><img width="32" src="https://raw.githubusercontent.com/cncf/artwork/master/projects/kubescape/stacked/color/kubescape-stacked-color.svg"></td>
        <td><a href="https://kubescape.io">Kubescape</a></td>
        <td>Kubernetes security platform</td>
    <tr>
        <td><img width="32" src="https://kube-vip.io/images/kube-vip.png"></td>
        <td><a href="https://kube-vip.io/">Kube VIP</a></td>
        <td>Kubernetes virtual IP for clusters and load balancer</td>
    </tr>
    </tr>
    <tr>
        <td><img width="32" src="https://github.com/grafana/loki/blob/main/docs/sources/logo.png?raw=true"></td>
        <td><a href="https://grafana.com/oss/loki">Loki</a></td>
        <td>Log aggregation system</td>
    </tr>
    <tr>
        <td><img width="32" src="https://longhorn.io/img/logos/longhorn-icon-white.png"></td>
        <td><a href="https://longhorn.io">Longhorn</a></td>
        <td>Distributed block storage for Kubernetes</td>
    </tr>
    <tr>
        <td><img width="32" src="https://avatars.githubusercontent.com/u/1412239?s=200&v=4"></td>
        <td><a href="https://www.nginx.com">NGINX</a></td>
        <td>Kubernetes Ingress Controller</td>
    </tr>
    <tr>
        <td><img width="32" src="https://www.postgresql.org/media/img/about/press/elephant.png"></td>
        <td><a href="https://www.postgresql.org/">Postgres</a></td>
        <td>Database of choice</td>
    </tr>
    <tr>
        <td><img width="32" src="https://avatars.githubusercontent.com/u/3380462"></td>
        <td><a href="https://prometheus.io">Prometheus</a></td>
        <td>Systems monitoring and alerting toolkit</td>
    </tr>
    <tr>
        <td><img width="32" src="https://raw.githubusercontent.com/walkxcode/dashboard-icons/a02a5999fe56948671721da8b0830cdd5b609ed7/svg/proxmox.svg"></td>
        <td><a href="https://www.proxmox.com/en/">Proxmox</a></td>
        <td>Bare Metal hypervisor OS</td>
    </tr>
    <tr>
        <td><img width="32" src="https://store-images.s-microsoft.com/image/apps.1667.62b087ba-b0aa-4d22-aa02-a155bc245ecb.81d32dfa-16ca-4058-982c-03bd0fce135f.4e41e100-e821-4a7d-9a32-47c7ac37db51"></td>
        <td><a href="https://tailscale.com/">TailScale</a></td>
        <td>Zero config VPN</td>
    </tr>
    <tr>
        <td><img width="32" src="https://raw.githubusercontent.com/walkxcode/dashboard-icons/a02a5999fe56948671721da8b0830cdd5b609ed7/svg/terraform.svg"></td>
        <td><a href="https://www.terraform.io/">Terraform</a></td>
        <td>Infrastructure as code</td>
    </tr>
    <tr>
        <td><img width="32" src="https://upload.wikimedia.org/wikipedia/commons/a/ab/Logo-ubuntu_cof-orange-hex.svg"></td>
        <td><a href="https://getfedora.org/en/server">Ubuntu Server</a></td>
        <td>Base OS minimized for all VMs</td>
    </tr>
</table>

---

## 🔧 Hardware

| Device                        | Count | OS Disk Size | Data Disk Size | Ram  | Operating System | Purpose            |
| ----------------------------- | ----- | ------------ | -------------- | ---- | ---------------- | ------------------ |
| UniFi Cloud Gateway Max 1TB   | 1     | -            | 1TB NVMe       | -    | -                | Gateway / AP / NVR |
| UniFi Lite 8 PoE              | 2     | -            | -              | -    | -                | PoE switch         |
| Lenovo ThinkCentre M720q tiny | 1     | 120GB SSD    | 1TB NVMe       | 32GB | Proxmox VE       | Hypervisor         |

---

## 🤝 Gratitude and Thanks

Thanks to all the people who donate their time to the [Home Operations](https://discord.gg/home-operations) Discord community. Be sure to check out [kubesearch.dev](https://kubesearch.dev/) for ideas on how to deploy applications or get ideas on what you may deploy.
