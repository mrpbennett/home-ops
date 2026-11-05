#!/usr/bin/env python3
"""Back up Terraform state and Talos config (including gitignored secrets) to the NAS NFS share.

Share: 192.168.4.110:/mnt/HD/HD_a2/backups/k8s, mounted at /mnt/k8s-backups (see /etc/fstab).
"""

import gzip
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path

REPO: Path = Path(__file__).resolve().parents[2]
DEST = Path(os.environ.get("BACKUP_DEST", "/mnt/k8s-backups"))
KEEP = int(os.environ.get("BACKUP_KEEP", "14"))
STAMP: str = datetime.now().strftime("%Y%m%d-%H%M%S")
NODES: list[str] = ["192.168.7.1", "192.168.7.2", "192.168.7.3"]
EXCLUDE: set[str] = {".terraform", "rendered"}

os.umask(0o077)


def check_mount() -> None:
    # Listing the path triggers the systemd automount, then confirm it is really NFS.
    next(DEST.iterdir(), None)
    if subprocess.run(["findmnt", "-n", "-t", "nfs", str(DEST)], capture_output=True).returncode:
        sys.exit(f"{DEST} is not an NFS mount, refusing to write")


@contextmanager
def backup_file(name: str, suffix: str, what: str):
    """Yield a temp path to write DEST/name/name-STAMP<suffix>, then publish it and keep the newest KEEP."""
    out_dir = DEST / name
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{name}-{STAMP}{suffix}"
    part = Path(f"{out}.part")  # don't leave a truncated file under the final name
    try:
        yield part
        part.rename(out)
    finally:
        part.unlink(missing_ok=True)
    # Timestamped names sort chronologically.
    for old in sorted(out_dir.glob(f"{name}-*{suffix}"), reverse=True)[KEEP:]:
        old.unlink()
    print(f"backed up {what} -> {out}")


def backup_dir(name: str, rel_dir: str) -> None:
    def skip_excluded(ti: tarfile.TarInfo):
        return None if EXCLUDE & set(Path(ti.name).parts) else ti

    with backup_file(name, ".tar.gz", rel_dir) as part, tarfile.open(part, "w:gz") as tar:
        tar.add(REPO / rel_dir, arcname=rel_dir, filter=skip_excluded)


def backup_etcd() -> None:
    env = {**os.environ, "TALOSCONFIG": str(REPO / "servers/talos-cluster/talosconfig")}
    with tempfile.TemporaryDirectory() as tmp:
        snap = Path(tmp) / "etcd.snapshot"
        for node in NODES:
            try:
                subprocess.run(
                    ["talosctl", "--nodes", node, "--endpoints", node, "etcd", "snapshot", str(snap)],
                    env=env,
                    check=True,
                )
                break
            except (subprocess.CalledProcessError, FileNotFoundError) as e:
                print(f"etcd snapshot via {node} failed ({e}), trying next node", file=sys.stderr)
        else:
            raise RuntimeError("etcd snapshot failed on all nodes")

        with (
            backup_file("etcd", ".snapshot.gz", f"etcd (via {node})") as part,
            open(snap, "rb") as src,
            gzip.open(part, "wb") as dst,
        ):
            shutil.copyfileobj(src, dst)


def main() -> int:
    check_mount()
    rc = 0
    for step in (
        lambda: backup_dir("terraform-vault", "terraform/vault"),
        lambda: backup_dir("talos-cluster", "servers/talos-cluster"),
        backup_etcd,
    ):
        try:
            step()
        except Exception as e:
            print(f"error: {e}", file=sys.stderr)
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
