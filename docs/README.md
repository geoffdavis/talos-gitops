# Talos GitOps Home-Ops Cluster Documentation

Welcome to the comprehensive documentation for the Talos GitOps home-ops cluster. This documentation is organized to help you quickly find the information you need, whether you're getting started, operating the cluster daily, or diving deep into specific components.

## Quick Start

New to the cluster? Start here:

- **[Getting Started](getting-started/)** - Setup guides and initial deployment
- **[Architecture Overview](architecture/overview.md)** - Understand the system design
- **[Bootstrap vs GitOps](architecture/bootstrap-vs-gitops.md)** - Core operational concepts

## Documentation Structure

### 🚀 [Getting Started](getting-started/)

Perfect for new users and initial setup:

- [Quick Start](getting-started/quick-start.md) - Fast deployment guide
- [Prerequisites](getting-started/prerequisites.md) - Requirements and setup
- [Bootstrap Guide](getting-started/bootstrap-guide.md) - Complete cluster bootstrap
- [First Deployment](getting-started/first-deployment.md) - Deploy your first application

### 🏗️ [Architecture](architecture/)

Understand the system design and principles:

- [Overview](architecture/overview.md) - High-level system architecture
- [Bootstrap vs GitOps](architecture/bootstrap-vs-gitops.md) - Two-phase architecture
- [Networking](architecture/networking.md) - Network architecture and BGP
- [Storage](architecture/storage.md) - USB SSD and Longhorn storage
- [Security](architecture/security.md) - Security architecture and practices

### ⚙️ [Operations](operations/)

Day-to-day cluster management:

- [Daily Operations](operations/daily-operations.md) - Routine procedures
- [Maintenance](operations/maintenance.md) - Maintenance and upgrades
- [Monitoring](operations/monitoring.md) - Monitoring and alerting
- [Backup & Recovery](operations/backup-recovery.md) - Backup and disaster recovery
- [Troubleshooting](operations/troubleshooting.md) - Common issues and solutions

### 🔧 [Components](components/)

Detailed component documentation:

#### Authentication

- [Authentik Setup](components/authentication/authentik-setup.md) - Identity provider
- [External Outpost](components/authentication/external-outpost.md) - External outpost config

#### Networking

- [BGP LoadBalancer](components/networking/bgp-loadbalancer.md) - BGP load balancer
- [Cilium Configuration](components/networking/cilium-configuration.md) - CNI setup
- [DNS Management](components/networking/dns-management.md) - DNS automation

#### Storage

- [Longhorn Setup](components/storage/longhorn-setup.md) - Distributed storage
- [USB SSD Operations](components/storage/usb-ssd-operations.md) - USB SSD management

#### Applications

- [Home Assistant](components/applications/home-assistant.md) - Home automation platform
- [Monitoring Stack](components/applications/monitoring-stack.md) - Prometheus/Grafana
- [Kubernetes Dashboard](components/applications/kubernetes-dashboard.md) - Dashboard

#### Infrastructure

- [Certificate Manager](components/infrastructure/cert-manager.md) - TLS certificates
- [External Secrets](components/infrastructure/external-secrets.md) - Secret management
- [Flux GitOps](components/infrastructure/flux-gitops.md) - GitOps configuration

### 📚 [Reference](reference/)

Quick lookup and reference materials:

- [Configuration Files](reference/configuration-files.md) - Key config file reference
- [Task Commands](reference/task-commands.md) - Taskfile command reference
- [Network Topology](reference/network-topology.md) - Network configuration details
- [Resource Requirements](reference/resource-requirements.md) - Hardware specs

### 👨‍💻 [Development](development/)

For developers and contributors:

- [Contributing](development/contributing.md) - Development guidelines
- [Testing](development/testing.md) - Testing procedures
- [Code Quality](development/code-quality.md) - Pre-commit and quality standards

### 🔄 Migration Guides

Comprehensive guides for various migration scenarios:

- [Bitnami Migration Guide](BITNAMI_MIGRATION_GUIDE.md) - Complete migration from Bitnami charts to upstream repositories
- [Bitnami Migration Testing](BITNAMI_MIGRATION_TESTING.md) - Testing procedures for Bitnami migration validation
- [Component Migration Guide](COMPONENT_MIGRATION_GUIDE.md) - Moving components between Bootstrap and GitOps phases
- [BGP LoadBalancer Migration](BGP_ONLY_LOADBALANCER_MIGRATION.md) - Migration to BGP-only architecture

## Cluster Overview

### Key Features

- **Cluster Name**: home-ops
- **Platform**: 3x Intel Mac mini devices (all-control-plane setup)
- **OS**: Talos OS v1.10.5
- **Kubernetes**: v1.31.1
- **CNI**: Cilium v1.17.6 with BGP peering
- **GitOps**: Flux v2.4.0
- **Storage**: Longhorn distributed storage on USB SSDs
- **Secrets**: 1Password Connect integration

### Network Configuration

- **Internal Domain**: k8s.home.geoffdavis.com
- **External Domain**: geoffdavis.com (via Cloudflare tunnel)
- **Cluster VIP**: 172.29.51.10
- **Node IPs**: 172.29.51.11-13
- **Pod CIDR**: 10.244.0.0/16 (IPv4), fd47:25e1:2f96:51:2000::/64 (IPv6)
- **Service CIDR**: 10.96.0.0/12 (IPv4), fd47:25e1:2f96:51:1000::/108 (IPv6)
- **LoadBalancer Pools**: 172.29.52.50-220 (BGP-advertised)

### Key Services

- **Home Assistant**: <https://homeassistant.k8s.home.geoffdavis.com>
- **Longhorn**: <https://longhorn.k8s.home.geoffdavis.com>
- **Grafana**: <https://grafana.k8s.home.geoffdavis.com>
- **Prometheus**: <https://prometheus.k8s.home.geoffdavis.com>
- **Dashboard**: <https://dashboard.k8s.home.geoffdavis.com>

## Quick Reference

### Essential Commands

```bash
# Cluster status
task cluster:status

# GitOps health
flux get kustomizations

# Node health
kubectl get nodes

# Pod status
kubectl get pods --all-namespaces
```

### Emergency Procedures

```bash
# Safe cluster reset
task cluster:safe-reset

# Emergency recovery
task cluster:emergency-recovery

# Redeploy core services
task apps:deploy-core
```

### 5-Second Decision Rules

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

## Getting Help

### Documentation Navigation

- **New Users**: Start with [Getting Started](getting-started/)
- **Daily Operations**: See [Operations](operations/) section
- **Component Issues**: Check [Components](components/) documentation
- **Quick Lookup**: Use [Reference](reference/) section
- **Development**: See [Development](development/) section

### Common Tasks

- **Deploy Application**: [First Deployment](getting-started/first-deployment.md)
- **Troubleshoot Issues**: [Troubleshooting](operations/troubleshooting.md)
- **Update Components**: [Maintenance](operations/maintenance.md)
- **Monitor Cluster**: [Monitoring](operations/monitoring.md)
- **Backup/Recovery**: [Backup & Recovery](operations/backup-recovery.md)

### Support Resources

- **Talos Documentation**: <https://www.talos.dev/>
- **Flux Documentation**: <https://fluxcd.io/flux/>
- **Cilium Documentation**: <https://docs.cilium.io/>
- **Longhorn Documentation**: <https://longhorn.io/docs/>

---

**Last Updated**: 2025-07-29  
**Cluster Version**: Talos OS v1.10.5, Kubernetes v1.31.1  
**Documentation Version**: 2.0 (Reorganized Structure)

For the most up-to-date information, always refer to the specific component documentation and the cluster's current state.
