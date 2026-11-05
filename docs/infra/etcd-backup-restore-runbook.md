# etcd backup and restore runbook

Status: backup is running; **restore has not been tested**. Written 2026-11-05.
Design background and the planned in-cluster second path: `docs/plans/2026-10-19-talos-etcd-backup.md`.

## What is backed up

A cron job in `pb`'s crontab on the Pi (`node-pi-3`) runs `scripts/k8s/backup-to-nas.sh` daily at 02:30. The cron entry puts the
mise-installed `talosctl` on `PATH` and logs to `~/.local/state/k8s-backup.log`. Cron does not catch up if the Pi was off at 02:30.

| Backup | Source | Destination (NAS share mounted at `/mnt/k8s-backups`) |
| --- | --- | --- |
| etcd | `talosctl etcd snapshot`, via `192.168.7.1`, falling back to `.2` then `.3` | `etcd/etcd-<timestamp>.snapshot.gz` |
| Talos config and secrets | `servers/talos-cluster/` (includes gitignored `secrets.yaml` and `talosconfig`) | `talos-cluster/talos-cluster-<timestamp>.tar.gz` |
| Terraform Vault state | `terraform/vault/` (includes `terraform.tfstate*`, `terraform.tfvars`) | `terraform-vault/terraform-vault-<timestamp>.tar.gz` |

- NAS: `192.168.4.110:/mnt/HD/HD_a2/backups/k8s`. It only speaks NFSv3. fstab entry uses `vers=3,_netdev,nofail,x-systemd.automount`.
- Retention: the 14 newest of each type (`BACKUP_KEEP`). Files are mode `600`.
- **Archives are not encrypted.** An etcd snapshot contains every Kubernetes Secret in plaintext, and the NAS export is open to `*`.

Day-to-day checks:

```sh
crontab -l
tail -n 30 ~/.local/state/k8s-backup.log
ls -lh /mnt/k8s-backups/etcd
/home/pb/home-operations/operations/scripts/k8s/backup-to-nas.sh      # run a backup now
```

If the NAS is down the job exits non-zero and nothing alerts. Check the log.

## When to restore (and when not to)

etcd is replicated across all three nodes, so a snapshot restore is for **quorum loss or corruption**, not for losing one node.

| Situation | Action |
| --- | --- |
| One node dead or etcd broken on one node, other two healthy | Do **not** restore. Remove the member and rejoin or replace the node (`talosctl etcd members`, `talosctl etcd remove-member`, reset the node, apply config). |
| Two or three nodes lost, or etcd corrupted everywhere | Restore from a snapshot (below). |
| All nodes and disks gone | Rebuild from `secrets.yaml` and `talosconfig` in the Talos archive, then restore etcd. |

## Warning: the restore wipes Longhorn data on the nodes it touches

Each node has a single NVMe. Talos's `EPHEMERAL` partition is `/var`, and Longhorn stores its replicas in
`/var/lib/longhorn`, so resetting `EPHEMERAL` destroys the local Longhorn replicas on that node. If you do that on all three
nodes, every Longhorn volume is lost locally and must be restored from the Longhorn NAS backups
(`longhorn-backups` export). CNPG restores from its own backups. Check what is current in Longhorn before you start.
I know of no Talos API that wipes only the etcd data directory. Confirm against the Talos disaster-recovery docs for the
running version (Talos v1.14.x) before running the steps.

## Restore procedure

Run from `/home/pb/home-operations/operations/servers/talos-cluster`, with `TALOSCONFIG=$PWD/talosconfig`. These steps are disruptive. Get explicit approval first.

1. Get the snapshot and the Talos config.
   ```sh
   mkdir -p ~/restore && cd ~/restore
   gunzip -c /mnt/k8s-backups/etcd/etcd-<timestamp>.snapshot.gz > etcd.snapshot
   ```
   If `talosconfig` and `secrets.yaml` are gone, extract them from `/mnt/k8s-backups/talos-cluster/talos-cluster-<timestamp>.tar.gz`.
2. Check the state. `talosctl --nodes 192.168.7.1,192.168.7.2,192.168.7.3 service etcd` and `talosctl etcd status`.
   If etcd still runs on a node, take a fresh snapshot first: `talosctl --nodes <ip> etcd snapshot fresh.snapshot`.
3. Wipe etcd on **every** control-plane node (this also wipes `/var`, see the warning above).
   ```sh
   talosctl --nodes <ip> reset --graceful=false --reboot --system-labels-to-wipe=EPHEMERAL
   ```
4. Wait until `talosctl --nodes <ip> service etcd` shows `Preparing` on each node (the API and kubelet stay down until bootstrap).
5. Bootstrap one node from the snapshot. Use `--recover-skip-hash-check` only if the file was copied from an etcd data directory instead of taken with `etcd snapshot`.
   ```sh
   talosctl --nodes 192.168.7.1 bootstrap --recover-from=./etcd.snapshot
   ```
   The other two nodes join automatically.
6. Verify.
   ```sh
   talosctl etcd members
   talosctl kubeconfig --force          # refresh kubeconfig if the CA changed
   kubectl --context portland get nodes
   kubectl --context portland get applications -n argocd
   ```
7. Aftermath: objects created after the snapshot are gone. Argo CD reconciles everything that is in git. Longhorn volumes
   come back as faulted or missing, so restore them from the NAS backups (`docs/infra/backup-stratergy.md`, section 7).
   Re-create any hand-made secrets and Argo CD repo credentials that were not in git or Vault.

## To do

- Test the restore on a throwaway single-node Talos VM (plan Part 4) and record the date here. Repeat quarterly.
- Encrypt the archives with `age`, or restrict the NAS export to the Pi and the nodes.
- Add a failure alert for the cron job, and an off-NAS copy.
