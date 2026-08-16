# volume-snapshots

Scheduled, tiered CSI snapshots of every Ceph-backed PVC in the cluster, with automatic pruning.
One config for the whole cluster; every snapshot is a normal namespaced `VolumeSnapshot`, so any
single app can be restored on its own.

## What is and isn't covered

| Storage | Covered by | Why |
|---|---|---|
| `ceph-block`, `ceph-filesystem` | **this** | RBD/CephFS CSI snapshots, copy-on-write |
| `local-path` (PostgreSQL, Prometheus) | CNPG Barman → S3 (`k8s/postgresql-clusters/`) | the local-path provisioner has no CSI snapshot support at all |
| static NFS PVs (Jellyfin/qBittorrent/Stump media) | TrueNAS ZFS snapshots + Glacier | no CSI driver involved |

Two things these snapshots are **not**:

- **Not offsite.** They live in the same Ceph cluster as the data. This covers accidental deletes,
  bad upgrades, and logical corruption — not loss of the cluster. Velero to S3 is the follow-up; the
  `VolumeSnapshotClass`es already carry `velero.io/csi-volumesnapshot-class: "true"` for it.
- **Not application-consistent.** Nothing is quiesced. Apps with embedded SQLite (Memos, Jellyfin,
  Stump, Vaultwarden) restore as if the node lost power. SQLite's WAL recovery handles that in
  practice, but it is not equivalent to a logical dump.

## Schedule and retention

| CronJob | Schedule (Europe/Tallinn) | Keeps | Window |
|---|---|---|---|
| `volume-snapshot-daily` | `0 3 * * *` | 14 | 2 weeks |
| `volume-snapshot-weekly` | `30 3 * * 0` | 8 | ~2 months |
| `volume-snapshot-monthly` | `0 4 1 * *` | 12 | 12 months |

Tiers are independent — a Sunday produces both a daily and a weekly snapshot. ~34 snapshots per PVC.

## Selection

Opt-out, but allowlisted by StorageClass. A PVC is snapshotted when it is `Bound`, its
`storageClassName` is `ceph-block` or `ceph-filesystem`, and it is not annotated:

```yaml
metadata:
  annotations:
    snapshot.homelab/enabled: "false"
```

New apps on Ceph are therefore covered automatically. The StorageClass allowlist is what makes
opt-out safe: `local-path` and the static NFS PVCs (which carry no `storageClassName`) can never be
selected, so a snapshot attempt against a driver that doesn't support them can't happen.

Per-PVC retention override:

```yaml
metadata:
  annotations:
    snapshot.homelab/daily: "7"     # also /weekly, /monthly
```

Currently excluded: `immich/immich-ml-cache-pvc` (regenerable model cache).

## Labels on generated snapshots

```
snapshot.homelab/managed = "true"
snapshot.homelab/tier    = daily | weekly | monthly
snapshot.homelab/pvc     = <source pvc name>
```

Name: `<pvc>-<tier>-<YYYYMMDDHHMM>`.

## Restore runbook

Everything below goes through git → ArgoCD. Nothing is applied by hand.

1. **Find the snapshot.**

   ```bash
   kubectl get volumesnapshot -n memos \
     -l snapshot.homelab/pvc=memos-data-pvc \
     --sort-by=.metadata.creationTimestamp
   ```

   `READYTOUSE=true` is the only usable state.

2. **Scale the app to 0.** `ceph-block` is RWO — the source PVC must be detached before its
   replacement can bind. (CephFS RWX volumes can skip this, but verify offline anyway.)

3. **Commit a restore PVC** next to the app's existing one. Same StorageClass, size ≥ the snapshot:

   ```yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: memos-data-restore-pvc
     namespace: memos
   spec:
     accessModes: [ReadWriteOnce]
     storageClassName: ceph-block
     resources:
       requests:
         storage: 2Gi
     dataSource:
       apiGroup: snapshot.storage.k8s.io
       kind: VolumeSnapshot
       name: memos-data-pvc-daily-202601150300
   ```

   The provisioner must match between snapshot and target — you cannot restore an RBD snapshot into
   a CephFS PVC or vice versa.

4. **Verify before committing to it.** Point a throwaway pod at the restore PVC and read the data,
   rather than swapping it under the app blind.

5. **Swap it in** — either repoint the workload at the restore PVC, or do the same-name
   delete/recreate dance used for the Ceph RBD migration.

6. **Scale back up**, then clean up. Both StorageClasses are `reclaimPolicy: Retain`, so the
   displaced PV survives PVC deletion and must be removed by hand once you're satisfied.

## Capacity

Copy-on-write: cost tracks churn, not volume size. Watch the two 200Gi CephFS volumes (Immich,
Nextcloud). Baseline and re-check with:

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph df
```

Ceilings worth knowing: CephFS `mds_max_snaps_per_dir` defaults to **100** per subvolume (34 leaves
headroom, but don't raise retention much further without bumping it); RBD tolerates ~512 snapshots
per image.

## Related

- `k8s/snapshot-controller/` — the CSI snapshot controller + CRDs (vendored upstream)
- `k8s/rook-ceph/rook-ceph-cluster-values.yaml` — `ceph{BlockPools,FileSystem}VolumeSnapshotClass`
  create the `ceph-block` / `ceph-filesystem` snapshot classes
- `k8s/rook-ceph/ceph-csi-drivers-values.yaml` — `snapshotPolicy: volumeSnapshot`, without which
  the RBD driver ships no snapshotter sidecar
- `k8s/monitoring/volume-snapshot-alert-rules.yaml` — job-failure and stale-schedule alerts
