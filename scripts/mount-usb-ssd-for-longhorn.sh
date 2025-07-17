#!/bin/bash
# Mount USB SSDs for Longhorn integration
# This script mounts Samsung T5 SSDs and adds them to Longhorn nodes

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NODES=("172.29.51.11" "172.29.51.12" "172.29.51.13")
NODE_NAMES=("mini01" "mini02" "mini03")
MOUNT_POINT="/var/lib/longhorn-ssd"
DEVICE_PATH="/dev/sda1"  # Samsung T5 partition

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Mount USB SSD on a node using machine config patch
mount_usb_ssd_on_node() {
    local node_ip=$1
    local node_name=$2
    
    log_info "Mounting USB SSD on $node_name ($node_ip)..."
    
    # Check if Samsung T5 is detected
    local t5_device
    t5_device=$(talosctl -n "$node_ip" ls /dev/disk/by-id/ | grep -E "usb-Samsung_Portable_SSD_T5.*-0:0$" | head -1 || true)
    
    if [[ -z "$t5_device" ]]; then
        log_error "No Samsung Portable SSD T5 found on $node_name"
        return 1
    fi
    
    log_success "Samsung T5 detected on $node_name: $t5_device"
    
    # Check if already mounted
    local mount_check
    mount_check=$(talosctl -n "$node_ip" read /proc/mounts | grep "$MOUNT_POINT" || true)
    
    if [[ -n "$mount_check" ]]; then
        log_warning "USB SSD already mounted on $node_name at $MOUNT_POINT"
        return 0
    fi
    
    # Create a machine config patch to mount the USB SSD
    log_info "Creating mount configuration for $node_name..."
    
    cat <<EOF | talosctl -n "$node_ip" patch machineconfig --patch-file /dev/stdin
machine:
  mounts:
    - device: $DEVICE_PATH
      destination: $MOUNT_POINT
      type: ext4
      options:
        - defaults
        - noatime
EOF
    
    log_success "Mount configuration applied to $node_name"
    
    # Wait for mount to be applied
    log_info "Waiting for mount to be applied..."
    sleep 10
    
    # Verify mount
    mount_check=$(talosctl -n "$node_ip" read /proc/mounts | grep "$MOUNT_POINT" || true)
    if [[ -n "$mount_check" ]]; then
        log_success "USB SSD successfully mounted on $node_name"
    else
        log_warning "Mount may not be active yet on $node_name - this is normal after config change"
    fi
}

# Add USB SSD disk to Longhorn node
add_longhorn_disk() {
    local node_name=$1
    
    log_info "Adding USB SSD disk to Longhorn node $node_name..."
    
    # Check if node exists in Longhorn
    if ! kubectl get nodes.longhorn.io "$node_name" -n longhorn-system &>/dev/null; then
        log_error "Longhorn node $node_name not found"
        return 1
    fi
    
    # Create disk configuration
    local disk_id="usb-ssd-$(date +%s)"
    
    # Patch the Longhorn node to add the USB SSD disk
    kubectl patch nodes.longhorn.io "$node_name" -n longhorn-system --type='merge' -p="$(cat <<EOF
{
  "spec": {
    "disks": {
      "$disk_id": {
        "allowScheduling": true,
        "diskType": "filesystem",
        "evictionRequested": false,
        "path": "$MOUNT_POINT",
        "storageReserved": 107374182400,
        "tags": ["ssd", "usb", "samsung-t5"]
      }
    }
  }
}
EOF
)"
    
    log_success "USB SSD disk added to Longhorn node $node_name with ID: $disk_id"
}

# Main function
main() {
    log_info "Starting USB SSD mounting and Longhorn integration..."
    echo
    
    # Check prerequisites
    if ! command -v talosctl &> /dev/null; then
        log_error "talosctl command not found"
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl command not found"
        exit 1
    fi
    
    # Set TALOSCONFIG
    export TALOSCONFIG=talos/generated/talosconfig
    
    # Process each node
    for i in "${!NODES[@]}"; do
        local node_ip="${NODES[$i]}"
        local node_name="${NODE_NAMES[$i]}"
        
        log_info "=== Processing node: $node_name ($node_ip) ==="
        
        # Mount USB SSD
        if mount_usb_ssd_on_node "$node_ip" "$node_name"; then
            log_success "USB SSD mount configured for $node_name"
        else
            log_error "Failed to configure USB SSD mount for $node_name"
            continue
        fi
        
        # Add to Longhorn
        if add_longhorn_disk "$node_name"; then
            log_success "USB SSD added to Longhorn for $node_name"
        else
            log_error "Failed to add USB SSD to Longhorn for $node_name"
        fi
        
        echo
    done
    
    log_info "=== Summary ==="
    log_success "USB SSD mounting and Longhorn integration completed"
    log_info "Note: Mounts may require a node reboot to become active"
    log_info "Check mount status with: talosctl -n <node> read /proc/mounts | grep longhorn-ssd"
    log_info "Check Longhorn disks with: kubectl get nodes.longhorn.io -n longhorn-system"
}

# Run main function
main "$@"