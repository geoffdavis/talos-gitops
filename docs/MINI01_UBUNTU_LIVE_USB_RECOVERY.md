# Mini01 Ubuntu Live USB Recovery Guide

## Overview
This guide provides step-by-step instructions for using Ubuntu Live USB to completely wipe mini01's disk and eliminate the persistent disk encryption corruption.

## Prerequisites
- USB drive (8GB or larger)
- Ubuntu Desktop 22.04 LTS ISO
- Physical access to mini01

## Step 1: Create Ubuntu Live USB

### Download Ubuntu ISO
```bash
# Download Ubuntu 22.04 LTS Desktop
curl -LO https://releases.ubuntu.com/22.04/ubuntu-22.04.3-desktop-amd64.iso
```

### Create Bootable USB (macOS)
```bash
# Find USB device
diskutil list

# Unmount USB (replace diskX with your USB device)
diskutil unmountDisk /dev/diskX

# Write ISO to USB
sudo dd if=ubuntu-22.04.3-desktop-amd64.iso of=/dev/rdiskX bs=1m

# Eject USB
diskutil eject /dev/diskX
```

## Step 2: Boot Mini01 from Ubuntu Live USB

1. **Insert USB drive** into mini01
2. **Power on mini01** and immediately hold **Option key**
3. **Select USB drive** from boot menu
4. **Choose "Try Ubuntu"** (don't install)
5. **Wait for desktop** to load

## Step 3: Complete Disk Wipe

### Open Terminal
Press `Ctrl+Alt+T` to open terminal

### Identify Internal Disk
```bash
# List all storage devices
lsblk

# Get detailed disk information
sudo fdisk -l

# Look for Apple SSD (usually /dev/nvme0n1 or /dev/sda)
# Should show something like "Apple SSD" in model
```

### Complete Disk Wipe
```bash
# Set disk variable (REPLACE WITH YOUR ACTUAL DISK!)
DISK="/dev/nvme0n1"  # or /dev/sda - verify this first!

# CRITICAL: Verify this is the correct disk before proceeding
echo "About to wipe disk: $DISK"
sudo fdisk -l $DISK

# Proceed only if you're certain this is the internal disk

# 1. Wipe all filesystem signatures
sudo wipefs -af $DISK

# 2. Zero out partition table and boot sectors
sudo dd if=/dev/zero of=$DISK bs=1M count=100 status=progress

# 3. Zero out end of disk (backup partition tables)
DISK_SIZE=$(sudo blockdev --getsz $DISK)
END_SECTORS=$((DISK_SIZE / 2048 - 100))
sudo dd if=/dev/zero of=$DISK bs=1M seek=$END_SECTORS count=100 status=progress

# 4. Secure wipe entire disk (this will take time)
sudo shred -vfz -n 1 $DISK

# 5. Create fresh GPT partition table
sudo parted $DISK mklabel gpt

# 6. Verify clean state
sudo parted $DISK print
sudo blkid $DISK  # Should show no output (no filesystems)
```

### Verification Commands
```bash
# Verify no encryption signatures remain
sudo cryptsetup isLuks $DISK && echo "LUKS found - wipe failed!" || echo "No LUKS - wipe successful!"

# Verify no filesystems detected
sudo blkid $DISK || echo "No filesystems detected - good!"

# Check partition table
sudo fdisk -l $DISK
```

## Step 4: Reboot to Talos

1. **Remove USB drive**
2. **Reboot mini01**
3. **Boot from network/PXE** or insert Talos USB installer
4. **Let Talos install fresh** to the clean disk

## Step 5: Verify Clean Installation

After Talos boots:

```bash
# From recovery workstation
export TALOSCONFIG=clusterconfig/talosconfig

# Check if mini01 is in maintenance mode (expected)
talosctl version --nodes 172.29.51.11 --endpoints 172.29.51.11 --insecure

# Should show maintenance mode without encryption errors
```

## Safety Warnings

⚠️ **CRITICAL SAFETY CHECKS:**
- **VERIFY DISK DEVICE** before running any wipe commands
- **DOUBLE-CHECK** you're wiping the internal disk, not USB drive
- **BACKUP ANY IMPORTANT DATA** (though this is intentional wipe for security)
- **ENSURE PHYSICAL ACCESS** to mini01 in case of issues

## Expected Results

After successful completion:
- ✅ All disk encryption corruption eliminated
- ✅ Clean GPT partition table
- ✅ No filesystem signatures
- ✅ Ready for fresh Talos installation
- ✅ mini01 boots to maintenance mode without errors

## Troubleshooting

### If disk wipe fails:
- Try different wipe tools: `dd`, `shred`, `scrub`
- Use multiple passes: `shred -vfz -n 3`
- Check for hardware write protection

### If Talos won't install:
- Verify UEFI boot mode
- Check network connectivity
- Ensure Talos installer image is valid

### If still getting encryption errors:
- Repeat the secure wipe process
- Try zeroing more of the disk
- Consider hardware-level secure erase

## Next Steps

Once mini01 is clean and in maintenance mode:
1. Continue with cluster recovery script
2. Apply fresh Talos configuration to all nodes
3. Bootstrap cluster with fresh credentials
4. Deploy Cilium CNI
5. Complete security incident response

This approach gives us complete control over the disk wiping process and should eliminate the persistent encryption corruption.