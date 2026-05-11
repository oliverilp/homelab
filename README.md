# :house: Homelab

A GitOps-managed Kubernetes homelab built for learning, experimentation, and independence from big cloud providers. Everything runs on self-hosted infrastructure with declarative configuration and automated deployments.

## :rocket: Installed Apps & Tools

### :globe_with_meridians: Apps

End user applications.
<table>
    <tr>
        <th>Logo</th>
        <th>Name</th>
        <th>Description</th>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/filestash.svg"></td>
        <td><a href="https://www.filestash.app/">Filestash</a></td>
        <td>Google Drive alternative. Web UI for my TrueNAS SMB shares. Lightweight and more reliable than Nextcloud.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/immich.svg"></td>
        <td><a href="https://immich.app/">Immich</a></td>
        <td>Google Photos alternative.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/jellyfin.svg"></td>
        <td><a href="https://jellyfin.org/">Jellyfin</a></td>
        <td>Netflix alternative. Uses <a href="https://firecore.com/infuse">Infuse</a> as the client on Apple devices.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/home-assistant.svg"></td>
        <td><a href="https://www.home-assistant.io/">Home Assistant</a></td>
        <td>Open-source home automation platform for smart device control and monitoring.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/vaultwarden.svg"></td>
        <td><a href="https://github.com/dani-garcia/vaultwarden">Vaultwarden</a></td>
        <td>Self-hosted, Bitwarden-compatible password manager.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/memos.png"></td>
        <td><a href="https://www.usememos.com/">Memos</a></td>
        <td>Google Keep alternative for personal note-taking.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/stump.svg"></td>
        <td><a href="https://www.stumpapp.dev/">Stump</a></td>
        <td>Digital book server for comics, manga, and ebooks.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/linkwarden.png"></td>
        <td><a href="https://linkwarden.app/">Linkwarden</a></td>
        <td>Bookmark manager to collect and download webpages.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/authentik.svg"></td>
        <td><a href="https://goauthentik.io/">Authentik</a></td>
        <td>Provides single sign-on functionality with OIDC for other apps. Superior to Keycloak.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/qbittorrent.svg"></td>
        <td><a href="https://www.qbittorrent.org/">qBittorrent</a></td>
        <td>Used for legally downloading Linux ISOs with the <a href="https://github.com/VueTorrent/VueTorrent">VueTorrent</a> web UI.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/librespeed.svg"></td>
        <td><a href="https://github.com/librespeed/speedtest/">LibreSpeed</a></td>
        <td>A self-hosted speed test primarily used to measure the performance of my local network across different devices.</td>
    </tr>
</table>

### :hammer: Infrastructure

