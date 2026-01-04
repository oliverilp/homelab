# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a GitOps-managed Kubernetes homelab infrastructure running on Talos Linux. The cluster is deployed on Proxmox VE and managed entirely through declarative configuration. ArgoCD provides continuous deployment for all applications and infrastructure components.

## Architecture

### Infrastructure Stack

- **Hypervisor**: Proxmox VE virtualization layer
- **OS**: Talos Linux (immutable, API-managed Kubernetes OS)
- **Provisioning**: Terraform modules for VM creation
- **GitOps**: ArgoCD with app-of-apps pattern
- **Networking**: Cilium CNI with eBPF (kube-proxy disabled), L2 load balancing
- **Ingress**: Dual Traefik gateways (public on 10.1.20.100, internal on 10.1.20.101)
- **Storage**: NFS CSI driver connected to TrueNAS server at 10.1.30.10
- **DNS**: External-DNS syncing with Cloudflare
- **TLS**: cert-manager with Let's Encrypt
- **Secrets**: External Secrets Operator with Bitwarden Secrets Manager backend
- **Databases**: CloudNativePG operator for PostgreSQL, Dragonfly operator for Redis-compatible caching

### Network Configuration

- Kubernetes API VIP: 10.1.20.10
- Control plane nodes: 10.1.20.11-13
- Worker nodes: 10.1.20.21-23
- LoadBalancer IP pool: 10.1.20.100-120
- NFS server: 10.1.30.10

### Key Applications

Applications include Immich (photos), Jellyfin (media), Vaultwarden (passwords), Authentik (SSO), Home Assistant (smart home), Linkwarden (bookmarks), Memos (notes), qBittorrent, and LibreSpeed.

## Directory Structure

```
.
├── k8s/                          # Kubernetes manifests (124 files)
│   ├── argocd/                   # ArgoCD configuration
│   │   ├── applications/         # ArgoCD Application definitions (20 apps)
│   │   ├── argocd-helmfile.yaml  # Helmfile for ArgoCD deployment
│   │   └── argocd-applications.yaml  # App-of-apps root application
│   ├── [app-name]/               # Per-application directories
│   │   ├── *-namespace.yaml      # Namespace definition
│   │   ├── *-deployment.yaml     # Deployment/StatefulSet
│   │   ├── *-service.yaml        # Services
│   │   ├── *-gateway.yaml        # Gateway API HTTPRoute
│   │   ├── *-external-secret.yaml # External Secret definitions
│   │   ├── *-pvc.yaml            # Persistent volume claims
│   │   └── *-redis.yaml          # Dragonfly Redis instances (where applicable)
│   ├── cert-manager/             # TLS certificate management
│   ├── cilium/                   # CNI and network policies
│   ├── external-dns/             # DNS automation
│   ├── external-secrets/         # Secret management
│   ├── postgresql-clusters/      # CloudNativePG cluster definitions
│   └── traefik/                  # Ingress controllers
│       ├── traefik-public/       # Public-facing gateway
│       └── traefik-internal/     # Internal-only gateway
├── terraform/                    # Infrastructure as Code
│   ├── modules/
│   │   ├── talos-vm/             # Reusable Talos VM module
│   │   └── docker-vm/            # Docker host module
│   └── k8s-cluster.tf            # Main cluster definition
├── talos/                        # Talos Linux configuration
│   ├── patches/                  # Configuration patches
│   │   ├── cni.yaml              # Disable built-in CNI
│   │   ├── disable-kube-proxy.yaml
│   │   ├── install-disk.yaml
│   │   ├── interface-names.yaml
│   │   ├── kubelet-certificates.yaml
│   │   └── vip.yaml              # Virtual IP configuration
│   ├── out/                      # Generated configurations
│   └── secrets.yaml              # Cluster secrets (not committed)
├── BOOTSTRAP.MD                  # Detailed bootstrap instructions
├── README.md                     # Application inventory
└── renovate.json                 # Automated dependency updates
```

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
# Navigate to terraform directory
cd terraform/

# Plan infrastructure changes
terraform plan

# Apply changes
terraform apply

# View current state
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
  --output out/

# Apply configuration updates
talosctl apply-config --insecure -n 10.1.20.11,10.1.20.12,10.1.20.13 -f out/controlplane.yaml
talosctl apply-config --insecure -n 10.1.20.21,10.1.20.22,10.1.20.23 -f out/worker.yaml

