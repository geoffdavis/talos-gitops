# USB SSD Storage Configuration

The Talos GitOps Home-Ops Cluster leverages external USB SSDs for distributed storage, primarily managed by Longhorn. This document details the hardware used, the optimizations applied, and how these SSDs are integrated into the cluster's storage architecture.

## Hardware

- **Devices**: 3x Samsung Portable SSD T5 (1TB each)
- **Total Raw Capacity**: 3TB
- **Effective Capacity**: Approximately 1.35TB with a 2-replica factor in Longhorn.

## Optimization

To ensure optimal performance and reliability from the USB SSDs, several system-level optimizations have been applied:

- **Smart Disk Selection**: Talos OS is configured to automatically select the correct disks for installation and data partitions using `installDiskSelector: model: "APPLE*"` for internal drives and `match: disk.model == "Portable SSD T5"` for the USB SSDs.
- **Custom udev Rules**: Specific `udev` rules are applied to ensure consistent device naming and proper handling of the USB drives.
- **Sysctl Tuning**: Kernel parameters (`sysctls`) are tuned to improve I/O performance and reduce latency for the SSDs. These typically include adjustments to `vm.dirty_ratio`, `vm.dirty_background_ratio`, and `scheduler` settings.

## Integration with Longhorn

The USB SSDs are configured as storage devices for Longhorn, allowing it to create and manage distributed block volumes across the cluster.

Key aspects of this integration include:

- **Longhorn Storage Nodes**: Each USB SSD is registered as a storage device on its respective node within Longhorn.
- **Data Path**: Longhorn is configured to use a specific path on the SSDs (e.g., `/mnt/longhorn`) for storing volume data.
- **Automatic Disk Discovery**: Longhorn can be configured to automatically discover and utilize available disks that meet certain criteria.
- **Replication**: Longhorn replicates data across the SSDs on different nodes to ensure high availability and data durability.

## Operational Considerations

### Verifying USB SSD Status

- Check disk presence and health on each node: `lsblk` or `fdisk -l` on the Talos nodes.
- Verify Longhorn has registered the SSDs as active storage devices in its UI.

### Troubleshooting

- **Disk Not Detected**:
  - Ensure the USB SSD is properly connected and powered.
  - Check Talos OS logs for any disk detection errors.
  - Verify `udev` rules are correctly applied.
- **Performance Issues**:
  - Monitor I/O performance using tools like `iostat` (if available on Talos or via a debug container).
  - Review `sysctl` settings to ensure optimizations are active.
- **Longhorn Storage Errors**:
  - Check Longhorn manager and engine logs for errors related to disk I/O or device access.
  - Verify the `defaultDataPath` in Longhorn's configuration points to the correct mount point on the SSD.

## Related Files

- [`talconfig.yaml`](../../talconfig.yaml) - Talos OS configuration, including disk selection.
- [`infrastructure/longhorn/helmrelease.yaml`](../../infrastructure/longhorn/helmrelease.yaml) - Longhorn configuration, including data paths.
- [`docs/USB_SSD_OPERATIONAL_PROCEDURES.md`](../../docs/USB_SSD_OPERATIONAL_PROCEDURES.md) - General operational procedures for USB SSDs.

Please ensure this file is created with the exact content provided. After creation, use the `attempt_completion` tool to report the successful creation of the file.