Everything needed to run my cluster and deploy my applications.
<table>
    <tr>
        <th>Logo</th>
        <th>Name</th>
        <th>Cloud equivalent</th>
        <th>Purpose</th>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/traefik-proxy.svg"></td>
        <td><a href="https://traefik.io/traefik/">Traefik</a></td>
        <td>AWS ALB</td>
        <td>Reverse proxy, also known as an ingress and gateway controller in Kubernetes jargon. Lightyears ahead of nginx.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/cert-manager.svg"></td>
        <td><a href="https://cert-manager.io/">Cert Manager</a></td>
        <td>AWS Certificate Manager</td>
        <td>X.509 certificate management for Kubernetes.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/cilium.svg"></td>
        <td><a href="https://cilium.io/">Cilium</a></td>
        <td>AWS VPC & NLB</td>
        <td>Overlay network that also provides L2/L3-level load balancing, which replaces MetalLB. Features fast eBPF-based networking which replaces ancient Linux iptables.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/postgresql.svg"></td>
        <td><a href="https://cloudnative-pg.io/">CloudNativePG Operator</a></td>
        <td>AWS RDS for PostgreSQL</td>
        <td>Database operator for running highly available PostgreSQL clusters.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cloudnative-pg.io/plugin-barman-cloud/img/logo.svg"></td>
        <td><a href="https://pgbarman.org/">Barman Cloud</a></td>
        <td>AWS RDS Backups</td>
        <td>PostgreSQL backup and recovery tool integrated with CloudNativePG for automated backups to S3.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://www.dragonflydb.io/favicon.ico"></td>
        <td><a href="https://www.dragonflydb.io/">Dragonfly Operator</a></td>
        <td>AWS ElastiCache</td>
        <td>Dragonfly database operator for running highly available Redis-compatible clusters.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/mosquitto.svg"></td>
        <td><a href="https://mosquitto.org/">Eclipse Mosquitto</a></td>
        <td>AWS IoT Core</td>
        <td>Lightweight MQTT broker for IoT device communication and message routing.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/zigbee2mqtt.svg"></td>
        <td><a href="https://www.zigbee2mqtt.io/">Zigbee2MQTT</a></td>
        <td>—</td>
        <td>Zigbee to MQTT bridge enabling Home Assistant integration with Zigbee devices.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://raw.githubusercontent.com/kubernetes-sigs/external-dns/refs/heads/master/docs/img/external-dns.png"></td>
        <td><a href="https://github.com/kubernetes-sigs/external-dns">External DNS</a></td>
        <td>—</td>
        <td>Synchronizes exposed Kubernetes services with Cloudflare DNS.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://raw.githubusercontent.com/external-secrets/external-secrets/refs/heads/main/assets/eso-round-logo.svg"></td>
        <td><a href="https://external-secrets.io/">External Secrets Operator</a></td>
        <td>—</td>
        <td>Used to sync my secrets from Bitwarden Secrets Manager to my cluster.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/argo-cd.svg"></td>
        <td><a href="https://argoproj.github.io/cd/">Argo CD</a></td>
        <td>—</td>
        <td>My GitOps solution of choice.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/svg/grafana.svg"></td>
        <td><a href="https://grafana.com/">Grafana</a></td>
        <td>AWS AMG</td>
        <td>Creates dashboards to visualize metrics and logs from multiple data sources.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/svg/prometheus.svg"></td>
        <td><a href="https://prometheus.io/">Prometheus Operator</a></td>
        <td>AWS AMP</td>
        <td>Collects metrics from applications and infrastructure for monitoring and alerting.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/svg/alertmanager.svg"></td>
        <td><a href="https://prometheus.io/docs/alerting/latest/alertmanager/">Alertmanager</a></td>
        <td>AWS SNS</td>
        <td>Handles Prometheus alerts and routes notifications for cluster and application incidents.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/gatus.svg"></td>
        <td><a href="https://gatus.io/">Gatus</a></td>
        <td>AWS CloudWatch Synthetics</td>
        <td>External status dashboard that monitors public-facing services from outside the homelab.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://raw.githubusercontent.com/stakater/Reloader/refs/heads/master/assets/web/reloader.jpg"></td>
        <td><a href="https://github.com/stakater/Reloader">Reloader</a></td>
        <td>—</td>
        <td>Triggers Kubernetes rollouts for annotated Deployments and StatefulSets when referenced Secrets or ConfigMaps change.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/terraform.svg"></td>
        <td><a href="https://www.hashicorp.com/en/products/terraform/">Terraform</a></td>
        <td>—</td>
        <td>Used for automating and provisioning virtual machines.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://www.svgrepo.com/download/374041/renovate.svg"></td>
        <td><a href="https://github.com/renovatebot/renovate">Renovate</a></td>
        <td>—</td>
        <td>Automated dependency updates.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/helm.svg"></td>
        <td><a href="https://helm.sh/">Helm</a></td>
        <td>—</td>
        <td>Package manager for deploying third-party operators and applications. No custom charts since single environment.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/talos.svg"></td>
        <td><a href="https://www.talos.dev/">Talos Linux</a></td>
        <td>AWS EKS & Bottlerocket</td>
        <td>Modern and lightweight Linux distribution built for Kubernetes that provides production-grade security right out of the box.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/truenas.svg"></td>
        <td><a href="https://www.truenas.com/">TrueNAS</a></td>
        <td>AWS EBS</td>
        <td>Used to provision block storage with the NFS CSI driver on my TrueNAS server. I'm planning to migrate to Rook Ceph in the near future.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/proxmox.svg"></td>
        <td><a href="https://www.proxmox.com/en/products/proxmox-virtual-environment/overview">Proxmox VE</a></td>
        <td>AWS EC2</td>
        <td>Virtualization layer.</td>
    </tr>
