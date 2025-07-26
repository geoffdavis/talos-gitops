# Backup Strategy Implementation Guide

## Quick Start

This guide provides step-by-step instructions to implement the comprehensive backup strategy for your Talos GitOps cluster.

## Prerequisites

- Longhorn storage system deployed and configured
- Volume snapshot controller installed
- S3 backup target configured with credentials
- Prometheus/Grafana monitoring stack deployed

## Implementation Steps

### Step 1: Deploy Backup Infrastructure

The backup configurations are already included in your Longhorn kustomization. Deploy them with:

```bash
# Apply the updated Longhorn configuration
kubectl apply -k infrastructure/longhorn/

# Verify RecurringJobs are created
kubectl get recurringjobs -n longhorn-system

# Check VolumeSnapshotClasses
kubectl get volumesnapshotclass
```

### Step 2: Verify Backup Target

```bash
# Check S3 backup target status
kubectl get backuptarget default -n longhorn-system -o yaml

# Verify credentials are available
kubectl get secret longhorn-s3-backup-credentials -n longhorn-system
```

### Step 3: Label Existing Volumes for Backup

Update your existing Prometheus and Grafana PVCs to use backup groups:

```bash
# Label Prometheus PVC
kubectl label pvc prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0 \
  -n monitoring backup-tier=critical backup-group=monitoring app=prometheus

# Label Grafana PVC
kubectl label pvc kube-prometheus-stack-grafana \
  -n monitoring backup-tier=critical backup-group=monitoring app=grafana
```

### Step 4: Test Manual Snapshot Creation

```bash
# Create a manual snapshot for testing
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: test-prometheus-snapshot
  namespace: monitoring
  labels:
    app: prometheus
    backup-tier: critical
    backup-type: manual
spec:
  source:
    persistentVolumeClaimName: prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0
  volumeSnapshotClassName: longhorn-snapshot-vsc
EOF

# Check snapshot status
kubectl get volumesnapshot test-prometheus-snapshot -n monitoring -w
```

### Step 5: Verify Monitoring Integration

```bash
# Check if backup verification job is scheduled
kubectl get cronjob backup-verification -n longhorn-system

# Check if Prometheus rules are loaded
kubectl get prometheusrule longhorn-backup-alerts -n longhorn-system

# Verify backup metrics are being collected (after first backup runs)
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-stack-prometheus 9090:9090
# Then visit http://localhost:9090 and search for "longhorn_backup" metrics
```

### Step 6: Test Restore Procedures

```bash
# Run the restore test manually
kubectl create job --from=cronjob/backup-restore-test manual-restore-test -n longhorn-system

# Check test results
kubectl logs job/manual-restore-test -n longhorn-system
```

## Database Deployment Example

When you're ready to deploy databases, use the provided examples:

### PostgreSQL Deployment

```bash
# Create database namespace
kubectl create namespace database

# Deploy PostgreSQL with backup integration
kubectl apply -f infrastructure/longhorn/database-backup-examples.yaml

# Create required secrets
kubectl create secret generic postgresql-secret \
  --from-literal=password=your-secure-password \
  -n database

# Verify deployment
kubectl get statefulset postgresql -n database
kubectl get pvc -n database -l app=postgresql
```

## Backup Schedule Overview

| Time     | Job                   | Description                            |
| -------- | --------------------- | -------------------------------------- |
| 1:00 AM  | Database snapshots    | Daily snapshots of all databases       |
| 2:00 AM  | Monitoring snapshots  | Daily snapshots of Prometheus/Grafana  |
| 3:00 AM  | Monitoring S3 backup  | Weekly S3 backup of monitoring data    |
| 4:00 AM  | Database S3 backup    | Weekly S3 backup of database data      |
| 5:00 AM  | Application snapshots | Weekly snapshots of other applications |
| 7:00 AM  | Cleanup               | Remove old snapshots                   |
| 8:00 AM  | Verification          | Verify backup health                   |
| 10:00 AM | Restore test          | Weekly restore testing (Sundays)       |

## Monitoring Backup Health

### Grafana Dashboard Queries

Add these queries to your Grafana dashboards:

```promql
# Backup target health
longhorn_backup_target_healthy

# Recent backup success count
longhorn_recent_backup_success_count

# Snapshot count by tier
longhorn_snapshots_ready_count

# Storage availability
longhorn_storage_available_bytes
```

### Key Alerts to Monitor

1. **Backup Target Down**: S3 connectivity issues
2. **No Recent Backups**: Backup jobs failing
3. **Snapshot Creation Failed**: Volume snapshot issues
4. **Storage Low**: Running out of space

## Troubleshooting Common Issues

### Issue: RecurringJob Not Running

```bash
# Check RecurringJob status
kubectl describe recurringjob monitoring-daily-snapshot -n longhorn-system

# Check Longhorn manager logs
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=100
```

### Issue: S3 Backup Failing

```bash
# Check backup target status
kubectl get backuptarget default -n longhorn-system -o yaml

# Verify S3 credentials
kubectl get secret longhorn-s3-backup-credentials -n longhorn-system -o yaml

# Test S3 connectivity
kubectl run -it --rm debug --image=amazon/aws-cli --restart=Never -- \
  aws s3 ls s3://longhorn-backups-home-ops --region us-west-2
```

### Issue: Snapshot Creation Failing

```bash
# Check VolumeSnapshotClass
kubectl get volumesnapshotclass longhorn-snapshot-vsc -o yaml

# Check snapshot controller logs
kubectl logs -n volume-snapshot-system deployment/snapshot-controller

# Verify CSI driver
kubectl get csidriver driver.longhorn.io
```

## Maintenance Tasks

### Weekly

- Review backup job success rates in Grafana
- Check S3 storage usage and costs
- Verify restore test results

### Monthly

- Update backup retention policies if needed
- Review storage capacity planning
- Test disaster recovery procedures

### Quarterly

- Update Longhorn version
- Review and update backup strategy
- Conduct full disaster recovery drill

## Security Best Practices

1. **Credentials Management**
   - S3 credentials stored in 1Password
   - Regular credential rotation
   - Least privilege access policies

2. **Access Control**
   - RBAC for backup operations
   - Separate service accounts
   - Namespace isolation

3. **Encryption**
   - S3 server-side encryption enabled
   - Longhorn volume encryption
   - TLS for all communications

## Cost Optimization Tips

1. **S3 Lifecycle Policies**
   - Move to IA after 30 days
   - Archive to Glacier after 90 days
   - Delete after retention period

2. **Backup Frequency Tuning**
   - Adjust based on actual RPO needs
   - Consider differential backups for large datasets
   - Monitor backup sizes and optimize

3. **Storage Efficiency**
   - Enable compression where possible
   - Regular cleanup of old snapshots
   - Monitor storage usage trends

## Next Steps

1. **Deploy the backup infrastructure** using the steps above
2. **Monitor backup operations** for the first week
3. **Adjust schedules** based on your specific needs
4. **Plan database deployments** using the provided examples
5. **Set up alerting** for backup failures
6. **Document any customizations** for your environment

## Support

For issues or questions:

1. Check the [Comprehensive Backup Strategy](./COMPREHENSIVE_BACKUP_STRATEGY.md) documentation
2. Review Longhorn documentation
3. Check GitHub issues for similar problems
4. Create new issue with detailed logs and configuration

---

This implementation guide should get your backup strategy up and running quickly while providing the foundation for future database deployments.
