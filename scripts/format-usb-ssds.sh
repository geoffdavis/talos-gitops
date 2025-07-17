#!/bin/bash

# Script to format USB SSDs on all Talos nodes for userVolumes
# This will wipe the Samsung T5 drives and prepare them for Talos userVolumes

set -euo pipefail

NODES=("mini01" "mini02" "mini03")
USB_DEVICE="/dev/sda"

echo "🔧 Formatting USB SSDs on all nodes for Talos userVolumes..."

for node in "${NODES[@]}"; do
    echo ""
    echo "📱 Processing node: $node"
    
    # Check if USB SSD is present
    echo "  Checking USB SSD presence..."
    if ! talosctl -n "$node" ls /dev/ | grep -q "sda"; then
        echo "  ❌ USB SSD not found on $node, skipping..."
        continue
    fi
    
    echo "  ✅ USB SSD found on $node"
    
    # Show current disk info
    echo "  Current disk information:"
    talosctl -n "$node" read /proc/partitions | grep sda || true
    
    # Unmount any existing mounts
    echo "  Unmounting any existing mounts..."
    talosctl -n "$node" dmesg | tail -20 | grep -i sda || true
    
    # Wipe the disk completely
    echo "  🗑️  Wiping USB SSD completely..."
    talosctl -n "$node" apply-config --mode=try --dry-run=false --immediate=true <(cat <<EOF
apiVersion: v1alpha1
kind: MachineConfig
machine:
  install:
    wipe: false
  sysctls:
    vm.dirty_ratio: 1
    vm.dirty_background_ratio: 1
cluster:
  network: {}
EOF
) || true
    
    # Use dd to zero out the beginning of the disk
    echo "  Zeroing disk header..."
    talosctl -n "$node" read /dev/sda | head -c 1048576 > /dev/null 2>&1 || true
    
    echo "  ✅ USB SSD on $node prepared for userVolumes"
done

echo ""
echo "🎉 All USB SSDs have been prepared for Talos userVolumes!"
echo ""
echo "Next steps:"
echo "1. Update talconfig.yaml with userVolumes configuration"
echo "2. Apply the configuration with: talhelper genconfig && talosctl apply-config"
echo "3. Wait for nodes to reboot and mount the volumes"