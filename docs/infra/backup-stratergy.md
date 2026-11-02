# Cluster Backup & Recovery Plan

Talos Kubernetes cluster (3 nodes) with Longhorn block storage, SeaweedFS object storage, an off-cluster NFS server, and an off-site GCP copy.

> Items marked **(suggested)** are recommended values to confirm or adjust. Everything else reflects the current layout diagram.

---

## 1. Architecture summary

| Layer | Component | Role |
| --- | --- | --- |
| Compute | Talos cluster (3 nodes) | Runs all workloads |
| Block storage | Longhorn (LH), replicated across all nodes | Live data for PostgreSQL (CNPG), Valkey, Loki log PVC |
| Object storage | SeaweedFS (in cluster) | CNPG backups/WAL, Loki buckets |
| SeaweedFS volumes | PVCs on NFS via nfs-csi | Keeps object data off the cluster |
| Off-cluster backup | NFS server | Longhorn backup target; backing store for SeaweedFS |
| Off-site | GCP (GCS bucket) | Copy of NFS contents |

Databases served by the PostgreSQL layer: Forgejo/Gitea-style git service, Keycloak, and one further app (see the databases group in the diagram).

---

## 2. Backup objectives

| Data | RPO (max data loss) | RTO (time to restore) | Notes |
| --- | --- | --- | --- |
| PostgreSQL (CNPG) | Minutes (WAL archiving) **(suggested)** | 1-2 hours **(suggested)** | Point-in-time recovery |
| Valkey | Up to 24h, or none if purely a cache | Minutes | Confirm cache vs. persistent |
| Loki logs | Best effort | Not critical | Low DR value |
| Other Longhorn PVCs | 24h | A few hours **(suggested)** | Daily backups |
| Cluster config (Talos, manifests) | Last commit | 1-2 hours | Lives in git, see section 8 |

---

## 3. Backup flows

### 3.1 Live data: Longhorn replication

- All Longhorn volumes use **3 replicas**, one per node **(suggested)**.
- This protects against node or disk failure only. It is **not** a backup.

### 3.2 PostgreSQL (CNPG)

- **Primary recovery path:** CNPG `barmanObjectStore` backups to SeaweedFS (S3 API).
  - Continuous WAL archiving.
  - Scheduled base backup (`ScheduledBackup`): daily **(suggested)**.
- **Secondary:** Longhorn volume backups of the DB PVCs (crash-consistent only; safety net, not the primary restore method).
- Retention (CNPG `retentionPolicy`): 30 days **(suggested)**.

### 3.3 Valkey

- Data PVC on Longhorn, included in the Longhorn backup schedule.
- If Valkey is used only as a cache, exclude it from backups.

### 3.4 Loki

- Chunks and index live in SeaweedFS buckets.
- Log-data PVC on Longhorn (WAL/cache); backed up with the other Longhorn volumes, or excluded to save space.
- Retention set in Loki (e.g. 14-30 days **(suggested)**); not copied off-site, or given a short retention there.

### 3.5 Longhorn volume backups to NFS

- Recurring jobs: **daily** (keep 7) and **weekly** (keep 4) **(suggested)**.
- Backup target: NFS share on the off-cluster server.
- Apply jobs via Longhorn recurring-job groups so new PVCs are picked up automatically.

### 3.6 SeaweedFS storage

- Volume data is stored on PVCs provisioned by nfs-csi, so it physically lives on the NFS server.
- Treat SeaweedFS as a **backup transport**, not a primary copy of anything.

### 3.7 Off-site copy to GCP

- Source: NFS server.
- Destination: GCS bucket (Nearline or Coldline class **(suggested)**).
- Method: an encrypting sync tool (restic, or rclone with crypt) on a schedule, nightly **(suggested)**.
- **Consistency caution:** do not file-copy a live SeaweedFS volume directory. Choose one of:
  1. Add a second CNPG `barmanObjectStore` destination pointing directly at GCS, or
  2. Use SeaweedFS's own remote-storage/replication to GCS, or
  3. Sync the Longhorn backup directory only, and treat CNPG-in-SeaweedFS as covered by option 1 or 2.
- Exclude Loki chunk data, or give it a short lifecycle rule.

---

## 4. Schedule overview

| Time | Job |
| --- | --- |
| Continuous | CNPG WAL archiving to SeaweedFS |
| Daily 01:00 **(suggested)** | CNPG base backup |
| Daily 02:00 **(suggested)** | Longhorn daily backup to NFS |
| Sunday 03:00 **(suggested)** | Longhorn weekly backup to NFS |
| Daily 04:30 **(suggested)** | NFS to GCP sync (runs after the backups above finish) |

