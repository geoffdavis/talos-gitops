# USB SSD Storage Deployment Summary

This document provides a quick reference for deploying USB SSD storage support in the Talos cluster.

## Overview

The USB SSD storage configuration enables high-performance external storage for Longhorn on Mac mini nodes. Each node can have a dedicated USB SSD that provides faster storage compared to internal Apple storage.

## Files Created/Modified

### New Files

1. **[`talos/patches/usb-ssd-storage.yaml`](../talos/patches/usb-ssd-storage.yaml)**
   - Talos machine configuration patch for USB SSD support
   - Includes automatic detection, mounting, and optimization scripts
   - Configures systemd service for USB SSD management

2. **[`docs/USB_SSD_STORAGE_CONFIGURATION.md`](USB_SSD_STORAGE_CONFIGURATION.md)**
   - Comprehensive documentation for USB SSD requirements and configuration
   - Hardware specifications and connection guidelines
   - Troubleshooting and maintenance procedures

3. **[`scripts/validate-usb-ssd-storage.sh`](../scripts/validate-usb-ssd-storage.sh)**
   - Automated validation script for USB SSD storage
   - Tests detection, mounting, and Longhorn integration
   - Provides detailed error reporting and troubleshooting

4. **[`docs/USB_SSD_DEPLOYMENT_SUMMARY.md`](USB_SSD_DEPLOYMENT_SUMMARY.md)** (this file)
   - Quick deployment reference and summary

### Modified Files

1. **[`talconfig.yaml`](../talconfig.yaml)**
   - Added USB SSD storage patch to control plane configuration
   - Patch applied to all three nodes (mini01, mini02, mini03)

## Deployment Steps

### 1. Hardware Setup

Connect USB SSDs to each Mac mini node:
- **Minimum requirements**: USB 3.0/3.1, 100GB+ capacity, 400MB/s+ speeds
- **Recommended**: Samsung T7, SanDisk Extreme Pro, or similar high-performance USB SSDs
- **Connection**: Use rear USB ports for stable connections

### 2. Apply Talos Configuration

Deploy the updated configuration to all nodes:

```bash
# Generate new Talos configuration with USB SSD support
talosctl gen config home-ops https://172.29.51.10:6443 --config-patch @talconfig.yaml

# Apply configuration to all nodes
talosctl apply-config --insecure --nodes 172.29.51.11 --file controlplane.yaml
talosctl apply-config --insecure --nodes 172.29.51.12 --file controlplane.yaml
talosctl apply-config --insecure --nodes 172.29.51.13 --file controlplane.yaml

# Wait for nodes to reboot and come back online
talosctl health --nodes 172.29.51.11,172.29.51.12,172.29.51.13
```

### 3. Validate Configuration

Run the automated validation script:

```bash
# Make script executable (if not already)
chmod +x scripts/validate-usb-ssd-storage.sh

# Run comprehensive validation
./scripts/validate-usb-ssd-storage.sh
```

### 4. Verify Longhorn Integration

Check that Longhorn recognizes the USB SSD storage:

```bash
# Check Longhorn nodes and disks
kubectl get nodes.longhorn.io -n longhorn-system

# Verify storage class
kubectl get storageclass longhorn-ssd

# Test storage functionality
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-usb-ssd
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-ssd
  resources:
    requests:
      storage: 1Gi
EOF

# Wait for PVC to bind
kubectl wait --for=condition=Bound pvc/test-usb-ssd --timeout=60s

# Clean up test PVC
kubectl delete pvc test-usb-ssd
```

## Configuration Details

### USB SSD Detection

The configuration automatically detects USB SSDs using:
- Device path pattern: `/dev/disk/by-id/usb-*`
- Size filtering: Minimum 100GB to exclude small USB devices
- Non-removable USB block devices only

### Mount Configuration

- **Mount point**: `/var/lib/longhorn-ssd`
- **Filesystem**: ext4 with SSD optimizations
- **Mount options**: `defaults,noatime,nodiratime,discard`
- **Permissions**: 755 with root ownership

### Longhorn Integration

- **Disk labeling**: Automatic `ssd` tag for disk selector
- **Storage class**: `longhorn-ssd` with `diskSelector: "ssd"`
- **Replica count**: 3 replicas across all nodes
- **Data locality**: `strict-local` for performance

### System Optimizations

- **I/O scheduler**: `mq-deadline` for optimal SSD performance
- **Rotational flag**: Set to `0` (non-rotational) for SSD recognition
- **VM settings**: Optimized dirty page ratios for SSD workloads

## Monitoring and Maintenance

### Health Checks

```bash
# Check USB SSD mount status
talosctl df | grep longhorn-ssd

# Verify USB device detection
talosctl ls /dev/disk/by-id/usb-*

# Check systemd service status
talosctl service mount-usb-ssd status

# Monitor Longhorn disk health
kubectl get disks -n longhorn-system
```

### Performance Monitoring

```bash
# Check I/O statistics
talosctl iostat

# Monitor disk usage
talosctl df

# Check system logs for USB events
talosctl dmesg | grep -i usb
```

## Troubleshooting

### Common Issues

1. **USB SSD not detected**
   - Check physical connection and power
   - Verify device appears in `/dev/disk/by-id/usb-*`
   - Check system logs: `talosctl dmesg | grep usb`

2. **Mount point not created**
   - Verify systemd service is running: `talosctl service mount-usb-ssd status`
   - Check filesystem format: `talosctl blkid /dev/disk/by-id/usb-*`
   - Review service logs: `talosctl logs mount-usb-ssd`

3. **Longhorn not recognizing SSD**
   - Verify disk labeling: `talosctl cat /var/lib/longhorn/disks/*/tags`
   - Check storage class configuration: `kubectl get storageclass longhorn-ssd -o yaml`
   - Restart Longhorn manager: `kubectl rollout restart deployment/longhorn-manager -n longhorn-system`

### Recovery Procedures

1. **USB SSD disconnection**
   - Longhorn automatically handles temporary disconnections
   - Reconnect USB SSD and verify mount restoration
   - Check replica status in Longhorn UI

2. **Service restart**
   ```bash
   # Restart USB SSD mounting service
   talosctl service mount-usb-ssd restart
   
   # Verify mount restoration
   talosctl df | grep longhorn-ssd
   ```

## Security Considerations

- USB SSDs are only accessible to Longhorn and system processes
- Consider filesystem-level encryption for sensitive data
- Monitor for unauthorized USB device connections
- Ensure physical security of Mac mini nodes

## Performance Expectations

With properly configured USB 3.0/3.1 SSDs:
- **Sequential read/write**: 400-1000+ MB/s (depending on SSD model)
- **Random I/O**: Significantly improved over internal storage
- **Latency**: Lower latency compared to traditional storage

## Next Steps

After successful deployment:

1. **Configure Longhorn backups** to external storage
2. **Set up monitoring** for USB SSD health and performance
3. **Test failover scenarios** to ensure high availability
4. **Document any site-specific configurations** or customizations

## Support

For issues or questions:
- Review the comprehensive documentation: [`USB_SSD_STORAGE_CONFIGURATION.md`](USB_SSD_STORAGE_CONFIGURATION.md)
- Run the validation script: [`scripts/validate-usb-ssd-storage.sh`](../scripts/validate-usb-ssd-storage.sh)
- Check Talos and Longhorn documentation for additional troubleshooting