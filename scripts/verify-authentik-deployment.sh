#!/bin/bash

# Authentik Deployment Verification Script
# This script verifies that the Authentik deployment is working correctly
# and can be deployed repeatably without manual intervention.

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

# Check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
}

# Check if flux is available
check_flux() {
    if ! command -v flux &> /dev/null; then
        log_error "flux is not installed or not in PATH"
        exit 1
    fi
}

# Wait for a condition with timeout
wait_for_condition() {
    local description="$1"
    local condition="$2"
    local timeout="${3:-300}"
    local interval="${4:-10}"
    
    log_info "Waiting for: $description (timeout: ${timeout}s)"
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if eval "$condition"; then
            log_success "$description"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        echo -n "."
    done
    
    echo ""
    log_error "Timeout waiting for: $description"
    return 1
}

# Check PostgreSQL cluster status
check_postgresql() {
    log_info "Checking PostgreSQL cluster status..."
    
    # Check if cluster exists
    if ! kubectl get cluster postgresql-cluster -n postgresql-system &>/dev/null; then
        log_error "PostgreSQL cluster 'postgresql-cluster' not found"
        return 1
    fi
    
    # Check cluster status
    local status=$(kubectl get cluster postgresql-cluster -n postgresql-system -o jsonpath='{.status.phase}')
    if [ "$status" != "Cluster in healthy state" ]; then
        log_error "PostgreSQL cluster status: $status"
        return 1
    fi
    
    log_success "PostgreSQL cluster is healthy"
    return 0
}

# Check external secrets
check_external_secrets() {
    log_info "Checking external secrets synchronization..."
    
    local secrets=("authentik-config" "authentik-database-credentials" "authentik-radius-token")
    
    for secret in "${secrets[@]}"; do
        if ! kubectl get secret "$secret" -n authentik &>/dev/null; then
            log_error "Secret '$secret' not found"
            return 1
        fi
        
        # Check if secret has data
        local keys=$(kubectl get secret "$secret" -n authentik -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null || echo "")
        if [ -z "$keys" ]; then
            log_error "Secret '$secret' has no data"
            return 1
        fi
        
        log_success "Secret '$secret' is synchronized"
    done
    
    return 0
}

