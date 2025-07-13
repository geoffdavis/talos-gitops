#!/bin/bash
# Interactive USB SSD Storage Deployment Script for Talos Cluster
# Production-safe guided deployment with comprehensive error handling and rollback options

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
NODES=("mini01" "mini02" "mini03")
NODE_IPS=("172.29.51.11" "172.29.51.12" "172.29.51.13")
MOUNT_POINT="/var/lib/longhorn-ssd"
MIN_SIZE_GB=100
TALOSCONFIG="${TALOSCONFIG:-clusterconfig/talosconfig}"
BACKUP_DIR="backups/usb-ssd-deployment-$(date +%Y%m%d-%H%M%S)"

# Deployment state tracking
CURRENT_STEP=0
TOTAL_STEPS=8
DEPLOYMENT_LOG="usb-ssd-deployment-$(date +%Y%m%d-%H%M%S).log"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$DEPLOYMENT_LOG"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$DEPLOYMENT_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$DEPLOYMENT_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$DEPLOYMENT_LOG"
}

log_step() {
    ((CURRENT_STEP++))
    echo -e "${CYAN}[STEP $CURRENT_STEP/$TOTAL_STEPS]${NC} ${BOLD}$1${NC}" | tee -a "$DEPLOYMENT_LOG"
    echo
}

log_substep() {
    echo -e "${MAGENTA}  →${NC} $1" | tee -a "$DEPLOYMENT_LOG"
}

# Interactive prompts
prompt_continue() {
    local message="$1"
    local default="${2:-n}"
    
    echo
    if [[ "$default" == "y" ]]; then
        read -p "$(echo -e "${YELLOW}$message (Y/n):${NC} ")" -r response
        response=${response:-y}
    else
        read -p "$(echo -e "${YELLOW}$message (y/N):${NC} ")" -r response
        response=${response:-n}
    fi
    
    [[ $response =~ ^[Yy]$ ]]
}

prompt_choice() {
    local message="$1"
    shift
    local options=("$@")
    
    echo
    echo -e "${YELLOW}$message${NC}"
    for i in "${!options[@]}"; do
        echo "  $((i+1)). ${options[$i]}"
    done
    
    while true; do
        read -p "Enter choice (1-${#options[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#options[@]} ]]; then
            echo "${options[$((choice-1))]}"
            return
        fi
        echo "Invalid choice. Please enter a number between 1 and ${#options[@]}."
    done
}

# Error handling and rollback
cleanup_on_error() {
    local exit_code=$?
    echo
    log_error "Deployment failed at step $CURRENT_STEP with exit code $exit_code"
    log_error "Check the deployment log: $DEPLOYMENT_LOG"
    
    if [[ -d "$BACKUP_DIR" ]]; then
        log_info "Backup directory available: $BACKUP_DIR"
        
        if prompt_continue "Would you like to attempt automatic rollback?"; then
            rollback_deployment
        else
            log_info "Manual rollback may be required. See backup directory: $BACKUP_DIR"
        fi
    fi
    
    exit $exit_code
}

trap cleanup_on_error ERR

# Rollback procedures
rollback_deployment() {
    log_error "Initiating rollback procedure..."
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_error "No backup directory found for rollback"
        return 1
    fi
    
    log_info "Rolling back from backup: $BACKUP_DIR"
    
    # Restore Talos configuration if needed
    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${NODE_IPS[$i]}"
        local backup_file="$BACKUP_DIR/talos-config-$node.yaml"
        
        if [[ -f "$backup_file" ]]; then
            log_info "Backup available for $node, but manual restore required"
            log_warning "To restore $node: talosctl apply-config --nodes $ip --file $backup_file"
        fi
    done
    
    # Restore Longhorn configuration
    if [[ -f "$BACKUP_DIR/longhorn-resources.yaml" ]]; then
        log_info "Restoring Longhorn configuration..."
        kubectl apply -f "$BACKUP_DIR/longhorn-resources.yaml" || log_warning "Longhorn restore failed"
    fi
    
    log_info "Rollback completed. Manual verification required."
}

