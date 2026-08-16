# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a GitOps-managed Kubernetes homelab infrastructure running on Talos Linux. The cluster is deployed on Proxmox VE and managed entirely through declarative configuration. ArgoCD provides continuous deployment for all applications and infrastructure components.

`README.md` is the canonical inventory of applications, hardware, VLANs, storage classes, and backup strategy — consult it before answering questions about what runs where.

## Architecture

### Infrastructure Stack

- **Hypervisor**: Proxmox VE virtualization layer (3 bare-metal nodes: Melchior, Balthasar, Casper)
- **OS**: Talos Linux (immutable, API-managed Kubernetes OS)
- **Provisioning**: Terraform modules for VM creation
- **GitOps**: ArgoCD with app-of-apps pattern
- **Networking**: Cilium CNI with eBPF (kube-proxy disabled), L2 load balancing
- **Ingress**: Dual Traefik gateways (public on 10.1.20.100, internal on 10.1.20.101)
- **Storage**: Rook Ceph (primary, NVMe) + static NFS PVs from TrueNAS (bulk media) + local-path (latency-sensitive)
- **DNS**: External-DNS syncing with Cloudflare
- **TLS**: cert-manager with Let's Encrypt (DNS-01)
- **Secrets**: External Secrets Operator with Bitwarden Secrets Manager backend
- **Databases**: CloudNativePG for PostgreSQL (with Barman Cloud S3 backups), Dragonfly operator for Redis-compatible caching
- **Observability**: kube-prometheus-stack (Prometheus, Alertmanager, Grafana), blackbox-exporter, external Gatus

### Network Configuration

- Kubernetes API VIP: 10.1.20.10
- Control plane nodes: 10.1.20.11-13
- Worker nodes: 10.1.20.21-23
- LoadBalancer IP pool: 10.1.20.100-120
- TrueNAS (NFS/SMB): 10.1.30.10
- Ceph 10GbE mesh: 10.10.10.0/24 (direct triangle between the Proxmox nodes)

### Key Applications

Nextcloud + Collabora, Immich (photos), Jellyfin (media), Stump (ebooks), Vaultwarden (passwords), Authentik (SSO), Home Assistant (smart home), Linkwarden (bookmarks), Memos (notes), qBittorrent, LibreSpeed.

## Directory Structure

