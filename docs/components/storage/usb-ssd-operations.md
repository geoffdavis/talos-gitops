# USB SSD Storage Operations

## Overview

This cluster uses external USB SSDs for distributed storage via Longhorn. The storage system provides high availability and performance for persistent workloads using Samsung Portable SSD T5 devices.

## Storage Architecture

### Hardware Configuration

- **3x 1TB USB SSDs**: One per node for distributed storage
- **Model**: Samsung Portable SSD T5 (optimized configuration)
- **Total Capacity**: 3TB raw storage
- **Effective Capacity**: ~1.35TB with 2-replica factor
- **Performance**: Optimized with custom udev rules and sysctls

### Storage Classes

- **`longhorn-ssd`**: High-performance storage for applications
- **`longhorn`**: Standard storage (if available)
- **Automatic Detection**: USB SSDs are automatically detected and configured
- **Node Affinity**: Automatically uses SSD-tagged nodes

### Capacity Management

#### Current Capacity

- **Total Raw**: 3TB (3x 1TB USB SSDs)
- **Usable**: ~2.7TB (with overhead)
- **Effective**: ~1.35TB (with 2-replica factor)
- **Reserved**: 10% for operations

#### Expansion Options

1. **Vertical Scaling**: Replace with larger USB SSDs (2TB, 4TB)
2. **Horizontal Scaling**: Add more nodes with USB SSDs
3. **Additional Storage**: Add more USB SSDs per node

## USB SSD Operations

### Deployment and Validation

#### Initial Deployment

```bash
# Deploy USB SSD storage configuration
./scripts/deploy-usb-ssd-storage.sh

# Comprehensive validation of USB SSD setup
./scripts/validate-complete-usb-ssd-setup.sh

# Quick health check
./scripts/validate-usb-ssd-storage.sh

# Longhorn-specific validation
./scripts/validate-longhorn-usb-ssd.sh
```

#### Daily Operations

```bash
# Check storage health
kubectl get nodes.longhorn.io -n longhorn-system
kubectl get volumes.longhorn.io -n longhorn-system

# Monitor storage usage
kubectl get pv | grep longhorn-ssd
kubectl top nodes

# Access Longhorn UI
# Internal: https://longhorn.k8s.home.geoffdavis.com
# External: https://longhorn.geoffdavis.com
```

### Maintenance Procedures

#### USB SSD Replacement (Planned)

```bash
# 1. Drain node replicas
kubectl patch node.longhorn.io $NODE_NAME -p '{"spec":{"allowScheduling":false}}' --type=merge

# 2. Shutdown node
talosctl -n $NODE_IP shutdown

# 3. Replace USB SSD hardware
# 4. Boot node and verify detection
talosctl -n $NODE_IP get disks

# 5. Re-enable scheduling
kubectl patch node.longhorn.io $NODE_NAME -p '{"spec":{"allowScheduling":true}}' --type=merge
```

#### Node Maintenance with USB SSDs

```bash
# 1. Check replica distribution
kubectl get replicas.longhorn.io -n longhorn-system -o wide

# 2. Ensure replicas are distributed
kubectl patch volume.longhorn.io $VOLUME_NAME -n longhorn-system -p '{"spec":{"numberOfReplicas":3}}'

# 3. Perform node maintenance
kubectl drain $NODE_NAME --ignore-daemonsets --delete-emptydir-data

# 4. Maintenance operations (reboot, hardware changes, etc.)
talosctl -n $NODE_IP reboot

# 5. Uncordon node after maintenance
kubectl uncordon $NODE_NAME
```

### Storage Classes and Usage

#### Using USB SSD Storage

```yaml
# Example PVC using USB SSD storage
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-ssd
  resources:
    requests:
      storage: 10Gi
```

#### Storage Class Features

