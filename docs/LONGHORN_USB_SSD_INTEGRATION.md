h# Longhorn Samsung Portable SSD T5 Integration

This document describes the Longhorn configuration for optimal Samsung Portable SSD T5 storage integration in the Talos cluster.

## Overview

The Longhorn configuration has been updated to properly utilize Samsung Portable SSD T5 drives mounted at `/var/lib/longhorn-ssd` on each control plane node. This provides high-performance storage for applications requiring fast I/O operations.

## Configuration Changes

### 1. HelmRelease Configuration Updates

**File**: [`infrastructure/longhorn/helmrelease.yaml`](../infrastructure/longhorn/helmrelease.yaml)

Key changes made:

- **Disabled automatic disk creation**: `createDefaultDiskLabeledNodes: false`
- **Optimized storage settings for SSDs**:
  - `storageOverProvisioningPercentage: 150` (reduced from 200 for SSD efficiency)
  - `storageMinimalAvailablePercentage: 15` (reduced from 25 for better utilization)
- **SSD-optimized filesystem parameters**: `mkfsExt4Parameters: "-O ^64bit,^metadata_csum"`
- **Enhanced performance settings**:
  - `fastReplicaRebuildEnabled: true`
  - `snapshotDataIntegrity: "fast-check"`
  - `replicaFileSyncHttpClientTimeout: 30`

### 2. Storage Class Configuration

**File**: [`infrastructure/longhorn/storage-class.yaml`](../infrastructure/longhorn/storage-class.yaml)

The `longhorn-ssd` storage class includes:

- **Disk selector**: `diskSelector: "ssd"` - Uses only Samsung Portable SSD T5 drives with "ssd" tag
- **Data locality**: `dataLocality: "strict-local"` - Ensures data stays on the same node for performance
- **SSD optimizations**:
  - `mkfsExt4Parameters: "-O ^64bit,^metadata_csum -F"`
  - `disableRevisionCounter: "true"`
  - `replicaReplenishmentWaitInterval: "600"`
- **Replica configuration**: `numberOfReplicas: "3"` - Ensures high availability across all nodes

### 3. Volume Snapshot Classes

**File**: [`infrastructure/longhorn/volume-snapshot-class.yaml`](../infrastructure/longhorn/volume-snapshot-class.yaml)

Added SSD-specific snapshot class:

- **`longhorn-ssd-snapshot-vsc`**: Optimized for Samsung T5 storage with `diskSelector: "ssd"`
- Maintains existing default snapshot classes for compatibility

## Integration with Talos Samsung Portable SSD T5 Configuration

The Longhorn configuration works seamlessly with the Talos Samsung Portable SSD T5 setup:

### Talos Side (Automatic)

- Samsung Portable SSD T5 drives are detected via model-specific matching
- T5 drives are mounted at `/var/lib/longhorn-ssd`
- Disks are automatically tagged with "ssd" label
- I/O scheduler optimized for SSD performance (`mq-deadline`)
- Rotational flag set to `0` for SSD recognition
- Model verification ensures only T5 drives are used

### Longhorn Side (This Configuration)

- Disabled automatic disk creation to prevent conflicts
- Storage classes use `diskSelector: "ssd"` to target Samsung T5 drives
- Optimized settings for T5 performance and longevity

## Storage Classes Available

### 1. `longhorn-ssd` (Samsung Portable SSD T5 Storage)

- **Use case**: High-performance applications requiring fast I/O
- **Replicas**: 3 (across all nodes)
- **Data locality**: Strict local for performance
- **Reclaim policy**: Retain (data preserved on PVC deletion)

### 2. `longhorn` (Default - System Storage)

- **Use case**: General-purpose storage
- **Managed by**: Longhorn automatically
- **Storage**: Uses system disk (`/var/lib/longhorn`)

### 3. `longhorn-single-replica`

- **Use case**: Non-critical data, testing
- **Replicas**: 1 (no redundancy)
- **Reclaim policy**: Delete

## Usage Examples

### Using Samsung Portable SSD T5 Storage

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: high-performance-storage
  namespace: my-app
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-ssd # Uses Samsung T5 drives
  resources:
    requests:
      storage: 10Gi
```

### Creating T5-Optimized Snapshots

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: t5-ssd-snapshot
  namespace: my-app
spec:
  volumeSnapshotClassName: longhorn-ssd-snapshot-vsc
  source:
    persistentVolumeClaimName: high-performance-storage
```

