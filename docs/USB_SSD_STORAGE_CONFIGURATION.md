# Samsung Portable SSD T5 Storage Configuration for Talos and Longhorn

This document describes the configuration and requirements for using Samsung Portable SSD T5 drives with Talos and Longhorn storage in the home-ops cluster.

## Overview

The cluster is configured to use external Samsung Portable SSD T5 drives for high-performance storage via Longhorn. Each Mac mini node (mini01, mini02, mini03) can have a dedicated Samsung Portable SSD T5 that provides faster storage compared to the internal Apple storage.

## Hardware Requirements

### Samsung Portable SSD T5 Specifications

- **Model**: Samsung Portable SSD T5 (specifically required)
- **Interface**: USB 3.1 Gen 2 (USB-C with USB-A adapter included)
- **Capacity**: Available in 250GB, 500GB, 1TB, 2TB (minimum 250GB required)
- **Performance**: Up to 540 MB/s read/write speeds
- **Form Factor**: Compact portable design (57.3 x 74 x 10.5 mm)
- **Reliability**: Samsung V-NAND flash memory with AES 256-bit hardware encryption support

### Why Samsung Portable SSD T5

The configuration specifically targets Samsung Portable SSD T5 drives for several reasons:

- **Consistent performance**: Reliable 540 MB/s speeds across all capacity variants
- **Hardware compatibility**: Proven compatibility with Mac mini USB ports
- **Model-based detection**: Reliable device identification through model string matching
- **Durability**: Shock-resistant design suitable for always-connected operation
- **Power efficiency**: Low power consumption suitable for bus-powered operation

## Physical Connection Requirements

### Mac Mini USB Ports

Each Mac mini has multiple USB ports available:

- **USB-A ports**: 2x USB 3.0 ports (rear)
- **USB-C/Thunderbolt ports**: 2x Thunderbolt 3/4 ports (rear)

### Connection Guidelines

1. **Dedicated Samsung T5 per node**: Each control plane node should have its own Samsung Portable SSD T5
2. **Stable connection**: Use rear USB ports for permanent storage connections
3. **Power considerations**: Samsung T5 is bus-powered and works reliably with Mac mini USB ports
4. **Cable quality**: Use the included Samsung USB-C to USB-A cable or equivalent high-quality cable

## Device Detection and Naming

### Device Path Patterns

The Talos configuration detects Samsung Portable SSD T5 drives using model-specific patterns:

```bash
# Samsung Portable SSD T5 detection pattern
/dev/disk/by-id/usb-Samsung_Portable_SSD_T5*

# Example device paths
/dev/disk/by-id/usb-Samsung_Portable_SSD_T5_1234567890ABCDEF-0:0
/dev/disk/by-id/usb-Samsung_Portable_SSD_T5_ABCDEF1234567890-0:0
```

### Device Identification

Samsung Portable SSD T5 drives are identified by:

- **Model string**: "Portable SSD T5" in the device model field
- **Vendor**: Samsung Electronics
- **Device path**: Specific USB device ID pattern matching T5 drives
- **Size validation**: Minimum capacity requirements (250GB+)

## Talos Configuration

### Machine Disk Configuration

The Samsung Portable SSD T5 storage is configured via [`talos/patches/usb-ssd-storage.yaml`](../talos/patches/usb-ssd-storage.yaml):

```yaml
machine:
  disks:
    - device: /dev/disk/by-id/usb-Samsung_Portable_SSD_T5*
      partitions:
        - mountpoint: /var/lib/longhorn-ssd
          size: 0 # Use entire disk
          format: ext4
          options:
            - defaults
            - noatime
            - nodiratime
            - discard
          label: longhorn-ssd
```

### Key Configuration Features

- **Model-specific detection**: Detects only Samsung Portable SSD T5 drives
- **Full disk usage**: Uses the entire Samsung T5 for storage
- **Optimized mounting**: SSD-optimized mount options (noatime, discard)
- **Proper labeling**: Labels disk for Longhorn discovery

### Udev Rules

Custom udev rules ensure proper Samsung Portable SSD T5 handling:

1. **T5 identification**: Marks Samsung T5 devices as SSDs (non-rotational)
2. **I/O scheduler**: Sets `mq-deadline` scheduler for optimal SSD performance
3. **Model verification**: Validates device model matches "Portable SSD T5"
4. **Longhorn labeling**: Creates disk tags for Longhorn disk selector