```
.
├── k8s/                          # Kubernetes manifests (~214 files)
│   ├── argocd/                   # ArgoCD configuration
│   │   ├── applications/         # ArgoCD Application definitions (~30 apps)
│   │   ├── argocd-helmfile.yaml  # Helmfile for bootstrapping ArgoCD itself
│   │   └── argocd-applications.yaml  # App-of-apps root application
│   ├── [app-name]/               # Per-application directories
│   │   ├── *-namespace.yaml           # Namespace definition
│   │   ├── *-deployment.yaml          # Deployment/StatefulSet
│   │   ├── *-service.yaml             # Services
│   │   ├── *-gateway.yaml             # Gateway API HTTPRoute
│   │   ├── *-external-secret(s).yaml  # External Secret definitions
│   │   ├── *-pvc.yaml                 # Persistent volume claims
│   │   ├── *-redis.yaml               # Dragonfly instances (where applicable)
│   │   ├── *-networkpolicy.yaml       # Ingress policy (default-deny + allow)
│   │   ├── *-egress-networkpolicy.yaml # Egress policy
│   │   ├── *-pdb.yaml                 # PodDisruptionBudget
│   │   └── *-values.yaml              # Helm values, referenced by the ArgoCD app
│   ├── gateway-api/              # Pinned Gateway API CRDs (standard-install-v1.5.1.yaml)
│   ├── rook-ceph/                # Ceph operator, cluster, CSI driver values
│   ├── local-path-storage/       # local-path provisioner
│   ├── monitoring/               # Prometheus stack values, dashboards, alert rules
│   ├── blackbox-exporter/        # External probe targets
│   ├── cert-manager/             # TLS certificate management
│   ├── cilium/                   # CNI and network policies
│   ├── external-dns/             # DNS automation
│   ├── external-secrets/         # Secret management
│   ├── cnpg-barman-cloud/        # CNPG Barman Cloud plugin (S3 WAL archiving)
│   ├── postgresql-clusters/      # CloudNativePG clusters (namespace: postgresql)
│   ├── dragonfly/                # README only — operator applied from upstream manifest
│   ├── reloader/                 # Stakater Reloader
│   ├── mkv-strip/                # CronJob deploying the mkv-strip image
│   └── traefik/                  # Gateway controllers
│       ├── traefik-public/       # Public-facing gateway + values
│       ├── traefik-internal/     # Internal-only gateway + values
│       └── error-pages/          # Custom error page service + middleware
├── terraform/                    # Infrastructure as Code
│   ├── modules/talos-vm/         # Reusable Talos VM module
│   ├── modules/docker-vm/        # Docker host module
│   ├── k8s-cluster.tf            # Main cluster definition
│   └── docker.tf                 # Docker VM definition
├── talos/                        # Talos Linux configuration
│   ├── patches/                  # cni, dns, disable-kube-proxy, install-disk,
│   │                             # interface-names, kubelet-certificates, kubelet-nodeip,
│   │                             # vip, metrics, control-plane-resources,
│   │                             # storage-net-worker-0{1,2,3} (per-node Ceph 10G NIC)
│   ├── out/                      # Generated configurations (gitignored)
│   └── secrets.yaml              # Cluster secrets (gitignored)
├── jobs/mkv-strip/               # Source + Dockerfile for the mkv-strip container
├── docker/gatus/                 # Compose stack for the external Gatus status page
├── .github/workflows/            # mkv-strip image build
├── talos-upgrade.sh              # Rolling Talos/Kubernetes upgrade with health checks
├── postgresql_backup.sh          # Logical pg_dump backups (redundancy alongside Barman)
├── BOOTSTRAP.MD                  # Detailed bootstrap instructions
├── README.md                     # Application inventory + infrastructure documentation
├── AGENTS.md                     # Codex-facing copy of this file — keep in sync
└── renovate.json                 # Automated dependency updates
```

## Available CLI Tools

`kubectl`, `talosctl`, `argocd`, `helm`, `helmfile`, `terraform`, `docker`, `gh`, `git`.

## Common Commands

### Cluster Access

```bash
# Configure kubectl context (after bootstrap)
talosctl kubeconfig -n 10.1.20.11

# Access Talos API
talosctl dashboard -n 10.1.20.11

# Port-forward to ArgoCD (initial setup)
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### Kubernetes Operations

```bash
# Apply manifests for a specific app
kubectl apply -f k8s/[app-name]/

# Watch ArgoCD sync status
kubectl get applications -n argocd -w

# View application logs
kubectl logs -f deployment/[app-name] -n [namespace]

# Check Gateway API routes
kubectl get httproutes -A
kubectl get gateways -A
```

### Terraform

```bash
cd terraform/
terraform plan
terraform apply
terraform show
```

### Talos Configuration

```bash
# Generate new cluster configuration (from talos/ directory)
talosctl gen config magi https://10.1.20.10:6443 \
  --install-image factory.talos.dev/nocloud-installer/[image-id]:v1.10.4 \
  --with-secrets secrets.yaml \
  --config-patch @patches/cni.yaml \
  --config-patch @patches/dns.yaml \
  --config-patch @patches/disable-kube-proxy.yaml \
  --config-patch @patches/install-disk.yaml \
  --config-patch @patches/interface-names.yaml \
  --config-patch @patches/kubelet-certificates.yaml \
  --config-patch-control-plane @patches/vip.yaml \
  --config-patch-control-plane @patches/metrics.yaml \
  --config-patch-control-plane @patches/control-plane-resources.yaml \
  --output out/

# Apply configuration updates
talosctl apply-config --insecure -n 10.1.20.11,10.1.20.12,10.1.20.13 -f out/controlplane.yaml
talosctl apply-config --insecure -n 10.1.20.21,10.1.20.22,10.1.20.23 -f out/worker.yaml