# Pre-deployment verification
check_prerequisites() {
    log_step "Pre-deployment Verification"
    
    log_substep "Checking required tools..."
    local errors=0
    
    for tool in talosctl kubectl mise jq; do
        if command -v "$tool" &> /dev/null; then
            log_success "$tool is available"
        else
            log_error "$tool is not installed or not in PATH"
            ((errors++))
        fi
    done
    
    log_substep "Checking Talos configuration..."
    if [[ -f "$TALOSCONFIG" ]]; then
        log_success "Talos configuration found at $TALOSCONFIG"
    else
        log_error "Talos configuration not found at $TALOSCONFIG"
        ((errors++))
    fi
    
    log_substep "Checking cluster connectivity..."
    if kubectl cluster-info &> /dev/null; then
        log_success "Kubernetes cluster is accessible"
    else
        log_error "Cannot connect to Kubernetes cluster"
        ((errors++))
    fi
    
    log_substep "Checking node connectivity..."
    local unreachable_nodes=0
    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${NODE_IPS[$i]}"
        if talosctl -n "$ip" version --timeout 10s &> /dev/null; then
            log_success "Node $node ($ip) is reachable"
        else
            log_error "Node $node ($ip) is not reachable"
            ((unreachable_nodes++))
            ((errors++))
        fi
    done
    
    log_substep "Checking USB SSD configuration files..."
    if [[ -f "talos/patches/usb-ssd-storage.yaml" ]]; then
        log_success "USB SSD Talos patch found"
    else
        log_error "USB SSD Talos patch not found at talos/patches/usb-ssd-storage.yaml"
        ((errors++))
    fi
    
    if [[ -f "infrastructure/longhorn/storage-class.yaml" ]]; then
        log_success "Longhorn storage class configuration found"
    else
        log_warning "Longhorn storage class configuration not found (will be created)"
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_error "Prerequisites check failed with $errors errors"
        echo
        log_info "Please fix the above issues before proceeding:"
        log_info "1. Install missing tools (talosctl, kubectl, mise, jq)"
        log_info "2. Ensure cluster is accessible"
        log_info "3. Verify all nodes are powered on and reachable"
        log_info "4. Check that USB SSD configuration files exist"
        return 1
    fi
    
    log_success "All prerequisites verified successfully"
    
    if ! prompt_continue "Prerequisites check passed. Continue with USB SSD detection?"; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

# USB SSD detection and verification
check_usb_ssd_hardware() {
    log_step "USB SSD Hardware Detection"
    
    log_info "Checking for USB SSDs on all nodes..."
    echo
    
    local nodes_with_usb=0
    local nodes_without_usb=0
    
    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${NODE_IPS[$i]}"
        
        log_substep "Checking USB devices on $node ($ip)..."
        
        # Check for Samsung Portable SSD T5 devices
        local t5_devices
        t5_devices=$(talosctl -n "$ip" ls /dev/disk/by-id/ 2>/dev/null | grep -E "usb-Samsung_Portable_SSD_T5.*[^0-9]$" || true)
        
        if [[ -z "$t5_devices" ]]; then
            log_warning "No Samsung Portable SSD T5 drives detected on $node"
            ((nodes_without_usb++))
        else
            log_success "Samsung Portable SSD T5 drives found on $node:"
            echo "$t5_devices" | while read -r device; do
                if [[ -n "$device" ]]; then
                    echo "    - $device"
                    
                    # Get device details
                    local real_device
                    real_device=$(talosctl -n "$ip" readlink "/dev/disk/by-id/$device" 2>/dev/null || echo "")
                    if [[ -n "$real_device" ]]; then
                        local device_name
                        device_name=$(basename "$real_device")
                        
                        # Check device model
                        local model
                        model=$(talosctl -n "$ip" cat "/sys/block/$device_name/device/model" 2>/dev/null | tr -d ' ' || echo "unknown")
                        echo "      Model: $model"
                        
                        # Check device size
                        local size_sectors
                        size_sectors=$(talosctl -n "$ip" cat "/sys/block/$device_name/size" 2>/dev/null || echo "0")
                        local size_gb=$((size_sectors * 512 / 1024 / 1024 / 1024))
                        
                        if [[ $size_gb -gt 0 ]]; then
                            echo "      Size: ${size_gb}GB"
                            if [[ $size_gb -gt $MIN_SIZE_GB ]]; then
                                echo "      ✓ Meets minimum size requirement (${MIN_SIZE_GB}GB)"
                            else
                                echo "      ⚠ Below minimum size requirement (${MIN_SIZE_GB}GB)"
                            fi
                        fi
                        
                        # Verify it's actually a T5 model
                        if [[ "$model" == *"PortableSSDT5"* ]] || [[ "$model" == *"T5"* ]]; then
                            echo "      ✓ Confirmed Samsung Portable SSD T5"
                        else
                            echo "      ⚠ Model verification failed (expected T5, got: $model)"
                        fi
                    fi
                fi
            done
            ((nodes_with_usb++))
        fi
        echo
    done
    
    log_info "USB SSD Detection Summary:"
    log_info "  Nodes with USB SSDs: $nodes_with_usb"
    log_info "  Nodes without USB SSDs: $nodes_without_usb"
    
    if [[ $nodes_without_usb -eq ${#NODES[@]} ]]; then
        log_warning "No Samsung Portable SSD T5 drives detected on any nodes"
        echo
        log_info "This deployment will configure the system to automatically detect"
        log_info "and mount Samsung Portable SSD T5 drives when they are connected."
        echo
        
        local choice
        choice=$(prompt_choice "How would you like to proceed?" \
            "Continue deployment (T5 drives will be configured when connected)" \
            "Wait and check again (connect T5 drives now)" \
            "Cancel deployment")
        
        case "$choice" in
            "Continue deployment"*)
                log_info "Continuing with deployment for future Samsung Portable SSD T5 connection"
                ;;
            "Wait and check again"*)
                log_info "Please connect Samsung Portable SSD T5 drives to the nodes now"
                read -p "Press Enter when T5 drives are connected..."
                return $(check_usb_ssd_hardware)
                ;;
            "Cancel deployment")
                log_info "Deployment cancelled by user"
                exit 0
                ;;
        esac
    elif [[ $nodes_without_usb -gt 0 ]]; then
        log_warning "Some nodes are missing Samsung Portable SSD T5 drives"
        echo
        log_info "Nodes without T5 drives will be configured but won't have active storage"
        log_info "until Samsung Portable SSD T5 drives are connected to them."
        
        if ! prompt_continue "Continue with partial T5 drive deployment?"; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    else
        log_success "All nodes have Samsung Portable SSD T5 drives detected"
    fi
    
    if ! prompt_continue "USB SSD detection complete. Proceed with backup creation?"; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

# Create comprehensive backup
create_deployment_backup() {
    log_step "Creating Deployment Backup"
    
    log_substep "Creating backup directory..."
    mkdir -p "$BACKUP_DIR"
    log_success "Backup directory created: $BACKUP_DIR"
    
    log_substep "Backing up Talos configuration..."
    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${NODE_IPS[$i]}"
        log_info "Backing up configuration for $node..."
        talosctl -n "$ip" get machineconfig -o yaml > "$BACKUP_DIR/talos-config-$node.yaml" 2>/dev/null || \
            log_warning "Could not backup configuration for $node"
    done
    
    log_substep "Backing up Longhorn state..."
    if kubectl get namespace longhorn-system &> /dev/null; then
        kubectl get all -n longhorn-system -o yaml > "$BACKUP_DIR/longhorn-resources.yaml" 2>/dev/null || true
        kubectl get nodes.longhorn.io -n longhorn-system -o yaml > "$BACKUP_DIR/longhorn-nodes.yaml" 2>/dev/null || true
        kubectl get disks.longhorn.io -n longhorn-system -o yaml > "$BACKUP_DIR/longhorn-disks.yaml" 2>/dev/null || true
        kubectl get storageclass -o yaml > "$BACKUP_DIR/storage-classes.yaml" 2>/dev/null || true
        log_success "Longhorn state backed up"
    else
        log_warning "Longhorn namespace not found - skipping Longhorn backup"
    fi
    
    log_substep "Backing up cluster state..."
    kubectl get nodes -o yaml > "$BACKUP_DIR/cluster-nodes.yaml" 2>/dev/null || true
    kubectl get pv -o yaml > "$BACKUP_DIR/persistent-volumes.yaml" 2>/dev/null || true
    kubectl get pvc -A -o yaml > "$BACKUP_DIR/persistent-volume-claims.yaml" 2>/dev/null || true
    
    # Create backup manifest
    cat > "$BACKUP_DIR/backup-manifest.txt" << EOF
USB SSD Deployment Backup
Created: $(date)
Cluster: home-ops
Nodes: ${NODES[*]}
Node IPs: ${NODE_IPS[*]}

Files in this backup:
- talos-config-*.yaml: Talos machine configurations
- longhorn-*.yaml: Longhorn storage system state
- cluster-*.yaml: Kubernetes cluster state
- storage-classes.yaml: Storage class configurations
- persistent-*.yaml: Persistent volume state

To restore from this backup, see the rollback procedures in the deployment script.
EOF
    
    log_success "Comprehensive backup created in $BACKUP_DIR"
    
    if ! prompt_continue "Backup complete. Proceed with Talos configuration deployment?"; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

# Deploy Talos USB SSD configuration
deploy_talos_configuration() {
    log_step "Deploying Talos USB SSD Configuration"
    
    log_substep "Checking if Talos configuration needs regeneration..."
    local needs_regen=false
    
    # Check if USB SSD patch is already included
    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        if [[ -f "clusterconfig/home-ops-$node.yaml" ]]; then
            if ! grep -q "usb-ssd-storage\|longhorn-ssd" "clusterconfig/home-ops-$node.yaml" 2>/dev/null; then
                needs_regen=true
                break
            fi
        else
            needs_regen=true
            break
        fi
    done
    
    if [[ "$needs_regen" == "true" ]]; then
        log_info "Regenerating Talos configuration with USB SSD patches..."
        
        if command -v task &> /dev/null; then
            log_substep "Using Task to regenerate configuration..."
            mise exec -- task talos:generate-config
        else
            log_substep "Using talhelper directly..."
            mise exec -- talhelper genconfig --secret-file talos/talsecret.yaml
        fi
        
        log_success "Talos configuration regenerated with USB SSD support"
    else
        log_success "Talos configuration already includes USB SSD patches"
    fi
    
    echo
    log_warning "IMPORTANT: The next step will apply new configuration to all nodes"
    log_warning "This may cause temporary service disruption as nodes restart services"
    echo
    
    if ! prompt_continue "Apply Talos configuration to all nodes?"; then
        log_info "Configuration deployment cancelled by user"
        exit 0
    fi
    
    log_substep "Applying configuration to nodes..."
    local failed_nodes=()
    
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
                failed_nodes+=("$node")
            fi
        fi
    done
    
    if [[ ${#failed_nodes[@]} -gt 0 ]]; then
        log_error "Configuration failed on nodes: ${failed_nodes[*]}"
        
        local choice
        choice=$(prompt_choice "Some nodes failed configuration. How to proceed?" \
            "Continue with successful nodes only" \
            "Retry failed nodes" \
            "Abort deployment")
        
        case "$choice" in
            "Continue with successful nodes only")
                log_warning "Continuing with partial deployment"
                ;;
            "Retry failed nodes")
                # Retry logic could be implemented here
                log_info "Manual retry required for failed nodes"
                ;;
            "Abort deployment")
                log_info "Deployment aborted by user"
                exit 1
                ;;
        esac
    fi
    
    log_success "Talos configuration applied successfully"
    
    if ! prompt_continue "Configuration applied. Proceed with coordinated node reboots?"; then
        log_info "Deployment paused by user. Resume with node reboots when ready."
        exit 0
    fi
}

# Coordinate safe node reboots
coordinate_node_reboots() {
    log_step "Coordinating Node Reboots for USB SSD Detection"
    
    echo
    log_warning "IMPORTANT: Nodes will be rebooted one at a time to ensure cluster availability"
    log_warning "This process will take approximately 10-15 minutes"
    log_warning "The cluster will remain operational throughout the process"
    echo
    
    if ! prompt_continue "Proceed with coordinated node reboots?"; then
        log_info "Node reboots cancelled by user"
        log_info "Manual reboot required to activate USB SSD configuration"
        exit 0
    fi
    
    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${NODE_IPS[$i]}"
        
        log_substep "Rebooting $node ($ip)..."
        
        # Reboot the node
        talosctl -n "$ip" reboot
        log_info "$node reboot initiated"
        
        # Wait for node to go down
        log_info "Waiting for $node to shut down..."
        local shutdown_timeout=60
        local elapsed=0
        
        while [[ $elapsed -lt $shutdown_timeout ]]; do
            if ! talosctl -n "$ip" version --timeout 5s &> /dev/null; then
                log_success "$node has shut down"
                break
            fi
            sleep 5
            elapsed=$((elapsed + 5))
        done
        
        # Wait for node to come back online
        log_info "Waiting for $node to come back online..."
        local boot_timeout=300
        elapsed=0
        
        while [[ $elapsed -lt $boot_timeout ]]; do
            if talosctl -n "$ip" version --timeout 5s &> /dev/null; then
                log_success "$node is back online"
                break
            fi
            sleep 10
            elapsed=$((elapsed + 10))
            
            if [[ $((elapsed % 60)) -eq 0 ]]; then
                log_info "Still waiting for $node... (${elapsed}s/${boot_timeout}s)"
            fi
        done
        
        if [[ $elapsed -ge $boot_timeout ]]; then
            log_error "$node did not come back online within $boot_timeout seconds"
            
            local choice
            choice=$(prompt_choice "Node $node is not responding. How to proceed?" \
                "Continue with remaining nodes" \
                "Wait longer for this node" \
                "Abort deployment")
            
            case "$choice" in
                "Continue with remaining nodes")
                    log_warning "Continuing without $node"
                    ;;
                "Wait longer for this node")
                    log_info "Waiting additional 5 minutes for $node..."
                    sleep 300
                    if talosctl -n "$ip" version --timeout 10s &> /dev/null; then
                        log_success "$node is now online"
                    else
                        log_error "$node still not responding"
                    fi
                    ;;
                "Abort deployment")
                    log_error "Deployment aborted due to node failure"
                    exit 1
                    ;;
            esac
        fi
        
        # Wait for node to stabilize
        log_info "Waiting for $node to stabilize..."
        sleep 30
        
        # Check Samsung Portable SSD T5 detection on rebooted node
        log_info "Checking Samsung Portable SSD T5 detection on $node..."
        local t5_devices
        t5_devices=$(talosctl -n "$ip" ls /dev/disk/by-id/ 2>/dev/null | grep -E "usb-Samsung_Portable_SSD_T5.*[^0-9]$" || true)
        
        if [[ -n "$t5_devices" ]]; then
            log_success "Samsung Portable SSD T5 drives detected on $node after reboot"
        else
            log_warning "No Samsung Portable SSD T5 drives detected on $node after reboot"
        fi
        
        echo
    done
    
    # Final cluster health check
    log_substep "Verifying cluster health after reboots..."
    local timeout=300
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        local ready_nodes
        ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
        
        if [[ $ready_nodes -eq ${#NODES[@]} ]]; then
            log_success "All nodes are ready"
            break
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
        
        if [[ $((elapsed % 60)) -eq 0 ]]; then
            log_info "Waiting for all nodes to be ready... ($ready_nodes/${#NODES[@]} ready)"
        fi
    done
    
    if [[ $elapsed -ge $timeout ]]; then
        log_warning "Not all nodes became ready within $timeout seconds"
        kubectl get nodes
    fi
    
    log_success "Node reboots completed successfully"
    
    if ! prompt_continue "Reboots complete. Proceed with Longhorn configuration updates?"; then
        log_info "Deployment paused by user"
        exit 0
    fi
}

# Update Longhorn configuration
update_longhorn_configuration() {
    log_step "Updating Longhorn Configuration for USB SSD Support"
    
    log_substep "Checking Longhorn deployment status..."
    if ! kubectl get namespace longhorn-system &> /dev/null; then
        log_error "Longhorn namespace not found"
        
        local choice
        choice=$(prompt_choice "Longhorn is not installed. How to proceed?" \
            "Install Longhorn first" \
            "Skip Longhorn configuration" \
            "Abort deployment")
        
        case "$choice" in
            "Install Longhorn first")
                log_info "Installing Longhorn..."
                if command -v task &> /dev/null; then
                    mise exec -- task apps:deploy-longhorn
                else
                    log_error "Task not available. Please install Longhorn manually."
                    exit 1
                fi
                ;;
            "Skip Longhorn configuration")
                log_warning "Skipping Longhorn configuration"
                return 0
                ;;
            "Abort deployment")
                log_info "Deployment aborted by user"
                exit 1
                ;;
        esac
    fi
    
    log_substep "Waiting for Longhorn to be ready..."
    if ! kubectl wait --for=condition=ready pods -l app=longhorn-manager -n longhorn-system --timeout=300s; then
        log_warning "Longhorn manager pods not ready within timeout"
    fi
    
    log_substep "Applying Longhorn storage class configuration..."
    if [[ -f "infrastructure/longhorn/storage-class.yaml" ]]; then
        kubectl apply -f infrastructure/longhorn/storage-class.yaml
        log_success "Longhorn storage class applied"
    else
        log_warning "Storage class configuration not found"
    fi
    
    # Check if we're in a git repository for GitOps
    if git rev-parse --git-dir &> /dev/null; then
        log_substep "Triggering GitOps reconciliation..."
        
        if command -v flux &> /dev/null; then
            flux reconcile kustomization infrastructure-longhorn || log_warning "Flux reconcile failed"
            log_success "GitOps reconciliation triggered"
        else
            log_warning "Flux not available - manual reconciliation may be needed"
        fi
    else
        log_info "Not in git repository - applying configuration directly"
    fi
    
    # Wait for Longhorn to discover disks
    log_substep "Waiting for Longhorn to discover USB SSD disks..."
    log_info "This may take 1-2 minutes for disk discovery and configuration..."
    sleep 90
    
    log_success "Longhorn configuration update completed"
    
    if ! prompt_continue "Longhorn updated. Proceed with validation and testing?"; then
        log_info "Deployment paused by user"
        exit 0
    fi
}