## Longhorn Integration

### Storage Class Configuration

The [`longhorn-ssd`](../infrastructure/longhorn/storage-class.yaml) storage class is configured to use Samsung Portable SSD T5 drives:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-ssd
parameters:
  diskSelector: "ssd"
  numberOfReplicas: "3"
  dataLocality: "strict-local"
```

### Disk Discovery

Longhorn automatically discovers Samsung Portable SSD T5 drives through:

- **Mount point**: `/var/lib/longhorn-ssd`
- **Disk label**: `ssd` tag applied via udev rules
- **Disk selector**: Matches `diskSelector: "ssd"` in storage class
- **Model verification**: Confirms device model is "Portable SSD T5"

## Operational Procedures

### Initial Setup

1. **Connect Samsung T5 drives**: Attach one Samsung Portable SSD T5 to each Mac mini node
2. **Apply configuration**: Deploy updated Talos configuration
3. **Verify detection**: Check that Samsung T5 drives are detected and mounted
4. **Validate Longhorn**: Confirm Longhorn recognizes the T5 storage

### Automated Validation

The repository includes a comprehensive validation script at [`scripts/validate-usb-ssd-storage.sh`](../scripts/validate-usb-ssd-storage.sh) that performs:

- **Samsung T5 Detection**: Verifies Samsung Portable SSD T5 drives are detected on all nodes
- **Model Verification**: Confirms detected devices are actually T5 models
- **Mount Point Validation**: Confirms proper mounting at `/var/lib/longhorn-ssd`
- **I/O Scheduler Check**: Validates optimal SSD scheduler settings
- **Longhorn Integration**: Tests disk discovery and storage class functionality
- **Storage Functionality**: Creates and tests a PVC using the Samsung T5 storage

Run the validation script after applying the configuration:

```bash
./scripts/validate-usb-ssd-storage.sh
```

The script provides colored output and detailed error reporting for troubleshooting.

### Verification Commands

Use the automated validation script for comprehensive testing:

```bash
# Run complete Samsung Portable SSD T5 storage validation
./scripts/validate-usb-ssd-storage.sh
```

Manual verification commands:

```bash
# Check Samsung T5 detection
talosctl get disks

# Verify mount points
talosctl ls /var/lib/longhorn-ssd

# Check Longhorn disk discovery
kubectl get nodes -o yaml | grep longhorn

# Verify storage class
kubectl get storageclass longhorn-ssd

# Verify Samsung T5 device detection
talosctl -n mini01 ls /dev/disk/by-id/usb-Samsung_Portable_SSD_T5*

# Check device model verification
talosctl -n mini01 cat /sys/block/*/device/model | grep "Portable SSD T5"
```

### Monitoring

Monitor Samsung Portable SSD T5 health and performance:

```bash
# Check disk usage
talosctl df

# Monitor I/O statistics
talosctl dmesg | grep "Portable SSD T5"

# Longhorn disk status
kubectl get disks -n longhorn-system

# Check T5-specific device information
talosctl -n mini01 cat /sys/block/*/device/model
```

## Troubleshooting

### Common Issues

#### Samsung T5 Not Detected

**Symptoms**: Samsung Portable SSD T5 not appearing in Talos disk list

**Troubleshooting**:

1. Check physical connection
2. Verify T5 power (try different port)
3. Check device detection: `talosctl dmesg | grep "Portable SSD T5"`
4. Validate device path: `talosctl ls /dev/disk/by-id/`
5. Confirm model string: `talosctl cat /sys/block/*/device/model`

**Resolution**:

```bash
# Check Samsung T5 devices
talosctl ls /dev/disk/by-id/usb-Samsung_Portable_SSD_T5*

# Verify model detection
talosctl cat /sys/block/*/device/model | grep "Portable SSD T5"

# Check udev rules
talosctl get udev
```

#### Mount Point Issues

**Symptoms**: Samsung T5 detected but not mounted

**Troubleshooting**:

1. Check filesystem format
2. Verify mount point permissions
3. Review system logs
4. Confirm T5 model verification

**Resolution**:

```bash
# Check mount status
talosctl df | grep longhorn-ssd

# Verify filesystem
talosctl fsck /dev/disk/by-id/usb-Samsung_Portable_SSD_T5*

