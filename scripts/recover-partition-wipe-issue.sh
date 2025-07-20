#!/bin/bash
set -euo pipefail

# Partition Wipe Recovery Script
# Addresses the read-only filesystem issue on mini01 after security incident

echo "=== Talos Partition Wipe Recovery Script ==="
echo "Date: $(date)"
echo "Context: Post-security incident cluster recovery"
echo

# Configuration
TALOSCONFIG_PATH="clusterconfig/talosconfig"
NODES=(172.29.51.11 172.29.51.12 172.29.51.13)
ENDPOINTS="172.29.51.11"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v talosctl &> /dev/null; then
        log_error "talosctl not found. Please install Talos CLI."
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

diagnose_current_state() {
    log_info "Diagnosing current node states..."
    
    export TALOSCONFIG="$TALOSCONFIG_PATH"
    
    for node in "${NODES[@]}"; do
        echo
        log_info "Testing node $node..."
        
        # Test network connectivity
        if ping -c 1 "$node" &>/dev/null; then
            log_success "  Network: Responsive"
        else
            log_error "  Network: Unresponsive"
            continue
        fi
        
        # Test Talos API (authenticated)
        if talosctl version --nodes "$node" --endpoints "$node" &>/dev/null; then
            log_success "  Talos API: Authenticated access working"
            
            # Check for read-only filesystem errors
            if talosctl dmesg --nodes "$node" --endpoints "$node" 2>/dev/null | grep -q "read-only file system"; then
                log_warning "  Status: Read-only filesystem detected"
            else
                log_success "  Status: Normal operation"
            fi
        else
            # Test insecure mode (maintenance mode)
            if talosctl version --nodes "$node" --endpoints "$node" --insecure 2>&1 | grep -q "maintenance mode"; then
                log_success "  Talos API: Maintenance mode (ready for config)"
            else
                log_warning "  Talos API: Connection issues"
            fi
        fi
    done
}

fix_mini01_readonly() {
    log_info "Attempting to fix mini01 read-only filesystem issue..."
    
    export TALOSCONFIG="$TALOSCONFIG_PATH"
    
    log_info "Option 1: Applying wipe configuration to force maintenance mode..."
    if talosctl apply-config --nodes 172.29.51.11 --file clusterconfig/home-ops-mini01.yaml --mode=reboot; then
        log_success "Configuration applied, waiting for reboot..."
        sleep 60
        
        # Check if now in maintenance mode
        if talosctl version --nodes 172.29.51.11 --endpoints 172.29.51.11 --insecure 2>&1 | grep -q "maintenance mode"; then
            log_success "mini01 is now in maintenance mode!"
            return 0
        fi
    fi
    
    log_warning "Option 1 failed, trying Option 2: Force reset..."
    if talosctl reset --nodes 172.29.51.11 --endpoints 172.29.51.11 --graceful=false --reboot; then
        log_success "Reset command sent, waiting for maintenance mode..."
        sleep 90
        
        if talosctl version --nodes 172.29.51.11 --endpoints 172.29.51.11 --insecure 2>&1 | grep -q "maintenance mode"; then
            log_success "mini01 is now in maintenance mode after reset!"
            return 0
        fi
    fi
    
    log_error "Automated fixes failed. Manual intervention required:"
    echo "  1. Physically power cycle mini01"
    echo "  2. Wait for boot completion"
    echo "  3. Re-run this script"
    return 1
}

generate_fresh_secrets() {
    log_info "Generating fresh cluster secrets..."
    
    # Backup existing secrets
    if [[ -f "$TALOSCONFIG_PATH" ]]; then
        cp "$TALOSCONFIG_PATH" "${TALOSCONFIG_PATH}.backup.$(date +%Y%m%d-%H%M%S)"
        log_info "Backed up existing talosconfig"
    fi
    
    # Generate new secrets
    if mise exec -- task talos:generate-config; then
        log_success "Fresh cluster secrets generated"
    else
        log_error "Failed to generate fresh secrets"
        return 1
    fi
}

