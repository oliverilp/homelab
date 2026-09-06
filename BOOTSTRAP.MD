# Homelab Bootstrap Guide

This guide walks through setting up a complete Kubernetes homelab environment using Talos Linux, managed with GitOps via ArgoCD.

## Overview

This homelab setup includes:
- **Infrastructure**: Proxmox VMs provisioned with Terraform
- **OS**: Talos Linux (immutable Kubernetes OS)
- **Networking**: Cilium CNI with L2 load balancing
- **Ingress**: Traefik (public and internal gateways)
- **GitOps**: ArgoCD for application management
- **Storage**: NFS CSI driver for persistent volumes
- **Applications**: Immich, Jellyfin, Linkwarden, Memos, qBittorrent
- **Auth**: Authentik for SSO
- **TLS**: cert-manager with Let's Encrypt

## Prerequisites

### 1. Install Required Tools

```bash
brew install siderolabs/tap/talosctl kubectl helm helmfile
```

### 2. Infrastructure Provisioning

Before proceeding, ensure your Proxmox infrastructure is provisioned using Terraform:
- 3x control plane nodes (k8s-master-01, k8s-master-02, k8s-master-03)
- 3x worker nodes (k8s-worker-01, k8s-worker-02, k8s-worker-03)
- NFS server at 10.1.30.10 with shared storage

## Talos Configuration

### 1. Generate Talos Configuration

Schematic (nocloud + qemu-guest-agent): `ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515`

Generate image from (update version as needed):
https://factory.talos.dev/?arch=amd64&cmdline-set=true&extensions=-&extensions=siderolabs%2Fqemu-guest-agent&platform=nocloud&target=cloud&version=1.13.5

**Create the Proxmox VM template** (run on each Proxmox host, replace `<node>` with e.g. `casper`):
```bash
wget -O /tmp/talos-v1.13.5.raw.xz \
  "https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.13.5/nocloud-amd64.raw.xz"
xz -d /tmp/talos-v1.13.5.raw.xz
qm create 9000 --name talos-v1.13.5 --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
qm importdisk 9000 /tmp/talos-v1.13.5.raw <node>-nvme
qm set 9000 --scsihw virtio-scsi-pci --scsi0 <node>-nvme:vm-9000-disk-0
qm set 9000 --boot c --bootdisk scsi0
qm template 9000
```
The terraform module clones from `talos-v1.13.5` — update `terraform/modules/talos-vm/main.tf` if the template name changes.

Generate the initial cluster configuration with custom patches:

```bash
talosctl gen config magi https://10.1.20.10:6443 \
--install-image factory.talos.dev/nocloud-installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.13.5 \
--kubernetes-version v1.35.3 \
--with-secrets secrets.yaml \
--config-patch @patches/cni.yaml \
--config-patch @patches/dns.yaml \
--config-patch @patches/disable-kube-proxy.yaml \
--config-patch @patches/install-disk.yaml \
--config-patch @patches/interface-names.yaml \
--config-patch @patches/kubelet-certificates.yaml \
--config-patch @patches/kubelet-nodeip.yaml \
--config-patch @patches/kubelet-image-gc.yaml \
--config-patch-control-plane @patches/vip.yaml \
--config-patch-control-plane @patches/metrics.yaml \
--config-patch-control-plane @patches/control-plane-resources.yaml \
--output out/
```

### 2. Setup Talos Client Configuration

```bash
mkdir -p ~/.talos && cp out/talosconfig ~/.talos/config
```

## Cluster Bootstrap

### 1. Apply Node Configurations

Apply configurations to control plane nodes:

```bash
talosctl apply-config --insecure -n 10.1.20.11,10.1.20.12,10.1.20.13 -f out/controlplane.yaml
```

Apply configurations to worker nodes. Each worker also gets a per-node patch adding
its Ceph 10G storage-mesh NIC (`eth1` on `10.1.11.2x/24`, MTU 9000) — the IP is
unique per node, so it can't be a shared `gen` patch and is applied here with `-p`:

```bash
talosctl apply-config --insecure -n 10.1.20.21 -f out/worker.yaml -p @patches/storage-net-worker-01.yaml
talosctl apply-config --insecure -n 10.1.20.22 -f out/worker.yaml -p @patches/storage-net-worker-02.yaml
talosctl apply-config --insecure -n 10.1.20.23 -f out/worker.yaml -p @patches/storage-net-worker-03.yaml
```

The storage NIC depends on the Proxmox-side 10G mesh (STP bridge `vmbr1`) and the
VM's second NIC (`qm set 41x -net1 virtio=BC:24:11:00:11:2x,bridge=vmbr1,mtu=9000`).

### 2. Configure Talos Client

```bash
talosctl config endpoint 10.1.20.11 10.1.20.12 10.1.20.13
talosctl config node 10.1.20.11
talosctl config contexts
```

### 3. Bootstrap the Cluster

```bash
talosctl bootstrap
talosctl get members -n 10.1.20.11
talosctl kubeconfig -n 10.1.20.11
```

## Kubernetes Setup

### 1. Install Cilium CNI

Since Talos is configured with CNI disabled, Cilium must be installed first to enable networking functionality.

Apply the Cilium configuration and wait for it to be ready:

```bash
kubectl apply -f k8s/cilium/
```

Wait for Cilium to be ready:

```bash
kubectl wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=300s
```

### 2. Install Local Path Provisioner

The local-path-provisioner provides dynamic provisioning of local storage on each node. This is useful for applications that need fast local storage or as a fallback storage class.

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.32/deploy/local-path-storage.yaml
```

### 3. Install NFS CSI Snapshotter

Install the NFS CSI Snapshotter Custom Resource Definitions:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml
```