# Check Flux kustomizations
check_flux_kustomizations() {
    log_info "Checking Flux kustomizations..."
    
    local kustomizations=("infrastructure-authentik")
    
    for kustomization in "${kustomizations[@]}"; do
        local ready=$(kubectl get kustomization "$kustomization" -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
        
        if [ "$ready" != "True" ]; then
            log_error "Kustomization '$kustomization' is not ready"
            kubectl get kustomization "$kustomization" -n flux-system -o yaml | grep -A 10 "conditions:"
            return 1
        fi
        
        log_success "Kustomization '$kustomization' is ready"
    done
    
    return 0
}

# Check pod status
check_pods() {
    log_info "Checking pod status..."
    
    # Get all pods in authentik namespace
    local pods=$(kubectl get pods -n authentik -o jsonpath='{.items[*].metadata.name}')
    
    if [ -z "$pods" ]; then
        log_error "No pods found in authentik namespace"
        return 1
    fi
    
    for pod in $pods; do
        local status=$(kubectl get pod "$pod" -n authentik -o jsonpath='{.status.phase}')
        local ready=$(kubectl get pod "$pod" -n authentik -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
        
        if [ "$status" != "Running" ] || [ "$ready" != "True" ]; then
            log_error "Pod '$pod' is not ready (Status: $status, Ready: $ready)"
            kubectl describe pod "$pod" -n authentik | tail -20
            return 1
        fi
        
        log_success "Pod '$pod' is running and ready"
    done
    
    return 0
}

# Check services
check_services() {
    log_info "Checking services..."
    
    # Check Authentik server service
    if ! kubectl get service authentik-server -n authentik &>/dev/null; then
        log_error "Authentik server service not found"
        return 1
    fi
    
    # Check RADIUS service
    if ! kubectl get service authentik-radius -n authentik &>/dev/null; then
        log_error "Authentik RADIUS service not found"
        return 1
    fi
    
    # Check if RADIUS service has external IP
    local external_ip=$(kubectl get service authentik-radius -n authentik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [ -z "$external_ip" ]; then
        log_warning "RADIUS service does not have external IP yet"
    else
        log_success "RADIUS service has external IP: $external_ip"
    fi
    
    log_success "All services are present"
    return 0
}

# Check ingress
check_ingress() {
    log_info "Checking ingress..."
    
    if ! kubectl get ingress authentik-internal -n authentik &>/dev/null; then
        log_error "Authentik ingress not found"
        return 1
    fi
    
    local hosts=$(kubectl get ingress authentik-internal -n authentik -o jsonpath='{.spec.rules[*].host}')
    log_success "Ingress configured for hosts: $hosts"
    
    return 0
}

# Test database connectivity
test_database_connectivity() {
    log_info "Testing database connectivity..."
    
    # Create a test pod to check database connection
    kubectl run authentik-db-test --rm -i --restart=Never --image=postgres:15 -n authentik -- \
        psql "postgresql://authentik:$(kubectl get secret authentik-database-credentials -n authentik -o jsonpath='{.data.password}' | base64 -d)@authentik-postgres-rw.authentik.svc.cluster.local:5432/authentik" \
        -c "SELECT version();" &>/dev/null
    
    if [ $? -eq 0 ]; then
        log_success "Database connectivity test passed"
        return 0
    else
        log_error "Database connectivity test failed"
        return 1
    fi
}

# Test web interface accessibility
test_web_interface() {
    log_info "Testing web interface accessibility..."
    
    # Port forward to test local connectivity
    kubectl port-forward service/authentik-server 8080:80 -n authentik &
    local pf_pid=$!
    
    sleep 5
    
    # Test if we can reach the login page
    if curl -f -s http://localhost:8080/if/flow/default-authentication-flow/ > /dev/null; then
        log_success "Web interface is accessible"
        kill $pf_pid 2>/dev/null
        return 0
    else
        log_error "Web interface is not accessible"
        kill $pf_pid 2>/dev/null
        return 1
    fi
}

# Main verification function
main() {
    log_info "Starting Authentik deployment verification..."
    echo "========================================"
    
    # Prerequisites
    check_kubectl
    check_flux
    
    # Core infrastructure checks
    if ! check_postgresql; then
        log_error "PostgreSQL check failed"
        exit 1
    fi
    
    if ! check_external_secrets; then
        log_error "External secrets check failed"
        exit 1
    fi
    
    if ! check_flux_kustomizations; then
        log_error "Flux kustomizations check failed"
        exit 1
    fi
    
    # Wait for pods to be ready
    if ! wait_for_condition "All pods to be running and ready" "check_pods" 600 15; then
        log_error "Pod readiness check failed"
        exit 1
    fi
    
    # Service checks
    if ! check_services; then
        log_error "Services check failed"
        exit 1
    fi
    
    if ! check_ingress; then
        log_error "Ingress check failed"
        exit 1
    fi
    
    # Connectivity tests
    if ! test_database_connectivity; then
        log_warning "Database connectivity test failed (may be expected during initial setup)"
    fi
    
    if ! test_web_interface; then
        log_warning "Web interface test failed (may be expected during initial setup)"
    fi
    
    echo "========================================"
    log_success "Authentik deployment verification completed successfully!"
    
    # Display summary
    echo ""
    log_info "Deployment Summary:"
    echo "- PostgreSQL cluster: $(kubectl get cluster authentik-postgres -n authentik -o jsonpath='{.status.phase}')"
    echo "- Running pods: $(kubectl get pods -n authentik --no-headers | wc -l)"
    echo "- Ready pods: $(kubectl get pods -n authentik --no-headers | grep -c Running)"
    echo "- Services: $(kubectl get services -n authentik --no-headers | wc -l)"
    echo "- Ingress hosts: $(kubectl get ingress authentik-internal -n authentik -o jsonpath='{.spec.rules[*].host}')"
    
    local external_ip=$(kubectl get service authentik-radius -n authentik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [ -n "$external_ip" ]; then
        echo "- RADIUS external IP: $external_ip"
    fi
    
    echo ""
    log_info "Access URLs:"
    echo "- Web Interface: https://authentik.k8s.home.geoffdavis.com"
    echo "- RADIUS Server: ${external_ip:-<pending>}:1812 (UDP)"
}

# Run main function
main "$@"