- **High Performance**: Optimized for SSD performance
- **Replication**: 2-replica default for high availability
- **Expansion**: Supports volume expansion
- **Snapshots**: Supports volume snapshots and backups
- **Node Affinity**: Automatically uses SSD-tagged nodes

### Troubleshooting USB SSD Issues

#### USB Device Not Detected

```bash
# Check USB device detection
talosctl -n $NODE_IP get disks
talosctl -n $NODE_IP dmesg | grep -i usb

# Hard reboot if needed (ensures USB detection)
talosctl -n $NODE_IP reboot --mode=hard

# Verify disk model detection
talosctl -n $NODE_IP get disks | grep "Portable SSD T5"
```

#### Storage Performance Issues

```bash
# Run performance validation
./scripts/validate-complete-usb-ssd-setup.sh --performance

# Check Longhorn replica distribution
kubectl get replicas.longhorn.io -n longhorn-system -o wide

# Monitor I/O statistics
kubectl top nodes

# Check for disk errors
talosctl -n $NODE_IP dmesg | grep -i error
```

#### Volume Attachment Issues

```bash
# Check volume status
kubectl get volumes.longhorn.io -n longhorn-system
kubectl describe volume $VOLUME_NAME -n longhorn-system

# Check volume attachment
kubectl get volumeattachments

# Restart Longhorn manager if needed
kubectl rollout restart daemonset/longhorn-manager -n longhorn-system
```

#### Disk Space Issues

```bash
# Check disk usage on nodes
kubectl exec -n longhorn-system $LONGHORN_MANAGER_POD -- df -h

# Check Longhorn volume usage
kubectl get pv | grep longhorn-ssd

# Clean up unused volumes
kubectl delete pv $UNUSED_VOLUME_NAME
```

### Performance Optimization

#### USB SSD Optimization

The cluster includes several optimizations for Samsung Portable SSD T5 devices:

```bash
# Custom udev rules (applied via Talos configuration)
# Located in talos/patches/usb-ssd-optimization.yaml

# Sysctls for SSD performance
# Applied automatically via Talos machine configuration

# Verify optimizations are applied
talosctl -n $NODE_IP get sysctl | grep -E "(dirty|writeback)"
```

#### Longhorn Performance Tuning

```yaml
# Longhorn settings for USB SSD optimization
# Applied via infrastructure/longhorn/helmrelease.yaml

defaultSettings:
  defaultDataPath: /var/lib/longhorn/
  defaultDataLocality: best-effort
  replicaSoftAntiAffinity: true
  storageOverProvisioningPercentage: 200
  storageMinimalAvailablePercentage: 25
  upgradeChecker: false
  defaultReplicaCount: 2
  guaranteedEngineCPU: 0.25
  defaultLonghornStaticStorageClass: longhorn-ssd
```

### Backup and Recovery

#### Volume Snapshots

```bash
# Create manual snapshot
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: app-data-snapshot
  namespace: default
spec:
  source:
    persistentVolumeClaimName: app-data
  volumeSnapshotClassName: longhorn-snapshot-vsc
EOF

# List snapshots
kubectl get volumesnapshots

# Restore from snapshot
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data-restored
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-ssd
  resources:
    requests:
      storage: 10Gi
  dataSource:
    name: app-data-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF
```

#### Backup to S3

```bash
# Configure backup target (via GitOps)
vim infrastructure/longhorn/helmrelease.yaml

# Create volume backup
kubectl create backup $VOLUME_NAME -n longhorn-system

# Restore from backup
kubectl apply -f restore-from-backup.yaml
```

### Monitoring and Alerting

#### Key Metrics to Monitor

1. **Disk Usage**: Monitor available space on each USB SSD
2. **Replica Health**: Ensure replicas are healthy and distributed
3. **Volume Performance**: Monitor I/O latency and throughput
4. **Node Availability**: Ensure all nodes with USB SSDs are available

#### Health Check Script