### 4. Install Gateway API CRDs

The Gateway API CRDs (standard channel) are managed via GitOps in
`k8s/gateway-api/` and applied automatically by the `gateway-api` ArgoCD
Application (sync-wave -35, before Traefik). No manual step is required once
the app-of-apps is deployed.

> **Note:** Traefik v3.7+ (chart v40) requires Gateway API **v1.5.x**, where
> `TLSRoute` graduated to the standard channel. With older CRDs (e.g. v1.4.0)
> the gateway provider's informer cache fails to sync and Traefik serves its
> default self-signed certificate. To bump the version, replace the bundle in
> `k8s/gateway-api/` with the new `standard-install-<version>.yaml` from
> https://github.com/kubernetes-sigs/gateway-api/releases.

If you need the CRDs before ArgoCD is bootstrapped, apply the pinned bundle
manually (server-side apply is required — the schemas exceed kubectl's
client-side annotation limit):

```bash
kubectl apply --server-side -f k8s/gateway-api/standard-install-v1.5.1.yaml
```

### 5. Install CloudNative-PG Operator

Install the PostgreSQL operator for database management:

```bash
kubectl apply --server-side -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.26/releases/cnpg-1.26.0.yaml
```

#### 5.1. Install Barman Plugin for Backups

Install the Barman Cloud plugin for PostgreSQL backup functionality:

```bash
kubectl apply -f https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v0.5.0/manifest.yaml
```

### 6. Install Dragonfly Operator

Install the Dragonfly operator for Redis-compatible caching:

```bash
kubectl apply -f https://raw.githubusercontent.com/dragonflydb/dragonfly-operator/main/manifests/dragonfly-operator.yaml
```

### 7. Install External Secrets Operator

Deploy External Secrets Operator with Bitwarden Secrets Manager integration:

#### 7.1. Create Bitwarden Access Token Secret

> [!WARNING]  
> We use a temporary file instead of a one-liner kubectl command to avoid storing the access token in bash history.

First, create the Bitwarden access token secret. Create a temporary manifest file and then edit it with a text editor such as Vim or nano:

```bash
cat > /tmp/bitwarden-token.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: bitwarden-access-token
  namespace: external-secrets
type: Opaque
stringData:
  token: bws_YOUR_ACCESS_TOKEN_HERE
EOF
```

Apply the secret and remove the temporary file:

```bash
kubectl apply -f /tmp/bitwarden-token.yaml
rm -f /tmp/bitwarden-token.yaml
```

#### 7.2. Deploy External Secrets Operator

```bash
kubectl apply -f k8s/external-secrets
```

Wait for ESO pods to be ready:

```bash
kubectl wait --for=condition=available --timeout=300s deployment/external-secrets -n external-secrets
kubectl wait --for=condition=available --timeout=300s deployment/bitwarden-sdk-server -n external-secrets
```

### 8. Install ArgoCD

Deploy ArgoCD with external Redis (Dragonfly) and secret management:

#### 8.1. Deploy Redis Secret

```bash
kubectl apply -f k8s/argocd/argocd-external-secrets.yaml
```

Wait for the secret to be created:

```bash
kubectl wait --for=condition=ready externalsecret/argocd-redis-auth-es -n argocd --timeout=60s
```

#### 8.2. Deploy Dragonfly Redis

```bash
kubectl apply -f k8s/argocd/argocd-redis.yaml
```

Wait for Dragonfly to be ready:

```bash
kubectl wait --for=condition=ready dragonfly/argocd-dragonfly -n argocd --timeout=300s
```

#### 8.3. Deploy ArgoCD

```bash
helmfile -f k8s/argocd/argocd-helmfile.yaml apply
```

Wait for ArgoCD to be ready:

```bash
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

#### 8.4. Configure Git Repository

Add your Git repository to ArgoCD. See the [ArgoCD documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories) for detailed instructions.

#### 8.5. Deploy Applications

```bash
kubectl apply -f k8s/argocd/argocd-applications.yaml
```

#### 8.6. Configure ArgoCD Access

Initially, access ArgoCD using kubectl port-forward:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then access the UI at: [https://localhost:8080](https://localhost:8080)

After Traefik and cert-manager are deployed by ArgoCD, apply the gateway configuration:

```bash
kubectl apply -f k8s/argocd/argocd-gateway.yaml
```

Access ArgoCD UI at: [https://argocd.oliverilp.ee](https://argocd.oliverilp.ee)

#### 8.7. Configure OIDC Authentication

Apply the ArgoCD configuration map for OIDC login via Authentik:

```bash
kubectl apply -f k8s/argocd/argocd-config-map.yaml
```

## Post-Bootstrap

After completing these steps, the cluster foundation is ready. The remaining applications and configurations will be managed through ArgoCD's GitOps workflow.

### What's Next

1. **ArgoCD**: Will be deployed and configured to manage all applications
2. **Infrastructure Apps**: Cilium, cert-manager, external-dns, NFS CSI, Traefik
3. **Database Clusters**: PostgreSQL clusters for applications
4. **Applications**: Immich, Jellyfin, Linkwarden, Memos, qBittorrent, Authentik

All subsequent deployments are automated through ArgoCD applications defined in `k8s/argocd/applications/`.

## Network Architecture

- **VIP**: 10.1.20.10 (Kubernetes API)
- **Control Plane**: 10.1.20.11-13
- **Workers**: 10.1.20.21-23
- **LoadBalancer Pool**: 10.1.20.100-120
- **Public Traefik**: 10.1.20.100
- **Internal Traefik**: 10.1.20.101
- **NFS Server**: 10.1.30.10