# Rolling upgrade of Talos (+ optionally Kubernetes) with health checks
./talos-upgrade.sh --talos-image factory.talos.dev/installer/[image-id]:v1.10.x
./talos-upgrade.sh --talos-image ... --k8s-version 1.32.0 --dry-run
```

### ArgoCD Management

```bash
# Deploy ArgoCD with helmfile
helmfile -f k8s/argocd/argocd-helmfile.yaml apply

# Deploy app-of-apps
kubectl apply -f k8s/argocd/argocd-applications.yaml

# Sync an application
kubectl patch application [app-name] -n argocd -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}' --type merge

# Get admin password (initial)
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
```

### Database Operations

```bash
# List PostgreSQL clusters (they live in the `postgresql` namespace)
kubectl get clusters -A

kubectl describe cluster postgres-apps -n postgresql
kubectl exec -it [cluster-pod] -n postgresql -- psql -U [user] [database]
```

### Ceph Operations

```bash
# Ceph health via the toolbox
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd tree

# Storage classes
kubectl get sc
```

## Development Workflow

### Adding a New Application

1. **Create application directory**: `k8s/[app-name]/`
2. **Create manifests** in this order:
   - `[app-name]-namespace.yaml` - Namespace
   - `[app-name]-external-secret.yaml` - Secrets (if needed)
   - `[app-name]-pvc.yaml` - Storage (if needed)
   - `[app-name]-redis.yaml` - Dragonfly instance (if needed)
   - Role + database in `k8s/postgresql-clusters/postgres-apps/` (if needed)
   - `[app-name]-deployment.yaml` or `[app-name]-statefulset.yaml`
   - `[app-name]-service.yaml` - Services
   - `[app-name]-gateway.yaml` - HTTPRoute with Gateway API
   - `[app-name]-networkpolicy.yaml` + `[app-name]-egress-networkpolicy.yaml`
   - `[app-name]-pdb.yaml` - PodDisruptionBudget for multi-replica workloads
3. **Create ArgoCD Application**: `k8s/argocd/applications/[app-name].yaml` with a `sync-wave` annotation (see below)
4. **Test locally**: `kubectl apply -f k8s/[app-name]/`
5. **Commit and push** - ArgoCD will automatically sync

### Sync Waves

Waves in use, roughly ordered:

| Wave | Components |
|------|-----------|
| -35 | gateway-api CRDs |
| -30 | cilium |
| -15 | argocd |
| -10 | cert-manager |
| -9 | external-secrets |
| -8 | external-dns, metrics-server, monitoring, reloader, blackbox-exporter |
| -7 | rook-ceph-operator, snapshot-controller |
| -6 | ceph-csi-drivers |
| -5 | rook-ceph-cluster, local-path-storage, traefik (gateways) |
| -4 | traefik (controller) |
| 5 | cnpg-barman-cloud |
| 10 | postgresql clusters |
| 20-30 | applications |
| 35 | volume-snapshots (discovers PVCs at runtime, so it goes last) |

### Gateway API Pattern

Applications use the Gateway API (not Ingress) with HTTPRoute resources. Note the `external-dns` hostname annotation — it drives the Cloudflare record:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: [app-name]-http-route
  namespace: [namespace]
  annotations:
    external-dns.alpha.kubernetes.io/hostname: [hostname].oliverilp.ee
spec:
  parentRefs:
    - name: traefik-public-gateway  # or traefik-internal-gateway
      namespace: traefik
  hostnames:
    - [hostname].oliverilp.ee
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: [service-name]
          port: [port]
```

### External Secrets Pattern

Secrets are stored in Bitwarden Secrets Manager and synced via External Secrets Operator. The API version is **`external-secrets.io/v1`** (not `v1beta1`):

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: [app-name]-es
  namespace: [namespace]
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: bitwarden-secrets-manager
    kind: ClusterSecretStore
  target:
    name: [app-name]-secret
    creationPolicy: Owner
  data:
    - secretKey: [key-name]
      remoteRef:
        key: [bitwarden-secret-uuid]
