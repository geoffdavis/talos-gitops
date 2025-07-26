#!/bin/bash
set -euo pipefail

# BGP-only Load Balancer Migration Script
# Migrates from L2 announcements to BGP-only load balancer architecture
# Uses dedicated 172.29.52.0/24 network segment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="home-ops"
OLD_LB_NETWORK="172.29.51.0/24"
NEW_LB_NETWORK="172.29.52.0/24"
BACKUP_DIR="$PROJECT_ROOT/backups/bgp-migration-$(date +%Y%m%d-%H%M%S)"

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check required tools
    for tool in kubectl mise talosctl flux; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is required but not installed"
        fi
    done
    
    # Check cluster connectivity
    if ! kubectl get nodes &> /dev/null; then
        error "Cannot connect to Kubernetes cluster"
    fi
    
    # Check Flux status
    if ! flux get kustomizations &> /dev/null; then
        error "Flux is not accessible or not installed"
    fi
    
    success "Prerequisites check passed"
}

backup_current_config() {
    log "Creating backup of current configuration..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup current Cilium configuration
    kubectl get ciliumloadbalancerippool -o yaml > "$BACKUP_DIR/current-loadbalancer-pools.yaml"
    kubectl get ciliuml2announcementpolicy -o yaml > "$BACKUP_DIR/current-l2-policies.yaml"
    kubectl get ciliumbgpclusterconfig -o yaml > "$BACKUP_DIR/current-bgp-config.yaml"
    kubectl get ciliumbgpadvertisement -o yaml > "$BACKUP_DIR/current-bgp-advertisements.yaml"
    
    # Backup current services with LoadBalancer type
    kubectl get svc --all-namespaces -o yaml | grep -A 50 -B 10 "type: LoadBalancer" > "$BACKUP_DIR/current-loadbalancer-services.yaml"
    
    # Backup Cilium Helm release
    kubectl get helmrelease cilium -n kube-system -o yaml > "$BACKUP_DIR/current-cilium-helmrelease.yaml"
    
    success "Configuration backed up to $BACKUP_DIR"
}

validate_network_setup() {
    log "Validating network setup..."
    
    # Check if new network segment is routable
    if ping -c 1 -W 2 172.29.52.1 &> /dev/null; then
        success "New load balancer network (172.29.52.0/24) is routable"
    else
        warn "New load balancer network may not be configured on UDM Pro yet"
        echo "Please ensure VLAN 52 (172.29.52.0/24) is configured on your UDM Pro"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

phase_1_prepare_new_config() {
    log "Phase 1: Preparing new BGP-only configuration..."
    
    # Copy new configuration files to active locations
    cp "$PROJECT_ROOT/infrastructure/cilium/loadbalancer-pool-bgp.yaml" \
       "$PROJECT_ROOT/infrastructure/cilium/loadbalancer-pool-new.yaml"
    
    cp "$PROJECT_ROOT/infrastructure/cilium-bgp/bgp-policy-bgp-only.yaml" \
       "$PROJECT_ROOT/infrastructure/cilium-bgp/bgp-policy-new.yaml"
    
    cp "$PROJECT_ROOT/infrastructure/cilium/helmrelease-bgp-only.yaml" \
       "$PROJECT_ROOT/infrastructure/cilium/helmrelease-new.yaml"
    
    success "New configuration files prepared"
}

phase_2_update_bgp_pools() {
    log "Phase 2: Updating BGP load balancer IP pools..."
    
    # Apply new load balancer IP pools
    kubectl apply -f "$PROJECT_ROOT/infrastructure/cilium/loadbalancer-pool-new.yaml"
    
    # Wait for pools to be ready
    sleep 10
    
    # Verify new pools are created
    if kubectl get ciliumloadbalancerippool bgp-default &> /dev/null; then
        success "New BGP load balancer pools created"
    else
        error "Failed to create new load balancer pools"
    fi
}

phase_3_update_bgp_policy() {
    log "Phase 3: Updating BGP policy configuration..."
    
    # Apply new BGP policy
    kubectl apply -f "$PROJECT_ROOT/infrastructure/cilium-bgp/bgp-policy-new.yaml"
    
    # Wait for BGP configuration to be applied
    sleep 15
    
    # Verify BGP configuration
    if kubectl get ciliumbgpclusterconfig cilium-bgp-cluster &> /dev/null; then
        success "BGP policy configuration updated"
    else
        error "Failed to update BGP policy"
    fi
}

phase_4_update_cilium_helm() {
    log "Phase 4: Updating Cilium Helm release (removes L2 announcements)..."
    
    # Replace current Cilium Helm release
    cp "$PROJECT_ROOT/infrastructure/cilium/helmrelease-new.yaml" \
       "$PROJECT_ROOT/infrastructure/cilium/helmrelease.yaml"
    
    # Commit changes to trigger Flux deployment
    cd "$PROJECT_ROOT"
    git add infrastructure/cilium/helmrelease.yaml
    git commit -m "feat: migrate to BGP-only load balancer (disable L2 announcements)"
    
    log "Waiting for Flux to apply Cilium changes..."
    sleep 30
    
    # Wait for Cilium pods to be ready
    kubectl rollout status daemonset/cilium -n kube-system --timeout=300s
    
    success "Cilium updated to BGP-only configuration"
}

phase_5_remove_l2_policies() {
    log "Phase 5: Removing L2 announcement policies..."
    
    # Remove old L2 announcement policies
    kubectl delete ciliuml2announcementpolicy --all -n kube-system || true
    
    # Remove old load balancer pools
    kubectl delete ciliumloadbalancerippool default ingress default-ipv6-pool -n kube-system || true
    
    success "L2 announcement policies removed"
}

phase_6_migrate_services() {
    log "Phase 6: Migrating services to new IP ranges..."
    
    # Get all LoadBalancer services
    services=$(kubectl get svc --all-namespaces -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace)/\(.metadata.name)"')
    
    if [ -z "$services" ]; then
        log "No LoadBalancer services found to migrate"
        return
    fi
    
    for service in $services; do
        namespace=$(echo "$service" | cut -d'/' -f1)
        name=$(echo "$service" | cut -d'/' -f2)
        
        log "Migrating service $namespace/$name..."
        
        # Update service to use new IP pool
        kubectl patch svc "$name" -n "$namespace" -p '{"metadata":{"labels":{"io.cilium/lb-ipam-pool":"default"}}}'
        
        # Force service to get new IP from new pool
        kubectl patch svc "$name" -n "$namespace" -p '{"spec":{"loadBalancerIP":null}}'
        
        sleep 5
    done
    
    success "Services migrated to new IP ranges"
}

phase_7_update_ingress_controllers() {
    log "Phase 7: Updating ingress controllers..."
    
    # Update ingress controller services to use new IP pool
    for ingress_ns in ingress-nginx-internal ingress-nginx-public ingress-nginx; do
        if kubectl get namespace "$ingress_ns" &> /dev/null; then
            kubectl patch svc -n "$ingress_ns" -l app.kubernetes.io/name=ingress-nginx \
                -p '{"metadata":{"labels":{"io.cilium/lb-ipam-pool":"ingress"}}}'
        fi
    done
    
    success "Ingress controllers updated"
}

phase_8_verify_migration() {
    log "Phase 8: Verifying migration..."
    
    # Check BGP peering status
    log "Checking BGP configuration..."
    kubectl get ciliumbgpclusterconfig -o wide
    
    # Check load balancer pools
    log "Checking load balancer IP pools..."
    kubectl get ciliumloadbalancerippool -o wide
    
    # Check services with new IPs
    log "Checking LoadBalancer services..."
    kubectl get svc --all-namespaces -o wide | grep LoadBalancer
    
    # Verify no L2 announcement policies exist
    l2_policies=$(kubectl get ciliuml2announcementpolicy -n kube-system --no-headers 2>/dev/null | wc -l)
    if [ "$l2_policies" -eq 0 ]; then
        success "L2 announcement policies successfully removed"
    else
        warn "Some L2 announcement policies still exist"
    fi
    
    success "Migration verification completed"
}

cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    rm -f "$PROJECT_ROOT/infrastructure/cilium/loadbalancer-pool-new.yaml"
    rm -f "$PROJECT_ROOT/infrastructure/cilium-bgp/bgp-policy-new.yaml"
    rm -f "$PROJECT_ROOT/infrastructure/cilium/helmrelease-new.yaml"
    
    success "Temporary files cleaned up"
}

