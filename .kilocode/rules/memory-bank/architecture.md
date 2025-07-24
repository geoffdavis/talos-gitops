# Architecture: Talos GitOps Home-Ops Cluster

## System Architecture Overview

This cluster implements a sophisticated two-phase architecture that separates foundational system components (Bootstrap Phase) from operational services (GitOps Phase), enabling both reliable cluster operations and collaborative development workflows.

## Core Architecture Principles

### Bootstrap vs GitOps Separation

**Bootstrap Phase** - Direct deployment of foundational components:
- Components required for cluster to start
- System-level configurations that need direct hardware/OS access
- Dependencies required for GitOps system to function
- Managed via Taskfile commands and direct kubectl/talosctl operations

**GitOps Phase** - Git-managed operational components:
- Kubernetes-native resources that benefit from version control
- Infrastructure services and applications
- Operational configurations that change over time
- Managed via Flux GitOps with Git commits triggering deployments

## Source Code Structure

### Key Configuration Files
- **[`talconfig.yaml`](../talconfig.yaml)**: Talos OS cluster configuration with all-control-plane setup
- **[`Taskfile.yml`](../Taskfile.yml)**: Bootstrap automation and operational tasks
- **[`bootstrap-config.yaml`](../bootstrap-config.yaml)**: Phased bootstrap configuration
- **[`.env.example`](../.env.example)**: Environment configuration template

### Directory Structure
```
├── clusters/home-ops/           # GitOps cluster configuration
│   ├── flux-system/            # Flux GitOps system
│   └── infrastructure/         # Infrastructure Kustomizations
├── infrastructure/             # Infrastructure service manifests
│   ├── authentik/              # Identity provider
│   ├── authentik-proxy/        # External outpost for authentication
│   ├── cilium/                 # CNI configuration (GitOps part)
│   ├── longhorn/               # Distributed storage
│   ├── onepassword-connect/    # Secret management
│   └── monitoring/             # Observability stack
├── apps/                       # Application deployments
├── talos/                      # Talos OS configuration
│   ├── patches/                # Configuration patches
│   └── manifests/              # System manifests
├── scripts/                    # Bootstrap and utility scripts
├── taskfiles/                  # Modular task definitions
└── docs/                       # Comprehensive documentation
```

## Component Architecture

### Bootstrap Phase Components

#### 1. Talos OS Configuration
- **Location**: [`talconfig.yaml`](../talconfig.yaml), [`talos/patches/`](../talos/patches/)
- **Purpose**: Node operating system configuration
- **Key Features**:
  - All-control-plane setup (3 nodes, all control plane + worker)
  - Smart disk selection with `installDiskSelector: model: "APPLE*"`
  - USB SSD optimization for Samsung Portable SSD T5
  - Dual-stack IPv6 networking
  - LUKS2 encryption for STATE and EPHEMERAL partitions

#### 2. Cluster Networking (Cilium CNI Core)
- **Location**: [`Taskfile.yml:apps:deploy-cilium`](../Taskfile.yml)
- **Purpose**: Container networking foundation
- **Configuration**:
  - Kube-proxy replacement disabled in Talos
  - Dual-stack IPv4/IPv6 support
  - BGP control plane enabled
  - LoadBalancer IPAM enabled (Cilium v1.17.6)
  - XDP disabled for Mac mini compatibility

#### 3. Secret Management Foundation
- **Components**: 1Password Connect + External Secrets Operator
- **Bootstrap Script**: [`scripts/bootstrap-1password-secrets.sh`](../scripts/bootstrap-1password-secrets.sh)
- **Purpose**: Secure credential management for GitOps
- **Features**:
  - Supports both legacy and separate 1Password entries
  - Credential format validation and truncation handling
  - Automatic Kubernetes secret creation

#### 4. Flux GitOps System
- **Location**: [`Taskfile.yml:flux:bootstrap`](../Taskfile.yml)
- **Purpose**: GitOps operator deployment
- **Integration**: GitHub repository with webhook support

### GitOps Phase Components

#### 1. Infrastructure Services
- **Location**: [`infrastructure/`](../infrastructure/) directory
- **Management**: Flux Kustomizations with dependency ordering
- **Key Services**:
  - **cert-manager**: TLS certificate automation
  - **ingress-nginx**: HTTP/HTTPS ingress (multiple instances)
  - **external-dns**: Automatic DNS record management
  - **monitoring**: Prometheus, Grafana, AlertManager stack
  - **longhorn**: Distributed storage system