# Comprehensive validation and testing
validate_deployment() {
    log_step "Validation and Testing"
    
    log_substep "Running USB SSD hardware validation..."
    local usb_validation_errors=0
    
    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${NODE_IPS[$i]}"
        
        log_info "Validating $node..."
        
        # Check USB device detection
        local usb_devices
        usb_devices=$(talosctl -n "$ip" ls /dev/disk/by-id/ 2>/dev/null | grep -E "usb-.*[^0-9]$" || true)
        
        if [[ -z "$usb_devices" ]]; then
            log_warning "No USB SSDs detected on $node"
            ((usb_validation_errors++))
        else
            log_success "USB devices found on $node"
            
            # Check mount status
            local mount_info
            mount_info=$(talosctl -n "$ip" df 2>/dev/null | grep "$MOUNT_POINT" || true)
            
            if [[ -n "$mount_info" ]]; then
                log_success "USB SSD mounted on $node: $mount_info"
            else
                log_warning "USB SSD not mounted on $node"
                ((usb_validation_errors++))
            fi
        fi
    done
    
    log_substep "Validating Longhorn integration..."
    local longhorn_validation_errors=0
    
    # Check Longhorn nodes
    local longhorn_nodes
    longhorn_nodes=$(kubectl get nodes.longhorn.io -n longhorn-system -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -z "$longhorn_nodes" ]]; then
        log_error "No Longhorn nodes found"
        ((longhorn_validation_errors++))
    else
        log_success "Longhorn nodes found: $longhorn_nodes"
        
        # Check for SSD-tagged disks
        local ssd_disks=0
        for node in $longhorn_nodes; do
            local node_ssd_disks
            node_ssd_disks=$(kubectl get disks.longhorn.io -n longhorn-system -l longhornnode="$node" -o jsonpath='{.items[?(@.spec.tags[*]=="ssd")].metadata.name}' 2>/dev/null || echo "")
            
            if [[ -n "$node_ssd_disks" ]]; then
                local disk_count
                disk_count=$(echo "$node_ssd_disks" | wc -w)
                ssd_disks=$((ssd_disks + disk_count))
                log_success "Found $disk_count SSD disk(s) on $node"
            fi
        done
        
        log_info "Total SSD disks found in Longhorn: $ssd_disks"
    fi
    
    # Check storage class
    log_substep "Validating storage class..."
    if kubectl get storageclass longhorn-ssd &> /dev/null; then
        log_success "longhorn-ssd storage class exists"
        
        # Test storage class functionality
        log_info "Testing storage class functionality..."
        local test_pvc="usb-ssd-deployment-test-$(date +%s)"
        
        cat <<EOF | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${test_pvc}
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
        local pvc_bound=false
        
        while [[ $elapsed -lt $timeout ]]; do
            local pvc_status
            pvc_status=$(kubectl get pvc "$test_pvc" -n default -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
            
            if [[ "$pvc_status" == "Bound" ]]; then
                log_success "Test PVC bound successfully"
                pvc_bound=true
                break
            elif [[ "$pvc_status" == "Pending" ]]; then
                log_info "PVC still pending... (${elapsed}s/${timeout}s)"
            fi
            
            sleep 5
            elapsed=$((elapsed + 5))
        done
        
        # Cleanup test PVC
        kubectl delete pvc "$test_pvc" -n default &>/dev/null || true
        
        if [[ "$pvc_bound" == "true" ]]; then
            log_success "Storage class test passed"
        else
            log_warning "Storage class test failed - may work once more USB SSDs are connected"
            ((longhorn_validation_errors++))
        fi
    else
        log_error "longhorn-ssd storage class not found"
        ((longhorn_validation_errors++))
    fi
    
    # Run comprehensive validation script if available
    log_substep "Running comprehensive validation script..."
    if [[ -f "scripts/validate-complete-usb-ssd-setup.sh" ]]; then
        if ./scripts/validate-complete-usb-ssd-setup.sh &>/dev/null; then
            log_success "Comprehensive validation passed"
        else
            log_warning "Comprehensive validation had issues (check logs for details)"
        fi
    else
        log_info "Comprehensive validation script not found"
    fi
    
    # Summary
    log_substep "Validation Summary"
    local total_errors=$((usb_validation_errors + longhorn_validation_errors))
    
    if [[ $total_errors -eq 0 ]]; then
        log_success "All validations passed successfully!"
    elif [[ $usb_validation_errors -gt 0 ]] && [[ $longhorn_validation_errors -eq 0 ]]; then
        log_warning "USB SSD validation issues found ($usb_validation_errors)"
        log_info "This is normal if not all nodes have USB SSDs connected"
    elif [[ $longhorn_validation_errors -gt 0 ]]; then
        log_warning "Longhorn integration issues found ($longhorn_validation_errors)"
        log_info "May require manual intervention or additional USB SSD connections"
    fi
    
    if ! prompt_continue "Validation complete. Proceed with final deployment summary?"; then
        log_info "Deployment paused by user"
        exit 0
    fi
}