```bash
#!/bin/bash
echo "=== USB SSD Storage Health Check ==="
echo "Date: $(date)"
echo

# Check Longhorn system health
echo "Longhorn System Status:"
kubectl get pods -n longhorn-system | grep -E "(manager|driver|ui)"

# Check node storage
echo "Node Storage Status:"
kubectl get nodes.longhorn.io -n longhorn-system

# Check volume health
echo "Volume Health:"
kubectl get volumes.longhorn.io -n longhorn-system | grep -v Healthy | head -10

# Check disk usage
echo "Disk Usage:"
for node in 172.29.51.11 172.29.51.12 172.29.51.13; do
  echo "Node $node:"
  talosctl -n $node get disks | grep -E "(NAME|sda|Portable)"
done

echo "Health check completed"
```

#### Prometheus Metrics

Longhorn exposes metrics for monitoring:

- `longhorn_volume_actual_size_bytes`
- `longhorn_volume_state`
- `longhorn_node_storage_usage_bytes`
- `longhorn_disk_usage_bytes`

### Configuration Files

#### Key Configuration Files

- **Longhorn HelmRelease**: [`infrastructure/longhorn/helmrelease.yaml`](../../../infrastructure/longhorn/helmrelease.yaml)
- **Storage Classes**: Defined in Longhorn HelmRelease values
- **Talos USB Optimization**: [`talos/patches/usb-ssd-optimization.yaml`](../../../talos/patches/usb-ssd-optimization.yaml)
- **Backup Configuration**: [`infrastructure/longhorn/backup-target-patch.yaml`](../../../infrastructure/longhorn/backup-target-patch.yaml)

#### Validation Scripts

- **Complete Setup Validation**: [`scripts/validate-complete-usb-ssd-setup.sh`](../../../scripts/validate-complete-usb-ssd-setup.sh)
- **Storage Validation**: [`scripts/validate-usb-ssd-storage.sh`](../../../scripts/validate-usb-ssd-storage.sh)
- **Longhorn Validation**: [`scripts/validate-longhorn-usb-ssd.sh`](../../../scripts/validate-longhorn-usb-ssd.sh)
- **Deployment Script**: [`scripts/deploy-usb-ssd-storage.sh`](../../../scripts/deploy-usb-ssd-storage.sh)

## Best Practices

### USB SSD Management

1. **Use Identical Hardware**: All USB SSDs should be the same model for consistency
2. **Monitor Temperature**: USB SSDs can overheat; ensure adequate ventilation
3. **Regular Health Checks**: Monitor SMART data and disk health
4. **Backup Strategy**: Regular backups to external storage (S3)
5. **Replacement Planning**: Keep spare USB SSDs for quick replacement

### Longhorn Configuration

1. **Replica Distribution**: Ensure replicas are distributed across nodes
2. **Resource Limits**: Set appropriate CPU and memory limits
3. **Backup Frequency**: Configure regular automated backups
4. **Monitoring**: Set up alerts for volume and disk issues
5. **Upgrade Planning**: Plan Longhorn upgrades during maintenance windows

### Performance Best Practices

1. **Node Affinity**: Use node selectors for SSD-optimized workloads
2. **Storage Classes**: Use appropriate storage classes for different workloads
3. **Volume Sizing**: Right-size volumes to avoid waste
4. **Cleanup**: Regularly clean up unused volumes and snapshots
5. **Monitoring**: Monitor performance metrics and optimize as needed

## Related Documentation

- [Longhorn Setup](longhorn-setup.md) - Distributed storage configuration
- [Architecture Overview](../../architecture/overview.md) - System architecture
- [Daily Operations](../../operations/daily-operations.md) - Routine procedures
- [Backup & Recovery](../../operations/backup-recovery.md) - Backup procedures
- [Troubleshooting](../../operations/troubleshooting.md) - Common issues

---

This comprehensive guide covers all aspects of USB SSD storage operations in the Talos GitOps cluster, from initial deployment to ongoing maintenance and troubleshooting.
