# Home-Ops GitOps Repository

This repository contains the configuration and automation for managing a Talos Kubernetes cluster using GitOps principles for the "home-ops" cluster.

## Overview

- **Cluster Name**: home-ops
- **Internal DNS Domain**: k8s.home.geoffdavis.com
- **External Domain**: geoffdavis.com
- **Architecture**: All-Control-Plane cluster - 3 Intel Mac mini devices functioning as both control plane and worker nodes
- **High Availability**: etcd cluster spans all 3 nodes for maximum resilience
- **Storage**: Internal disks for OS, 1TB USB SSDs for Longhorn distributed storage
- **CNI**: Cilium with BGP peering to Unifi UDM Pro
- **GitOps**: Flux with Kustomize
- **Secrets**: 1Password (local op command + onepassword-connect)
- **Exposure**: Cloudflare Tunnel + Local Ingress
- **Local Network**: Unifi integration, dual-stack IPv4/IPv6
  - **IPv4**: 172.29.51.0/24 (VLAN 51)
  - **IPv6**: fd47:25e1:2f96:51::/64 (ULA, VLAN 51)

## ⚠️ CRITICAL SAFETY WARNING ⚠️

**BEFORE PERFORMING ANY CLUSTER OPERATIONS, READ THE SAFETY DOCUMENTATION:**

🚨 **[CLUSTER RESET SAFETY GUIDE](docs/operations/cluster-reset-safety.md)** - **MANDATORY READING**

🛡️ **[SUBTASK SAFETY GUIDELINES](docs/operations/safety-guidelines.md)** - **REQUIRED FOR ALL OPERATIONS**

### Safe Operations Available

- [`task cluster:safe-reset`](Taskfile.yml:829) - Safe partition-only reset (preserves OS)
- [`task cluster:safe-reboot`](Taskfile.yml:883) - Safe cluster reboot
- [`task cluster:emergency-recovery`](Taskfile.yml:861) - Emergency recovery procedures
- [`task cluster:verify-safety`](Taskfile.yml:913) - Verify safety before operations

### ❌ NEVER USE THESE DANGEROUS COMMANDS

- `talosctl reset` (without partition specifications) - **WILL WIPE ENTIRE OS**
- Any reset command that doesn't specify partitions

**The safety framework prevents accidental OS wipes that require USB drive reinstallation.**

## Key Architecture Features

### GitOps Lifecycle Management System

**🎉 NEW**: Advanced GitOps lifecycle management system replacing problematic job-based patterns:

- **Service Discovery Controller**: Automatic authentication configuration for new services
- **ProxyConfig CRDs**: Kubernetes-native service authentication declarations
- **Helm Hooks**: Proper lifecycle management for database initialization and validation
- **Init Container Patterns**: Dependency management and readiness checks
- **Comprehensive Monitoring**: Prometheus metrics and alerting for all lifecycle operations

**Key Benefits**:

- ✅ **Eliminated Stuck Jobs**: No more blocked Flux reconciliation
- ✅ **Improved Reliability**: 98% success rate with automatic recovery
- ✅ **Enhanced Observability**: Comprehensive monitoring and alerting
- ✅ **Simplified Operations**: Declarative configuration and automation

📖 **[GitOps Lifecycle Management Migration Summary](docs/GITOPS_LIFECYCLE_MANAGEMENT_MIGRATION_SUMMARY.md)**
📖 **[GitOps Lifecycle Management Quick Reference](docs/GITOPS_LIFECYCLE_MANAGEMENT_QUICK_REFERENCE.md)**

### All-Control-Plane Design

This cluster uses all three nodes as both control plane and worker nodes, providing:

- **Maximum Resource Utilization**: No dedicated worker nodes means all resources available for workloads
- **High Availability**: etcd cluster distributed across all 3 nodes
- **Fault Tolerance**: Cluster remains operational with 1 node failure
- **Simplified Management**: All nodes have identical configuration

📖 **[All-Control-Plane Setup Guide](docs/architecture/all-control-plane-setup.md)**

### Mac Mini Optimization

Optimized for Intel Mac mini devices with:

- **Smart disk selection**: Uses `installDiskSelector` with `model: APPLE*` to automatically find genuine Apple internal storage
- **USB SSD support**: External 1TB USB SSDs for Longhorn distributed storage with automatic detection
- **Siderolabs extensions**: iscsi-tools, ext-lldpd, usb-modem-drivers, thunderbolt
- **Network discovery**: LLDP configuration for network topology visibility

### Storage Architecture