# Upgrade Talos
talosctl upgrade --nodes [node-ip] --image factory.talos.dev/[image-id]:v1.10.x
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
# List PostgreSQL clusters
kubectl get clusters -A

# View cluster status
kubectl describe cluster [cluster-name] -n [namespace]

# Connect to PostgreSQL
kubectl exec -it [cluster-pod] -n [namespace] -- psql -U [user] [database]
```

## Development Workflow

### Adding a New Application

1. **Create application directory**: `k8s/[app-name]/`
2. **Create manifests** in this order:
   - `[app-name]-namespace.yaml` - Namespace
   - `[app-name]-external-secret.yaml` - Secrets (if needed)
   - `[app-name]-pvc.yaml` - Storage (if needed)
   - `[app-name]-redis.yaml` - Dragonfly instance (if needed)
   - PostgreSQL cluster in `k8s/postgresql-clusters/` (if needed)
   - `[app-name]-deployment.yaml` or `[app-name]-statefulset.yaml`
   - `[app-name]-service.yaml` - Services
   - `[app-name]-gateway.yaml` - HTTPRoute with Gateway API
3. **Create ArgoCD Application**: `k8s/argocd/applications/[app-name].yaml`
   - Set appropriate sync wave with `argocd.argoproj.io/sync-wave` annotation
   - Infrastructure components use negative waves (-10 to -1)
   - Database clusters use wave 0
   - Applications use positive waves (1+)
4. **Test locally**: `kubectl apply -f k8s/[app-name]/`
5. **Commit and push** - ArgoCD will automatically sync

### Gateway API Pattern

Applications use the Gateway API (not Ingress) with HTTPRoute resources:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: [app-name]
  namespace: [namespace]
spec:
  parentRefs:
    - name: traefik-public-gateway  # or traefik-internal-gateway
      namespace: traefik
      sectionName: https
  hostnames:
    - [hostname].oliverilp.ee
  rules:
    - backendRefs:
        - name: [service-name]
          port: [port]
```

### External Secrets Pattern

Secrets are stored in Bitwarden Secrets Manager and synced via External Secrets Operator:

```yaml
apiVersion: external-secrets.io/v1beta1
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

PostgreSQL databases are created as CloudNativePG clusters in `k8s/postgresql-clusters/`:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: [app-name]-database
  namespace: postgres
spec:
  instances: 2
  storage:
    size: 5Gi
    storageClass: nfs-csi
  postgresql:
    parameters:
      shared_buffers: 256MB
  bootstrap:
    initdb:
      database: [dbname]
      owner: [user]
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
4. CloudNativePG operator before database clusters
5. Dragonfly operator before Dragonfly instances
6. ArgoCD is bootstrapped with helmfile, then takes over via app-of-apps

### Secrets Management

- Never commit secrets to git
- All application secrets should use External Secrets Operator
- Bootstrap secrets (Bitwarden access token) are manually created via kubectl
- The `talos/secrets.yaml` file is gitignored and contains cluster secrets

### Traefik Gateways

- **Public gateway** (10.1.20.100): Exposed to internet, uses external-dns for Cloudflare
- **Internal gateway** (10.1.20.101): Local network only, used for internal services
- Both gateways use Gateway API, not legacy Ingress resources
- TLS certificates are centrally managed in cert-manager namespace and referenced via certificateRefs

### Storage

- All persistent storage uses NFS CSI driver pointing to TrueNAS at 10.1.30.10
- Storage class: `nfs-csi`
- Some applications (Jellyfin, Immich) use PersistentVolumes with specific NFS paths for large media
- Snapshots are supported via NFS CSI Snapshotter CRDs

### Renovate

Automated dependency updates are configured for:

- Kubernetes manifests in `k8s/`
- ArgoCD applications in `k8s/argocd/applications/`
- Helmfile in `k8s/argocd/argocd-helmfile.yaml`

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

### Database issues

1. Check cluster status: `kubectl get cluster [name] -n postgres`
2. View operator logs: `kubectl logs -n cnpg-system deployment/cnpg-controller-manager`
3. Check cluster pods: `kubectl get pods -n postgres -l cnpg.io/cluster=[name]`

### DNS not updating

1. Check external-dns logs: `kubectl logs -n external-dns deployment/external-dns`
2. Verify Gateway annotations: `kubectl get gateway traefik-public-gateway -n traefik -o yaml`
3. Check Cloudflare API token in external-dns configuration
