# Mini01 Simplified Recovery - Alternative Approach

## Issue

The disk encryption corruption on mini01 is persistent and the Talos installer ISO doesn't provide a command line for manual disk wiping.

## Alternative Recovery Strategy

### Option 1: Use Talos Reset with Wipe Flag

Since mini01 is still having PKI issues, let's use the Talos configuration with explicit wipe flag:

```bash
# Create a temporary wipe configuration for mini01
export TALOSCONFIG=clusterconfig/talosconfig

# Apply configuration with explicit wipe to force clean installation
talosctl apply-config --nodes 172.29.51.11 --file clusterconfig/home-ops-mini01.yaml --insecure --mode=reboot
```

The `talconfig.yaml` already has `wipe: true` in the install configuration, which should force a complete disk wipe.

### Option 2: Use Different Boot Media

If the Talos installer doesn't provide command line access, try:

1. **Ubuntu Live USB** - Boot from Ubuntu Live USB to get full command line access
2. **SystemRescue CD** - Specialized rescue distribution with disk tools
3. **GParted Live** - Focused on partition management

### Option 3: Force Wipe via Talos Configuration

Update the Talos configuration to be more aggressive about wiping:

```yaml
machine:
  install:
    wipe: true
    extraKernelArgs:
      - talos.logging.kernel=udp://172.29.51.1:514/
    # Force complete disk wipe
    disk: /dev/nvme0n1 # or whatever the disk is
```

### Option 4: Remote Disk Wipe via Talos API

If mini01 is accessible via Talos API (even with errors), we can try:

```bash
# Force reset with complete wipe
talosctl reset --nodes 172.29.51.11 --endpoints 172.29.51.11 --graceful=false --reboot --wipe-user-disks
```

## Recommended Immediate Action

Let's try the simplest approach first - use Ubuntu Live USB for complete control:

1. **Download Ubuntu Desktop Live ISO** (22.04 LTS or newer)
2. **Flash to USB drive**
3. **Boot mini01 from Ubuntu Live USB**
4. **Open terminal and run disk wipe commands**:

```bash
# Identify the internal disk
lsblk
sudo fdisk -l

# Assuming internal disk is /dev/nvme0n1
DISK="/dev/nvme0n1"

# Complete wipe
sudo wipefs -af $DISK
sudo dd if=/dev/zero of=$DISK bs=1M count=100
sudo dd if=/dev/zero of=$DISK bs=1M seek=$(($(sudo blockdev --getsz $DISK) / 2048 - 100)) count=100

# Create fresh partition table
sudo parted $DISK mklabel gpt

# Verify clean state
sudo parted $DISK print
```

5. **Reboot and let Talos install fresh**

This gives us complete control over the disk wiping process without relying on Talos installer limitations.

## Why This Approach Works

- Ubuntu Live USB provides full Linux environment
- Complete control over disk operations
- Can verify disk is completely clean before Talos installation
- Eliminates any possibility of encryption corruption persistence

Would you like to try the Ubuntu Live USB approach?