rollback_migration() {
    log "Rolling back migration..."
    
    if [ ! -d "$BACKUP_DIR" ]; then
        error "Backup directory not found: $BACKUP_DIR"
    fi
    
    # Restore original configuration
    kubectl apply -f "$BACKUP_DIR/current-loadbalancer-pools.yaml"
    kubectl apply -f "$BACKUP_DIR/current-l2-policies.yaml"
    kubectl apply -f "$BACKUP_DIR/current-bgp-config.yaml"
    kubectl apply -f "$BACKUP_DIR/current-cilium-helmrelease.yaml"
    
    success "Migration rolled back"
}

show_post_migration_steps() {
    log "Post-migration steps:"
    echo
    echo "1. Update UDM Pro BGP configuration:"
    echo "   - Upload: $PROJECT_ROOT/scripts/unifi-bgp-config-bgp-only.conf"
    echo "   - Via UniFi Network UI: Network > Settings > Routing > BGP"
    echo
    echo "2. Update DNS records to point to new load balancer IPs"
    echo
    echo "3. Test connectivity to all services"
    echo
    echo "4. Monitor BGP peering status:"
    echo "   task bgp:verify-peering"
    echo
    echo "5. If issues occur, rollback with:"
    echo "   $0 --rollback"
    echo
}

main() {
    case "${1:-}" in
        --rollback)
            rollback_migration
            exit 0
            ;;
        --help|-h)
            echo "Usage: $0 [--rollback] [--help]"
            echo "  --rollback  Rollback the migration"
            echo "  --help      Show this help message"
            exit 0
            ;;
    esac
    
    log "Starting BGP-only load balancer migration for $CLUSTER_NAME cluster"
    echo
    warn "This will migrate from L2 announcements to BGP-only load balancing"
    warn "Services will get new IP addresses in the 172.29.52.0/24 range"
    echo
    read -p "Continue with migration? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Migration cancelled"
        exit 0
    fi
    
    check_prerequisites
    backup_current_config
    validate_network_setup
    
    phase_1_prepare_new_config
    phase_2_update_bgp_pools
    phase_3_update_bgp_policy
    phase_4_update_cilium_helm
    phase_5_remove_l2_policies
    phase_6_migrate_services
    phase_7_update_ingress_controllers
    phase_8_verify_migration
    cleanup_temp_files
    
    success "BGP-only load balancer migration completed successfully!"
    show_post_migration_steps
}

main "$@"