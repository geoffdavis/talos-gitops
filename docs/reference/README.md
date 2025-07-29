# Reference

This section contains reference materials and quick lookup information.

## Quick Navigation

- [Configuration Files](configuration-files.md) - Key configuration file reference
- [Task Commands](task-commands.md) - Taskfile command reference
- [Network Topology](network-topology.md) - Network configuration details
- [Resource Requirements](resource-requirements.md) - Hardware and resource specifications

## Quick Reference

### Key URLs

- **Home Assistant**: <https://homeassistant.k8s.home.geoffdavis.com>
- **Longhorn**: <https://longhorn.k8s.home.geoffdavis.com>
- **Grafana**: <https://grafana.k8s.home.geoffdavis.com>
- **Prometheus**: <https://prometheus.k8s.home.geoffdavis.com>
- **Dashboard**: <https://dashboard.k8s.home.geoffdavis.com>

### Network Configuration

- **Cluster VIP**: 172.29.51.10
- **Node IPs**: 172.29.51.11-13
- **Pod CIDR**: 10.244.0.0/16 (IPv4), fd47:25e1:2f96:51:2000::/64 (IPv6)
- **Service CIDR**: 10.96.0.0/12 (IPv4), fd47:25e1:2f96:51:1000::/108 (IPv6)
- **LoadBalancer Pools**: 172.29.52.50-220 (BGP-advertised)

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

For detailed procedures, see the [Operations](../operations/) section.