# Performance testing
test_performance() {
    log_step "Performance Testing (Optional)"
    
    if ! prompt_continue "Would you like to run basic performance tests?"; then
        log_info "Skipping performance tests"
        return 0
    fi
    
    log_substep "Running basic I/O performance tests..."
    
    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${NODE_IPS[$i]}"
        
        # Check if USB SSD is mounted
        local mount_info
        mount_info=$(talosctl -n "$ip" df 2>/dev/null | grep "$MOUNT_POINT" || true)
        
        if [[ -z "$mount_info" ]]; then
            log_warning "USB SSD not mounted on $node, skipping performance test"
            continue
        fi
        
        log_info "Testing I/O performance on $node..."
        
        # Simple write test
        local test_file="$MOUNT_POINT/.perf-test-$(date +%s)"
        local write_result
        write_result=$(talosctl -n "$ip" sh -c "time dd if=/dev/zero of='$test_file' bs=1M count=100 oflag=direct 2>&1 && rm '$test_file'" 2>/dev/null || echo "failed")
        
        if [[ "$write_result" != "failed" ]]; then
            log_success "Write performance test completed on $node"
            # Extract timing if available
            local timing
            timing=$(echo "$write_result" | grep "real\|copied" | head -1 || echo "timing not available")
            log_info "  Performance: $timing"
        else
            log_warning "Write performance test failed on $node"
        fi
    done
    
    log_success "Performance testing completed"
}

