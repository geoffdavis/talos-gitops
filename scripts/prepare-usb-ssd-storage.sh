#!/bin/bash
# USB SSD Storage Preparation Script for Talos Cluster
# Prepares Samsung Portable SSD T5 drives for Longhorn integration

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

# Check if talosctl is available
check_talosctl() {
    if ! command -v talosctl &> /dev/null; then
        log_error "talosctl command not found. Please install Talos CLI."
        exit 1
    fi
    log_success "talosctl is available"
}

# Check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl command not found. Please install kubectl."
        exit 1
    fi
    log_success "kubectl is available"
}

# Prepare USB SSD on a node
prepare_usb_ssd_on_node() {
    local node_ip=$1
    local node_name=$2
    
    log_info "Preparing USB SSD on $node_name ($node_ip)..."
    
    # Check if Samsung T5 is detected
    local t5_device
    t5_device=$(talosctl -n "$node_ip" ls /dev/disk/by-id/ | grep -E "usb-Samsung_Portable_SSD_T5.*[^0-9]$" | head -1 || true)
    
    if [[ -z "$t5_device" ]]; then
        log_error "No Samsung Portable SSD T5 found on $node_name"
        return 1
    fi
    
    log_success "Samsung T5 detected on $node_name: $t5_device"
    
    # Check if device exists
    if ! talosctl -n "$node_ip" ls "$DEVICE_PATH" &>/dev/null; then
        log_error "Device $DEVICE_PATH not found on $node_name"
        return 1
    fi
    
    # Check if already mounted
    local mount_check
    mount_check=$(talosctl -n "$node_ip" read /proc/mounts | grep "$MOUNT_POINT" || true)
    
    if [[ -n "$mount_check" ]]; then
        log_warning "USB SSD already mounted on $node_name at $MOUNT_POINT"
        return 0
    fi
    
    # Create mount point directory
    log_info "Creating mount point $MOUNT_POINT on $node_name..."
    if ! talosctl -n "$node_ip" ls "$MOUNT_POINT" &>/dev/null; then
        # Use a machine config patch to create the directory
        cat <<EOF | talosctl -n "$node_ip" patch machineconfig --patch-file /dev/stdin
machine:
  files:
    - path: $MOUNT_POINT
      permissions: 0755
      op: create
EOF
    fi
    
    # Check filesystem type
    local fs_type
    fs_type=$(talosctl -n "$node_ip" read /proc/filesystems | grep ext4 || true)
    
    if [[ -z "$fs_type" ]]; then
        log_error "ext4 filesystem support not available on $node_name"
        return 1
    fi
    
    # Format the device if needed (check if it has a filesystem)
    local has_fs
    has_fs=$(talosctl -n "$node_ip" blkid "$DEVICE_PATH" 2>/dev/null | grep -o 'TYPE="[^"]*"' || true)
    
    if [[ -z "$has_fs" ]]; then
        log_info "Formatting $DEVICE_PATH with ext4 on $node_name..."
        talosctl -n "$node_ip" read /dev/null # This is a placeholder - Talos doesn't allow direct formatting
        log_warning "Device needs to be pre-formatted with ext4. Please format $DEVICE_PATH manually."
        return 1
    else
        log_success "Filesystem detected on $DEVICE_PATH: $has_fs"
    fi
    
    # Mount the device
    log_info "Mounting $DEVICE_PATH to $MOUNT_POINT on $node_name..."
    
    # Create a machine config patch to mount the USB SSD
    cat <<EOF | talosctl -n "$node_ip" patch machineconfig --patch-file /dev/stdin
machine:
  disks:
    - device: $DEVICE_PATH
      partitions:
        - mountpoint: $MOUNT_POINT
EOF
    
    log_success "USB SSD preparation completed on $node_name"
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
    local disk_id
    disk_id="usb-ssd-$(date +%s)"
    
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

# Wait for Longhorn to be ready
wait_for_longhorn() {
    log_info "Waiting for Longhorn to be ready..."
    
    local timeout=300
    local elapsed=0
    local interval=10
    
    while [ $elapsed -lt $timeout ]; do
        if kubectl get pods -n longhorn-system | grep -q "longhorn-manager.*Running"; then
            log_success "Longhorn is ready"
            return 0
        fi
        
        log_info "Waiting for Longhorn... ($elapsed/$timeout seconds)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_error "Timeout waiting for Longhorn to be ready"
    return 1
}

# Main execution
main() {
    log_info "Starting USB SSD storage preparation for Talos cluster..."
    
    # Check prerequisites
    check_talosctl
    check_kubectl
    
    # Wait for Longhorn to be ready
    wait_for_longhorn
    
    # Prepare USB SSDs on all nodes
    for i in "${!NODES[@]}"; do
        local node_ip="${NODES[$i]}"
        local node_name="${NODE_NAMES[$i]}"
        
        if prepare_usb_ssd_on_node "$node_ip" "$node_name"; then
            add_longhorn_disk "$node_name"
        else
            log_error "Failed to prepare USB SSD on $node_name"
        fi
    done
    
    log_success "USB SSD storage preparation completed!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
