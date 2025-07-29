# Operations

This section contains operational procedures and guides for day-to-day cluster management.

## Quick Navigation

- [Daily Operations](daily-operations.md) - Routine operational procedures
- [Maintenance](maintenance.md) - Maintenance and upgrade procedures
- [Monitoring](monitoring.md) - Monitoring and alerting setup
- [Backup & Recovery](backup-recovery.md) - Backup and disaster recovery
- [Troubleshooting](troubleshooting.md) - Common issues and solutions

## Operational Philosophy

The cluster follows a **Bootstrap vs GitOps** operational model:

- **Bootstrap Phase**: Direct deployment for system-level components
- **GitOps Phase**: Git-managed deployment for applications and infrastructure

## Quick Decision Rules

### Use Bootstrap Phase When

- ✅ Node configuration changes → `task talos:*`
- ✅ Cluster won't start → `task bootstrap:*`
- ✅ Network/CNI issues → `task apps:deploy-cilium`
- ✅ System-level problems → `talosctl` commands

### Use GitOps Phase When

- ✅ Application deployments → Git commit to `apps/`
- ✅ Infrastructure services → Git commit to `infrastructure/`
- ✅ Configuration updates → Git commit + Flux reconcile
- ✅ Scaling operations → Update manifests + Git commit

## Daily Health Check

```bash
# Check overall cluster status
task cluster:status

# Check GitOps health
flux get kustomizations

# Check for any issues
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed
```

For detailed operational procedures, see the individual guides in this section.
