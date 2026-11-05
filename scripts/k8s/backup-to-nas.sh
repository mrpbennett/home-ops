#!/usr/bin/env bash
# Back up Terraform state and Talos config (including gitignored secrets) to the NAS NFS share.
# Share: 192.168.4.110:/mnt/HD/HD_a2/backups/k8s, mounted at /mnt/k8s-backups (see /etc/fstab).
set -euo pipefail
umask 077

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="${BACKUP_DEST:-/mnt/k8s-backups}"
KEEP="${BACKUP_KEEP:-14}"
STAMP="$(date +%Y%m%d-%H%M%S)"

# Touch the path so the systemd automount triggers, then confirm it is really the NAS.
ls "$DEST" >/dev/null
findmnt -n -t nfs "$DEST" >/dev/null || { echo "$DEST is not an NFS mount, refusing to write" >&2; exit 1; }

backup() {
  local name="$1" dir="$2"
  mkdir -p "$DEST/$name"
  tar -C "$REPO" --exclude='.terraform' --exclude='rendered' -czf "$DEST/$name/$name-$STAMP.tar.gz" "$dir"
  # prune old archives, keep the newest $KEEP
  ls -1t "$DEST/$name"/"$name"-*.tar.gz | tail -n +"$((KEEP + 1))" | xargs -r rm -f --
  echo "backed up $dir -> $DEST/$name/$name-$STAMP.tar.gz"
}

backup_etcd() {
  local tmp node
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  export TALOSCONFIG="$REPO/servers/talos-cluster/talosconfig"
  for node in 192.168.7.1 192.168.7.2 192.168.7.3; do
    if talosctl --nodes "$node" --endpoints "$node" etcd snapshot "$tmp/etcd.snapshot"; then
      mkdir -p "$DEST/etcd"
      gzip -c "$tmp/etcd.snapshot" > "$DEST/etcd/etcd-$STAMP.snapshot.gz"
      ls -1t "$DEST/etcd"/etcd-*.snapshot.gz | tail -n +"$((KEEP + 1))" | xargs -r rm -f --
      echo "backed up etcd (via $node) -> $DEST/etcd/etcd-$STAMP.snapshot.gz"
      return 0
    fi
    echo "etcd snapshot via $node failed, trying next node" >&2
  done
  echo "etcd snapshot failed on all nodes" >&2
  return 1
}

rc=0
backup terraform-vault terraform/vault || rc=1
backup talos-cluster servers/talos-cluster || rc=1
backup_etcd || rc=1
exit "$rc"