## Performance Expectations

With Samsung Portable SSD T5 drives (USB 3.1 Gen 2):

- **Sequential I/O**: Up to 540 MB/s (T5 specification)
- **Random I/O**: Significantly improved over system storage
- **Latency**: Lower latency for database and cache workloads
- **IOPS**: Higher IOPS for transaction-heavy applications
- **Consistency**: Reliable performance across all capacity variants (250GB-2TB)

## Monitoring and Validation

### Check Disk Recognition

```bash
# Verify Longhorn recognizes Samsung T5 drives
kubectl get nodes.longhorn.io -n longhorn-system -o wide

# Check disk details
kubectl get disks.longhorn.io -n longhorn-system

# Verify T5 model detection
kubectl get disks.longhorn.io -n longhorn-system -o yaml | grep -A5 -B5 "T5"
```

### Validate Storage Classes

```bash
# List all storage classes
kubectl get storageclass

# Test Samsung T5 storage class
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-t5-ssd-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-ssd
  resources:
    requests:
      storage: 1Gi
EOF

# Wait for binding
kubectl wait --for=condition=Bound pvc/test-t5-ssd-pvc --timeout=60s

# Check volume details
kubectl get pv -o wide | grep test-t5-ssd-pvc

# Clean up
kubectl delete pvc test-t5-ssd-pvc
```

### Monitor Performance

```bash
# Check Longhorn volume performance
kubectl exec -n longhorn-system deployment/longhorn-ui -- \
  curl -s http://localhost:9500/v1/volumes | jq '.data[].performanceStats'

# Monitor disk usage
kubectl top nodes
```

## Troubleshooting

### Samsung T5 Not Recognized

1. **Check Talos Samsung T5 mounting**:

   ```bash
   talosctl df | grep longhorn-ssd
   # Check T5-specific device detection
   talosctl ls /dev/disk/by-id/usb-Samsung_Portable_SSD_T5*
   ```

2. **Verify T5 model detection**:

   ```bash
   talosctl cat /sys/block/*/device/model | grep "Portable SSD T5"
   ```

3. **Verify disk tagging**:

   ```bash
   talosctl ls /var/lib/longhorn/disks/
   talosctl cat /var/lib/longhorn/disks/*/tags
   ```

4. **Check Longhorn disk discovery**:
   ```bash
   kubectl logs -n longhorn-system deployment/longhorn-manager
   kubectl get events -n longhorn-system --sort-by='.lastTimestamp'
   ```

### Storage Class Issues

1. **Verify storage class parameters**:

   ```bash
   kubectl get storageclass longhorn-ssd -o yaml
   ```

2. **Check PVC binding issues**:
   ```bash
   kubectl describe pvc <pvc-name>
   kubectl get events --field-selector involvedObject.name=<pvc-name>
   ```

### Performance Issues

1. **Check I/O scheduler**:

   ```bash
   talosctl cat /sys/block/*/queue/scheduler
   ```

2. **Monitor T5 disk performance**:

   ```bash
   talosctl iostat
   talosctl dmesg | grep "Portable SSD T5"
   ```

3. **Verify T5 SSD optimizations**:
   ```bash
   talosctl cat /sys/block/*/queue/rotational
   talosctl cat /sys/block/*/device/model
   ```

## Maintenance

### Regular Health Checks

- Monitor Samsung T5 connection status
- Check Longhorn volume health in UI
- Verify replica distribution across nodes
- Monitor storage usage and performance metrics
- Verify T5 model detection remains consistent

### Backup Considerations

- Configure Longhorn backup targets for Samsung T5 volumes
- Test restore procedures regularly
- Consider cross-region backup for critical data

## Security Considerations

- Samsung T5 drives are only accessible to Longhorn and system processes
- T5 supports AES 256-bit hardware encryption (optional)
- Monitor for unauthorized USB device connections
- Ensure physical security of Mac mini nodes

## Next Steps

1. **Deploy the configuration**: Apply the updated Longhorn configuration
2. **Validate integration**: Run validation scripts to ensure proper Samsung T5 recognition
3. **Performance testing**: Benchmark storage performance with real workloads
4. **Monitoring setup**: Configure alerts for Samsung T5 health and performance
5. **Backup configuration**: Set up automated backups for Samsung T5 volumes
