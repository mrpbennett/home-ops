# KubeVirt VM rename pruned the old VM, orphaned its disk, and left SSH with no endpoints

**Date:** 2026-10-22
**Status:** Open (VM running on a fresh disk; SSH service still has no endpoints, fix not yet in git)
**Duration:** 12:09 UTC to ongoing (VM never down for more than seconds; SSH unreachable since 12:09 UTC)
**Impact:** The `ubuntu-vm` guest was replaced by `dor1-kv-ubuntu` on a fresh disk. SSH to the VM has not worked since the rename.

## Summary

Commit `ad0f018a` renamed the VM `ubuntu-vm` to `dor1-kv-ubuntu` in git. Argo CD
(`prune: true`) deleted the old VM and created a new one. A VM rename is a delete
and create, not an update. The new VM reused the old DataVolume name
(`ubuntu-vm-rootdisk`), which was already mid-delete, so for about 35 minutes
it ran on a PVC in `Terminating`. That was fixed by renaming the DataVolume
(`1e804771`) and restarting the VM, which moved it to a fresh, empty-state disk
and let the old PVC be deleted. Separately, the same commit changed the SSH
Service selector to `dor1-kv-ubuntu-ssh`, which matches no pod, so SSH to
`192.168.7.17` has no endpoints. The selector fix is still outstanding.

## Impact

- **VM replaced, not preserved.** The old guest disk (`ubuntu-vm-rootdisk`,
  20Gi) was deleted. The new VM booted a fresh `ubuntu:22.04` containerdisk
  import. Whether anything on the old disk mattered was not stated; no backup existed
  (Longhorn backups and Velero are disabled).
- **SSH unreachable.** The old Service (`ubuntu-vm-ssh`, `192.168.7.15`) was pruned.
  The new Service (`dor1-kv-ubuntu-ssh`, `192.168.7.17`) has `ENDPOINTS <none>`.
- **Monitoring.** The Gatus check `dor1-kv-ubuntu SSH` (`tcp://192.168.7.17:22`)
  should be failing. Not verified; whether the Discord alert fired was not checked.
- **Not affected:** other apps, the other namespaces, and Argo CD health
  (`kubevirt-vms` stayed `Synced/Healthy` throughout, which is why it hid the problem).
