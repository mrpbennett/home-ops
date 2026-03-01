# Fixing ArgoCD Sync Failure for KubeVirt VirtualMachine Resources

**Date:** 2026-03-01

## The Problem

After adding a `KubeVirt` CR and a `VirtualMachine` manifest to the kubevirt ArgoCD Application,
the sync kept failing with:

```
one or more synchronization tasks are not valid
VirtualMachine.kubevirt.io "" not found
```

The sync was stuck in a retry loop (hit limit: 5) and the app health showed `Missing`.

## Root Cause

KubeVirt has a two-stage CRD installation process:

1. `kubevirt-operator.yaml` installs the operator and the `kubevirts.kubevirt.io` CRD.
2. The `KubeVirt` CR (`kubevirt-cr.yaml`) tells the operator to install itself fully.
3. The operator then dynamically creates the remaining CRDs — including `virtualmachines.kubevirt.io` — as part of its own startup.

The `VirtualMachine` CRD is **never present in the git repo**. It only exists in the cluster after
the KubeVirt operator has successfully processed the `KubeVirt` CR and run to completion.

When ArgoCD syncs the application, it performs a **dry-run validation** against every resource
before applying anything. For a `VirtualMachine` resource, this dry-run requires the
`virtualmachines.kubevirt.io` CRD to exist in the cluster. On a fresh sync (or if the operator
hasn't fully initialised yet), the CRD is absent — so the dry-run fails and blocks the entire sync.

The cryptic `VirtualMachine.kubevirt.io "" not found` message is ArgoCD failing to look up the CRD
schema, not a missing resource by name.

## The Fix

Add the `SkipDryRunOnMissingResource` sync option to any resource whose CRD is installed
dynamically (i.e. not present in the repo):

```yaml
# kubernetes/clusters/portland/apps/kubevirt/vms/testvm.yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
```

This tells ArgoCD to skip the pre-sync dry-run for this resource when its CRD does not exist yet.
Once the KubeVirt operator is healthy and has installed the `virtualmachines.kubevirt.io` CRD,
ArgoCD will apply the `VirtualMachine` on the next sync cycle without any further intervention.

## How to Diagnose This Class of Error

Check the sync result for the affected ArgoCD Application:

```bash
kubectl get application <app-name> -n argocd -o yaml
```

Look for a `syncResult.resources` entry where `status: SyncFailed` and the message contains
`"" not found` (empty name). This pattern means ArgoCD cannot find the CRD for that resource kind
— it is not a missing object instance, it is a missing CRD schema.

To confirm, check whether the CRD exists in the cluster:

```bash
kubectl get crd virtualmachines.kubevirt.io
```

If the CRD is absent, the resource has a dynamic dependency on another controller to install it.

## When to Use This Pattern

Use `SkipDryRunOnMissingResource=true` on any resource that meets **all** of these criteria:

- Its CRD is not defined in the same repo (i.e. not in any YAML Argo is managing directly).
- The CRD is installed dynamically by an operator at runtime.
- The operator itself is in the same ArgoCD Application (or a dependency app that may not be
  fully ready yet).

Common examples in home-ops / self-hosted clusters:

| Operator | Dynamically installed CRDs |
|---|---|
| KubeVirt | `virtualmachines.kubevirt.io`, `virtualmachineinstances.kubevirt.io`, etc. |
| cert-manager | `certificates.cert-manager.io`, `issuers.cert-manager.io`, etc. (if operator and CRs are in the same app) |
| Prometheus Operator | `prometheusrules.monitoring.coreos.com`, `servicemonitors.monitoring.coreos.com`, etc. |

## Alternative Approaches

**Separate ArgoCD Applications with sync-wave ordering** — put the operator in one app (wave 0)
and the CRs/VMs in a dependent app (wave 1). This gives stronger ordering guarantees but adds
operational overhead of managing multiple apps.

**Sync waves within a single app** — annotate resources with `argocd.argoproj.io/sync-wave`
to control apply order. This helps with CRDs that _are_ in the repo, but does **not** solve the
problem of CRDs installed dynamically by an operator, since those will never appear in a sync wave.

`SkipDryRunOnMissingResource=true` is the simplest and most appropriate fix for operator-managed
CRDs that are outside of git.

## Gotcha: virt-handler CrashLoopBackOff on Raspberry Pi (inotify limits)

If you're running KubeVirt on a Raspberry Pi (or any low-resource ARM node), you may see
`virt-handler` pods crash immediately after the operator comes up:

```
fatal: Failed to create an inotify watcher
reason: too many open files
```

**This is not a RAM or CPU problem.** It is a kernel parameter ceiling. Raspberry Pi OS ships with
very low inotify defaults (typically `max_user_watches=8192`, `max_user_instances=128`). k3s,
containerd, and system services consume most of the available watchers before KubeVirt starts.
`virt-handler` needs to add its own certificate file watchers and hits the limit.

Note: the ARM64 architecture warning in the logs is expected and harmless:
```
host-model cpu mode is not supported for arm64 architecture
```

**Fix:** SSH into each affected worker node and raise the limits:

```bash
# Check current values
cat /proc/sys/fs/inotify/max_user_watches
cat /proc/sys/fs/inotify/max_user_instances

# Apply immediately (no reboot required)
sudo sysctl -w fs.inotify.max_user_watches=524288
sudo sysctl -w fs.inotify.max_user_instances=512

# Make persistent across reboots
echo -e "fs.inotify.max_user_watches=524288\nfs.inotify.max_user_instances=512" | sudo tee /etc/sysctl.d/99-inotify.conf
```

This is a known k3s-on-Pi issue — k3s's own documentation recommends bumping these values even
without KubeVirt. KubeVirt just pushes you over the default limit faster.

After applying, delete the crashed handler pod to force a restart:

```bash
kubectl delete pod -n kubevirt <virt-handler-pod-name>
```

## Lessons Learned

- **Not all CRDs come from your repo.** Operators like KubeVirt install their own CRDs at runtime.
  Any resource that depends on those CRDs will fail ArgoCD's dry-run until the operator is healthy.
- **`"" not found` in an ArgoCD sync error means the CRD is missing**, not the resource instance.
  The empty string is the group/version/kind lookup result, not the object name.
- **`SkipDryRunOnMissingResource=true` is safe for this use case.** The resource will simply be
  skipped until the CRD exists, then applied on the next sync. No manual intervention required.
- **Check operator health before debugging sync failures.** If the operator hasn't finished
  installing its CRDs, downstream resources will always fail. Confirm the operator pod is `Running`
  and the `KubeVirt` CR phase is `Deployed` before investigating further.
- **On Raspberry Pi, raise inotify limits before deploying KubeVirt.** The defaults are too low
  for k3s + KubeVirt combined. Add `fs.inotify.max_user_watches=524288` and
  `fs.inotify.max_user_instances=512` to `/etc/sysctl.d/99-inotify.conf` on every node.
