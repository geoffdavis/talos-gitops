# Quick Start Guide

This guide gets you up and running with the Talos GitOps home-ops cluster in the shortest time possible. For detailed explanations, see the [Architecture Overview](../architecture/overview.md).

## Prerequisites

### Hardware Requirements

- **3x Intel Mac mini devices** (or compatible x86_64 hardware)
- **3x USB SSDs** (Samsung Portable SSD T5 recommended, 1TB each)
- **Network**: Unifi UDM Pro or BGP-capable router
- **Internet**: Stable connection for container images and dependencies

### Software Requirements

- **macOS or Linux** development machine
- **1Password account** with Connect server capability
- **GitHub account** for GitOps repository access

## Quick Setup (30 minutes)

### 1. Install Development Tools

```bash
# Install mise for tool management
curl https://mise.jdx.dev/install.sh | sh

# Clone the repository
git clone <repository-url>
cd talos-gitops

# Install all required tools
mise install
```

This installs: `task`, `talosctl`, `kubectl`, `flux`, `helm`, `cilium`, `yq`, `jq`, `op`, and more.

### 2. Configure Environment

```bash
# Copy environment template
cp .env.example .env

# Edit .env and set your 1Password account
# OP_ACCOUNT=your-1password-account
```

### 3. Prepare Hardware

1. **Connect USB SSDs** to each Mac mini
2. **Boot from USB installer** (Talos OS installer)
3. **Network Setup**: Ensure all nodes can reach each other and the internet

### 4. Bootstrap the Cluster

```bash
# Run the complete phased bootstrap
task bootstrap:phased
```

This automated process takes 15-20 minutes and handles:

- Talos OS configuration and node setup
- Kubernetes cluster initialization
- Cilium CNI deployment with BGP LoadBalancer
- 1Password Connect and secret management setup
- Flux GitOps system deployment
- Infrastructure services via GitOps

### 5. Verify Cluster Status

```bash
# Check overall cluster health
task cluster:status

# Verify all nodes are ready
kubectl get nodes

# Check GitOps reconciliation
flux get kustomizations

# Verify BGP peering (if using BGP LoadBalancer)
task bgp:verify-peering
```

## Post-Bootstrap Configuration

### Configure BGP on Router (Optional)

If using BGP LoadBalancer with UDM Pro:

```bash
# Deploy BGP configuration to UDM Pro
task bgp:configure-unifi
```

### Access Cluster Services

After bootstrap completion, these services are available:

- **Longhorn Storage UI**: <https://longhorn.k8s.home.geoffdavis.com>
- **Grafana Monitoring**: <https://grafana.k8s.home.geoffdavis.com>
- **Kubernetes Dashboard**: <https://dashboard.k8s.home.geoffdavis.com>
- **Home Assistant**: <https://homeassistant.k8s.home.geoffdavis.com> (if deployed)

**Authentication**: All services use Authentik SSO - first user to access becomes admin.

## Key Commands

### Daily Operations

```bash
# Check cluster health
task cluster:status

# Monitor GitOps deployments
flux get kustomizations --watch

# View all services with external IPs
kubectl get svc -A --field-selector spec.type=LoadBalancer

# Check node resource usage
kubectl top nodes
```

### Application Management

```bash
# Deploy new application via GitOps
git add apps/my-app/
git commit -m "Deploy my-app"
git push  # Triggers automatic deployment

# Monitor deployment
kubectl rollout status deployment/my-app -n my-namespace
```

### Troubleshooting

```bash
# Check for failed pods
kubectl get pods -A | grep -v Running | grep -v Completed

# View recent cluster events
kubectl get events --sort-by='.lastTimestamp' | tail -20

# Emergency cluster reset (preserves OS)
task cluster:safe-reset CONFIRM=SAFE-RESET
```

## Architecture at a Glance

### Two-Phase Design

- **Bootstrap Phase**: System foundation (Talos, Kubernetes, Cilium, Secrets, Flux)
- **GitOps Phase**: Applications and infrastructure services (managed via Git commits)

### Network Layout

- **Cluster VIP**: 172.29.51.10
- **Node IPs**: 172.29.51.11-13 (management network)
- **Service IPs**: 172.29.52.100-220 (BGP-advertised LoadBalancer pool)
- **Internal Domain**: k8s.home.geoffdavis.com

### Storage Strategy

- **Distributed**: Longhorn across 3x USB SSDs
- **Capacity**: ~1.35TB effective (2-replica default)
- **Performance**: Optimized for SSD characteristics

## Next Steps

### For New Operators

1. **Read**: [Architecture Overview](../architecture/overview.md) for system understanding
2. **Learn**: [Daily Operations Guide](../operations/daily-operations.md) for routine maintenance
3. **Deploy**: Start with simple applications to understand GitOps workflow

### For Application Deployment

1. **Study**: Existing applications in [`apps/`](../../apps/) directory
2. **Follow**: GitOps patterns for new application deployment
3. **Monitor**: Use Grafana dashboards for application observability

### For System Administration

1. **Master**: [Bootstrap vs GitOps Decision Framework](../architecture/bootstrap-vs-gitops.md)
2. **Understand**: [BGP LoadBalancer Configuration](../components/networking/bgp-loadbalancer.md)
3. **Implement**: [Home Assistant Stack](../components/applications/home-assistant.md) for complete application example

## Common Issues & Solutions

### Bootstrap Failures

```bash
# Resume from last successful phase
task bootstrap:resume

# Check specific component status
task cluster:status
kubectl get pods -n kube-system
```

### Network Connectivity Issues

```bash
# Verify BGP peering
task bgp:verify-peering

# Check DNS resolution
dig @172.29.51.1 k8s.home.geoffdavis.com

# Test service accessibility
curl -I https://longhorn.k8s.home.geoffdavis.com
```

### GitOps Reconciliation Problems

```bash
# Force reconciliation
flux reconcile source git flux-system

# Check for resource conflicts
flux get all --status-selector ready=false

# View reconciliation logs
flux logs --follow
```

## Safety Features

- **Safe Reset**: `task cluster:safe-reset` preserves OS, only wipes cluster data
- **Phased Bootstrap**: Resumable process - can continue from failure points
- **GitOps Rollback**: Use `git revert` to rollback any application/infrastructure changes
- **Backup Strategy**: Longhorn handles automatic volume snapshots

## Getting Help

### Documentation Resources

- **Architecture**: [Overview](../architecture/overview.md) | [Bootstrap vs GitOps](../architecture/bootstrap-vs-gitops.md)
- **Components**: [BGP LoadBalancer](../components/networking/bgp-loadbalancer.md) | [Home Assistant](../components/applications/home-assistant.md)
- **Operations**: [Daily Operations](../operations/daily-operations.md) | [Troubleshooting](../operations/troubleshooting.md)

### Command Reference

```bash
# Show all available tasks
task --list

# Get help for specific task
task <task-name> --help

# Access tool-specific help
kubectl --help
flux --help
talosctl --help
```

---

**Success Indicator**: When `task cluster:status` shows all components healthy and `flux get kustomizations` shows all reconciliations successful, your cluster is fully operational and ready for application deployment.
