#!/bin/bash

# Longhorn Samsung Portable SSD T5 Integration Validation Script
# Validates that Longhorn is properly configured to use Samsung Portable SSD T5 drives

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Check if kubectl is available and cluster is accessible
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    if ! kubectl get namespace longhorn-system &> /dev/null; then
        log_error "Longhorn namespace not found. Is Longhorn installed?"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Check Longhorn deployment status
check_longhorn_status() {
    log_info "Checking Longhorn deployment status..."
    
    # Check if Longhorn manager is running
    if ! kubectl get deployment longhorn-manager -n longhorn-system &> /dev/null; then
        log_error "Longhorn manager deployment not found"
        return 1
    fi
    
    local ready_replicas
    ready_replicas=$(kubectl get deployment longhorn-manager -n longhorn-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired_replicas
    desired_replicas=$(kubectl get deployment longhorn-manager -n longhorn-system -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    
    if [[ "$ready_replicas" != "$desired_replicas" ]]; then
        log_warning "Longhorn manager not fully ready ($ready_replicas/$desired_replicas replicas)"
    else
        log_success "Longhorn manager is running ($ready_replicas/$desired_replicas replicas)"
    fi
    
    # Check Longhorn driver
    local driver_ready
    driver_ready=$(kubectl get daemonset longhorn-driver-deployer -n longhorn-system -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
    local driver_desired
    driver_desired=$(kubectl get daemonset longhorn-driver-deployer -n longhorn-system -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "1")
    
    if [[ "$driver_ready" != "$driver_desired" ]]; then
        log_warning "Longhorn driver not fully ready ($driver_ready/$driver_desired pods)"
    else
        log_success "Longhorn driver is running ($driver_ready/$driver_desired pods)"
    fi
}

# Check Longhorn nodes and Samsung Portable SSD T5 disks
check_longhorn_nodes() {
    log_info "Checking Longhorn nodes and Samsung Portable SSD T5 disks..."
    
    local nodes
    nodes=$(kubectl get nodes.longhorn.io -n longhorn-system -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -z "$nodes" ]]; then
        log_error "No Longhorn nodes found"
        return 1
    fi
    
    log_success "Found Longhorn nodes: $nodes"
    
    # Check for Samsung Portable SSD T5 disks
    local ssd_disks=0
    local total_disks=0
    
    for node in $nodes; do
        log_info "Checking disks on node: $node"
        
        local node_disks
        node_disks=$(kubectl get disks.longhorn.io -n longhorn-system -l longhornnode="$node" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
        
        for disk in $node_disks; do
            total_disks=$((total_disks + 1))
            
            local disk_path
            disk_path=$(kubectl get disk.longhorn.io "$disk" -n longhorn-system -o jsonpath='{.spec.path}' 2>/dev/null || echo "")
            
            local disk_tags
            disk_tags=$(kubectl get disk.longhorn.io "$disk" -n longhorn-system -o jsonpath='{.spec.tags[*]}' 2>/dev/null || echo "")
            
            local disk_ready
            disk_ready=$(kubectl get disk.longhorn.io "$disk" -n longhorn-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
            
            log_info "  Disk: $disk"
            log_info "    Path: $disk_path"
            log_info "    Tags: $disk_tags"
            log_info "    Ready: $disk_ready"
            
            if [[ "$disk_path" == "/var/lib/longhorn-ssd" ]] && [[ "$disk_tags" == *"ssd"* ]]; then
                ssd_disks=$((ssd_disks + 1))
                if [[ "$disk_ready" == "True" ]]; then
                    log_success "    Samsung Portable SSD T5 disk is ready"
                else
                    log_warning "    Samsung Portable SSD T5 disk is not ready"
                fi
            fi
        done
    done
    
    log_info "Total disks found: $total_disks"
    log_info "Samsung Portable SSD T5 disks found: $ssd_disks"
    
    if [[ $ssd_disks -eq 0 ]]; then
        log_error "No Samsung Portable SSD T5 disks found with path '/var/lib/longhorn-ssd' and 'ssd' tag"
        return 1
    else
        log_success "Found $ssd_disks Samsung Portable SSD T5 disk(s)"
    fi
}

# Check storage classes
check_storage_classes() {
    log_info "Checking Longhorn storage classes..."
    
    # Check longhorn-ssd storage class
    if kubectl get storageclass longhorn-ssd &> /dev/null; then
        log_success "longhorn-ssd storage class exists"
        
        local disk_selector
        disk_selector=$(kubectl get storageclass longhorn-ssd -o jsonpath='{.parameters.diskSelector}' 2>/dev/null || echo "")
        
        if [[ "$disk_selector" == "ssd" ]]; then
            log_success "longhorn-ssd storage class has correct diskSelector: $disk_selector"
        else
            log_error "longhorn-ssd storage class has incorrect diskSelector: $disk_selector (expected: ssd)"
        fi
        
        local data_locality
        data_locality=$(kubectl get storageclass longhorn-ssd -o jsonpath='{.parameters.dataLocality}' 2>/dev/null || echo "")
        
        if [[ "$data_locality" == "strict-local" ]]; then
            log_success "longhorn-ssd storage class has optimal dataLocality: $data_locality"
        else
            log_warning "longhorn-ssd storage class dataLocality: $data_locality (recommended: strict-local)"
        fi
    else
        log_error "longhorn-ssd storage class not found"
        return 1
    fi
    
    # Check default longhorn storage class
    if kubectl get storageclass longhorn &> /dev/null; then
        log_success "Default longhorn storage class exists"
    else
        log_warning "Default longhorn storage class not found"
    fi
}

# Check volume snapshot classes
check_snapshot_classes() {
    log_info "Checking volume snapshot classes..."
    
    if kubectl get volumesnapshotclass longhorn-ssd-snapshot-vsc &> /dev/null; then
        log_success "longhorn-ssd-snapshot-vsc volume snapshot class exists"
    else
        log_warning "longhorn-ssd-snapshot-vsc volume snapshot class not found"
    fi
    
    if kubectl get volumesnapshotclass longhorn-snapshot-vsc &> /dev/null; then
        log_success "Default longhorn-snapshot-vsc volume snapshot class exists"
    else
        log_warning "Default longhorn-snapshot-vsc volume snapshot class not found"
    fi
}

# Test Samsung Portable SSD T5 storage functionality
test_usb_ssd_storage() {
    log_info "Testing Samsung Portable SSD T5 storage functionality..."
    
    local test_pvc="test-samsung-t5-ssd-$(date +%s)"
    local test_namespace="default"
    
    # Create test PVC
    log_info "Creating test PVC: $test_pvc"
    
    kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $test_pvc
  namespace: $test_namespace
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-ssd
  resources:
    requests:
      storage: 1Gi
EOF

    # Wait for PVC to bind
    log_info "Waiting for PVC to bind..."
    
    local timeout=120
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        local pvc_status
        pvc_status=$(kubectl get pvc "$test_pvc" -n "$test_namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        
        if [[ "$pvc_status" == "Bound" ]]; then
            log_success "Test PVC bound successfully"
            break
        elif [[ "$pvc_status" == "Pending" ]]; then
            log_info "PVC still pending... (${elapsed}s/${timeout}s)"
        else
            log_warning "PVC status: $pvc_status"
        fi
        
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    # Check final status
    local final_status
    final_status=$(kubectl get pvc "$test_pvc" -n "$test_namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    
    if [[ "$final_status" == "Bound" ]]; then
        log_success "Samsung Portable SSD T5 storage test successful"
        
        # Get volume details
        local pv_name
        pv_name=$(kubectl get pvc "$test_pvc" -n "$test_namespace" -o jsonpath='{.spec.volumeName}' 2>/dev/null || echo "")
        
        if [[ -n "$pv_name" ]]; then
            log_info "Created PersistentVolume: $pv_name"
            
            # Check if volume is on Samsung Portable SSD T5
            local volume_info
            volume_info=$(kubectl get pv "$pv_name" -o jsonpath='{.spec.csi.volumeAttributes}' 2>/dev/null || echo "")
            log_info "Volume attributes: $volume_info"
        fi
    else
        log_error "Samsung Portable SSD T5 storage test failed - PVC status: $final_status"
        
        # Show PVC events for debugging
        log_info "PVC events:"
        kubectl describe pvc "$test_pvc" -n "$test_namespace" | grep -A 10 "Events:" || true
    fi
    
    # Cleanup
    log_info "Cleaning up test PVC..."
    kubectl delete pvc "$test_pvc" -n "$test_namespace" --ignore-not-found=true
}

# Check Longhorn settings
check_longhorn_settings() {
    log_info "Checking Longhorn settings..."
    
    # Check if createDefaultDiskLabeledNodes is disabled
    local create_default_disks
    create_default_disks=$(kubectl get setting create-default-disk-labeled-nodes -n longhorn-system -o jsonpath='{.value}' 2>/dev/null || echo "true")
    
    if [[ "$create_default_disks" == "false" ]]; then
        log_success "createDefaultDiskLabeledNodes is disabled (correct for Samsung Portable SSD T5 setup)"
    else
        log_warning "createDefaultDiskLabeledNodes is enabled (should be false for Samsung Portable SSD T5 setup)"
    fi
    
    # Check storage over-provisioning
    local storage_over_provisioning
    storage_over_provisioning=$(kubectl get setting storage-over-provisioning-percentage -n longhorn-system -o jsonpath='{.value}' 2>/dev/null || echo "200")
    
    log_info "Storage over-provisioning percentage: $storage_over_provisioning%"
    
    if [[ $storage_over_provisioning -le 150 ]]; then
        log_success "Storage over-provisioning is optimized for SSDs"
    else
        log_warning "Storage over-provisioning might be too high for SSDs"
    fi
    
    # Check storage minimal available
    local storage_minimal
    storage_minimal=$(kubectl get setting storage-minimal-available-percentage -n longhorn-system -o jsonpath='{.value}' 2>/dev/null || echo "25")
    
    log_info "Storage minimal available percentage: $storage_minimal%"
    
    if [[ $storage_minimal -le 20 ]]; then
        log_success "Storage minimal available is optimized for SSDs"
    else
        log_warning "Storage minimal available might be too high for SSDs"
    fi
}

# Main validation function
main() {
    echo "=============================================="
    echo "Longhorn Samsung Portable SSD T5 Integration Validation"
    echo "=============================================="
    echo
    
    local exit_code=0
    
    # Run all checks
    check_prerequisites || exit_code=1
    echo
    
    check_longhorn_status || exit_code=1
    echo
    
    check_longhorn_nodes || exit_code=1
    echo
    
    check_storage_classes || exit_code=1
    echo
    
    check_snapshot_classes || exit_code=1
    echo
    
    check_longhorn_settings || exit_code=1
    echo
    
    test_usb_ssd_storage || exit_code=1
    echo
    
    # Summary
    echo "=============================================="
    if [[ $exit_code -eq 0 ]]; then
        log_success "All Longhorn Samsung Portable SSD T5 integration checks passed!"
        echo
        log_info "Your Longhorn setup is properly configured for Samsung Portable SSD T5 storage."
        log_info "You can now use the 'longhorn-ssd' storage class for high-performance workloads."
    else
        log_error "Some Longhorn Samsung Portable SSD T5 integration checks failed!"
        echo
        log_info "Please review the errors above and check:"
        log_info "1. Samsung Portable SSD T5 drives are properly connected and mounted"
        log_info "2. Talos Samsung Portable SSD T5 configuration is applied"
        log_info "3. Longhorn configuration is deployed correctly"
        log_info "4. All Longhorn components are running"
    fi
    echo "=============================================="
    
    exit $exit_code
}

# Run main function
main "$@"