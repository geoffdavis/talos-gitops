# Technology Stack: Talos GitOps Home-Ops Cluster

## Core Technologies

### Operating System & Container Runtime
- **Talos OS v1.10.5**: Immutable Linux OS designed for Kubernetes
- **Kubernetes v1.31.1**: Container orchestration platform
- **containerd**: Container runtime (managed by Talos)

### Networking
- **Cilium v1.17.6**: CNI with eBPF-based networking and security
- **BGP**: Border Gateway Protocol for load balancer IP advertisement
- **Dual-Stack IPv6**: Full IPv4/IPv6 networking support
- **LLDP**: Link Layer Discovery Protocol for network topology

### Storage
- **Longhorn**: Distributed block storage for Kubernetes
- **Samsung Portable SSD T5**: External USB SSDs (3x 1TB)
- **XFS**: Filesystem for storage volumes
- **LUKS2**: Disk encryption for STATE and EPHEMERAL partitions

### GitOps & CI/CD
- **Flux v2.4.0**: GitOps operator for Kubernetes
- **Kustomize**: Kubernetes configuration management
- **GitHub**: Git repository hosting with webhook integration
- **Renovate**: Automated dependency updates

### Secret Management
- **1Password Connect**: Centralized secret management
- **External Secrets Operator**: Kubernetes secret synchronization
- **RBAC**: Role-based access control

### Monitoring & Observability
- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization and dashboards
- **AlertManager**: Alert routing and management
- **Hubble**: Cilium network observability

### Identity & Security
- **Authentik**: Identity provider and SSO
- **PostgreSQL**: Database backend for Authentik
- **cert-manager**: TLS certificate automation
- **Let's Encrypt**: Certificate authority for internal services

### Ingress & Load Balancing
- **ingress-nginx**: HTTP/HTTPS ingress controller (multiple instances)
- **Cloudflare Tunnel**: Secure external access
- **External DNS**: Automatic DNS record management

## Development Tools

### Required Tools (via mise)
- **task v3.38.0+**: Task runner for automation
- **talhelper**: Talos configuration helper
- **talosctl v1.10.5+**: Talos CLI tool
- **kubectl v1.31.1+**: Kubernetes CLI
- **flux v2.4.0+**: Flux CLI
- **helm v3.16.1+**: Kubernetes package manager
- **kustomize v5.4.3+**: Configuration management
- **cilium v0.16.16+**: Cilium CLI
- **yq v4.44.3+**: YAML processor
- **jq v1.7.1+**: JSON processor
- **op v2.0.0+**: 1Password CLI

### Development Environment Setup
```bash
# Install mise for tool management
curl https://mise.jdx.dev/install.sh | sh

# Install all required tools
mise install

# Configure environment
cp .env.example .env
# Edit .env to set OP_ACCOUNT
```

## Hardware Architecture

### Node Specifications
- **Platform**: Intel Mac mini devices
- **Count**: 3 nodes (all-control-plane)
- **Role**: Each node functions as both control plane and worker
- **Storage**: Apple internal storage for OS, USB SSDs for data

### Network Configuration
- **VLAN**: 51 (172.29.51.0/24)
- **IPv6**: fd47:25e1:2f96:51::/64 (ULA)
- **BGP ASN**: Cluster 64512, Router 64513
- **Upstream**: Unifi UDM Pro with BGP peering

### Storage Architecture
- **OS Storage**: Apple internal drives (auto-detected)
- **Data Storage**: 3x Samsung Portable SSD T5 (1TB each)
- **Total Capacity**: 3TB raw, ~1.35TB effective (2-replica)
- **Performance**: Optimized with custom udev rules and sysctls

## Technical Constraints

### Hardware Limitations
- **USB Storage**: External SSDs required due to Mac mini storage limitations
- **Network**: Single network interface per node
- **Power**: No redundant power supplies (home lab environment)

### Software Constraints
- **Talos Immutability**: OS changes require configuration regeneration
- **CNI Dependency**: Cilium must be deployed before any pods can start
- **Secret Bootstrap**: 1Password Connect required before GitOps can access secrets

### Operational Constraints
- **Bootstrap Order**: Strict dependency chain must be followed
- **Network Dependencies**: BGP peering required for load balancer functionality
- **DNS Integration**: External DNS providers must be properly configured