```

### CloudNativePG Pattern

Two clusters live in the `postgresql` namespace: `postgres-apps` (shared by most apps) and `postgres-immich`. Most new apps get a **managed role + database on `postgres-apps`**, not a new cluster.

Key conventions:

- `storage.storageClass: local-path` — databases run on node NVMe, not Ceph, for latency
- Node affinity excludes control-plane nodes; `podAntiAffinityType: preferred`
- WAL archiving to S3 via the `barman-cloud.cloudnative-pg.io` plugin (`plugins:` with `isWALArchiver: true`), **not** the deprecated `backup.barmanObjectStore`
- Per-app credentials come from `managed.roles[].passwordSecret` backed by an ExternalSecret
- Disaster recovery: uncomment `bootstrap.recovery` and comment out `plugins` (see the inline comment in the cluster manifest)

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-apps
  namespace: postgresql
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:17.5
  instances: 3
  managed:
    roles:
      - name: [app-name]
        ensure: present
        login: true
        passwordSecret:
          name: postgres-apps-[app-name]-auth
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: s3-apps
  storage:
    size: 10Gi
    storageClass: local-path
```

### ArgoCD Application Pattern

All infrastructure and applications are managed via ArgoCD Application CRDs:

- Multiple sources can be used (Helm chart + values from git + additional manifests)
- `syncPolicy.automated` enables auto-sync and self-healing
- `sync-wave` annotations control deployment order
- `prune: true` removes resources deleted from git

## Important Notes

### Bootstrap Order

When bootstrapping from scratch, follow BOOTSTRAP.MD strictly. Key dependencies:

1. Cilium must be installed first (cluster has no CNI by default)
2. Gateway API CRDs before Traefik
3. External Secrets Operator before applications with secrets
4. Rook Ceph operator + CSI drivers before the Ceph cluster and any Ceph PVCs
5. CloudNativePG operator (and the Barman Cloud plugin) before database clusters
6. Dragonfly operator before Dragonfly instances
7. ArgoCD is bootstrapped with helmfile, then takes over via app-of-apps

### Secrets Management

- Never commit secrets to git
- All application secrets should use External Secrets Operator
- Bootstrap secrets (Bitwarden access token) are manually created via kubectl
- `talos/secrets.yaml` and `terraform/credentials.auto.tfvars` are gitignored

### Traefik Gateways

- **Public gateway** (10.1.20.100): Exposed to internet, uses external-dns for Cloudflare. Only Authentik, Immich, Memos, Linkwarden, and Jellyfin are internet-accessible.
- **Internal gateway** (10.1.20.101): Local network only, reachable over WireGuard
- Both gateways use Gateway API, not legacy Ingress resources
- TLS certificates are centrally managed in cert-manager and referenced via `certificateRefs`
- Gateway API CRDs are pinned in `k8s/gateway-api/` and are version-coupled to the Traefik chart — a mismatch (e.g. missing TLSRoute CRD) makes Traefik fall back to a self-signed cert on **all** gateways
- Custom error pages are served by the nginx deployment in `k8s/traefik/error-pages/` via a Traefik middleware

### Storage

| Storage Class | Backend | Use Case |
|--------------|---------|----------|
| `ceph-block` | Rook Ceph RBD on NVMe | Single-writer application data (RWO) |
| `ceph-filesystem` | Rook Ceph CephFS on NVMe | Shared application data (RWX) |
| static NFS PVs | TrueNAS HDD (10.1.30.10) | Bulk media (Jellyfin, Stump, qBittorrent) |
| `local-path` | Node NVMe | Prometheus, PostgreSQL |

- Ceph is the default for application data, replicated 3× across the workers
- **Deployments that need RWX must use `ceph-filesystem`** — an RBD (RWO) volume causes Multi-Attach errors on rolling updates. StatefulSets can stay on `ceph-block`.
- PVC naming convention: `<app>-data-pvc`, or `<app>-<role>-pvc` when an app has several
- Bulk media is mounted as static NFS PersistentVolumes with explicit paths, not dynamically provisioned