# Remount if needed
talosctl mount /dev/disk/by-id/usb-Samsung_Portable_SSD_T5* /var/lib/longhorn-ssd
```

#### Longhorn Not Recognizing T5

**Symptoms**: Samsung T5 mounted but not available in Longhorn

**Troubleshooting**:

1. Check disk labeling
2. Verify Longhorn disk discovery
3. Review storage class configuration
4. Confirm T5 model verification

**Resolution**:

```bash
# Check Longhorn disks
kubectl get disks -n longhorn-system

# Verify disk tags
talosctl cat /var/lib/longhorn/disks/*/tags

# Confirm T5 model in Longhorn
kubectl get disks -n longhorn-system -o yaml | grep -A5 -B5 "T5"

# Restart Longhorn manager if needed
kubectl rollout restart deployment/longhorn-manager -n longhorn-system
```

### Performance Issues

#### Slow I/O Performance

**Symptoms**: Poor storage performance compared to expected SSD speeds

**Troubleshooting**:

1. Check I/O scheduler settings
2. Verify USB connection speed
3. Monitor system load

**Resolution**:

```bash
# Check I/O scheduler
talosctl cat /sys/block/*/queue/scheduler

# Monitor I/O statistics
talosctl iostat

# Test disk performance
talosctl dd if=/dev/zero of=/var/lib/longhorn-ssd/test bs=1M count=1000
```

## Failover and Recovery

### Samsung T5 Disconnection

**Automatic Handling**:

- Longhorn automatically handles temporary disconnections
- Replicas on other nodes maintain data availability
- Automatic reconnection when Samsung T5 is restored

**Manual Recovery**:

1. **Identify affected volumes**: Check Longhorn UI for degraded volumes
2. **Reconnect Samsung T5**: Ensure physical connection is restored
3. **Verify mount**: Confirm mount point is restored
4. **Rebuild replicas**: Longhorn automatically rebuilds if needed

### Node Replacement

**Procedure**:

1. **Drain node**: Move workloads to other nodes
2. **Replace hardware**: Install new Mac mini and Samsung Portable SSD T5
3. **Apply configuration**: Deploy Talos configuration to new node
4. **Restore data**: Longhorn handles replica redistribution

## Security Considerations

### Disk Encryption

- **Talos encryption**: System disk encryption is enabled via LUKS2
- **Samsung T5 encryption**: T5 supports AES 256-bit hardware encryption (optional)
- **Access control**: Samsung T5 drives are only accessible to Longhorn and system processes

### Physical Security

- **Secure mounting**: Ensure Samsung T5 drives are physically secured
- **Access control**: Limit physical access to Mac mini nodes
- **Monitoring**: Monitor for unauthorized USB device connections

## Performance Optimization

### SSD-Specific Optimizations

The configuration includes several SSD optimizations:

```yaml
# Mount options for SSD performance
options:
  - defaults
  - noatime # Disable access time updates
  - nodiratime # Disable directory access time updates
  - discard # Enable TRIM support

# System-level SSD optimizations
sysctls:
  vm.dirty_ratio: "5" # Reduce dirty page ratio
  vm.dirty_background_ratio: "2" # Background writeback threshold
  vm.dirty_expire_centisecs: "3000" # Dirty page expiration
  vm.dirty_writeback_centisecs: "500" # Writeback frequency
```

### I/O Scheduler

The configuration sets the `mq-deadline` scheduler for optimal SSD performance:

- Better suited for SSDs than CFQ scheduler
- Reduces latency for random I/O operations
- Optimizes for the parallel nature of SSD storage

## Maintenance

### Regular Maintenance Tasks

1. **Monitor disk health**: Check SMART data and error rates
2. **Verify performance**: Regular I/O performance testing
3. **Update firmware**: Keep Samsung T5 firmware updated via Samsung Magician
4. **Check connections**: Ensure stable physical connections
5. **Model verification**: Periodically verify T5 model detection

### Backup Considerations

- **Longhorn backups**: Configure regular backups to external storage
- **Replica distribution**: Ensure replicas are distributed across nodes
- **Disaster recovery**: Plan for complete Samsung T5 failure scenarios

## References

- [Talos Machine Configuration](https://www.talos.dev/v1.10/reference/configuration/)
- [Longhorn Storage Configuration](https://longhorn.io/docs/1.6.2/volumes-and-nodes/disks/)
- [USB Storage Best Practices](https://wiki.archlinux.org/title/USB_storage_devices)
