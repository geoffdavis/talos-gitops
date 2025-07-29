# Longhorn USB SSD Configuration Summary

This document summarizes the Longhorn configuration changes made to integrate with USB SSD storage in the Talos cluster.

## Overview

The Longhorn configuration has been updated to optimally utilize USB SSDs mounted at `/var/lib/longhorn-ssd` on each control plane node. This provides high-performance storage while maintaining the existing default storage for system operations.

## Files Modified

### 1. [`infrastructure/longhorn/helmrelease.yaml`](../infrastructure/longhorn/helmrelease.yaml)

**Key Changes:**

- **Disabled automatic disk creation**: `createDefaultDiskLabeledNodes: false`
  - Prevents conflicts with manually managed USB SSD disks
  - Allows explicit control over disk configuration

- **Optimized storage settings for SSDs**:
  - `storageOverProvisioningPercentage: 150` (reduced from 200)
  - `storageMinimalAvailablePercentage: 15` (reduced from 25)
  - Better utilization and efficiency for SSD storage

- **Enhanced performance settings**:
  - `fastReplicaRebuildEnabled: true` - Faster recovery for SSDs
  - `snapshotDataIntegrity: "fast-check"` - Optimized for SSD performance
  - `mkfsExt4Parameters: "-O ^64bit,^metadata_csum"` - SSD-optimized filesystem

### 2. [`infrastructure/longhorn/storage-class.yaml`](../infrastructure/longhorn/storage-class.yaml)

**Enhanced `longhorn-ssd` Storage Class:**

- **Disk targeting**: `diskSelector: "ssd"` - Uses only USB SSDs with "ssd" tag
- **Performance optimization**: `dataLocality: "strict-local"` - Keeps data on same node
- **SSD-specific parameters**:
  - `mkfsExt4Parameters: "-O ^64bit,^metadata_csum -F"`
  - `disableRevisionCounter: "true"`
  - `replicaReplenishmentWaitInterval: "600"`
- **High availability**: `numberOfReplicas: "3"` - Ensures data protection across nodes

### 3. [`infrastructure/longhorn/volume-snapshot-class.yaml`](../infrastructure/longhorn/volume-snapshot-class.yaml)

**Added SSD-Optimized Snapshot Class:**

- **`longhorn-ssd-snapshot-vsc`**: Dedicated snapshot class for USB SSD volumes
- **Disk targeting**: `diskSelector: "ssd"` - Ensures snapshots use SSD storage
- **Maintains compatibility**: Existing snapshot classes remain unchanged

## New Files Created

### 1. [`docs/LONGHORN_USB_SSD_INTEGRATION.md`](LONGHORN_USB_SSD_INTEGRATION.md)

- Comprehensive documentation for Longhorn USB SSD integration
- Usage examples and best practices
- Troubleshooting guide and performance expectations

### 2. [`scripts/validate-longhorn-usb-ssd.sh`](../scripts/validate-longhorn-usb-ssd.sh)

- Automated validation script for Longhorn USB SSD configuration
- Tests disk recognition, storage classes, and functionality
- Provides detailed diagnostics and error reporting

