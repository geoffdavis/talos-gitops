#!/bin/bash
# USB SSD Storage Validation Script for Talos Cluster
# Validates USB SSD detection, mounting, and Longhorn integration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NODES=("mini01" "mini02" "mini03")
MOUNT_POINT="/var/lib/longhorn-ssd"
MIN_SIZE_GB=100

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

# Validate Samsung Portable SSD T5 detection on a node
validate_usb_ssd_detection() {
    local node=$1
    log_info "Checking Samsung Portable SSD T5 detection on $node..."

    # Check for Samsung Portable SSD T5 devices
    local t5_devices
    t5_devices=$(talosctl -n "$node" ls /dev/disk/by-id/ | grep -E "usb-Samsung_Portable_SSD_T5.*[^0-9]$" || true)

    if [[ -z "$t5_devices" ]]; then
        log_warning "No Samsung Portable SSD T5 drives detected on $node"
        return 1
    fi

    echo "$t5_devices" | while read -r device; do
        if [[ -n "$device" ]]; then
            log_success "Samsung Portable SSD T5 found on $node: $device"

            # Get device details
            local real_device
            real_device=$(talosctl -n "$node" readlink "/dev/disk/by-id/$device" 2>/dev/null || echo "")
            if [[ -n "$real_device" ]]; then
                local device_name
                device_name=$(basename "$real_device")

                # Check device model
                local model
                model=$(talosctl -n "$node" cat "/sys/block/$device_name/device/model" 2>/dev/null | tr -d ' ' || echo "unknown")
                log_info "Device model: $model"

                # Verify it's actually a T5
                if [[ "$model" == *"PortableSSDT5"* ]] || [[ "$model" == *"T5"* ]]; then
                    log_success "Confirmed Samsung Portable SSD T5 model"
                else
                    log_warning "Model verification failed (expected T5, got: $model)"
                fi

                # Check device size
                local size_sectors
                size_sectors=$(talosctl -n "$node" cat "/sys/block/$device_name/size" 2>/dev/null || echo "0")
                local size_gb=$((size_sectors * 512 / 1024 / 1024 / 1024))

                if [[ $size_gb -gt $MIN_SIZE_GB ]]; then
                    log_success "Samsung Portable SSD T5 size on $node: ${size_gb}GB (meets minimum requirement)"
                else
                    log_warning "Samsung Portable SSD T5 on $node is only ${size_gb}GB (below ${MIN_SIZE_GB}GB minimum)"
                fi
            fi
        fi
    done
}

# Validate Samsung Portable SSD T5 mounting on a node
validate_usb_ssd_mounting() {
    local node=$1
    log_info "Checking Samsung Portable SSD T5 mounting on $node..."

    # Check if mount point exists
    if ! talosctl -n "$node" ls "$MOUNT_POINT" &>/dev/null; then
        log_error "Mount point $MOUNT_POINT does not exist on $node"
        return 1
    fi

    # Check if mount point is mounted
    local mount_info
    mount_info=$(talosctl -n "$node" df | grep "$MOUNT_POINT" || true)

    if [[ -z "$mount_info" ]]; then
        log_warning "Samsung Portable SSD T5 not mounted at $MOUNT_POINT on $node"
        return 1
    fi

    log_success "Samsung Portable SSD T5 mounted on $node: $mount_info"

    # Check filesystem type
    local fs_type
    fs_type=$(echo "$mount_info" | awk '{print $1}' | xargs -I {} talosctl -n "$node" blkid {} 2>/dev/null | grep -o 'TYPE="[^"]*"' | cut -d'"' -f2 || echo "unknown")

    if [[ "$fs_type" == "ext4" ]]; then
        log_success "Filesystem type on $node: $fs_type"
    else
        log_warning "Unexpected filesystem type on $node: $fs_type (expected ext4)"
    fi
}

# Validate I/O scheduler settings
validate_io_scheduler() {
    local node=$1
    log_info "Checking I/O scheduler settings on $node..."

    # Find Samsung Portable SSD T5 devices
    local t5_devices
    t5_devices=$(talosctl -n "$node" ls /dev/disk/by-id/ | grep -E "usb-Samsung_Portable_SSD_T5.*[^0-9]$" || true)

    if [[ -z "$t5_devices" ]]; then
        log_warning "No Samsung Portable SSD T5 devices found for scheduler check on $node"
        return 1
    fi

    echo "$t5_devices" | while read -r device; do
        if [[ -n "$device" ]]; then
            local real_device
            real_device=$(talosctl -n "$node" readlink "/dev/disk/by-id/$device" 2>/dev/null || echo "")
            if [[ -n "$real_device" ]]; then
                local device_name
                device_name=$(basename "$real_device")

                # Check I/O scheduler
                local scheduler
                scheduler=$(talosctl -n "$node" cat "/sys/block/$device_name/queue/scheduler" 2>/dev/null | grep -o '\[.*\]' | tr -d '[]' || echo "unknown")

                if [[ "$scheduler" == "mq-deadline" ]]; then
                    log_success "I/O scheduler on $node ($device_name): $scheduler"
                else
                    log_warning "Suboptimal I/O scheduler on $node ($device_name): $scheduler (expected mq-deadline)"
                fi

                # Check rotational setting
                local rotational
                rotational=$(talosctl -n "$node" cat "/sys/block/$device_name/queue/rotational" 2>/dev/null || echo "1")

                if [[ "$rotational" == "0" ]]; then
                    log_success "SSD detection on $node ($device_name): non-rotational"
                else
                    log_warning "Device on $node ($device_name) marked as rotational (expected non-rotational for SSD)"
                fi
            fi
        fi
    done
}