#### 2. Network Services
- **Cilium BGP**: [`infrastructure/cilium-bgp/`](../infrastructure/cilium-bgp/)
  - CiliumBGPClusterConfig: Global BGP configuration
  - CiliumBGPPeerConfig: BGP peering with UDM Pro (ASN 64513)
  - CiliumBGPAdvertisement: Route advertisement configuration (currently problematic)
- **Load Balancer Pools**: [`infrastructure/cilium/loadbalancer-pool-bgp.yaml`](../infrastructure/cilium/loadbalancer-pool-bgp.yaml)
  - bgp-default: 172.29.52.100-199 (default services)
  - bgp-ingress: 172.29.52.200-220 (ingress controllers)
  - bgp-reserved: 172.29.52.221-250 (reserved for future use)
- **External DNS**: Multiple providers (Cloudflare, Unifi, internal)
- **Cloudflare Tunnel**: [`infrastructure/cloudflare-tunnel/`](../infrastructure/cloudflare-tunnel/)

#### 3. Identity Management
- **Authentik**: [`infrastructure/authentik/`](../infrastructure/authentik/) - Complete SSO identity provider
- **PostgreSQL Backend**: [`infrastructure/postgresql-cluster/`](../infrastructure/postgresql-cluster/) - Database for Authentik
- **External Authentik-Proxy**: [`infrastructure/authentik-proxy/`](../infrastructure/authentik-proxy/) - External outpost for Kubernetes services
- **Authentication Architecture**: External outpost handles all *.k8s.home.geoffdavis.com services with dedicated deployment and Redis session storage

## Key Technical Decisions

### All-Control-Plane Architecture
- **Rationale**: Maximum resource utilization in home lab environment
- **Implementation**: All 3 nodes function as both control plane and worker nodes
- **Benefits**: High availability, simplified management, better resource usage
- **Configuration**: `allowSchedulingOnMasters: true` in talconfig.yaml

### USB SSD Storage Strategy
- **Hardware**: 3x Samsung Portable SSD T5 (1TB each)
- **Total Capacity**: 3TB raw, ~1.35TB effective with 2-replica factor
- **Optimization**: Custom udev rules and sysctls for SSD performance
- **Detection**: Automatic disk selection via `match: disk.model == "Portable SSD T5"`

### Dual-Stack IPv6 Networking
- **IPv4 Networks**:
  - Pods: 10.244.0.0/16
  - Services: 10.96.0.0/12
  - Management: 172.29.51.0/24 (VLAN 51)
  - LoadBalancer Pool: 172.29.52.0/24 (VLAN 52, BGP-advertised)
- **IPv6 Networks**:
  - Pods: fd47:25e1:2f96:51:2000::/64
  - Services: fd47:25e1:2f96:51:1000::/108
  - LoadBalancer Pool: fd47:25e1:2f96:51:100::/120

### BGP LoadBalancer Architecture
- **Architecture Model**: Hybrid L2/BGP (L2 for control plane, BGP for LoadBalancer services)
- **BGP Configuration**:
  - Cluster ASN: 64512 (all nodes participate in BGP)
  - UDM Pro ASN: 64513 (BGP peer and route acceptor)
  - Peering Status: ✅ Established and stable
  - Route Advertisement: ❌ Currently not working (CiliumBGPAdvertisement issue)
- **Network Separation**:
  - Management Traffic: VLAN 51 (172.29.51.x) - L2 announcements
  - LoadBalancer IPs: VLAN 52 (172.29.52.x) - BGP advertisements
- **IP Pool Management**:
  - Pool selectors match service annotations (io.cilium/lb-ipam-pool)
  - Automatic IP assignment from appropriate pools based on service type
  - IPAM conflicts resolved by removing duplicate pools

### DNS Architecture
- **Internal Domain**: k8s.home.geoffdavis.com (fits existing home domain structure)
- **External Domain**: geoffdavis.com (via Cloudflare tunnel)
- **Certificate Strategy**: Let's Encrypt for internal, Cloudflare for external
- **Integration**: BGP-advertised ingress IP (172.29.52.200 - new BGP pool)
- **DNS Management**: External DNS updates records for *.k8s.home.geoffdavis.com domain
- **Network Integration**: UDM Pro accepts BGP routes and provides DNS resolution

