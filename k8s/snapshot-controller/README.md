# snapshot-controller

Cluster-scoped CSI volume snapshot controller + the `snapshot.storage.k8s.io` CRDs. Neither Talos
nor Rook ships these, and Ceph-CSI's `csi-snapshotter` sidecar is useless without them — see the
[Rook prerequisites](https://rook.io/docs/rook/latest-release/Storage-Configuration/Ceph-CSI/ceph-csi-snapshot/).

Upstream ([kubernetes-csi/external-snapshotter](https://github.com/kubernetes-csi/external-snapshotter))
publishes raw manifests only — no first-party Helm chart — so they are vendored here with the
version in the filename, the same convention as `k8s/gateway-api/` and `k8s/cnpg-barman-cloud/`.

Installed in `kube-system`, as upstream recommends for base-distribution infrastructure.

| File | Source (tag `v8.6.0`) |
|---|---|
| `crds-v8.6.0.yaml` | `client/config/crd/*.yaml` — all 6, concatenated, **verbatim** |
| `snapshot-controller-v8.6.0.yaml` | `deploy/kubernetes/snapshot-controller/{rbac,setup}-snapshot-controller.yaml`, concatenated, **patched** |

The three `groupsnapshot.*` CRDs are unused (we take per-PVC snapshots, not group snapshots) but are
installed anyway — the controller's RBAC and watches cover them.

## Adopting the pre-existing CRDs

The cluster already carried the three `snapshot.storage.k8s.io` CRDs, `kubectl apply`-ed by hand on
2025-07-05 from external-snapshotter ~v8.0 (controller-gen v0.15.0) with no controller behind them —
inert, and exactly the kind of untracked state this directory exists to eliminate. ArgoCD adopts and
upgrades them in place on first sync.

Checked before the rollout, both conditions required for that to be safe:

- `status.storedVersions` is `["v1"]` on all three, and v8.6.0 still declares `v1beta1`
  (unserved) — so no stored version disappears and the apiserver accepts the update.
- No `VolumeSnapshot`, `VolumeSnapshotContent`, or `VolumeSnapshotClass` objects existed.

Re-check `storedVersions` against the new CRDs before any future major bump; that is the one thing
that turns a CRD upgrade into a hard rejection.

## Local patches to re-apply on upgrade

All marked `# LOCAL:` in the manifest:

1. Image digest-pinned. The **tag is left at upstream's `v8.5.0`** on purpose: that is also the
   `csi-snapshotter` sidecar version the `rook-ceph` operator chart pins
   (`csi.snapshotter.tag`), so controller and sidecar run the same version. Renovate's
   `kubernetes` manager matches `^k8s/.*\.yaml$` and will offer v8.6.0 — it is held to a manual
   PR (see `renovate.json`) because bumping the image alone would desync it from both the
   vendored CRDs here and Rook's sidecar.
2. `--v=5` → `--v=2`. Upstream defaults to debug logging.
3. `priorityClassName: system-cluster-critical`.
4. `topologySpreadConstraints` across hostnames for the 2 replicas.
5. Pod + container `securityContext` (non-root 65534, `readOnlyRootFilesystem`, drop ALL caps,
   `seccompProfile: RuntimeDefault`) — upstream ships none.
6. Resources: 20m/64Mi requests, 200m/256Mi limits.

## Upgrading

```bash
V=v8.7.0
B=https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/$V
for f in snapshot.storage.k8s.io_volumesnapshotclasses snapshot.storage.k8s.io_volumesnapshots snapshot.storage.k8s.io_volumesnapshotcontents groupsnapshot.storage.k8s.io_volumegroupsnapshotclasses groupsnapshot.storage.k8s.io_volumegroupsnapshots groupsnapshot.storage.k8s.io_volumegroupsnapshotcontents; do curl -sfL "$B/client/config/crd/$f.yaml"; done > crds-$V.yaml
for f in rbac-snapshot-controller setup-snapshot-controller; do curl -sfL "$B/deploy/kubernetes/snapshot-controller/$f.yaml"; done > snapshot-controller-$V.yaml
```

Then re-apply the patches above, delete the old-versioned files, and push — ArgoCD prunes the old
ones. CRD removals between majors are the risk to read the release notes for.

## Related

- `k8s/rook-ceph/ceph-csi-drivers-values.yaml` — `snapshotPolicy: volumeSnapshot` deploys the
  per-driver `csi-snapshotter` sidecars. The RBD driver defaults to `none`, so this is required.
- `k8s/rook-ceph/rook-ceph-cluster-values.yaml` — `ceph{BlockPools,FileSystem}VolumeSnapshotClass`
  create the two `VolumeSnapshotClass` resources (`ceph-block`, `ceph-filesystem`).
- `k8s/volume-snapshots/` — the scheduled snapshot CronJobs and the restore runbook.
