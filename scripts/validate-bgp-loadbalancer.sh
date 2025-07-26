#!/bin/bash
set -euo pipefail

# BGP Load Balancer Validation Script
# Validates BGP-only load balancer configuration and connectivity

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NEW_LB_NETWORK="172.29.52.0/24"
NEW_LB_RANGE_START="172.29.52.50"
NEW_LB_RANGE_END="172.29.52.220"
IPV6_LB_NETWORK="fd47:25e1:2f96:52::/64"

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

check_prerequisites() {
    log "Checking prerequisites..."

    for tool in kubectl dig curl ping; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is required but not installed"
        fi
    done

    if ! kubectl get nodes &> /dev/null; then
        error "Cannot connect to Kubernetes cluster"
    fi

    success "Prerequisites check passed"
}

validate_bgp_configuration() {
    log "Validating BGP configuration..."

    # Check BGP cluster config exists
    if kubectl get ciliumbgpclusterconfig cilium-bgp-cluster &> /dev/null; then
        success "BGP cluster configuration found"
    else
        error "BGP cluster configuration not found"
    fi

    # Check BGP advertisements
    if kubectl get ciliumbgpadvertisement bgp-loadbalancer-advertisements &> /dev/null; then
        success "BGP advertisements configuration found"
    else
        error "BGP advertisements configuration not found"
    fi

    # Verify no L2 announcement policies exist
    l2_policies=$(kubectl get ciliuml2announcementpolicy -n kube-system --no-headers 2>/dev/null | wc -l)
    if [ "$l2_policies" -eq 0 ]; then
        success "No L2 announcement policies found (BGP-only mode confirmed)"
    else
        warn "L2 announcement policies still exist: $l2_policies"
        kubectl get ciliuml2announcementpolicy -n kube-system
    fi
}

validate_load_balancer_pools() {
    log "Validating load balancer IP pools..."

    # Check BGP load balancer pools
    pools=("bgp-default" "bgp-ingress" "bgp-reserved" "bgp-default-ipv6")

    for pool in "${pools[@]}"; do
        if kubectl get ciliumloadbalancerippool "$pool" -n kube-system &> /dev/null; then
            success "Load balancer pool '$pool' found"

            # Show pool details
            kubectl get ciliumloadbalancerippool "$pool" -n kube-system -o yaml | grep -A 10 "blocks:"
        else
            error "Load balancer pool '$pool' not found"
        fi
    done
}

validate_cilium_configuration() {
    log "Validating Cilium configuration..."

    # Check Cilium pods are running
    cilium_pods=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium --no-headers | grep -c Running || echo "0")
    if [ "$cilium_pods" -gt 0 ]; then
        success "Cilium pods running: $cilium_pods"
    else
        error "No Cilium pods running"
    fi

    # Check BGP control plane is enabled
    bgp_enabled=$(kubectl get helmrelease cilium -n kube-system -o jsonpath='{.spec.values.bgpControlPlane.enabled}' 2>/dev/null || echo "false")
    if [ "$bgp_enabled" = "true" ]; then
        success "BGP control plane enabled in Cilium"
    else
        error "BGP control plane not enabled in Cilium"
    fi

    # Check L2 announcements are disabled
    l2_enabled=$(kubectl get helmrelease cilium -n kube-system -o jsonpath='{.spec.values.l2announcements.enabled}' 2>/dev/null || echo "true")
    if [ "$l2_enabled" = "false" ]; then
        success "L2 announcements disabled in Cilium"
    else
        warn "L2 announcements may still be enabled in Cilium"
    fi
}

