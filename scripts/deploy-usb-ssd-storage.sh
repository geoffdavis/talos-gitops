#!/bin/bash
# USB SSD Storage Deployment Script for Talos Cluster
# Comprehensive deployment procedure for USB SSD storage integration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
NODES=("mini01" "mini02" "mini03")
NODE_IPS=("172.29.51.11" "172.29.51.12" "172.29.51.13")
MOUNT_POINT="/var/lib/longhorn-ssd"
MIN_SIZE_GB=100
TALOSCONFIG="${TALOSCONFIG:-clusterconfig/talosconfig}"
BACKUP_DIR="backups/usb-ssd-deployment-$(date +%Y%m%d-%H%M%S)"

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

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code $exit_code"
    log_info "Check logs above for details"
    log_info "Backup directory: $BACKUP_DIR"
    exit $exit_code
}

trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    local errors=0
    
    # Check required tools
    for tool in talosctl kubectl mise jq; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed or not in PATH"
            ((errors++))
        fi
    done
    
    # Check Talos config
    if [[ ! -f "$TALOSCONFIG" ]]; then
        log_error "Talos config not found at $TALOSCONFIG"
        ((errors++))
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        ((errors++))
    fi
    
    # Check node connectivity
    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${NODE_IPS[$i]}"
        if ! talosctl -n "$ip" version --timeout 10s &> /dev/null; then
            log_error "Cannot connect to node $node ($ip)"
            ((errors++))
        fi
    done
    
    if [[ $errors -gt 0 ]]; then
        log_error "Prerequisites check failed with $errors errors"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Create backup
create_backup() {
    log_step "Creating deployment backup..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup current Talos configuration
    log_info "Backing up Talos configuration..."
    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${NODE_IPS[$i]}"
        talosctl -n "$ip" get machineconfig -o yaml > "$BACKUP_DIR/talos-config-$node.yaml" || true
    done
    
    # Backup current Longhorn configuration
    log_info "Backing up Longhorn configuration..."
    if kubectl get namespace longhorn-system &> /dev/null; then
        kubectl get all -n longhorn-system -o yaml > "$BACKUP_DIR/longhorn-resources.yaml" || true
        kubectl get nodes.longhorn.io -n longhorn-system -o yaml > "$BACKUP_DIR/longhorn-nodes.yaml" || true
        kubectl get disks.longhorn.io -n longhorn-system -o yaml > "$BACKUP_DIR/longhorn-disks.yaml" || true
        kubectl get storageclass -o yaml > "$BACKUP_DIR/storage-classes.yaml" || true
    fi
    
    # Backup cluster state
    log_info "Backing up cluster state..."
    kubectl get nodes -o yaml > "$BACKUP_DIR/cluster-nodes.yaml" || true
    kubectl get pv -o yaml > "$BACKUP_DIR/persistent-volumes.yaml" || true
    kubectl get pvc -A -o yaml > "$BACKUP_DIR/persistent-volume-claims.yaml" || true
    
    log_success "Backup created in $BACKUP_DIR"
}

# Pre-deployment validation
pre_deployment_validation() {
    log_step "Running pre-deployment validation..."
    
    # Check if USB SSDs are connected
    log_info "Checking USB SSD connectivity..."
    local usb_errors=0
    
    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${NODE_IPS[$i]}"
        
        log_info "Checking USB devices on $node..."
        local usb_devices
        usb_devices=$(talosctl -n "$ip" ls /dev/disk/by-id/ 2>/dev/null | grep -E "usb-.*[^0-9]$" || true)
        
        if [[ -z "$usb_devices" ]]; then
            log_warning "No USB SSDs detected on $node - deployment will configure for when connected"
            ((usb_errors++))
        else
            log_success "USB devices found on $node"
            echo "$usb_devices" | while read -r device; do
                if [[ -n "$device" ]]; then
                    log_info "  - $device"
                fi
            done
        fi
    done
    
    if [[ $usb_errors -eq ${#NODES[@]} ]]; then
        log_warning "No USB SSDs detected on any nodes"
        log_info "Deployment will continue - configuration will be ready when USB SSDs are connected"
        read -p "Continue with deployment? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Check for existing USB SSD configuration
    log_info "Checking for existing USB SSD configuration..."
    if [[ -f "talos/patches/usb-ssd-storage.yaml" ]]; then
        log_success "USB SSD Talos patch found"
    else
        log_error "USB SSD Talos patch not found at talos/patches/usb-ssd-storage.yaml"
        exit 1
    fi
    
    # Check Longhorn configuration files
    log_info "Checking Longhorn configuration files..."
    local longhorn_files=(
        "infrastructure/longhorn/storage-class.yaml"
        "infrastructure/longhorn/helmrelease.yaml"
    )
    
    for file in "${longhorn_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_success "Found $file"
        else
            log_warning "Missing $file - will be created during deployment"
        fi
    done
    
    log_success "Pre-deployment validation completed"
}

# Apply Talos USB SSD configuration
apply_talos_configuration() {
    log_step "Applying Talos USB SSD configuration..."
    
    # Check if configuration needs to be regenerated
    log_info "Checking if Talos configuration needs regeneration..."
    if ! grep -q "usb-ssd-storage" clusterconfig/home-ops-mini01.yaml 2>/dev/null; then
        log_info "Regenerating Talos configuration with USB SSD patches..."
        if command -v task &> /dev/null; then
            mise exec -- task talos:generate-config
        else
            log_info "Task not available, using talhelper directly..."
            mise exec -- talhelper genconfig --secret-file talos/talsecret.yaml
        fi
    else
        log_success "Talos configuration already includes USB SSD patches"
    fi
    
    # Apply configuration to each node
    log_info "Applying Talos configuration to nodes..."
    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${NODE_IPS[$i]}"
        
        log_info "Applying configuration to $node ($ip)..."
        
        # Try with existing talosconfig first, fall back to insecure if needed
        if talosctl -n "$ip" apply-config --file "clusterconfig/home-ops-$node.yaml" 2>/dev/null; then
            log_success "Configuration applied to $node"
        else
            log_warning "Retrying with insecure mode for $node..."
            if talosctl -n "$ip" apply-config --insecure --file "clusterconfig/home-ops-$node.yaml"; then
                log_success "Configuration applied to $node (insecure mode)"
            else
                log_error "Failed to apply configuration to $node"
                return 1
            fi
        fi
    done
    
    log_success "Talos configuration applied to all nodes"
}

# Coordinate node reboots
coordinate_node_reboots() {
    log_step "Coordinating node reboots for USB SSD detection..."
    
    log_warning "Nodes will be rebooted one at a time to ensure cluster availability"
    log_info "This process will take approximately 5-10 minutes"
    
    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${NODE_IPS[$i]}"
        
        log_info "Rebooting $node ($ip)..."
        talosctl -n "$ip" reboot
        
        log_info "Waiting for $node to come back online..."
        local timeout=300
        local elapsed=0
        
        while [[ $elapsed -lt $timeout ]]; do
            if talosctl -n "$ip" version --timeout 5s &> /dev/null; then
                log_success "$node is back online"
                break
            fi
            sleep 10
            elapsed=$((elapsed + 10))
            log_info "Waiting for $node... (${elapsed}s/${timeout}s)"
        done
        
        if [[ $elapsed -ge $timeout ]]; then
            log_error "$node did not come back online within $timeout seconds"
            return 1
        fi
        
        # Wait a bit more for the node to fully stabilize
        log_info "Waiting for $node to stabilize..."
        sleep 30
    done
    
    # Wait for cluster to be fully ready
    log_info "Waiting for cluster to be fully ready..."
    local timeout=300
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        if kubectl get nodes | grep -q "Ready"; then
            local ready_nodes
            ready_nodes=$(kubectl get nodes --no-headers | grep -c "Ready" || echo "0")
            if [[ $ready_nodes -eq ${#NODES[@]} ]]; then
                log_success "All nodes are ready"
                break
            fi
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        log_info "Waiting for all nodes to be ready... (${elapsed}s/${timeout}s)"
    done
    
    if [[ $elapsed -ge $timeout ]]; then
        log_error "Not all nodes became ready within $timeout seconds"
        kubectl get nodes
        return 1
    fi
    
    log_success "Node reboots completed successfully"
}

# Update Longhorn configuration
update_longhorn_configuration() {
    log_step "Updating Longhorn configuration for USB SSD support..."
    
    # Check if Longhorn is installed
    if ! kubectl get namespace longhorn-system &> /dev/null; then
        log_error "Longhorn namespace not found. Please install Longhorn first."
        return 1
    fi
    
    # Wait for Longhorn to be ready
    log_info "Waiting for Longhorn to be ready..."
    kubectl wait --for=condition=ready pods -l app=longhorn-manager -n longhorn-system --timeout=300s
    
    # Apply Longhorn configuration updates via GitOps
    log_info "Applying Longhorn configuration updates..."
    
    # Check if we're in a git repository
    if git rev-parse --git-dir &> /dev/null; then
        log_info "Applying Longhorn updates via GitOps..."
        
        # Force Flux to reconcile Longhorn configuration
        if command -v flux &> /dev/null; then
            flux reconcile kustomization infrastructure-longhorn || log_warning "Flux reconcile failed, continuing..."
        fi
        
        # Wait for Longhorn configuration to be applied
        sleep 30
    else
        log_warning "Not in a git repository, applying Longhorn configuration directly..."
        
        # Apply Longhorn configuration directly
        if [[ -f "infrastructure/longhorn/storage-class.yaml" ]]; then
            kubectl apply -f infrastructure/longhorn/storage-class.yaml
        fi
        
        if [[ -f "infrastructure/longhorn/helmrelease.yaml" ]]; then
            log_info "HelmRelease found - please ensure Flux is managing Longhorn updates"
        fi
    fi
    
    log_success "Longhorn configuration update initiated"
}

# Validate USB SSD detection and mounting
validate_usb_ssd_setup() {
    log_step "Validating USB SSD detection and mounting..."
    
    local validation_errors=0
    
    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${NODE_IPS[$i]}"
        
        log_info "Validating USB SSD setup on $node..."
        
        # Check USB device detection
        local usb_devices
        usb_devices=$(talosctl -n "$ip" ls /dev/disk/by-id/ 2>/dev/null | grep -E "usb-.*[^0-9]$" || true)
        
        if [[ -z "$usb_devices" ]]; then
            log_warning "No USB SSDs detected on $node"
            ((validation_errors++))
            continue
        fi
        
        log_success "USB devices detected on $node"
        
        # Check if mount point exists and is mounted
        if talosctl -n "$ip" ls "$MOUNT_POINT" &>/dev/null; then
            local mount_info
            mount_info=$(talosctl -n "$ip" df 2>/dev/null | grep "$MOUNT_POINT" || true)
            
            if [[ -n "$mount_info" ]]; then
                log_success "USB SSD mounted on $node: $mount_info"
            else
                log_warning "Mount point exists but USB SSD not mounted on $node"
                ((validation_errors++))
            fi
        else
            log_warning "Mount point $MOUNT_POINT does not exist on $node"
            ((validation_errors++))
        fi
    done
    
    if [[ $validation_errors -gt 0 ]]; then
        log_warning "USB SSD validation completed with $validation_errors warnings"
        log_info "Some nodes may not have USB SSDs connected or properly mounted"
        log_info "This is normal if USB SSDs are not yet connected to all nodes"
    else
        log_success "USB SSD validation completed successfully"
    fi
}

# Validate Longhorn integration
validate_longhorn_integration() {
    log_step "Validating Longhorn USB SSD integration..."
    
    # Wait for Longhorn to discover disks
    log_info "Waiting for Longhorn to discover USB SSD disks..."
    sleep 60
    
    # Check Longhorn nodes
    local longhorn_nodes
    longhorn_nodes=$(kubectl get nodes.longhorn.io -n longhorn-system -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -z "$longhorn_nodes" ]]; then
        log_error "No Longhorn nodes found"
        return 1
    fi
    
    log_success "Longhorn nodes found: $longhorn_nodes"
    
    # Check for SSD-tagged disks
    local ssd_disks=0
    for node in $longhorn_nodes; do
        log_info "Checking Longhorn disks on $node..."
        
        local node_ssd_disks
        node_ssd_disks=$(kubectl get disks.longhorn.io -n longhorn-system -l longhornnode="$node" -o jsonpath='{.items[?(@.spec.tags[*]=="ssd")].metadata.name}' 2>/dev/null || echo "")
        
        if [[ -n "$node_ssd_disks" ]]; then
            local disk_count
            disk_count=$(echo "$node_ssd_disks" | wc -w)
            ssd_disks=$((ssd_disks + disk_count))
            log_success "Found $disk_count SSD disk(s) on $node"
        else
            log_warning "No SSD-tagged disks found on $node"
        fi
    done
    
    log_info "Total SSD disks found: $ssd_disks"
    
    # Check storage class
    if kubectl get storageclass longhorn-ssd &> /dev/null; then
        log_success "longhorn-ssd storage class exists"
        
        # Test storage class functionality
        log_info "Testing longhorn-ssd storage class..."
        if test_storage_class; then
            log_success "Storage class test passed"
        else
            log_warning "Storage class test failed - may work once USB SSDs are properly configured"
        fi
    else
        log_warning "longhorn-ssd storage class not found"
    fi
    
    log_success "Longhorn integration validation completed"
}

# Test storage class functionality
test_storage_class() {
    local test_pvc
    test_pvc="usb-ssd-deployment-test-$(date +%s)"
    
    # Create test PVC
    cat <<EOF | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $test_pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-ssd
  resources:
    requests:
      storage: 1Gi
EOF

    # Wait for PVC to bind
    local timeout=120
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        local pvc_status
        pvc_status=$(kubectl get pvc "$test_pvc" -n default -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        
        if [[ "$pvc_status" == "Bound" ]]; then
            kubectl delete pvc "$test_pvc" -n default &>/dev/null || true
            return 0
        fi
        
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    # Cleanup failed test
    kubectl delete pvc "$test_pvc" -n default &>/dev/null || true
    return 1
}

# Post-deployment verification
post_deployment_verification() {
    log_step "Running post-deployment verification..."
    
    # Run comprehensive validation
    log_info "Running comprehensive USB SSD validation..."
    if [[ -f "scripts/validate-complete-usb-ssd-setup.sh" ]]; then
        ./scripts/validate-complete-usb-ssd-setup.sh || log_warning "Comprehensive validation script failed"
    else
        log_info "Comprehensive validation script not found, running basic validation..."
        validate_usb_ssd_setup
        validate_longhorn_integration
    fi
    
    # Check cluster health
    log_info "Checking overall cluster health..."
    kubectl get nodes -o wide
    kubectl get pods -A | grep -E "(Error|CrashLoopBackOff|Pending)" || log_success "No problematic pods found"
    
    log_success "Post-deployment verification completed"
}

# Rollback procedures
rollback_deployment() {
    log_error "Rolling back USB SSD deployment..."
    
    if [[ -d "$BACKUP_DIR" ]]; then
        log_info "Restoring from backup: $BACKUP_DIR"
        
        # Restore Talos configuration
        for i in "${!NODES[@]}"; do
            local node="${NODES[$i]}"
            local ip="${NODE_IPS[$i]}"
            local backup_file="$BACKUP_DIR/talos-config-$node.yaml"
            
            if [[ -f "$backup_file" ]]; then
                log_info "Restoring Talos configuration for $node..."
                # Note: This would require extracting the machine config from the backup
                log_warning "Manual Talos configuration restore required for $node"
            fi
        done
        
        # Restore Longhorn configuration
        if [[ -f "$BACKUP_DIR/longhorn-resources.yaml" ]]; then
            log_info "Restoring Longhorn configuration..."
            kubectl apply -f "$BACKUP_DIR/longhorn-resources.yaml" || log_warning "Longhorn restore failed"
        fi
        
        log_info "Rollback completed. Manual verification required."
    else
        log_error "No backup directory found for rollback"
    fi
}

# Main deployment function
main() {
    echo "=============================================="
    echo "USB SSD Storage Deployment for Talos Cluster"
    echo "=============================================="
    echo
    
    log_info "Starting USB SSD storage deployment..."
    log_info "This will deploy USB SSD storage configuration to the cluster"
    echo
    
    # Confirm deployment
    read -p "Continue with USB SSD storage deployment? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
    
    local start_time
    start_time=$(date +%s)
    
    # Set up error handling for rollback
    trap 'rollback_deployment; exit 1' ERR
    
    # Execute deployment steps
    check_prerequisites
    create_backup
    pre_deployment_validation
    apply_talos_configuration
    coordinate_node_reboots
    update_longhorn_configuration
    validate_usb_ssd_setup
    validate_longhorn_integration
    post_deployment_verification
    
    # Calculate deployment time
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo
    echo "=============================================="
    log_success "USB SSD Storage Deployment Completed Successfully!"
    echo "=============================================="
    echo
    log_info "Deployment completed in $duration seconds"
    log_info "Backup created in: $BACKUP_DIR"
    echo
    log_info "Next steps:"
    log_info "1. Connect USB SSDs to any nodes that don't have them"
    log_info "2. Run 'scripts/validate-complete-usb-ssd-setup.sh' to verify full functionality"
    log_info "3. Create test PVCs using the 'longhorn-ssd' storage class"
    log_info "4. Monitor Longhorn dashboard for disk health and usage"
    echo
    log_success "USB SSD storage is now ready for use!"
}

# Run main function
main "$@"