- **Data loss:** yes, the old guest disk contents (reported by the user as a
  deliberate choice to move to a fresh disk; the data's value is unknown).
  No security exposure.

## Timeline

| Time (UTC) | Event | Source |
| ---------- | ----- | ------ |
| 12:08:10 | Commit `ad0f018a` "naming infra updates": renames VM, SSH Service and its selector; deletes `test-vm.yaml` (`vm-lzz4r`) | git (commit time 13:08:10 +01:00) |
| 12:09:24 | Argo sync of `kubevirt-vms` at `ad0f018a`, initiated by a user (not automated); old DataVolume gets a deletion timestamp | argocd history id 3, DV `deletionTimestamp` |
| 12:09:25 | `dor1-kv-ubuntu` VM created; launcher pod scheduled on `kube-cp-1`, maps the old PVC `pvc-20e4db94…` | events |
| 12:09 | `ubuntu-vm` and `vm-lzz4r` shut down; `ubuntu-vm-ssh` (`.15`) pruned; `dor1-kv-ubuntu-ssh` gets `192.168.7.17` | events |
| 12:21:14 | Commit `0ac397bd`: Gatus check repointed to `192.168.7.17:22` | git |
| ~12:22 | User reports the VM "hasn't come back"; first check finds VM `Running` but PVC `Terminating` | user, kubectl |
| 12:29:10 | Commit `1e804771` renames DataVolume to `dor1-kv-ubuntu-rootdisk` | git |
| 12:30:55 | Automated sync of `1e804771`; new DataVolume imported, PVC bound (~12:31 to 12:35) | argocd history id 4, events |
| 12:33:04 | VM gets `RestartRequired` ("a non-live-updatable field was changed in the template spec") | VM conditions |
| ~12:45 | User restarts the VM; new launcher pod attaches `pvc-5deee4ea…`; old DV, PVC and Longhorn volume are gone | user, kubectl |
| ~12:55 | Service `dor1-kv-ubuntu-ssh` found with `ENDPOINTS <none>`; selector `vm.kubevirt.io/name=dor1-kv-ubuntu-ssh` vs pod label `vm.kubevirt.io/name=dor1-kv-ubuntu` | kubectl |

## Root Cause

### Trigger

A rename in `kubernetes/clusters/portland/apps/kubevirt/vms/ubuntu-test.yaml`
(the `&vm_name` anchor and the Service) without a plan for what a rename does
to a running VM and its disk.

### Cause 1: renaming a VM is a delete and create, with the disk tied to the old VM

Argo CD runs with `prune: true` and `selfHeal: true`
(`kubernetes/appsets/kubevirt/appset-kubevirt-vms.yaml`). The old
`VirtualMachine` was removed from git, so it was pruned. Its DataVolume (created from
`dataVolumeTemplates`) went with it. The `longhorn-kubevirt` StorageClass has
`reclaimPolicy: Delete` (verified), so deleting the PVC deletes the Longhorn volume.

The disk deletion mechanism is **inferred**: the DataVolume's owner reference to the
old VM was not inspected before it was gone. What was observed: the DV got a
deletion timestamp (`12:09:24Z`) and `foregroundDeletion` finalizer at the same moment
as the sync.

### Cause 2: the new VM reused the name of a DataVolume that was mid-delete

`dataVolumeTemplates` in the new VM still named `ubuntu-vm-rootdisk`. KubeVirt
attached the existing, `Terminating` PVC instead of creating a new one. The PVC was
held only by `kubernetes.io/pvc-protection` while the launcher pod used it, so
any restart would have deleted the disk under the VM.

```
persistentvolumeclaim/ubuntu-vm-rootdisk   Terminating   pvc-20e4db94-…   20Gi   RWX   longhorn-kubevirt
```

### Cause 3: Service selector changed to a value that matches no pod (open)

In `ad0f018a` the Service selector became:

```yaml
  selector:
    vm.kubevirt.io/name: dor1-kv-ubuntu-ssh   # pod label is dor1-kv-ubuntu
```

The `-ssh` suffix belongs on the Service name, not on the label value. The `&vm_name`
anchor cannot be reused here because YAML anchors are scoped to a single document
and the Service is a separate document.

### Contributing factors

- **Argo CD showed `Synced/Healthy` the whole time.** A Service with no endpoints and a
  `Terminating` PVC held by a running pod are both healthy as far as Argo is concerned.
- **No dry-run of what a prune would delete.** The Argo diff before sync would have shown
  the `VirtualMachine`/`Service` deletions, but nothing flagged the disk.
- **LB IP is not pinned.** The Service has no `metallb.io/loadBalancerIPs` annotation,
  so `192.168.7.17` was allocated from the pool and may change. The commit named
  "static ip change" suggests a fixed IP was intended.
- **`vm-lzz4r` was deleted deliberately.** `test-vm.yaml` was removed in the same commit,
  so its shutdown was expected, not a fault.

## Detection

- Noticed by the user about 13 minutes after the sync (VM looked like it hadn't come back).
- The Gatus SSH check was repointed at 12:21 UTC and should have started failing then.
  Whether an alert fired was not checked.
- The `Terminating` PVC was found by a read-only `kubectl get pvc`, not by any alert.
- The empty Service endpoints were found about 45 minutes later, only after a manual look.

## Resolution

1. **Actual fix for the disk:** commit `1e804771` renamed the DataVolume template and
   volume reference to `dor1-kv-ubuntu-rootdisk`. Argo created a new DV and PVC.
2. User restarted the VM (`RestartRequired` cleared). It attached the new PVC, and the old
   PVC and Longhorn volume `pvc-20e4db94…` were deleted. Verified: no old PVC or volume remains.
3. **Not yet fixed:** the SSH Service selector (see action items).

## What Went Well / What Went Poorly

- Went well: the disk problem was caught while the old PVC was still attached, and the
  fix went through git, not `kubectl patch`.
- Went well: the rename-then-restart ordering avoided the VM losing its disk mid-run.
- Went poorly: renaming a stateful resource had no pre-check for what pruning would delete.
- Went poorly: the first read-only checks declared the VM "up" from `Running/Ready`
  and the advertised SSH IP, without testing SSH or looking at the Service endpoints.
  That left the selector bug undetected for about 45 minutes.
- Went poorly: no backup path exists (Velero and Longhorn backups are disabled).

## Action Items

| Type | Action | Where | Status |
| ---- | ------ | ----- | ------ |
| Prevent | Fix Service selector to `vm.kubevirt.io/name: dor1-kv-ubuntu` | `kubernetes/clusters/portland/apps/kubevirt/vms/ubuntu-test.yaml` (line 91) | Todo |
| Prevent | Pin the SSH LB IP with `metallb.io/loadBalancerIPs: 192.168.7.17` on the Service (same idiom as `kubernetes/appsets/vault-helm/appset-helm-vault.yaml`) | `kubernetes/clusters/portland/apps/kubevirt/vms/ubuntu-test.yaml` | Todo |
| Prevent | Update the stale VM name, IP and size (`ubuntu-vm`, `192.168.7.15`) | `AGENTS.md` lines 62 and 107 | Todo |
| Prevent | Add `argocd.argoproj.io/sync-options: Prune=false` (or `PruneLast=true`) on VMs that own a disk, so a rename or removal needs a deliberate step | `kubernetes/clusters/portland/apps/kubevirt/vms/ubuntu-test.yaml` | Todo |
| Mitigate | Add a VM rename/removal runbook: back up or clone the Longhorn volume first, then rename the DataVolume in the same commit | `docs/` (new file, e.g. `docs/kubevirt-vm-rename.md`) | Todo |
| Mitigate | Decide whether the `longhorn-kubevirt` class should use `Retain` for VM disks. Today's `Delete` removes the data as soon as the PVC goes. Class is defined in the Longhorn appset values | `kubernetes/appsets/longhorn-helm/appset-helm-longhorn.yaml` | Todo (decision needed) |
| Detect | Confirm the Gatus `dor1-kv-ubuntu SSH` check fails and alerts on a no-endpoint Service; if it didn't alert, find out why | `kubernetes/appsets/gatus-helm/appset-helm-gatus.yaml` (line 229) | Todo |
| Detect | Add an alert for LoadBalancer Services with zero endpoints | `monitoring` alert rules manifests | Todo |
| Detect | Gatus SSH check repointed to the new name and IP | `kubernetes/appsets/gatus-helm/appset-helm-gatus.yaml` | Done (`0ac397bd`) |
| Prevent | DataVolume renamed so the VM no longer shares a name with the deleted one | `kubernetes/clusters/portland/apps/kubevirt/vms/ubuntu-test.yaml` | Done (`1e804771`) |

## Lessons Learned

**Renaming a Kubernetes resource is a delete plus a create.** With `prune: true`, the old
object, and anything it owns (including the disk), is removed on sync.

**Don't reuse a name that is mid-delete.** The new VM latched onto a `Terminating` PVC.
Change the dependent resource's name in the same commit.

**"Running/Ready" is not "reachable".** A Service with `ENDPOINTS <none>` looks healthy to
Argo CD and `kubectl get vm`. Test the thing the user actually uses.

**YAML anchors don't cross `---` documents.** The `&vm_name` anchor can't be aliased
from the Service, so the label value was edited by hand and the suffix landed on the
wrong string.

## How to Diagnose This Class of Problem

```sh
# VM, disk, and who is holding it
kubectl --context portland get vm,vmi,datavolume,pvc -n kubevirt-vms
kubectl --context portland get pvc -n kubevirt-vms -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.deletionTimestamp}{"\n"}{end}'

# Does the Service actually reach the VM?
kubectl --context portland get svc,endpoints -n kubevirt-vms -o wide
kubectl --context portland get pod -n kubevirt-vms -l kubevirt.io=virt-launcher --show-labels

# What did Argo sync, and who started it?
kubectl --context portland get application kubevirt-vms -n argocd -o jsonpath='{.status.history}'
```

Compare the Service `selector` with the launcher pod labels. A `Terminating` PVC with a
`pvc-protection` finalizer and a running pod means the disk is about to be deleted.
Past related incident: `docs/postmortems/kubevirt-argocd-sync-fix.md`.