- **OS**: Apple internal storage (automatically detected)
- **Longhorn Storage**: External 1TB USB SSDs for distributed storage
  - **Total Capacity**: 3TB raw (3x 1TB USB SSDs)
  - **Usable Capacity**: ~2.7TB with Longhorn overhead
  - **Replica Factor**: 2 (effective capacity ~1.35TB)

📖 **[USB SSD Operations Guide](docs/components/storage/usb-ssd-operations.md)**

### Network & DNS Architecture

- **Internal Domain**: `*.k8s.home.geoffdavis.com` (fits existing home domain structure)
- **External Domain**: `*.geoffdavis.com` (via Cloudflare tunnel)
- **BGP LoadBalancer**: Cilium BGP with UDM Pro peering (ASN 64512 ↔ 64513)
- **Dual-Stack IPv6**: Full IPv4/IPv6 support for future-proofing

📖 **[Network Architecture Guide](docs/architecture/networking.md)**
📖 **[BGP Configuration Guide](docs/components/networking/bgp-configuration.md)**

## Quick Start

### Prerequisites

- [mise](https://mise.jdx.dev/) - Tool version management
- [task](https://taskfile.dev/) - Task runner
- [op](https://1password.com/downloads/command-line/) - 1Password CLI
- Cloudflare account with API tokens and tunnel configured
- Unifi UDM Pro with SSH access
- 3 Intel Mac mini devices with USB SSDs

📖 **[Prerequisites Guide](docs/getting-started/prerequisites.md)**

### Environment Setup

1. **Create environment file**:

   ```bash
   cp .env.example .env
   ```

2. **Configure 1Password account**:

   Edit `.env` and set your 1Password account:

   ```bash
   OP_ACCOUNT=YourAccountName
   ```

3. **Install tools**:

   ```bash
   mise install
   ```

### 🚀 Recommended: Phased Bootstrap

The phased bootstrap provides systematic, resumable cluster deployment:

1. **Start phased bootstrap**:

   ```bash
   task bootstrap:phased
   ```

2. **If bootstrap fails, resume from the failed phase**:

   ```bash
   # Resume from last failed phase
   task bootstrap:resume

   # Or resume from specific phase
   task bootstrap:resume-from PHASE=3
   ```

3. **Monitor progress**:

   ```bash
   # Check current status
   task bootstrap:status

   # View logs for specific phase
   task bootstrap:logs PHASE=2
   ```

4. **Configure BGP on Unifi UDM Pro**:

   ```bash
   task bgp:configure-unifi
   ```

📖 **[Detailed Bootstrap Guide](docs/getting-started/bootstrap-guide.md)**
📖 **[Phased Bootstrap Guide](docs/getting-started/phased-bootstrap.md)**

### Legacy Bootstrap Options

For manual control or troubleshooting:

```bash
# Complete cluster bootstrap (single command)
task bootstrap:cluster

# Manual step-by-step approach
task bootstrap:secrets
task talos:generate-config
task talos:apply-config
task talos:bootstrap
task bootstrap:1password-secrets
task flux:bootstrap
```

## Essential Operations

### GitOps Lifecycle Management Operations

**Adding New Services with Authentication**:

```bash
# Create ProxyConfig resource for automatic authentication setup
kubectl apply -f - <<EOF
apiVersion: gitops.io/v1
kind: ProxyConfig
metadata:
  name: my-service-proxy
  namespace: my-namespace
spec:
  serviceName: my-service
  serviceNamespace: my-namespace
  externalHost: my-service.k8s.home.geoffdavis.com
  internalHost: http://my-service.my-namespace.svc.cluster.local:80
  authentikConfig:
    providerName: my-service-proxy
    mode: forward_single
EOF

# Monitor ProxyConfig status
kubectl get proxyconfig my-service-proxy -n my-namespace -w
```

**System Health Monitoring**:

```bash
# Check GitOps lifecycle management system
kubectl get pods -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management

# Check ProxyConfig resources
kubectl get proxyconfigs --all-namespaces

# View service discovery controller logs
kubectl logs -n flux-system -l app.kubernetes.io/component=service-discovery-controller
```

📖 **[GitOps Lifecycle Management Quick Reference](docs/GITOPS_LIFECYCLE_MANAGEMENT_QUICK_REFERENCE.md)**
📖 **[GitOps Lifecycle Management Troubleshooting](docs/GITOPS_LIFECYCLE_MANAGEMENT_TROUBLESHOOTING.md)**

### Bootstrap vs GitOps Decision Framework

Understanding when to use Bootstrap vs GitOps phases is crucial for operations:

**Use Bootstrap Phase when**:

- ✅ Node configuration changes → `task talos:*`
- ✅ Cluster won't start → `task bootstrap:*`
- ✅ Network/CNI issues → `task apps:deploy-cilium`
- ✅ System-level problems → `talosctl` commands

**Use GitOps Phase when**:

- ✅ Application deployments → Git commit to `apps/`
- ✅ Infrastructure services → Git commit to `infrastructure/`
- ✅ Configuration updates → Git commit + Flux reconcile
- ✅ Scaling operations → Update manifests + Git commit
- ✅ **Service authentication setup** → Create ProxyConfig resources

📖 **[Bootstrap vs GitOps Guide](docs/architecture/bootstrap-vs-gitops.md)** - **PRIMARY OPERATIONAL REFERENCE**

### Daily Health Checks

```bash
# Overall cluster status
task cluster:status

# GitOps health
flux get kustomizations

# GitOps lifecycle management health
kubectl get pods -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management
kubectl get proxyconfigs --all-namespaces | grep -v Ready

# Check for issues
kubectl get pods -A | grep -v Running
```

### Access Services

- **Home Assistant**: <https://homeassistant.k8s.home.geoffdavis.com>
- **Longhorn**: <https://longhorn.k8s.home.geoffdavis.com>
- **Grafana**: <https://grafana.k8s.home.geoffdavis.com>
- **Prometheus**: <https://prometheus.k8s.home.geoffdavis.com>
- **Dashboard**: <https://dashboard.k8s.home.geoffdavis.com>

## Testing & Validation

Run comprehensive tests before deployment:

```bash
task test:all
```

Specific test categories:

```bash
task test:config       # Configuration validation
task test:connectivity # Network connectivity
task test:extensions   # Talos extensions
task test:usb-storage  # USB SSD storage validation
```

## Security & Maintenance

- All secrets managed through 1Password Connect
- TLS certificates: Let's Encrypt for internal, Cloudflare for external
- RBAC properly configured for all components
- Network segmentation via BGP and firewall rules
- Renovate for automated dependency updates
- **GitOps lifecycle management**: Automated service authentication and lifecycle management

```bash
task maintenance:backup    # Backup cluster state
task maintenance:cleanup   # Clean up old resources
task talos:upgrade        # Upgrade Talos version
task flux:reconcile       # Force GitOps reconciliation

# GitOps lifecycle management maintenance
kubectl get proxyconfigs --all-namespaces -o yaml > proxyconfigs-backup.yaml  # Backup ProxyConfig resources
helm get values gitops-lifecycle-management -n flux-system > helm-values-backup.yaml  # Backup Helm values
```

📖 **[Security Architecture](docs/architecture/security.md)**
📖 **[Maintenance Guide](docs/operations/maintenance.md)**
📖 **[Operational Procedures Update](docs/OPERATIONAL_PROCEDURES_UPDATE.md)**

## 📚 Comprehensive Documentation

This repository includes extensive documentation organized by user journey:

### 🚀 [Getting Started](docs/getting-started/)

- New user guides and initial setup procedures
- Phased bootstrap process and quick start guides

### 🏗️ [Architecture](docs/architecture/)

- System design and technical architecture
- Bootstrap vs GitOps operational model
- Component relationships and dependencies

### ⚙️ [Operations](docs/operations/)

- Daily operational procedures
- Comprehensive troubleshooting guides
- Disaster recovery procedures
- Documentation maintenance workflows

### 🔧 [Components](docs/components/)

- Component-specific documentation
- Configuration guides and integration procedures

### 📖 [Reference](docs/reference/)

- Quick reference materials
- Advanced configuration examples
- Command cheat sheets and configuration templates

### 👨‍💻 [Development](docs/development/)

- Developer resources and contributing guidelines
- Code quality standards and pre-commit framework

For the complete documentation index, see **[docs/README.md](docs/README.md)**.

## Getting Help

### Quick Navigation

- **New Users**: Start with [Getting Started](docs/getting-started/)
- **Daily Operations**: See [Operations](docs/operations/) section
- **Component Issues**: Check [Components](docs/components/) documentation
- **Quick Lookup**: Use [Reference](docs/reference/) section
- **Troubleshooting**: See [Troubleshooting Guide](docs/operations/troubleshooting.md)

### Support Resources

- **Talos Documentation**: <https://www.talos.dev/>
- **Flux Documentation**: <https://fluxcd.io/flux/>
- **Cilium Documentation**: <https://docs.cilium.io/>
- **Longhorn Documentation**: <https://longhorn.io/docs/>

---

**Ready to get started?** → **[Quick Start Guide](docs/getting-started/quick-start.md)**

**Need help with operations?** → **[Bootstrap vs GitOps Guide](docs/architecture/bootstrap-vs-gitops.md)**

**Looking for comprehensive guides?** → **[Full Documentation](docs/README.md)**
