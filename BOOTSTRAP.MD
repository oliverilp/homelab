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
- NFS server at 10.1.1.22 with shared storage

## Talos Configuration

### 1. Generate Talos Configuration

Generate the initial cluster configuration with custom patches:

```bash
talosctl gen config ramiel-cluster https://10.1.1.30:6443 \
--install-image factory.talos.dev/nocloud-installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v1.10.4 \
--with-secrets secrets.yaml \
--config-patch @patches/cni.yaml \
--config-patch @patches/disable-kube-proxy.yaml \
--config-patch @patches/install-disk.yaml \
--config-patch @patches/interface-names.yaml \
--config-patch @patches/kubelet-certificates.yaml \
--config-patch-control-plane @patches/vip.yaml \
--output out/
```

### 2. Setup Talos Client Configuration

```bash
mkdir -p ~/.talos cp out/talosconfig ~/.talos/config
```

## Cluster Bootstrap

### 1. Apply Node Configurations

Apply configurations to control plane nodes:

```bash
talosctl apply-config --insecure -n 10.1.1.31,10.1.1.32,10.1.1.33 -f out/controlplane.yaml
```

Apply configurations to worker nodes:

```bash
talosctl apply-config --insecure -n 10.1.1.41,10.1.1.42,10.1.1.43 -f out/worker.yaml
```

### 2. Configure Talos Client

```bash
talosctl config endpoint 10.1.1.31 10.1.1.32 10.1.1.33
talosctl config node 10.1.1.31
talosctl config contexts
```

### 3. Bootstrap the Cluster

```bash
talosctl bootstrap
talosctl get members -n 10.1.1.31
talosctl kubeconfig -n 10.1.1.31
```

## Kubernetes Setup

### 1. Install Gateway API CRDs

Install the Gateway API Custom Resource Definitions:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.3.0/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.3.0/config/crd/standard/gateway.networking.k8s.io_gateways.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.3.0/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.3.0/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.3.0/config/crd/standard/gateway.networking.k8s.io_grpcroutes.yaml
```

### 2. Install CloudNative-PG Operator

Install the PostgreSQL operator for database management:

```bash
kubectl apply --server-side -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.26/releases/cnpg-1.26.0.yaml
```

### 3. Install Dragonfly Operator

Install the Dragonfly operator for Redis-compatible caching:

```bash
kubectl apply -f https://raw.githubusercontent.com/dragonflydb/dragonfly-operator/main/manifests/dragonfly-operator.yaml
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

- **VIP**: 10.1.1.30 (Kubernetes API)
- **Control Plane**: 10.1.1.31-33
- **Workers**: 10.1.1.41-43
- **LoadBalancer Pool**: 10.1.1.100-120
- **Public Traefik**: 10.1.1.100
- **Internal Traefik**: 10.1.1.101
- **NFS Server**: 10.1.1.22