validate_service_ips() {
    log "Validating LoadBalancer service IPs..."

    # Get all LoadBalancer services
    services=$(kubectl get svc --all-namespaces -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace)/\(.metadata.name)/\(.status.loadBalancer.ingress[0].ip // "pending")"')

    if [ -z "$services" ]; then
        warn "No LoadBalancer services found"
        return
    fi

    service_count=0
    valid_ip_count=0

    while IFS= read -r service_info; do
        if [ -z "$service_info" ]; then continue; fi

        namespace=$(echo "$service_info" | cut -d'/' -f1)
        name=$(echo "$service_info" | cut -d'/' -f2)
        ip=$(echo "$service_info" | cut -d'/' -f3)

        service_count=$((service_count + 1))

        if [ "$ip" = "pending" ] || [ "$ip" = "null" ]; then
            warn "Service $namespace/$name has no IP assigned"
        else
            # Check if IP is in new load balancer range
            if [[ "$ip" =~ ^172\.29\.52\. ]]; then
                success "Service $namespace/$name has valid BGP IP: $ip"
                valid_ip_count=$((valid_ip_count + 1))
            else
                warn "Service $namespace/$name has IP outside BGP range: $ip"
            fi
        fi
    done <<< "$services"

    log "LoadBalancer services summary: $valid_ip_count/$service_count have valid BGP IPs"
}

test_network_connectivity() {
    log "Testing network connectivity..."

    # Test connectivity to new load balancer network
    if ping -c 1 -W 2 172.29.52.1 &> /dev/null; then
        success "New load balancer network (172.29.52.0/24) is reachable"
    else
        warn "New load balancer network may not be fully configured"
    fi

    # Test connectivity to load balancer IPs
    services=$(kubectl get svc --all-namespaces -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer" and .status.loadBalancer.ingress[0].ip != null) | .status.loadBalancer.ingress[0].ip')

    if [ -n "$services" ]; then
        while IFS= read -r ip; do
            if [ -n "$ip" ] && [[ "$ip" =~ ^172\.29\.52\. ]]; then
                if ping -c 1 -W 2 "$ip" &> /dev/null; then
                    success "Load balancer IP $ip is reachable"
                else
                    warn "Load balancer IP $ip is not reachable"
                fi
            fi
        done <<< "$services"
    fi
}

test_service_endpoints() {
    log "Testing service endpoints..."

    # Test common services
    services_to_test=(
        "longhorn-system/longhorn-frontend:80"
        "kube-system/hubble-ui:80"
        "monitoring/grafana:80"
        "monitoring/prometheus:9090"
        "monitoring/alertmanager:9093"
    )

    for service_info in "${services_to_test[@]}"; do
        namespace=$(echo "$service_info" | cut -d'/' -f1)
        service_port=$(echo "$service_info" | cut -d'/' -f2)
        service_name=$(echo "$service_port" | cut -d':' -f1)
        port=$(echo "$service_port" | cut -d':' -f2)

        if kubectl get svc "$service_name" -n "$namespace" &> /dev/null; then
            ip=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

            if [ -n "$ip" ] && [ "$ip" != "null" ]; then
                if curl -s --connect-timeout 5 "http://$ip:$port" &> /dev/null; then
                    success "Service $namespace/$service_name is accessible at $ip:$port"
                else
                    warn "Service $namespace/$service_name is not accessible at $ip:$port"
                fi
            else
                warn "Service $namespace/$service_name has no external IP"
            fi
        fi
    done
}

validate_dns_resolution() {
    log "Validating DNS resolution..."

    # Test DNS resolution for services with known domains
    domains_to_test=(
        "longhorn.k8s.home.geoffdavis.com"
        "grafana.k8s.home.geoffdavis.com"
        "prometheus.k8s.home.geoffdavis.com"
        "hubble.k8s.home.geoffdavis.com"
    )

    for domain in "${domains_to_test[@]}"; do
        if dig +short "$domain" | grep -E '^172\.29\.52\.' &> /dev/null; then
            ip=$(dig +short "$domain" | head -1)
            success "DNS resolution for $domain points to BGP IP: $ip"
        else
            warn "DNS resolution for $domain may not point to BGP IP range"
        fi
    done
}

check_bgp_peering_status() {
    log "Checking BGP peering status (requires UDM Pro access)..."

    # This requires SSH access to UDM Pro - skip if not available
    if command -v ssh &> /dev/null && ssh -o ConnectTimeout=5 -o BatchMode=yes unifi-admin@udm-pro "echo test" &> /dev/null; then
        log "Testing BGP peering with UDM Pro..."

        # Check BGP summary
        if ssh unifi-admin@udm-pro "vtysh -c 'show bgp summary'" 2>/dev/null | grep -q "172.29.51.1[1-3]"; then
            success "BGP peering with cluster nodes detected"
        else
            warn "BGP peering status unclear"
        fi

        # Check advertised routes
        if ssh unifi-admin@udm-pro "vtysh -c 'show bgp ipv4 unicast'" 2>/dev/null | grep -q "172.29.52"; then
            success "Load balancer routes advertised via BGP"
        else
            warn "Load balancer routes may not be advertised"
        fi
    else
        warn "Cannot check BGP peering status (UDM Pro SSH access not available)"
        log "Manually verify BGP peering with: ssh unifi-admin@udm-pro 'vtysh -c \"show bgp summary\"'"
    fi
}

generate_validation_report() {
    log "Generating validation report..."

    report_file="$PROJECT_ROOT/bgp-validation-report-$(date +%Y%m%d-%H%M%S).txt"

    {
        echo "BGP Load Balancer Validation Report"
        echo "Generated: $(date)"
        echo "========================================"
        echo

        echo "BGP Configuration:"
        kubectl get ciliumbgpclusterconfig -o wide 2>/dev/null || echo "No BGP cluster config found"
        echo

        echo "Load Balancer IP Pools:"
        kubectl get ciliumloadbalancerippool -o wide 2>/dev/null || echo "No load balancer pools found"
        echo

        echo "LoadBalancer Services:"
        kubectl get svc --all-namespaces -o wide | grep LoadBalancer || echo "No LoadBalancer services found"
        echo

        echo "L2 Announcement Policies (should be empty):"
        kubectl get ciliuml2announcementpolicy -n kube-system 2>/dev/null || echo "No L2 announcement policies found"
        echo

    } > "$report_file"

    success "Validation report saved to: $report_file"
}

main() {
    case "${1:-}" in
        --help|-h)
            echo "Usage: $0 [--help]"
            echo "Validates BGP-only load balancer configuration"
            exit 0
            ;;
    esac

    log "Starting BGP load balancer validation..."
    echo

    check_prerequisites
    validate_bgp_configuration
    validate_load_balancer_pools
    validate_cilium_configuration
    validate_service_ips
    test_network_connectivity
    test_service_endpoints
    validate_dns_resolution
    check_bgp_peering_status
    generate_validation_report

    success "BGP load balancer validation completed!"
    echo
    log "Next steps:"
    echo "1. Review the validation report for any warnings"
    echo "2. Test service accessibility from client machines"
    echo "3. Monitor BGP peering status on UDM Pro"
    echo "4. Update monitoring dashboards for new IP ranges"
}

main "$@"