### Authentication Architecture
- **Identity Provider**: Authentik provides centralized SSO for all cluster services
- **External Outpost Model**: External outpost architecture with dedicated deployment for Kubernetes service integration
- **Ingress Architecture**: **CRITICAL** - Only external outpost ingress handles *.k8s.home.geoffdavis.com domains
- **Service Integration**: Individual services must NOT have their own ingresses for authenticated domains
- **Token Management**: External outpost API tokens properly managed with 1Password integration
- **Service Coverage**: All *.k8s.home.geoffdavis.com services redirect to Authentik for authentication via external outpost
- **Session Storage**: Dedicated Redis instance in authentik-proxy namespace for session management
- **SSL/TLS**: Proper certificate validation and secure communication between external outpost and Authentik server
- **Network Connectivity**: Verified clear network path between authentik-proxy namespace and service namespaces

### External Outpost Architecture Details
- **Deployment Model**: Standalone external outpost deployment separate from Authentik server
- **Components**:
  - **authentik-proxy deployment**: External outpost pods running proxy functionality
  - **Redis instance**: Dedicated Redis for session storage and caching
  - **Ingress controller**: BGP load balancer integration for *.k8s.home.geoffdavis.com domains
  - **Secret management**: ExternalSecret integration with 1Password for API tokens
- **Outpost Registration**: External outpost `3f0970c5-d6a3-43b2-9a36-d74665c6b24e` registered with Authentik server
- **Configuration Management**: Python-based configuration scripts for proxy provider setup
- **Scalability**: Independent scaling of authentication proxy separate from identity provider
- **Reliability**: Improved fault isolation between authentication proxy and identity provider

## Critical Implementation Paths

### Bootstrap Sequence
1. **Environment Setup**: Tool installation via mise
2. **Talos Configuration**: Generate and apply node configs
3. **Cluster Initialization**: Bootstrap first control plane node
4. **Core Networking**: Deploy Cilium CNI
5. **Secret Management**: Bootstrap 1Password Connect secrets
6. **GitOps Foundation**: Deploy Flux system
7. **Infrastructure Deployment**: Flux takes over via Git

### GitOps Dependency Chain
```mermaid
graph TD
    A[Flux System] --> B[Sources & External Secrets]
    B --> C[1Password Connect]
    C --> D[Cert Manager & Monitoring]
    D --> E[Ingress Controllers]
    E --> F[Storage & Database]
    F --> G[Identity Management]
    G --> H[Applications]
```

### Safety and Recovery Architecture
- **Safe Reset**: `task cluster:safe-reset` preserves OS, wipes only STATE/EPHEMERAL
- **Emergency Recovery**: `task cluster:emergency-recovery` for systematic troubleshooting
- **LLDPD Stability**: Integrated configuration prevents periodic reboot issues
- **Phased Bootstrap**: Resumable process with clear failure points

## Component Relationships

### Hybrid Components (Span Both Phases)
- **Cilium**: Core CNI (Bootstrap) + BGP/LoadBalancer config (GitOps)
- **Secret Management**: Initial K8s secrets (Bootstrap) + ExternalSecrets (GitOps)
- **Monitoring**: Basic health checks (Bootstrap) + Full observability stack (GitOps)

### Critical Dependencies
- **Talos → Kubernetes**: OS configuration before cluster initialization
- **Kubernetes → Cilium**: API server before CNI deployment
- **Cilium → Pods**: Networking before any pod can start
- **Pods → 1Password Connect**: Secret management requires pod networking
- **Secrets → Flux**: GitOps needs credentials for Git repository access
- **Flux → Everything Else**: GitOps manages all subsequent deployments

## Operational Patterns

### Decision Framework
- **Bootstrap Phase**: Node configuration, cluster networking, system-level changes
- **GitOps Phase**: Applications, infrastructure services, operational configuration
- **Emergency Override**: Direct kubectl/talosctl when GitOps is broken

### Change Management
- **Bootstrap Changes**: Update configuration files → regenerate → apply via tasks
- **GitOps Changes**: Update manifests → commit to Git → Flux deploys automatically
- **Rollback Procedures**: Git revert for GitOps, configuration restore for Bootstrap

This architecture enables both robust cluster operations and collaborative development workflows while maintaining clear operational boundaries and comprehensive safety procedures.