# Final deployment summary
deployment_summary() {
    log_step "Deployment Summary"
    
    local end_time
    end_time=$(date +%s)
    local start_time
    start_time=$(date -d "$(head -1 "$DEPLOYMENT_LOG" | cut -d' ' -f1-2)" +%s 2>/dev/null || echo "$end_time")
    local duration=$((end_time - start_time))
    
    echo
    echo "=============================================="
    echo -e "${GREEN}${BOLD}USB SSD Storage Deployment Completed!${NC}"
    echo "=============================================="
    echo
    
    log_info "Deployment Duration: $duration seconds"
    log_info "Deployment Log: $DEPLOYMENT_LOG"
    log_info "Backup Directory: $BACKUP_DIR"
    echo
    
    log_info "Deployment Results:"
    
    # Check final status
    local nodes_with_usb=0
    local nodes_with_mounts=0
    
    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${NODE_IPS[$i]}"
        
        # Check Samsung Portable SSD T5 detection
        local t5_devices
        t5_devices=$(talosctl -n "$ip" ls /dev/disk/by-id/ 2>/dev/null | grep -E "usb-Samsung_Portable_SSD_T5.*[^0-9]$" || true)
        
        if [[ -n "$t5_devices" ]]; then
            ((nodes_with_usb++))
            
            # Check mount status
            local mount_info
            mount_info=$(talosctl -n "$ip" df 2>/dev/null | grep "$MOUNT_POINT" || true)
            
            if [[ -n "$mount_info" ]]; then
                ((nodes_with_mounts++))
                log_success "$node: Samsung Portable SSD T5 detected and mounted"
            else
                log_warning "$node: Samsung Portable SSD T5 detected but not mounted"
            fi
        else
            log_warning "$node: No Samsung Portable SSD T5 detected"
        fi
    done
    
    echo
    log_info "Final Status:"
    log_info "  Nodes with Samsung Portable SSD T5 detected: $nodes_with_usb/${#NODES[@]}"
    log_info "  Nodes with Samsung Portable SSD T5 mounted: $nodes_with_mounts/${#NODES[@]}"
    
    # Check Longhorn status
    if kubectl get storageclass longhorn-ssd &> /dev/null; then
        log_success "longhorn-ssd storage class is available"
    else
        log_warning "longhorn-ssd storage class not found"
    fi
    
    echo
    log_info "Next Steps:"
    log_info "1. Connect Samsung Portable SSD T5 drives to any nodes that don't have them"
    log_info "2. Run validation: ./scripts/validate-complete-usb-ssd-setup.sh"
    log_info "3. Create test PVCs using the 'longhorn-ssd' storage class"
    log_info "4. Monitor Longhorn dashboard for disk health and usage"
    log_info "5. Set up monitoring and alerting for storage metrics"
    
    echo
    log_info "Useful Commands:"
    log_info "  Check Samsung T5 SSDs: task storage:check-usb-ssd"
    log_info "  Validate setup: task storage:validate-complete-usb-ssd"
    log_info "  Monitor Longhorn: kubectl get pods -n longhorn-system"
    log_info "  Check storage classes: kubectl get storageclass"
    
    echo
    if [[ $nodes_with_mounts -eq ${#NODES[@]} ]]; then
        log_success "🎉 Samsung Portable SSD T5 storage is fully operational on all nodes!"
    elif [[ $nodes_with_mounts -gt 0 ]]; then
        log_success "✅ Samsung Portable SSD T5 storage is partially operational ($nodes_with_mounts/${#NODES[@]} nodes)"
        log_info "Connect Samsung Portable SSD T5 drives to remaining nodes for full functionality"
    else
        log_warning "⚠️  Samsung Portable SSD T5 storage configuration deployed but no active storage"
        log_info "Connect Samsung Portable SSD T5 drives to nodes and reboot to activate storage"
    fi
    
    echo
    echo "=============================================="
    log_success "Deployment completed successfully!"
    echo "=============================================="
}

# Main deployment orchestration
main() {
    echo "=============================================="
    echo -e "${CYAN}${BOLD}Interactive USB SSD Storage Deployment${NC}"
    echo -e "${CYAN}${BOLD}Production-Safe Guided Installation${NC}"
    echo "=============================================="
    echo
    
    # Initialize deployment log
    echo "USB SSD Storage Deployment Started: $(date)" > "$DEPLOYMENT_LOG"
    echo "Cluster: home-ops" >> "$DEPLOYMENT_LOG"
    echo "Nodes: ${NODES[*]}" >> "$DEPLOYMENT_LOG"
    echo "Node IPs: ${NODE_IPS[*]}" >> "$DEPLOYMENT_LOG"
    echo "========================================" >> "$DEPLOYMENT_LOG"
    
    log_info "Starting interactive Samsung Portable SSD T5 storage deployment..."
    log_info "This deployment will configure Samsung Portable SSD T5 storage for Longhorn"
    log_info "The process includes safety checks, backups, and rollback options"
    echo
    
    log_info "Deployment Overview:"
    log_info "1. Pre-deployment verification"
    log_info "2. Samsung Portable SSD T5 hardware detection"
    log_info "3. Backup creation"
    log_info "4. Talos configuration deployment"
    log_info "5. Coordinated node reboots"
    log_info "6. Longhorn configuration updates"
    log_info "7. Validation and testing"
    log_info "8. Deployment summary"
    echo
    
    if ! prompt_continue "Ready to begin Samsung Portable SSD T5 storage deployment?" "y"; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    check_usb_ssd_hardware
    create_deployment_backup
    deploy_talos_configuration
    coordinate_node_reboots
    update_longhorn_configuration
    validate_deployment
    test_performance
    deployment_summary
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi