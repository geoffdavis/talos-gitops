# Mini01 Disk Recovery Procedure

## Context
Mini01 has disk encryption state corruption causing read-only filesystem errors. This procedure will completely wipe and repartition the internal disk to eliminate all encryption corruption.

## Prerequisites
- Talos USB installer image (v1.10.5)
- Physical access to mini01
- Network connectivity for Talos installation

## Procedure

### Step 1: Boot from USB Drive
1. Create Talos USB installer if not already available:
   ```bash
   # Download Talos installer image
   curl -LO https://github.com/siderolabs/talos/releases/download/v1.10.5/talos-amd64.iso
   
   # Flash to USB drive (replace /dev/sdX with your USB device)
   sudo dd if=talos-amd64.iso of=/dev/sdX bs=4M status=progress
   ```

2. Boot mini01 from USB drive:
   - Insert USB drive into mini01
   - Power on and hold Option key to access boot menu
   - Select USB drive to boot from

### Step 2: Identify and Wipe Internal Disk
Once booted into Talos installer environment:

1. Identify the internal disk:
   ```bash
   # List all disks
   lsblk
   
   # Look for the Apple internal SSD (typically /dev/nvme0n1 or /dev/sda)
   # Should show model containing "APPLE" 
   ```

2. Completely wipe the internal disk:
   ```bash
   # Replace /dev/nvme0n1 with your actual internal disk device
   INTERNAL_DISK="/dev/nvme0n1"
   
   # Wipe all partition tables and data
   wipefs -af $INTERNAL_DISK
   
   # Zero out the first and last few MB to clear any residual data
   dd if=/dev/zero of=$INTERNAL_DISK bs=1M count=100
   dd if=/dev/zero of=$INTERNAL_DISK bs=1M seek=$(($(blockdev --getsz $INTERNAL_DISK) / 2048 - 100)) count=100
   
   # Secure wipe (optional but recommended for encryption corruption)
   shred -vfz -n 1 $INTERNAL_DISK
   ```

### Step 3: Create Fresh Partition Table
```bash
# Create new GPT partition table
parted $INTERNAL_DISK mklabel gpt

# Verify clean state
parted $INTERNAL_DISK print
```

### Step 4: Install Fresh Talos
1. Install Talos to the clean internal disk:
   ```bash
   # Install Talos (this will create proper partitions)
   talos-installer \
     --disk $INTERNAL_DISK \
     --arch amd64 \
     --image ghcr.io/siderolabs/talos:v1.10.5
   ```

2. Remove USB drive and reboot:
   ```bash
   reboot
   ```

### Step 5: Verify Clean Boot
After reboot, mini01 should boot into Talos maintenance mode with:
- Clean partition table
- No encryption corruption
- Fresh Talos installation
- Ready for configuration

### Step 6: Verify Maintenance Mode
From the recovery workstation:
```bash
export TALOSCONFIG=clusterconfig/talosconfig
talosctl version --nodes 172.29.51.11 --endpoints 172.29.51.11 --insecure
```

Expected output should show maintenance mode without any filesystem errors.

## Post-Recovery Steps
Once mini01 is in clean maintenance mode:
1. Continue with the recovery script: `./scripts/recover-partition-wipe-issue.sh`
2. Apply fresh Talos configuration to all three nodes
3. Bootstrap the cluster with fresh credentials
4. Deploy Cilium CNI
5. Complete security incident response

## Safety Notes
- This procedure completely wipes mini01's internal disk
- All previous data and encryption keys are permanently destroyed
- This is the intended outcome for security incident response
- The procedure preserves the Talos OS installation while eliminating corruption

## Verification Commands
After completion, verify no encryption corruption:
```bash
# Check for read-only filesystem errors
talosctl dmesg --nodes 172.29.51.11 | grep -i "read-only\|filesystem"

# Should return no results or only normal boot messages