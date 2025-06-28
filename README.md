# :house: Homelab

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
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/immich.svg"></td>
        <td><a href="https://www.commafeed.com/#/welcome">Immich</a></td>
        <td>Google Photos alternative.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/jellyfin.svg"></td>
        <td><a href="https://github.com/gethomepage/homepage">Jellyfin</a></td>
        <td>Netflix alternative.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/memos.png"></td>
        <td><a href="https://github.com/gethomepage/homepage">Memos</a></td>
        <td>Personal note-taking app.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/linkwarden.png"></td>
        <td><a href="https://github.com/gethomepage/homepage">Linkwarden</a></td>
        <td>Bookmark manager to collect and download webpages.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/authentik.svg"></td>
        <td><a href="https://www.commafeed.com/#/welcome">Authentik</a></td>
        <td>Provides single sign-on functionality with OIDC for other apps.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/qbittorrent.svg"></td>
        <td><a href="https://n8n.io/">qBittorrent</a></td>
        <td>Used for legally downloading Linux ISOs.</td>
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
        <td>Reverse proxy, also known as an ingress and gateway controller in Kubernetes jargon.</td>
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
        <td>Overlay network that also provides L2/L3-level load balancing, which replaces MetalLB.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/postgresql.svg"></td>
        <td><a href="https://cloudnative-pg.io/">CloudNativePG</a></td>
        <td>AWS RDS for PostgreSQL</td>
        <td>Database operator for running highly available PostgreSQL clusters.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://www.dragonflydb.io/favicon.ico"></td>
        <td><a href="https://www.dragonflydb.io/">Dragonfly</a></td>
        <td>AWS ElastiCache</td>
        <td>Dragonfly database operator for running highly available Redis-compatible clusters.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://www.svgrepo.com/download/530451/dns.svg"></td>
        <td><a href="https://github.com/kubernetes-sigs/external-dns">External DNS</a></td>
        <td>—</td>
        <td>Synchronizes exposed Kubernetes services with Cloudflare DNS.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/argo-cd.svg"></td>
        <td><a href="https://argoproj.github.io/cd/">Argo CD</a></td>
        <td>—</td>
        <td>My GitOps solution of choice.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/terraform.svg"></td>
        <td><a href="https://www.hashicorp.com/en/products/terraform/">Terraform</a></td>
        <td>—</td>
        <td>Used for automating and provisioning virtual machines. I plan to start using it for IaC configuration of network devices (Mikrotik switches and router).</td>
    </tr>
    <tr>
        <td><img width="32" src="https://www.svgrepo.com/download/374041/renovate.svg"></td>
        <td><a href="https://github.com/renovatebot/renovate">Renovate</a></td>
        <td>—</td>
        <td>Automated dependency updates.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/talos.svg"></td>
        <td><a href="https://www.talos.dev/">Talos</a></td>
        <td>AWS EKS & Bottlerocket</td>
        <td>Modern and lightweight Linux distribution built for Kubernetes that provides production-grade security right out of the box.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/truenas.svg"></td>
        <td><a href="https://www.truenas.com/">TrueNAS</a></td>
        <td>AWS EBS</td>
        <td>Used to provision block storage with the NFS CSI driver on my TrueNAS server. I'm planning to migrate to Longhorn in the near future.</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/proxmox.svg"></td>
        <td><a href="https://www.proxmox.com/en/products/proxmox-virtual-environment/overview">Proxmox VE</a></td>
        <td>AWS EC2</td>
        <td>Virtualization layer.</td>
    </tr>
</table>

## :construction: Bootstrapping

This section documents the complete infrastructure provisioning and cluster bootstrap process, from Talos Linux configuration generation to Kubernetes cluster initialization and core operator deployment.

[Bootstrap documentation](BOOTSTRAP.MD)
