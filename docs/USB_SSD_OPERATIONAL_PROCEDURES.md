# USB SSD Operational Procedures

## Overview

This document provides comprehensive operational procedures for managing USB SSD storage in the Talos Kubernetes cluster with Longhorn distributed storage. These procedures cover daily operations, maintenance tasks, troubleshooting, and disaster recovery scenarios.

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Monitoring and Health Checks](#monitoring-and-health-checks)
3. [Maintenance Procedures](#maintenance-procedures)
4. [Troubleshooting](#troubleshooting)
5. [Performance Management](#performance-management)
6. [Backup and Disaster Recovery](#backup-and-disaster-recovery)
7. [Capacity Management](#capacity-management)
8. [Security Considerations](#security-considerations)
9. [Integration with GitOps](#integration-with-gitops)
10. [Emergency Procedures](#emergency-procedures)

## Daily Operations

### Health Check Routine

**Frequency**: Daily
**Approach**: GitOps Phase (monitoring dashboards) + Bootstrap Phase (hardware validation)

```bash
# 1. Quick health overview
task cluster:status

# 2. Check USB SSD hardware status
kubectl get nodes -o wide
kubectl describe nodes | grep -A 10 "Allocated resources"

# 3. Longhorn storage health
kubectl get pods -n longhorn-system
kubectl get volumes -n longhorn-system | head -20

# 4. Storage class availability
kubectl get storageclass

# 5. Check for storage alerts
kubectl get events -n longhorn-system --sort-by='.lastTimestamp' | tail -10
```

### Monitoring Dashboard Access

**Internal Access** (Home Network):
- Longhorn UI: https://longhorn.k8s.home.geoffdavis.com
- Grafana: https://grafana.k8s.home.geoffdavis.com
- Prometheus: https://prometheus.k8s.home.geoffdavis.com

**External Access** (Internet):
- Longhorn UI: https://longhorn.geoffdavis.com
- Grafana: https://grafana.geoffdavis.com
- Prometheus: https://prometheus.geoffdavis.com

### Daily Validation Script

```bash
# Run comprehensive daily validation
./scripts/validate-complete-usb-ssd-setup.sh --quick

# Check specific components
./scripts/validate-usb-ssd-storage.sh
./scripts/validate-longhorn-usb-ssd.sh
```

## Monitoring and Health Checks

### Key Metrics to Monitor

#### Storage Capacity
- **Total USB SSD capacity**: 3TB (3x 1TB USB SSDs)
- **Usable capacity**: ~2.7TB (accounting for Longhorn overhead)
- **Warning threshold**: 80% capacity
- **Critical threshold**: 90% capacity

#### Performance Metrics
- **IOPS**: Monitor read/write operations per second
- **Latency**: Track storage response times
- **Throughput**: Monitor data transfer rates
- **Queue depth**: Check storage queue utilization

#### Health Indicators
- **Node availability**: All 3 nodes should be Ready
- **USB device detection**: All USB SSDs should be mounted
- **Longhorn replica health**: Replicas should be healthy across nodes
- **Volume attachment**: Volumes should attach within 30 seconds

### Monitoring Commands

```bash
# Check USB SSD hardware detection
for node in 172.29.51.11 172.29.51.12 172.29.51.13; do
    echo "=== Node $node ==="
    talosctl -n $node get disks
    talosctl -n $node ls /dev/disk/by-id/ | grep usb
done

# Check Longhorn disk status
kubectl get nodes.longhorn.io -n longhorn-system

# Monitor storage usage
kubectl get pv | grep longhorn-ssd
kubectl get pvc -A | grep longhorn-ssd

# Check replica distribution
kubectl get replicas.longhorn.io -n longhorn-system -o wide
```

### Automated Monitoring Setup

**Grafana Dashboards**:
- Longhorn storage metrics
- Node storage utilization
- USB device health
- Performance trends

**Prometheus Alerts**:
- USB SSD disconnection
- High storage utilization
- Replica degradation
- Performance degradation

## Maintenance Procedures

### USB SSD Replacement

**Approach**: Bootstrap Phase (hardware changes require node-level operations)
**Downtime**: Minimal (rolling replacement with Longhorn replication)

#### Planned USB SSD Replacement

```bash
# 1. Identify the node with failing USB SSD
NODE_IP="172.29.51.11"  # Replace with actual node IP

# 2. Drain Longhorn replicas from the node
kubectl patch node.longhorn.io $NODE_NAME -p '{"spec":{"allowScheduling":false}}' --type=merge

# 3. Wait for replicas to migrate
kubectl get replicas.longhorn.io -n longhorn-system | grep $NODE_NAME

# 4. Safely shutdown the node
talosctl -n $NODE_IP shutdown

# 5. Replace USB SSD hardware
# Physical replacement of USB device

# 6. Boot the node
# Power on the node

# 7. Verify USB SSD detection
talosctl -n $NODE_IP get disks
talosctl -n $NODE_IP ls /dev/disk/by-id/ | grep usb

# 8. Re-enable Longhorn scheduling
kubectl patch node.longhorn.io $NODE_NAME -p '{"spec":{"allowScheduling":true}}' --type=merge

# 9. Validate storage functionality
./scripts/validate-complete-usb-ssd-setup.sh --node $NODE_IP
```

#### Emergency USB SSD Replacement

```bash
# 1. If node is unresponsive, force reboot
talosctl -n $NODE_IP reboot --mode=hard

# 2. Check cluster health during replacement
kubectl get nodes
kubectl get pods -n longhorn-system

# 3. Monitor replica rebuilding
kubectl get volumes.longhorn.io -n longhorn-system -o wide

# 4. Verify data integrity after replacement
./scripts/validate-complete-usb-ssd-setup.sh --full
```

### USB SSD Expansion (Adding Storage)

**Approach**: Bootstrap Phase (node configuration) + GitOps Phase (storage class updates)

#### Adding USB SSDs to Existing Nodes

```bash
# 1. Shutdown node for hardware addition
NODE_IP="172.29.51.11"
talosctl -n $NODE_IP shutdown

# 2. Add additional USB SSD
# Physical installation of additional USB device

# 3. Boot node and verify detection
talosctl -n $NODE_IP get disks

# 4. Update Longhorn to use new disk
# Longhorn will automatically detect and use new disks

# 5. Verify new storage capacity
kubectl get nodes.longhorn.io -n longhorn-system -o yaml | grep -A 5 storageAvailable
```

#### Adding New Nodes with USB SSDs

```bash
# 1. Prepare new node configuration
vim talconfig.yaml
# Add new node to configuration

# 2. Generate updated Talos configuration
task talos:generate-config

# 3. Apply configuration to new node
task talos:apply-config

# 4. Join node to cluster
talosctl -n NEW_NODE_IP bootstrap

# 5. Verify USB SSD detection on new node
./scripts/validate-usb-ssd-storage.sh --node NEW_NODE_IP

# 6. Update Longhorn configuration if needed
# GitOps phase - commit any storage class changes
git add infrastructure/longhorn/
git commit -m "Update storage configuration for new node"
git push
```

### Regular Maintenance Tasks

#### Weekly Maintenance

```bash
# 1. Check storage health
./scripts/validate-complete-usb-ssd-setup.sh --full

# 2. Review storage usage trends
kubectl top nodes
kubectl get pv | grep longhorn-ssd | awk '{sum+=$4} END {print "Total used: " sum}'

# 3. Check for storage alerts
kubectl get events -A | grep -i storage | grep -i warning

# 4. Verify backup integrity
# Check Longhorn backup status in UI
```

#### Monthly Maintenance

```bash
# 1. Performance baseline testing
./scripts/validate-complete-usb-ssd-setup.sh --performance

# 2. Capacity planning review
# Analyze growth trends and plan for expansion

# 3. Update storage documentation
# Document any configuration changes or issues

# 4. Review and update monitoring thresholds
# Adjust alerts based on observed patterns
```

## Troubleshooting

### Common Issues and Solutions

#### USB SSD Not Detected

**Symptoms**:
- Node shows reduced storage capacity
- Longhorn reports missing disk
- Mount failures in logs

**Diagnosis**:
```bash
# Check USB device detection
talosctl -n $NODE_IP get disks
talosctl -n $NODE_IP dmesg | grep -i usb

# Check mount status
talosctl -n $NODE_IP ls /var/lib/longhorn/
```

**Solutions**:
1. **Soft reboot** (try first):
   ```bash
   talosctl -n $NODE_IP reboot
   ```

2. **Hard reboot** (if soft reboot fails):
   ```bash
   talosctl -n $NODE_IP reboot --mode=hard
   ```

3. **USB device reseat**:
   - Shutdown node
   - Physically disconnect and reconnect USB SSD
   - Boot node

4. **Check USB power**:
   - Verify USB SSD has adequate power
   - Consider powered USB hub if needed

#### Longhorn Volume Stuck in Attaching State

**Symptoms**:
- Pods stuck in ContainerCreating
- Volume shows "Attaching" status
- Mount timeouts in events

**Diagnosis**:
```bash
# Check volume status
kubectl get volumes.longhorn.io -n longhorn-system
kubectl describe volume $VOLUME_NAME -n longhorn-system

# Check engine and replica status
kubectl get engines.longhorn.io -n longhorn-system
kubectl get replicas.longhorn.io -n longhorn-system
```

**Solutions**:
1. **Restart Longhorn manager**:
   ```bash
   kubectl rollout restart daemonset/longhorn-manager -n longhorn-system
   ```

2. **Detach and reattach volume**:
   ```bash
   # Via Longhorn UI or kubectl patch
   kubectl patch volume $VOLUME_NAME -n longhorn-system --type=merge -p '{"spec":{"nodeID":""}}'
   ```

3. **Check node storage availability**:
   ```bash
   kubectl get nodes.longhorn.io -n longhorn-system -o yaml
   ```

#### Performance Degradation

**Symptoms**:
- Slow application response times
- High storage latency
- I/O wait times

**Diagnosis**:
```bash
# Check storage performance
./scripts/validate-complete-usb-ssd-setup.sh --performance

# Monitor I/O statistics
kubectl top nodes
kubectl get --raw /api/v1/nodes/$NODE_NAME/proxy/stats/summary
```

**Solutions**:
1. **Check USB SSD health**:
   ```bash
   # Check for USB errors
   talosctl -n $NODE_IP dmesg | grep -i "usb\|error"
   ```

2. **Rebalance replicas**:
   - Use Longhorn UI to rebalance replicas across nodes
   - Ensure even distribution of storage load

3. **Optimize Longhorn settings**:
   ```bash
   # Update via GitOps
   vim infrastructure/longhorn/helmrelease.yaml
   # Adjust concurrent replica rebuild limit
   # Modify backup concurrency settings
   ```

#### Storage Capacity Issues

**Symptoms**:
- PVC creation failures
- "Insufficient storage" errors
- High storage utilization alerts

**Diagnosis**:
```bash
# Check overall capacity
kubectl get nodes.longhorn.io -n longhorn-system -o yaml | grep -A 5 storage

# Check PV usage
kubectl get pv | grep longhorn-ssd
df -h /var/lib/longhorn  # On each node
```

**Solutions**:
1. **Clean up unused volumes**:
   ```bash
   # Identify orphaned volumes
   kubectl get pv | grep Released
   
   # Clean up via Longhorn UI or kubectl
   kubectl delete pv $ORPHANED_VOLUME
   ```

2. **Expand existing volumes**:
   ```bash
   # Resize PVC (if storage class allows expansion)
   kubectl patch pvc $PVC_NAME -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
   ```

3. **Add storage capacity**:
   - Follow USB SSD expansion procedures above

## Performance Management

### Performance Monitoring

#### Key Performance Indicators

- **Latency**: < 10ms for 95th percentile
- **IOPS**: > 1000 IOPS per USB SSD
- **Throughput**: > 100 MB/s per USB SSD
- **Queue Depth**: < 32 average

#### Performance Testing

```bash
# Run comprehensive performance test
./scripts/validate-complete-usb-ssd-setup.sh --performance

# Manual performance testing
kubectl run fio-test --image=ljishen/fio --rm -it -- \
  fio --name=test --ioengine=libaio --iodepth=32 --rw=randwrite \
  --bs=4k --direct=1 --size=1G --numjobs=1 --runtime=60 \
  --group_reporting --filename=/tmp/test
```

### Performance Optimization

#### Longhorn Configuration Tuning

**Via GitOps** (infrastructure/longhorn/helmrelease.yaml):
```yaml
values:
  defaultSettings:
    concurrentReplicaRebuildPerNodeLimit: 2
    concurrentVolumeBackupRestorePerNodeLimit: 2
    replicaReplenishmentWaitInterval: 600
    storageMinimalAvailablePercentage: 10
```

#### Storage Class Optimization

**Via GitOps** (infrastructure/longhorn/storage-class-ssd.yaml):
```yaml
parameters:
  numberOfReplicas: "2"  # Optimize for performance vs redundancy
  staleReplicaTimeout: "2880"
  diskSelector: "ssd"
  nodeSelector: "storage-node"
  fsType: "ext4"  # Optimize filesystem choice
```

## Backup and Disaster Recovery

### Backup Strategy

#### Longhorn Backup Configuration

**Approach**: GitOps Phase (backup configuration)

```bash
# Configure backup target via GitOps
vim infrastructure/longhorn/helmrelease.yaml
# Set backup target (S3, NFS, etc.)

# Commit backup configuration
git add infrastructure/longhorn/
git commit -m "Configure Longhorn backup target"
git push
```

#### Backup Procedures

```bash
# Create volume backup
kubectl create -f - <<EOF
apiVersion: longhorn.io/v1beta1
kind: Backup
metadata:
  name: volume-backup-$(date +%Y%m%d-%H%M%S)
  namespace: longhorn-system
spec:
  snapshotName: snapshot-$(date +%Y%m%d-%H%M%S)
  volumeName: $VOLUME_NAME
EOF

# Schedule regular backups via CronJob
kubectl apply -f infrastructure/longhorn/backup-cronjob.yaml
```

### Disaster Recovery Scenarios

#### Single Node Failure

**Impact**: Minimal (Longhorn replication maintains availability)
**Recovery Time**: Automatic (< 5 minutes)

```bash
# 1. Verify cluster health
kubectl get nodes
kubectl get pods -n longhorn-system

# 2. Check replica status
kubectl get replicas.longhorn.io -n longhorn-system | grep $FAILED_NODE

# 3. Monitor automatic recovery
kubectl get volumes.longhorn.io -n longhorn-system -w
```

#### Multiple Node Failure

**Impact**: Potential data loss if majority of replicas lost
**Recovery Time**: 30 minutes to 2 hours

```bash
# 1. Assess damage
kubectl get nodes
kubectl get volumes.longhorn.io -n longhorn-system

# 2. Restore from backup if needed
kubectl apply -f restore-from-backup.yaml

# 3. Rebuild cluster if necessary
task cluster:emergency-recovery
```

#### Complete Cluster Loss

**Impact**: Full data loss without backups
**Recovery Time**: 2-4 hours

```bash
# 1. Rebuild cluster
task bootstrap:cluster

# 2. Restore Longhorn from backup
kubectl apply -f longhorn-restore-complete.yaml

# 3. Validate data integrity
./scripts/validate-complete-usb-ssd-setup.sh --full
```

### Backup Validation

```bash
# Test backup integrity
kubectl create -f test-restore.yaml

# Verify restored data
kubectl exec -it test-pod -- ls -la /data/

# Clean up test
kubectl delete -f test-restore.yaml
```

## Capacity Management

### Capacity Planning

#### Current Capacity

- **Total Raw Capacity**: 3TB (3x 1TB USB SSDs)
- **Usable Capacity**: ~2.7TB (with Longhorn overhead)
- **Replica Factor**: 2 (effective capacity ~1.35TB)
- **Reserved Space**: 10% (135GB for operations)

#### Growth Projections

```bash
# Analyze current usage trends
kubectl get pv | grep longhorn-ssd | awk '{sum+=$4} END {print "Total allocated: " sum}'

# Check growth rate
# Review Grafana dashboards for usage trends over time
```

#### Expansion Planning

**Vertical Scaling** (Larger USB SSDs):
- Replace 1TB USB SSDs with 2TB or 4TB models
- Requires node-by-node replacement
- Minimal downtime with proper planning

**Horizontal Scaling** (Additional Nodes):
- Add new nodes with USB SSDs
- Requires cluster configuration updates
- Increases both capacity and performance

### Capacity Alerts

**Warning Thresholds**:
- 80% capacity utilization
- Rapid growth rate (>10% per week)
- Low available space on any node

**Critical Thresholds**:
- 90% capacity utilization
- Unable to create new volumes
- Storage exhaustion predicted within 7 days

## Security Considerations

### Access Control

#### Longhorn UI Security

**Internal Access**:
- Protected by Kubernetes RBAC
- Ingress with TLS certificates
- Network-level access control

**External Access**:
- Cloudflare tunnel with authentication
- Additional authentication layer recommended
- Audit logging enabled

#### Storage Encryption

```bash
# Enable encryption at rest (via GitOps)
vim infrastructure/longhorn/storage-class-encrypted.yaml
# Configure encrypted storage class

# Apply encryption configuration
git add infrastructure/longhorn/
git commit -m "Enable storage encryption"
git push
```

### Security Monitoring

```bash
# Check for unauthorized access
kubectl get events -A | grep -i "unauthorized\|forbidden"

# Monitor storage access patterns
kubectl logs -n longhorn-system -l app=longhorn-manager | grep -i "access\|auth"

# Verify TLS certificates
kubectl get certificates -A
```

## Integration with GitOps

### GitOps-Managed Components

**Storage Classes**:
- Location: `infrastructure/longhorn/storage-class-*.yaml`
- Changes: Commit to Git, Flux applies automatically
- Validation: Monitor Flux reconciliation

**Longhorn Configuration**:
- Location: `infrastructure/longhorn/helmrelease.yaml`
- Changes: Update values, commit, push
- Rollback: Git revert + Flux reconciliation

**Monitoring Configuration**:
- Location: `infrastructure/monitoring/`
- Changes: Update dashboards, alerts via Git
- Deployment: Automatic via Flux

### Bootstrap-Managed Components

**USB SSD Hardware**:
- Detection: Node-level, requires bootstrap scripts
- Configuration: Talos configuration files
- Changes: `task talos:apply-config`

**Node Storage Labels**:
- Management: Talos node configuration
- Updates: `talconfig.yaml` + `task talos:generate-config`
- Application: `task talos:apply-config`

### Operational Workflow Integration

```bash
# Storage configuration change (GitOps)
vim infrastructure/longhorn/helmrelease.yaml
git add infrastructure/longhorn/
git commit -m "Update Longhorn configuration"
git push
flux reconcile kustomization infrastructure-longhorn

# Node hardware change (Bootstrap)
# Physical USB SSD replacement
talosctl -n $NODE_IP reboot --mode=hard
./scripts/validate-usb-ssd-storage.sh --node $NODE_IP

# Mixed change (both phases)
# 1. Update node configuration (Bootstrap)
vim talconfig.yaml
task talos:generate-config
task talos:apply-config

# 2. Update storage classes (GitOps)
vim infrastructure/longhorn/storage-class-ssd.yaml
git add infrastructure/longhorn/
git commit -m "Update storage class for new node configuration"
git push
```

## Emergency Procedures

### Emergency Response Checklist

#### Storage System Failure

1. **Immediate Assessment** (< 5 minutes):
   ```bash
   kubectl get nodes
   kubectl get pods -n longhorn-system
   kubectl get pv | grep longhorn-ssd
   ```

2. **Isolate Problem** (< 10 minutes):
   ```bash
   # Identify failed components
   kubectl describe nodes | grep -A 10 "Conditions"
   kubectl get events -A --sort-by='.lastTimestamp' | tail -20
   ```

3. **Implement Workaround** (< 30 minutes):
   ```bash
   # Scale down affected applications
   kubectl scale deployment $APP_NAME --replicas=0
   
   # Force volume detachment if needed
   kubectl patch volume $VOLUME_NAME -n longhorn-system --type=merge -p '{"spec":{"nodeID":""}}'
   ```

4. **Execute Recovery** (< 2 hours):
   ```bash
   # Follow specific recovery procedures based on failure type
   ./scripts/deploy-usb-ssd-storage.sh --emergency-recovery
   ```

#### Data Corruption Detection

1. **Stop Applications**:
   ```bash
   kubectl scale deployment $AFFECTED_APP --replicas=0
   ```

2. **Assess Corruption Scope**:
   ```bash
   # Check volume integrity
   kubectl exec -it longhorn-manager-pod -- longhorn volume check $VOLUME_NAME
   ```

3. **Restore from Backup**:
   ```bash
   # Create restore job
   kubectl apply -f emergency-restore.yaml
   ```

4. **Validate Recovery**:
   ```bash
   ./scripts/validate-complete-usb-ssd-setup.sh --full
   ```

### Emergency Contacts and Escalation

**Internal Escalation**:
1. Check cluster status and logs
2. Attempt automated recovery procedures
3. Review recent changes in Git history
4. Escalate to senior operations if needed

**External Escalation**:
1. Longhorn community support
2. Talos community support
3. Hardware vendor support (for USB SSD issues)

### Emergency Recovery Scripts

```bash
# Emergency cluster recovery
task cluster:emergency-recovery

# Emergency storage recovery
./scripts/deploy-usb-ssd-storage.sh --emergency-mode

# Emergency backup restore
kubectl apply -f emergency-restore-all-volumes.yaml
```

## Conclusion

This operational procedures document provides comprehensive guidance for managing USB SSD storage in the Talos Kubernetes cluster. Regular adherence to these procedures ensures optimal performance, reliability, and data protection.

### Key Operational Principles

1. **Proactive Monitoring**: Regular health checks prevent issues
2. **Proper Phase Separation**: Use Bootstrap for hardware, GitOps for configuration
3. **Backup Validation**: Regularly test backup and restore procedures
4. **Documentation**: Keep procedures updated with cluster changes
5. **Emergency Preparedness**: Practice emergency procedures regularly

### Regular Review Schedule

- **Daily**: Health checks and monitoring
- **Weekly**: Performance review and capacity planning
- **Monthly**: Procedure validation and documentation updates
- **Quarterly**: Emergency procedure testing and training

For additional support and detailed technical information, refer to:
- [USB SSD Deployment Script](../scripts/deploy-usb-ssd-storage.sh)
- [Comprehensive Validation Script](../scripts/validate-complete-usb-ssd-setup.sh)
- [Operational Workflows Guide](OPERATIONAL_WORKFLOWS.md)
- [Bootstrap vs GitOps Architecture](BOOTSTRAP_VS_GITOPS_PHASES.md)