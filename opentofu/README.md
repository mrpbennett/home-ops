# 🏠 Homelab Infrastructure as Code (Proxmox + Talos + TrueNAS)

This repository defines my **virtualized homelab infrastructure** using **OpenTofu** (Terraform-compatible).
It automates provisioning of all virtual machines on **Proxmox VE**, including:

- 🧱 **Talos Linux cluster** – 3 control planes, 3 workers
- 💾 **TrueNAS SCALE VM** – ZFS, NFS, and MinIO storage backend
- 🔧 Fully parameterized for easy scaling and hardware changes

---

## ⚙️ Overview

| Component                     | Role                     | OS                  | Notes                                |
| ----------------------------- | ------------------------ | ------------------- | ------------------------------------ |
| **Proxmox Host**              | Hypervisor               | Debian + Proxmox VE | Ryzen 9 7950X / 128 GB RAM           |
| **Talos Control Planes (×3)** | etcd, API server         | Talos Linux         | Minimal, lightweight                 |
| **Talos Workers (×3)**        | Workloads (K8s services) | Talos Linux         | Infra, data, and media               |
| **TrueNAS SCALE**             | NAS / S3 / Backup        | Debian-based        | ZFS RAIDZ1 pool, NFS + MinIO exports |

All monitoring (Prometheus, Loki, Grafana), CI/CD (Jenkins, Airflow), and app workloads run **in Kubernetes**, not as VMs.

---

## 🧩 Folder Layout

```
homelab-iac/
├── main.tf               # Provider + module orchestration
├── variables.tf          # All configurable settings
├── terraform.tfvars      # Your environment-specific values
├── outputs.tf            # Useful summary outputs
└── nodes/
    ├── talos.tf          # Talos control plane + worker templates
    └── truenas.tf        # TrueNAS VM definition
```

---

## 🚀 Getting Started

### 1. Install Requirements

- [OpenTofu](https://opentofu.org/docs/intro/install/) (`brew install opentofu` or manual)
- Proxmox VE with API access enabled
- A **cloud-init enabled VM template** for:
  - `talos-template` (for control planes and workers)
  - `truenas-template` (for TrueNAS SCALE)

### 2. Clone and Configure

```bash
git clone https://github.com/<yourname>/homelab-iac.git
cd homelab-iac
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your own values:

```hcl
proxmox_url      = "https://192.168.7.10:8006/api2/json"
proxmox_username = "root@pam"
proxmox_password = "changeme"
storage_pool     = "local-lvm"
network_bridge   = "vmbr0"
count_control_planes = 3
count_workers        = 3
```

---

### 3. Initialize & Deploy

```bash
tofu init
tofu plan
tofu apply -auto-approve
```

This will:

- Connect to Proxmox via API
- Clone your VM templates
- Provision:
  - 3 control plane VMs → `talos-cp-1` … `talos-cp-3`
  - 3 worker VMs → `talos-wk-1` … `talos-wk-3`
  - 1 TrueNAS VM → `truenas`

---

## 🧮 Default Resource Allocation

| VM                           | vCPUs  | RAM (GB) | Disk (GB) | Purpose                        |
| ---------------------------- | ------ | -------- | --------- | ------------------------------ |
| **TrueNAS SCALE**            | 8      | 16       | 100       | ZFS + NFS + MinIO              |
| **Talos Control Plane (×3)** | 2 each | 4 each   | 40        | etcd / API                     |
| **Talos Worker (×3)**        | 8 each | 16 each  | 60        | Infra / Data / Media workloads |

Total: **42 vCPUs / 76 GB RAM** allocated
Host: **128 GB RAM / 64 vCPUs available (2:1 ratio)**
→ ~40% overhead free for growth, ARC caching, or testing nodes.

---

## 🧠 Customization

Everything can be changed in **variables.tf** or **terraform.tfvars** — no need to touch the main code.

| Task                            | Where to Change                             | Example                                    |
| ------------------------------- | ------------------------------------------- | ------------------------------------------ |
| Change number of control planes | `terraform.tfvars`                          | `count_control_planes = 5`                 |
| Adjust worker resources         | `nodes/talos.tf` → `local.talos_ram.worker` | `16384 → 32768`                            |
| Change template names           | `variables.tf`                              | `talos_vm_template = "talos-1.6-template"` |
| Rename nodes                    | `node_prefix` variable                      | `"talos"` → `"k8s"`                        |

To scale nodes later:

```bash
tofu apply -var="count_workers=4"
```

---

## 📦 Outputs

After deployment:

```bash
tofu output
```

Example:

```
talos_nodes = {
  control_planes = ["talos-cp-1", "talos-cp-2", "talos-cp-3"]
  workers        = ["talos-wk-1", "talos-wk-2", "talos-wk-3"]
}
truenas_vm = "truenas"
```

---

## 🔐 Secrets

Don’t hardcode passwords in `terraform.tfvars`.
Instead, use:

- Environment variables
- OpenTofu Cloud secrets
- `.auto.tfvars` (git-ignored) for local-only use

Example:

```bash
export PM_PASS="changeme"
tofu apply -var="proxmox_password=$PM_PASS"
```

---

## 🧰 Maintenance

| Task              | Command                                                |
| ----------------- | ------------------------------------------------------ |
| Rebuild templates | `tofu apply -replace=proxmox_vm_qemu.talos_workers[0]` |
| Destroy lab       | `tofu destroy -auto-approve`                           |
| Upgrade nodes     | Modify variables, rerun `tofu apply`                   |

---

## 🧩 Next Steps

1. **Talos Cluster Bootstrapping**
   After VMs are created, use `talosctl` from your workstation to:
   - Bootstrap etcd on the first control plane
   - Join other control planes and workers
   - Apply your cluster config YAMLs

2. **Storage Integration**
   - Export NFS shares from TrueNAS for Longhorn/Velero backups
   - Expose MinIO for object storage workloads

3. **GitOps Integration**
   - Configure ArgoCD or Flux in Kubernetes
   - Deploy observability and automation stacks declaratively

---

## 💡 Tips

- Always test new VM templates manually before using in OpenTofu.
- For experimentation, keep VM disks on `local-lvm`; for production, switch to ZFS or SSD-backed pools.
- You can version-lock your cluster topology in Git — rollbacks are instant.

---

### 🧭 Example Command Summary

```bash
tofu init              # initialize project
tofu fmt               # format code
tofu plan              # preview changes
tofu apply             # deploy VMs
tofu destroy           # tear down lab
```