</table>

### :cloud: External Cloud Dependencies

While the goal is self-reliance, a few external services are used where self-hosting isn't practical:

| Service | Purpose | Tier |
|---------|---------|------|
| GitHub | Single source of truth for GitOps | Free |
| Bitwarden Secrets Manager | Secret storage for External Secrets Operator | Free |
| Cloudflare | DNS records for non-.ee domains | Free |
| Zone.ee | Domain registrar for .ee domains | Paid |
| AWS S3 | Off-site backups (see Backup Strategy below) | Pay-as-you-go |

**Why these services?**
- **Bitwarden Secrets Manager**: Self-hosting secrets (e.g., HashiCorp Vault) creates a chicken-and-egg problem when running in the same cluster, and maintaining HA Vault is significant overhead.
- **Cloudflare**: Required for ACME DNS-01 challenges (Let's Encrypt). High availability with global DNS caching minimizes risk.
- **Zone.ee**: Best Estonian registrar for .ee domains.
- **AWS S3**: Near-universal backup tool support. Minio was considered but has compatibility issues, and backups need to be offsite anyway.

## :desktop_computer: Physical Infrastructure

Three bare-metal servers form the foundation of this homelab: **Melchior**, **Balthasar**, and **Casper**.

| Node | Hardware | CPU | RAM | Storage |
|------|----------|-----|-----|---------|
| **Melchior** | Custom server | Intel Xeon E-2324G (4C/4T) | 128GB DDR4 ECC | 1TB NVMe + 2×500GB SSD + 3×10TB HDD |
| **Balthasar** | Minisforum MS-01 | Intel i5-12600H (12C/16T) | 32GB DDR5 | 1TB NVMe |
| **Casper** | Minisforum MS-01 | Intel i5-12600H (12C/16T) | 32GB DDR5 | 1TB NVMe |

All nodes run Proxmox VE in a cluster. Each node hosts Kubernetes control plane and worker VMs. Melchior additionally runs TrueNAS (storage) and a Windows 11 VM for game servers. Each server uses **dual network cables** in active/backup bond mode for fault tolerance against cable or switch failures.

**Why ECC memory on Melchior?** ECC (Error-Correcting Code) memory detects and fixes random bit flips in RAM that would otherwise cause crashes or silent data corruption. Since TrueNAS is a single point of failure for most storage, ECC is essential for both uptime and data integrity.

**Why NVMe on all nodes?** Both etcd (Kubernetes cluster state) and PostgreSQL databases require sub-millisecond disk latency. Slow storage causes cluster timeouts and poor database performance.

## :globe_with_meridians: Network Topology

### VLAN Segmentation

Traffic isolation using 802.1Q VLANs across the network:

| VLAN | Name | Subnet | Purpose |
|------|------|--------|---------|
| 1 | Default | 10.1.1.0/24 | Network infrastructure (router, switches) |
| 10 | Management | 10.1.10.0/24 | Proxmox hosts, IPMI/BMC interfaces |
| 20 | Kubernetes | 10.1.20.0/24 | K8s nodes and LoadBalancer services |
| 30 | Storage | 10.1.30.0/24 | NFS and SMB traffic to TrueNAS |
| 40 | VM Services | 10.1.40.0/24 | Non-Kubernetes VMs and Docker hosts |
| 50 | IoT | 10.1.50.0/24 | Smart home devices (Zigbee coordinator, sensors) |
| 80 | Trusted Clients | 10.1.80.0/24 | Personal devices (laptops, phones) |
| 100 | Isolated | 10.1.100.0/24 | Untrusted or guest devices |

### Network Hardware

| Device | Model | Role |
|--------|-------|------|
| Router | UniFi Express 7 | Main gateway with IDS/IPS and WiFi 7 AP |
| Primary Switch | USW Flex 2.5G 8 PoE | 2.5GbE backbone for servers |
| Secondary Switch | USW Flex Mini | Backup switch for redundancy |

### Kubernetes Network

- **API VIP**: 10.1.20.10 (virtual IP for HA control plane)
- **Control Plane**: 10.1.20.11-13
- **Workers**: 10.1.20.21-23
- **LoadBalancer Pool**: 10.1.20.100-120 (Cilium L2)
- **CNI**: Cilium with eBPF (kube-proxy replacement)

## :floppy_disk: Storage Architecture

### Kubernetes Storage

| Storage Class | Backend | Use Case |
|--------------|---------|----------|
| `nfs-csi` | TrueNAS NFS | Application data, media libraries |
| `local-path` | Node NVMe | Prometheus metrics, PostgreSQL databases |

**TrueNAS** (10.1.30.10) serves as the primary storage backend:

- **NFS shares** for Kubernetes persistent volumes via CSI driver
- **SMB shares** for macOS Time Machine backups and file access from personal devices
- **ZFS RAIDZ1** with snapshots and scheduled scrubbing — tolerates one disk failure without downtime or data loss

Performance-sensitive workloads (Prometheus, CloudNativePG clusters) use local NVMe storage to avoid network latency.

## :shield: Security Hardening

### Network Security

- **Geo-blocking**: WAN access restricted to Estonian IP addresses only
- **IPv6 disabled**: ISP lacks support; also avoids geo-blocking bypass vectors
- **VLAN isolation**: Inter-VLAN traffic blocked by default, explicit firewall rules for exceptions
- **UniFi IDS/IPS**: Active threat detection and prevention for WAN and LAN traffic
- **Honeypots**: Deployed to detect and alert on network scanning attempts
- **Minimal public exposure**: Only Authentik, Immich, Memos, Linkwarden, and Jellyfin are internet-accessible; all other services require WireGuard VPN

### Kubernetes Security

- **Talos Linux**: Immutable OS with minimal attack surface — no SSH, no shell, API-only management
- **Network Policies**: Default-deny egress to LAN; pods isolated to their namespace unless explicitly allowed
- **External Secrets Operator**: Secrets synced from Bitwarden Secrets Manager — no secrets in git
- **Namespace isolation**: Each application deployed in its own namespace

### Application Security

- **HTTPS everywhere**: All services (public and internal) use trusted Let's Encrypt certificates via DNS-01 challenge
- **Authentik SSO**: Centralized authentication with passwordless WebAuthn (Apple Touch/Face ID) or password + TOTP 2FA
- **Unique credentials**: All passwords randomly generated and stored in Bitwarden
- **Full disk encryption**: Data at rest encrypted on all storage devices
- **Automated updates**: Renovate bot maintains weekly dependency updates; UniFi firmware auto-updates enabled
- **Cluster upgrades**: [talos-upgrade.sh](talos-upgrade.sh) performs rolling Talos and Kubernetes upgrades with health checks and automatic rollback detection

> **Note on public documentation**: Publishing detailed infrastructure information is an intentional trade-off. It eliminates security through obscurity as a crutch and enforces rigorous security practices by design.

## :floppy_disk: Backup Strategy

Off-site backups to AWS S3 in `eu-north-1` (Stockholm), all client-side encrypted:

| Bucket | Storage Class | Contents |
|--------|---------------|----------|
| `oliverilp-postgresql` | S3 Standard | CloudNativePG continuous WAL backups via Barman |
| `oliverilp-truenas-k8s` | S3 Glacier | Kubernetes persistent volume snapshots |
| `oliverilp-truenas-files` | S3 Glacier | Personal files and documents |
| `oliverilp-synology` | S3 Glacier | Offsite Synology NAS for manual backups |

**PostgreSQL backups**: CloudNativePG handles continuous automated WAL backups. Additionally, [postgresql_backup.sh](postgresql_backup.sh) creates logical `pg_dump` exports for backup redundancy.

Each backup client authenticates with a dedicated IAM user and least-privilege policy scoped to its specific bucket only.

## :construction: Bootstrapping

This section documents the complete infrastructure provisioning and cluster bootstrap process, from Talos Linux configuration generation to Kubernetes cluster initialization and core operator deployment.

[Bootstrap documentation](BOOTSTRAP.MD)