---

## 5. Security

- Encrypt before data leaves the house (restic or rclone crypt, or GCS CMEK).
- Use a **narrowly scoped service account** for the sync: write/append only, no bucket delete.
- Enable **object versioning** and a retention/lock policy on the GCS bucket so a compromised cluster or NAS cannot erase the off-site copy.
- Store encryption keys and service-account credentials outside the cluster and the NFS server (password manager plus an offline copy).
- Restrict NFS exports to the cluster node IPs; no public exposure.

---

## 6. Monitoring and alerting

Alert on **age of last successful backup** at every hop:

| Hop | Signal | Alert if |
| --- | --- | --- |
| CNPG WAL archiving | `cnpg_collector_pg_wal_archive_status`, last archived time | No WAL archived for 15 min **(suggested)** |
| CNPG base backup | Last successful backup timestamp | Older than 26h |
| Longhorn to NFS | Backup status / last backup time per volume | Older than 26h |
| NFS to GCP | Job exit status and last-success timestamp | Older than 36h |
| NFS capacity | Free space on the NAS | Below 20% |
| Longhorn | Volume health (degraded/faulted) | Any degraded > 30 min |

Use a dead-man's-switch (e.g. a healthcheck ping) for the NFS to GCP job so silent failures are caught.

---

## 7. Restore runbooks

### 7.1 Single volume lost or corrupted (cluster healthy)

1. In Longhorn, restore the volume from the latest NFS backup.
2. Recreate the PV/PVC bound to the restored volume.
3. Restart the workload and verify.

### 7.2 PostgreSQL recovery

1. Create a new CNPG `Cluster` with `bootstrap.recovery` pointing at the SeaweedFS (or GCS) object store.
2. Optionally set a `recoveryTarget.targetTime` for point-in-time recovery.
3. Verify data, then repoint applications (or promote the recovered cluster under the original name).

### 7.3 Node loss

1. Replace or reinstall the Talos node and rejoin it to the cluster.
2. Longhorn rebuilds replicas automatically; watch for volumes returning to healthy.

### 7.4 Full cluster rebuild (NAS survives)

Restore in dependency order:

1. Rebuild Talos cluster from machine configs and cluster manifests in git.
2. Install the CSI drivers (Longhorn, nfs-csi).
3. Bring up **NFS mounts, then SeaweedFS** (its volumes live on NFS).
4. Point Longhorn at the existing NFS backup target and restore volumes.
5. Restore PostgreSQL via CNPG recovery from SeaweedFS.
6. Restore Valkey, Loki, then applications.

### 7.5 Disaster: NAS lost (or site lost)

1. Provision replacement NFS storage.
2. Pull the latest copy from GCP (decrypt with offline keys).
3. Restore the NFS contents, then follow 7.4 from step 1.

---

## 8. Configuration backup (not shown in the diagram)

- Talos machine configs and secrets: encrypted in git (e.g. SOPS/age) plus an offline copy.
- Kubernetes manifests / Helm values / GitOps repo: in git, with the git service itself being a dependency. Keep a mirror somewhere independent of the cluster (a hosted git remote).
- **etcd:** take periodic `talosctl etcd snapshot` backups and store them on NFS and in GCP **(suggested: daily)**.
- Backup-tool secrets (S3 credentials for CNPG, Longhorn backup target secret, GCS credentials): in the secrets manager or encrypted in git.

---

## 9. Testing schedule

| Test | Frequency | Success criteria |
| --- | --- | --- |
| CNPG point-in-time restore into a scratch namespace | Quarterly **(suggested)** | Data matches expected time; record duration |
| Longhorn volume restore from NFS | Quarterly | Volume mounts, app starts |
| Restore a sample from GCP (decrypt + verify) | Twice a year | Files intact, keys work |
| Full rebuild drill (NAS-lost scenario) | Yearly | Meets RTO targets |

Record the date, duration, and issues found after each test.

---

## 10. Open items / decisions

- [ ] Decide how SeaweedFS-held CNPG backups reach GCP (second barman destination vs. SeaweedFS remote sync).
- [ ] Confirm whether Valkey holds data that must survive, or is purely a cache.
- [ ] Decide whether Loki data is synced off-site at all.
- [ ] Confirm per-database needs: PITR vs. nightly dumps (git service, Keycloak, third app).
- [ ] Set GCS bucket versioning, lifecycle, and retention lock.
- [ ] Implement and test all alerts in section 6.
- [ ] Run the first full restore test and record RTO/RPO actuals.