apply_fresh_configuration() {
    log_info "Applying fresh configuration to all nodes..."
    
    export TALOSCONFIG="$TALOSCONFIG_PATH"
    
    # Check node states and proceed with available nodes
    local available_nodes=()
    for node in "${NODES[@]}"; do
        if talosctl version --nodes "$node" --endpoints "$node" --insecure 2>&1 | grep -q "maintenance mode"; then
            log_success "Node $node is in maintenance mode"
            available_nodes+=("$node")
        elif ping -c 1 "$node" &>/dev/null; then
            log_warning "Node $node is responsive but not in maintenance mode - will attempt insecure config application"
            available_nodes+=("$node")
        else
            log_error "Node $node is not accessible - skipping"
        fi
    done
    
    if [ ${#available_nodes[@]} -eq 0 ]; then
        log_error "No nodes are accessible. Cannot proceed."
        return 1
    fi
    
    log_info "Proceeding with ${#available_nodes[@]} available nodes: ${available_nodes[*]}"
    
    # Apply configuration to each available node
    local configs=("home-ops-mini01.yaml" "home-ops-mini02.yaml" "home-ops-mini03.yaml")
    local node_configs=()
    node_configs[0]="clusterconfig/home-ops-mini01.yaml"  # 172.29.51.11
    node_configs[1]="clusterconfig/home-ops-mini02.yaml"  # 172.29.51.12
    node_configs[2]="clusterconfig/home-ops-mini03.yaml"  # 172.29.51.13
    
    for node in "${available_nodes[@]}"; do
        local config=""
        case "$node" in
            "172.29.51.11") config="${node_configs[0]}" ;;
            "172.29.51.12") config="${node_configs[1]}" ;;
            "172.29.51.13") config="${node_configs[2]}" ;;
            *) log_error "Unknown node $node"; continue ;;
        esac
        
        log_info "Applying configuration to $node..."
        if talosctl apply-config --nodes "$node" --endpoints "$node" --file "$config" --insecure; then
            log_success "Configuration applied to $node"
        else
            log_error "Failed to apply configuration to $node"
            return 1
        fi
    done
    
    log_info "Waiting for nodes to reboot and initialize..."
    sleep 120
}

bootstrap_cluster() {
    log_info "Bootstrapping new cluster..."
    
    export TALOSCONFIG="$TALOSCONFIG_PATH"
    
    if talosctl bootstrap --nodes 172.29.51.11 --endpoints 172.29.51.11; then
        log_success "Cluster bootstrap initiated"
    else
        log_error "Failed to bootstrap cluster"
        return 1
    fi
    
    log_info "Waiting for cluster initialization..."
    sleep 60
    
    # Generate fresh kubeconfig
    if talosctl kubeconfig --nodes 172.29.51.11 --endpoints 172.29.51.11 --force; then
        log_success "Fresh kubeconfig generated"
    else
        log_error "Failed to generate kubeconfig"
        return 1
    fi
}

verify_recovery() {
    log_info "Verifying recovery..."
    
    export TALOSCONFIG="$TALOSCONFIG_PATH"
    
    # Check node status
    log_info "Checking node status..."
    if kubectl get nodes; then
        log_success "Cluster is accessible"
    else
        log_error "Cluster is not accessible"
        return 1
    fi
    
    # Check for read-only filesystem errors
    log_info "Checking for read-only filesystem errors..."
    local readonly_errors=0
    for node in "${NODES[@]}"; do
        if talosctl dmesg --nodes "$node" --endpoints 172.29.51.11 2>/dev/null | grep -q "read-only file system"; then
            log_warning "Read-only filesystem errors still present on $node"
            readonly_errors=$((readonly_errors + 1))
        fi
    done
    
    if [[ $readonly_errors -eq 0 ]]; then
        log_success "No read-only filesystem errors detected"
    else
        log_warning "$readonly_errors nodes still have read-only filesystem issues"
    fi
}

main() {
    echo "Starting partition wipe recovery process..."
    echo
    
    check_prerequisites
    echo
    
    diagnose_current_state
    echo
    
    read -p "Continue with recovery? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Recovery cancelled by user"
        exit 0
    fi
    
    # Check if mini01 needs fixing
    export TALOSCONFIG="$TALOSCONFIG_PATH"
    if talosctl dmesg --nodes 172.29.51.11 --endpoints 172.29.51.11 2>/dev/null | grep -q "read-only file system"; then
        fix_mini01_readonly || exit 1
        echo
    fi
    
    generate_fresh_secrets || exit 1
    echo
    
    apply_fresh_configuration || exit 1
    echo
    
    bootstrap_cluster || exit 1
    echo
    
    verify_recovery
    echo
    
    log_success "Recovery process completed!"
    echo
    echo "Next steps:"
    echo "1. Deploy Cilium CNI: task apps:deploy-cilium"
    echo "2. Wait for nodes to become Ready: watch kubectl get nodes"
    echo "3. Deploy infrastructure: kubectl apply -k clusters/home-ops/infrastructure/"
    echo "4. Verify 1Password Connect: kubectl get clustersecretstore"
}

# Run main function
main "$@"