## Cilium Configuration Details

### Cilium v1.17.6 Deployment Parameters
- **XDP Acceleration**: Disabled for Mac mini compatibility (`--set loadBalancer.acceleration=disabled`)
- **LoadBalancer IPAM**: Enabled (`--set enable-lb-ipam=true`)
- **L2 Announcements**: Disabled (`--set loadBalancer.l2.enabled=false`)
- **BGP Control Plane**: Enabled for load balancer IP advertisement
- **Kube-proxy Replacement**: Disabled in Talos configuration
- **Dual-Stack Support**: IPv4/IPv6 networking enabled

### BGP LoadBalancer Configuration
- **Cluster ASN**: 64512 (all nodes participate in BGP)
- **UDM Pro ASN**: 64513 (BGP peer and route acceptor)
- **BGP Peering Status**: ✅ Established and stable
- **Route Advertisement**: ❌ Currently not working (CiliumBGPAdvertisement issue)
- **IP Pool Architecture**:
  - bgp-default: 172.29.52.100-199 (default services)
  - bgp-ingress: 172.29.52.200-220 (ingress controllers)
  - bgp-reserved: 172.29.52.221-250 (reserved for future use)

## Tool Usage Patterns

### Bootstrap Operations
```bash
# Cluster lifecycle
task bootstrap:phased          # Complete phased bootstrap
task cluster:safe-reset        # Safe cluster reset
task cluster:emergency-recovery # Emergency procedures

# Node operations
task talos:apply-config        # Apply Talos configuration
task talos:bootstrap          # Initialize cluster
task talos:reboot             # Reboot nodes

# Core services
task apps:deploy-cilium       # Deploy CNI (Cilium v1.17.6 with XDP disabled)
task bootstrap:1password-secrets # Bootstrap secrets
task flux:bootstrap           # Deploy GitOps
```

### GitOps Operations
```bash
# Flux management
flux get kustomizations       # Check deployment status
flux reconcile source git flux-system # Force sync
flux logs --follow           # Monitor deployments

# Application management
git add apps/my-app/         # Stage application
git commit -m "Add my-app"   # Commit changes
git push                     # Trigger deployment
```

### Monitoring & Diagnostics
```bash
# Cluster health
task cluster:status          # Overall cluster status
kubectl get nodes           # Node status
kubectl get pods -A         # Pod status

# Network diagnostics
cilium status               # CNI status
task bgp:verify-peering     # BGP status
task network:check-ipv6     # IPv6 configuration

# BGP troubleshooting
kubectl get ciliumbgppeers  # BGP peering status
kubectl get ciliumbgpadvertisements # Route advertisement config
kubectl exec -n kube-system -l k8s-app=cilium -- cilium bgp routes # BGP routes
kubectl logs -n kube-system -l k8s-app=cilium | grep -i bgp # BGP logs

# Storage diagnostics
task storage:check-longhorn  # Storage health
task storage:validate-usb-ssd # USB SSD validation
```

## Integration Patterns

### External Service Integration
- **1Password**: API-based secret retrieval and management
- **Cloudflare**: DNS management and tunnel configuration
- **GitHub**: Git repository with webhook integration
- **Unifi**: BGP peering and network integration

### Internal Service Dependencies
- **Bootstrap → GitOps**: Sequential deployment phases
- **Secrets → Applications**: External secrets provide credentials
- **Networking → Storage**: CNI required for distributed storage
- **Monitoring → Everything**: Observability across all components

## Security Architecture

### Encryption
- **Disk Encryption**: LUKS2 for STATE and EPHEMERAL partitions
- **Network Encryption**: TLS for all service communication
- **Secret Encryption**: Kubernetes secrets encrypted at rest

### Access Control
- **RBAC**: Kubernetes role-based access control
- **Network Policies**: Cilium-based network segmentation
- **Pod Security**: Pod Security Standards enforcement

### Certificate Management
- **Internal**: Let's Encrypt via cert-manager
- **External**: Cloudflare-managed certificates
- **Cluster**: Talos-generated cluster certificates

This technology stack provides a robust, secure, and scalable foundation for home lab operations while demonstrating enterprise-grade Kubernetes practices and GitOps workflows.