# Validate Longhorn disk discovery
validate_longhorn_disks() {
    log_info "Checking Longhorn disk discovery..."

    # Check if Longhorn namespace exists
    if ! kubectl get namespace longhorn-system &>/dev/null; then
        log_error "Longhorn namespace not found. Is Longhorn installed?"
        return 1
    fi

    # Check Longhorn nodes
    local longhorn_nodes
    longhorn_nodes=$(kubectl get nodes.longhorn.io -n longhorn-system -o name 2>/dev/null || true)

    if [[ -z "$longhorn_nodes" ]]; then
        log_error "No Longhorn nodes found"
        return 1
    fi

    log_success "Longhorn nodes found: $(echo "$longhorn_nodes" | wc -l)"

    # Check for SSD-tagged disks
    for node in "${NODES[@]}"; do
        log_info "Checking Longhorn disks on $node..."

        local node_disks
        node_disks=$(kubectl get nodes.longhorn.io "$node" -n longhorn-system -o jsonpath='{.spec.disks}' 2>/dev/null || echo "{}")

        if [[ "$node_disks" == "{}" ]]; then
            log_warning "No disks configured in Longhorn for $node"
            continue
        fi

        # Check for SSD-tagged disks
        local ssd_disks
        ssd_disks=$(kubectl get nodes.longhorn.io "$node" -n longhorn-system -o jsonpath='{.spec.disks}' 2>/dev/null | jq -r 'to_entries[] | select(.value.tags[]? == "ssd") | .key' 2>/dev/null || true)

        if [[ -n "$ssd_disks" ]]; then
            log_success "SSD-tagged disks found on $node: $ssd_disks"
        else
            log_warning "No SSD-tagged disks found on $node"
        fi
    done
}

# Validate storage class
validate_storage_class() {
    log_info "Checking longhorn-ssd storage class..."

    if ! kubectl get storageclass longhorn-ssd &>/dev/null; then
        log_error "longhorn-ssd storage class not found"
        return 1
    fi

    local disk_selector
    disk_selector=$(kubectl get storageclass longhorn-ssd -o jsonpath='{.parameters.diskSelector}' 2>/dev/null || echo "")

    if [[ "$disk_selector" == "ssd" ]]; then
        log_success "Storage class longhorn-ssd has correct diskSelector: $disk_selector"
    else
        log_warning "Storage class longhorn-ssd has unexpected diskSelector: $disk_selector (expected 'ssd')"
    fi
}

# Test storage functionality
test_storage_functionality() {
    log_info "Testing storage functionality with a test PVC..."

    # Create test PVC
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: usb-ssd-test
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-ssd
  resources:
    requests:
      storage: 1Gi
EOF

    # Wait for PVC to be bound
    log_info "Waiting for test PVC to be bound..."
    if kubectl wait --for=condition=Bound pvc/usb-ssd-test --timeout=60s &>/dev/null; then
        log_success "Test PVC successfully bound to USB SSD storage"

        # Clean up test PVC
        kubectl delete pvc usb-ssd-test &>/dev/null || true
    else
        log_error "Test PVC failed to bind within 60 seconds"
        kubectl delete pvc usb-ssd-test &>/dev/null || true
        return 1
    fi
}

# Main validation function
main() {
    log_info "Starting Samsung Portable SSD T5 storage validation..."
    echo

    # Check prerequisites
    check_talosctl
    check_kubectl
    echo

    # Validate each node
    local node_errors=0
    for node in "${NODES[@]}"; do
        log_info "=== Validating node: $node ==="

        if ! validate_usb_ssd_detection "$node"; then
            ((node_errors++))
        fi

        if ! validate_usb_ssd_mounting "$node"; then
            ((node_errors++))
        fi

        if ! validate_io_scheduler "$node"; then
            ((node_errors++))
        fi

        echo
    done

    # Validate Longhorn integration
    log_info "=== Validating Longhorn integration ==="
    local longhorn_errors=0

    if ! validate_longhorn_disks; then
        ((longhorn_errors++))
    fi

    if ! validate_storage_class; then
        ((longhorn_errors++))
    fi

    if ! test_storage_functionality; then
        ((longhorn_errors++))
    fi

    echo

    # Summary
    log_info "=== Validation Summary ==="
    if [[ $node_errors -eq 0 && $longhorn_errors -eq 0 ]]; then
        log_success "All Samsung Portable SSD T5 storage validations passed!"
        exit 0
    else
        if [[ $node_errors -gt 0 ]]; then
            log_error "Node validation issues found: $node_errors"
        fi
        if [[ $longhorn_errors -gt 0 ]]; then
            log_error "Longhorn integration issues found: $longhorn_errors"
        fi
        log_error "Samsung Portable SSD T5 storage validation completed with errors"
        exit 1
    fi
}

# Run main function
main "$@"
