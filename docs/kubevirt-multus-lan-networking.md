# Plan: KubeVirt VMs with Real LAN IPs via Multus

## Context

KubeVirt VMs currently use masquerade networking (NAT through the pod network). This means VMs are not directly reachable from the LAN — they need a Kubernetes Service per exposed port and can't be pinged. For VMs running network services (pihole, NAS, etc.) that external devices need to access, we need VMs to be first-class LAN citizens with their own static IPs.

**Solution**: Deploy Multus CNI + macvlan so any VM can get a second NIC with a real IP on the `192.168.7.0/24` home network. Also deploy CDI for persistent VM disks via Longhorn.

## Pre-requisite: Discover Host NIC Name

Before implementing, run on any K3s node:
```bash
kubectl debug node/<node-name> -it --image=busybox -- ip link show
```
Look for the physical NIC (not `lo`, `cni0`, `flannel.1`, `veth*`). Common: `eth0`, `eno1`, `enp0s3`. This value is needed as `MASTER_NIC` in the NetworkAttachmentDefinition.

---

## Changes

### 1. Deploy Multus CNI (new ArgoCD app)

**Create** `kubernetes/clusters/portland/registry/multus.yaml`
- ArgoCD Application pointing to `apps/multus`, destination `kube-system`

**Create** `kubernetes/clusters/portland/apps/multus/multus-daemonset.yaml`
- Vendor the [thick-plugin DaemonSet](https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml)
- Patch K3s-specific CNI paths:
  - CNI config: `/var/lib/rancher/k3s/agent/etc/cni/net.d`
  - CNI binaries: `/var/lib/rancher/k3s/data/current/bin`

### 2. Deploy CDI — Containerized Data Importer (new ArgoCD app)

Enables importing disk images into Longhorn PVCs via `DataVolume` resources.

**Create** `kubernetes/clusters/portland/registry/cdi.yaml`
- ArgoCD Application pointing to `apps/cdi`

**Create** `kubernetes/clusters/portland/apps/cdi/cdi-operator.yaml`
- Vendor from [CDI releases](https://github.com/kubevirt/containerized-data-importer/releases) (latest stable)

**Create** `kubernetes/clusters/portland/apps/cdi/cdi-cr.yaml`
- Minimal CDI custom resource to activate the operator

### 3. Enable DataVolumes feature gate in KubeVirt

**Modify** `kubernetes/clusters/portland/apps/kubevirt/kubevirt-cr.yaml`
- Change `featureGates: []` → `featureGates: ["DataVolumes"]`

### 4. Create NetworkAttachmentDefinition (macvlan)

**Create** `kubernetes/clusters/portland/apps/kubevirt/net-attach-def.yaml`
- macvlan in bridge mode, `master: MASTER_NIC` (replace with discovered NIC)
- No CNI-side IPAM — VMs set their own static IPs via cloud-init
- `SkipDryRunOnMissingResource=true` annotation (Multus CRD may not exist during dry-run)
- Lives in `kubevirt` namespace (same as VMs)

### 5. Create example pihole VM using the new infrastructure

**Create** `kubernetes/clusters/portland/apps/kubevirt/vms/pihole.yaml`
- `DataVolume`: imports Ubuntu 22.04 cloud image into 10Gi Longhorn PVC
- `VirtualMachine` with **two interfaces**:
  - `default` — masquerade on pod network (for outbound internet)
  - `lan` — bridge mode via `lan-macvlan` NAD (for LAN access with static IP)
- Cloud-init `networkData` sets static IP (e.g. `192.168.7.201/24`) on the LAN interface
- Cloud-init `userData` creates user + installs pihole via unattended script
- **No LoadBalancer Service needed** — LAN devices reach the VM directly

---

## File Summary

| Action | File | Purpose |
|--------|------|---------|
| Create | `registry/multus.yaml` | ArgoCD app for Multus |
| Create | `apps/multus/multus-daemonset.yaml` | Multus thick-plugin DaemonSet |
| Create | `registry/cdi.yaml` | ArgoCD app for CDI |
| Create | `apps/cdi/cdi-operator.yaml` | CDI operator manifest |
| Create | `apps/cdi/cdi-cr.yaml` | CDI custom resource |
| Modify | `apps/kubevirt/kubevirt-cr.yaml` | Add DataVolumes feature gate |
| Create | `apps/kubevirt/net-attach-def.yaml` | macvlan NAD for LAN access |
| Create | `apps/kubevirt/vms/pihole.yaml` | Example VM using the new infra |

All paths relative to `kubernetes/clusters/portland/`.

---

## Key Pattern for Future VMs

Once the infrastructure is in place, any new VM that needs a LAN IP follows this template:

```yaml
# In the VM spec:
interfaces:
  - name: default
    masquerade: {}        # pod network (internet access)
  - name: lan
    bridge: {}            # real LAN NIC
networks:
  - name: default
    pod: {}
  - name: lan
    multus:
      networkName: lan-macvlan

# In cloud-init networkData:
version: 2
ethernets:
  enp2s0:                 # second NIC = LAN
    addresses:
      - 192.168.7.XXX/24
```

Pick a static IP outside MetalLB range (50-150) and your DHCP range.

---

## Known Caveats

- **macvlan host isolation**: The K3s node running the VM cannot directly reach the VM's LAN IP (macvlan limitation). All other LAN devices can.
- **NIC naming inside VM**: The names `enp1s0`/`enp2s0` are based on PCI bus order. If they don't match, boot once and run `ip addr` to check.
- **Talos migration**: Multus CNI paths revert to upstream defaults (`/etc/cni/net.d`, `/opt/cni/bin`). Talos also supports Multus as a system extension.
- **DataVolume import**: First boot takes a few minutes while CDI downloads the Ubuntu image (~700MB).

---

## Verification

```bash
# Multus running on all nodes
kubectl get pods -n kube-system -l app=multus

# NAD exists
kubectl get net-attach-def -n kubevirt

# CDI healthy
kubectl get pods -n cdi

# DataVolume imported
kubectl get dv -n kubevirt pihole-rootdisk  # Phase: Succeeded

# VM running with both interfaces
kubectl get vmi -n kubevirt pihole-vm
virtctl console pihole-vm -n kubevirt
# → ip addr show (expect two NICs)

# Reachable from LAN (from any device, not the host node)
ping 192.168.7.201
dig @192.168.7.201 google.com
curl http://192.168.7.201/admin
```