## Integration Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│                    Talos Layer                              │
├─────────────────────────────────────────────────────────────┤
│ • USB SSD Detection & Mounting                              │
│ • Mount Point: /var/lib/longhorn-ssd                        │
│ • Disk Tagging: "ssd" label                                 │
│ • I/O Optimization: mq-deadline scheduler                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  Longhorn Layer                             │
├─────────────────────────────────────────────────────────────┤
│ • Disk Discovery: Disabled automatic creation               │
│ • Storage Classes:                                          │
│   - longhorn-ssd (USB SSDs, diskSelector: "ssd")            │
│   - longhorn (Default, system storage)                      │
│ • Snapshot Classes:                                         │
│   - longhorn-ssd-snapshot-vsc (SSD-optimized)               │
│   - longhorn-snapshot-vsc (Default)                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                Application Layer                            │
├─────────────────────────────────────────────────────────────┤
│ • High-Performance Workloads → longhorn-ssd                 │
│ • General Applications → longhorn (default)                 │
│ • Testing/Development → longhorn-single-replica             │
└─────────────────────────────────────────────────────────────┘
```

## Storage Classes Available

| Storage Class             | Use Case              | Replicas | Storage     | Performance             |
| ------------------------- | --------------------- | -------- | ----------- | ----------------------- |
| `longhorn-ssd`            | High-performance apps | 3        | USB SSDs    | High I/O, Low latency   |
| `longhorn`                | General purpose       | 3        | System disk | Standard                |
| `longhorn-single-replica` | Testing/Dev           | 1        | System disk | Standard, No redundancy |

## Configuration Benefits

### Performance Improvements

- **Higher IOPS**: USB SSDs provide significantly better random I/O performance
- **Lower Latency**: Reduced access times for database and cache workloads
- **Better Throughput**: Sequential read/write speeds of 400-1000+ MB/s
- **SSD Optimizations**: Proper I/O scheduler and filesystem parameters

### Operational Benefits

- **Explicit Control**: Manual disk management prevents configuration conflicts
- **Storage Separation**: High-performance and general storage are isolated
- **Scalability**: Easy to add more USB SSDs as needed
- **Monitoring**: Clear separation allows better performance monitoring

### Reliability Features

- **High Availability**: 3 replicas across all control plane nodes
- **Data Protection**: Retain reclaim policy preserves data on PVC deletion
- **Backup Support**: Integrated with Longhorn backup and snapshot features
- **Automatic Recovery**: Fast replica rebuild for SSD failures

## Deployment Process

### 1. Prerequisites

- USB SSDs connected to all control plane nodes
- Talos USB SSD configuration applied and validated
- Longhorn already installed in the cluster

### 2. Apply Configuration

```bash
# Apply updated Longhorn configuration
kubectl apply -k infrastructure/longhorn/

# Wait for Longhorn to reconcile
kubectl rollout status deployment/longhorn-manager -n longhorn-system
```

### 3. Validate Integration

```bash
# Run comprehensive validation
./scripts/validate-longhorn-usb-ssd.sh

# Check storage classes
kubectl get storageclass

# Verify USB SSD disks
kubectl get disks.longhorn.io -n longhorn-system
```

### 4. Test Functionality

```bash
# Create test PVC using USB SSD storage
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-ssd-storage
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: longhorn-ssd
  resources:
    requests:
      storage: 5Gi
EOF

# Verify binding
kubectl get pvc test-ssd-storage

# Clean up
kubectl delete pvc test-ssd-storage
```

## Monitoring and Maintenance

### Health Checks

- Monitor USB SSD connection status via Talos
- Check Longhorn disk health in the UI
- Verify replica distribution across nodes
- Monitor storage usage and performance metrics

### Performance Monitoring

- Use Longhorn UI for volume performance statistics
- Monitor I/O metrics via Talos system tools
- Track storage utilization and growth trends
- Set up alerts for disk health and performance issues

### Backup Strategy

- Configure Longhorn backup targets for USB SSD volumes
- Test restore procedures regularly
- Consider cross-region backup for critical data
- Implement automated backup schedules

## Troubleshooting

### Common Issues

1. **USB SSD not recognized**: Check Talos mounting and disk tagging
2. **Storage class not working**: Verify diskSelector configuration
3. **Performance issues**: Check I/O scheduler and SSD optimizations
4. **Replica placement**: Ensure all nodes have USB SSDs connected

### Diagnostic Commands

```bash
# Check Talos USB SSD status
talosctl df | grep longhorn-ssd
talosctl service mount-usb-ssd status

# Check Longhorn disk status
kubectl get disks.longhorn.io -n longhorn-system
kubectl get nodes.longhorn.io -n longhorn-system

# Run validation script
./scripts/validate-longhorn-usb-ssd.sh
```

## Next Steps

1. **Deploy Configuration**: Apply the updated Longhorn configuration
2. **Validate Setup**: Run validation scripts and manual tests
3. **Performance Testing**: Benchmark with real workloads
4. **Monitoring Setup**: Configure alerts and dashboards
5. **Backup Configuration**: Set up automated backup strategies
6. **Documentation**: Update operational procedures and runbooks

## Security Considerations

- USB SSDs are only accessible to Longhorn and system processes
- Consider filesystem-level encryption for sensitive data
- Monitor for unauthorized USB device connections
- Ensure physical security of Mac mini nodes and USB SSDs
- Regular security updates for Longhorn and Talos components

This configuration provides a production-ready, high-performance storage solution that leverages USB SSDs while maintaining operational simplicity and data protection.