#### Volume Snapshots

`k8s/volume-snapshots/` snapshots **every** `ceph-block`/`ceph-filesystem` PVC on a daily(14) /
weekly(8) / monthly(12) schedule with automatic pruning. Three CronJobs share one script; there is
nothing to add per app.

- Selection is opt-out but allowlisted by storage class — `local-path` and static NFS PVCs are
  structurally unreachable (neither supports CSI snapshots)
- Exclude a PVC with the annotation `snapshot.homelab/enabled: "false"`; override retention with
  `snapshot.homelab/daily|weekly|monthly: "<n>"`
- Snapshot classes `ceph-block` / `ceph-filesystem` come from
  `ceph{BlockPools,FileSystem}VolumeSnapshotClass` in `rook-ceph-cluster-values.yaml`
  (chart default is `enabled: false`); `deletionPolicy: Delete` so pruning reclaims space
- Requires `drivers.*.snapshotPolicy: volumeSnapshot` in `ceph-csi-drivers-values.yaml` — the RBD
  driver defaults to `none` and ships no snapshotter sidecar
- The CSI snapshot controller + CRDs are vendored upstream in `k8s/snapshot-controller/`; the image
  version and the vendored manifest version must be bumped together
- These are in-cluster and crash-consistent only — not offsite, not a substitute for the CNPG
  Barman backups. Restore runbook: `k8s/volume-snapshots/README.md`

### Network Policies

Nearly every namespace ships a default-deny plus explicit allow policy. Most are standard `NetworkPolicy`; a few use `CiliumNetworkPolicy` where L7 or entity selectors are needed. When adding an app, expect to write both an ingress and an egress policy — traffic to the postgres namespace and to the internet is denied by default.

### Renovate

Automated dependency updates are configured for:

- Kubernetes manifests in `k8s/`
- ArgoCD applications in `k8s/argocd/applications/`
- Helmfile in `k8s/argocd/argocd-helmfile.yaml`

The `review-renovate-prs` skill in `.claude/skills/` drives the review/merge loop for these PRs.

### Backups

- CloudNativePG streams WAL to S3 (`oliverilp-postgresql`, eu-north-1) via Barman Cloud
- `postgresql_backup.sh` produces logical `pg_dump` exports for redundancy
- TrueNAS replicates snapshots and personal files to S3 Glacier buckets

## Troubleshooting

### Application won't start

1. Check ArgoCD sync status: `kubectl get application [app-name] -n argocd`
2. Check if secrets are synced: `kubectl get externalsecret -n [namespace]`
3. Check pod status: `kubectl describe pod [pod-name] -n [namespace]`
4. Check logs: `kubectl logs [pod-name] -n [namespace]`

### Network connectivity issues

1. Verify Cilium status: `kubectl get pods -n kube-system -l k8s-app=cilium`
2. Check Gateway status: `kubectl get gateway -n traefik`
3. Verify LoadBalancer IPs: `kubectl get svc -A | grep LoadBalancer`
4. Check for a blocking policy: `kubectl get networkpolicy,ciliumnetworkpolicy -n [namespace]`

### Database issues

1. Check cluster status: `kubectl get cluster [name] -n postgresql`
2. View operator logs: `kubectl logs -n cnpg-system deployment/cnpg-controller-manager`
3. Check cluster pods: `kubectl get pods -n postgresql -l cnpg.io/cluster=[name]`

### Storage / Ceph issues

1. `kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status`
2. Check for stuck volumes: `kubectl get volumeattachment | grep [pvc]`
3. Multi-Attach errors on a Deployment usually mean an RWO `ceph-block` PVC that should be `ceph-filesystem`

### DNS not updating

1. Check external-dns logs: `kubectl logs -n external-dns deployment/external-dns`
2. Verify the HTTPRoute/Gateway annotation: `external-dns.alpha.kubernetes.io/hostname`
3. Check Cloudflare API token in external-dns configuration
