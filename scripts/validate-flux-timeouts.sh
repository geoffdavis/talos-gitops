#!/bin/bash

# Flux Timeout Configuration Validation Script
# This script validates that all Flux resources have appropriate timeout configurations

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_CHECKS++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNING_CHECKS++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_CHECKS++))
}

increment_total() {
    ((TOTAL_CHECKS++))
}

# Check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log_info "Connected to Kubernetes cluster"
}

# Check if Flux is installed
check_flux() {
    if ! kubectl get namespace flux-system &> /dev/null; then
        log_error "Flux system namespace not found"
        exit 1
    fi
    
    log_info "Flux system namespace found"
}

# Validate HelmRelease timeout configurations
validate_helmrelease_timeouts() {
    log_info "Validating HelmRelease timeout configurations..."
    
    # Get all HelmReleases
    local helmreleases
    helmreleases=$(kubectl get helmrelease -A -o jsonpath='{range .items[*]}{.metadata.namespace}{","}{.metadata.name}{"\n"}{end}')
    
    if [[ -z "$helmreleases" ]]; then
        log_warning "No HelmReleases found"
        return
    fi
    
    while IFS=',' read -r namespace name; do
        [[ -z "$namespace" ]] && continue
        
        increment_total
        log_info "Checking HelmRelease: $namespace/$name"
        
        # Get HelmRelease spec
        local spec
        spec=$(kubectl get helmrelease "$name" -n "$namespace" -o json)
        
        # Check main timeout
        local timeout
        timeout=$(echo "$spec" | jq -r '.spec.timeout // "null"')
        if [[ "$timeout" == "null" ]]; then
            log_error "HelmRelease $namespace/$name missing main timeout"
            continue
        fi
        
        # Check install timeout
        local install_timeout
        install_timeout=$(echo "$spec" | jq -r '.spec.install.timeout // "null"')
        if [[ "$install_timeout" == "null" ]]; then
            log_error "HelmRelease $namespace/$name missing install timeout"
            continue
        fi
        
        # Check upgrade timeout
        local upgrade_timeout
        upgrade_timeout=$(echo "$spec" | jq -r '.spec.upgrade.timeout // "null"')
        if [[ "$upgrade_timeout" == "null" ]]; then
            log_error "HelmRelease $namespace/$name missing upgrade timeout"
            continue
        fi
        
        # Check rollback timeout
        local rollback_timeout
        rollback_timeout=$(echo "$spec" | jq -r '.spec.rollback.timeout // "null"')
        if [[ "$rollback_timeout" == "null" ]]; then
            log_warning "HelmRelease $namespace/$name missing rollback timeout"
        fi
        
        # Check remediation retries
        local install_retries
        install_retries=$(echo "$spec" | jq -r '.spec.install.remediation.retries // "null"')
        if [[ "$install_retries" == "null" ]]; then
            log_warning "HelmRelease $namespace/$name missing install remediation retries"
        fi
        
        local upgrade_retries
        upgrade_retries=$(echo "$spec" | jq -r '.spec.upgrade.remediation.retries // "null"')
        if [[ "$upgrade_retries" == "null" ]]; then
            log_warning "HelmRelease $namespace/$name missing upgrade remediation retries"
        fi
        
        # Validate timeout values based on component type
        local component_type="unknown"
        case "$name" in
            "longhorn"|"cilium")
                component_type="critical"
                ;;
            "cert-manager"|"ingress-nginx")
                component_type="standard"
                ;;
            "external-dns"|"monitoring"*)
                component_type="simple"
                ;;
        esac
        
        # Convert timeout to minutes for comparison
        local timeout_minutes
        timeout_minutes=$(echo "$timeout" | sed 's/m$//' | sed 's/s$//' | awk '{print int($1/60)}')
        
        case "$component_type" in
            "critical")
                if [[ "$timeout_minutes" -lt 15 ]]; then
                    log_warning "HelmRelease $namespace/$name timeout ($timeout) may be too short for critical component"
                else
                    log_success "HelmRelease $namespace/$name has appropriate timeout for critical component"
                fi
                ;;
            "standard")
                if [[ "$timeout_minutes" -lt 10 ]]; then
                    log_warning "HelmRelease $namespace/$name timeout ($timeout) may be too short for standard component"
                else
                    log_success "HelmRelease $namespace/$name has appropriate timeout for standard component"
                fi
                ;;
            "simple")
                if [[ "$timeout_minutes" -lt 5 ]]; then
                    log_warning "HelmRelease $namespace/$name timeout ($timeout) may be too short"
                else
                    log_success "HelmRelease $namespace/$name has appropriate timeout for simple component"
                fi
                ;;
            *)
                log_success "HelmRelease $namespace/$name has timeout configured: $timeout"
                ;;
        esac
        
    done <<< "$helmreleases"
}

# Validate Kustomization timeout configurations
validate_kustomization_timeouts() {
    log_info "Validating Kustomization timeout configurations..."
    
    # Get all Kustomizations
    local kustomizations
    kustomizations=$(kubectl get kustomization -A -o jsonpath='{range .items[*]}{.metadata.namespace}{","}{.metadata.name}{"\n"}{end}')
    
    if [[ -z "$kustomizations" ]]; then
        log_warning "No Kustomizations found"
        return
    fi
    
    while IFS=',' read -r namespace name; do
        [[ -z "$namespace" ]] && continue
        
        increment_total
        log_info "Checking Kustomization: $namespace/$name"
        
        # Get Kustomization spec
        local spec
        spec=$(kubectl get kustomization "$name" -n "$namespace" -o json)
        
        # Check timeout
        local timeout
        timeout=$(echo "$spec" | jq -r '.spec.timeout // "null"')
        if [[ "$timeout" == "null" ]]; then
            log_error "Kustomization $namespace/$name missing timeout"
            continue
        fi
        
        # Check retry interval
        local retry_interval
        retry_interval=$(echo "$spec" | jq -r '.spec.retryInterval // "null"')
        if [[ "$retry_interval" == "null" ]]; then
            log_warning "Kustomization $namespace/$name missing retryInterval"
        fi
        
        # Check wait setting
        local wait
        wait=$(echo "$spec" | jq -r '.spec.wait // "null"')
        if [[ "$wait" != "true" ]]; then
            log_warning "Kustomization $namespace/$name should have wait: true"
        fi
        
        log_success "Kustomization $namespace/$name has timeout configured: $timeout"
        
    done <<< "$kustomizations"
}

# Validate GitRepository timeout configurations
validate_gitrepository_timeouts() {
    log_info "Validating GitRepository timeout configurations..."
    
    # Get all GitRepositories
    local gitrepos
    gitrepos=$(kubectl get gitrepository -A -o jsonpath='{range .items[*]}{.metadata.namespace}{","}{.metadata.name}{"\n"}{end}')
    
    if [[ -z "$gitrepos" ]]; then
        log_warning "No GitRepositories found"
        return
    fi
    
    while IFS=',' read -r namespace name; do
        [[ -z "$namespace" ]] && continue
        
        increment_total
        log_info "Checking GitRepository: $namespace/$name"
        
        # Get GitRepository spec
        local spec
        spec=$(kubectl get gitrepository "$name" -n "$namespace" -o json)
        
        # Check timeout
        local timeout
        timeout=$(echo "$spec" | jq -r '.spec.timeout // "null"')
        if [[ "$timeout" == "null" ]]; then
            log_error "GitRepository $namespace/$name missing timeout"
            continue
        fi
        
        log_success "GitRepository $namespace/$name has timeout configured: $timeout"
        
    done <<< "$gitrepos"
}

# Validate HelmRepository timeout configurations
validate_helmrepository_timeouts() {
    log_info "Validating HelmRepository timeout configurations..."
    
    # Get all HelmRepositories
    local helmrepos
    helmrepos=$(kubectl get helmrepository -A -o jsonpath='{range .items[*]}{.metadata.namespace}{","}{.metadata.name}{"\n"}{end}')
    
    if [[ -z "$helmrepos" ]]; then
        log_warning "No HelmRepositories found"
        return
    fi
    
    while IFS=',' read -r namespace name; do
        [[ -z "$namespace" ]] && continue
        
        increment_total
        log_info "Checking HelmRepository: $namespace/$name"
        
        # Get HelmRepository spec
        local spec
        spec=$(kubectl get helmrepository "$name" -n "$namespace" -o json)
        
        # Check timeout
        local timeout
        timeout=$(echo "$spec" | jq -r '.spec.timeout // "null"')
        if [[ "$timeout" == "null" ]]; then
            log_error "HelmRepository $namespace/$name missing timeout"
            continue
        fi
        
        log_success "HelmRepository $namespace/$name has timeout configured: $timeout"
        
    done <<< "$helmrepos"
}

# Check Flux controller health
check_flux_controllers() {
    log_info "Checking Flux controller health..."
    
    local controllers=("source-controller" "kustomize-controller" "helm-controller" "notification-controller")
    
    for controller in "${controllers[@]}"; do
        increment_total
        
        if kubectl get deployment "$controller" -n flux-system &> /dev/null; then
            local ready
            ready=$(kubectl get deployment "$controller" -n flux-system -o jsonpath='{.status.readyReplicas}')
            local desired
            desired=$(kubectl get deployment "$controller" -n flux-system -o jsonpath='{.spec.replicas}')
            
            if [[ "$ready" == "$desired" ]]; then
                log_success "Flux controller $controller is ready ($ready/$desired)"
            else
                log_error "Flux controller $controller is not ready ($ready/$desired)"
            fi
        else
            log_error "Flux controller $controller not found"
        fi
    done
}

# Check monitoring configuration
check_monitoring_config() {
    log_info "Checking Flux monitoring configuration..."
    
    increment_total
    if kubectl get servicemonitor flux-system-source-controller -n monitoring &> /dev/null; then
        log_success "Flux source-controller ServiceMonitor found"
    else
        log_warning "Flux source-controller ServiceMonitor not found"
    fi
    
    increment_total
    if kubectl get servicemonitor flux-system-helm-controller -n monitoring &> /dev/null; then
        log_success "Flux helm-controller ServiceMonitor found"
    else
        log_warning "Flux helm-controller ServiceMonitor not found"
    fi
    
    increment_total
    if kubectl get prometheusrule flux-system-alerts -n monitoring &> /dev/null; then
        log_success "Flux PrometheusRule found"
    else
        log_warning "Flux PrometheusRule not found"
    fi
}

# Test timeout scenarios (optional)
test_timeout_scenarios() {
    if [[ "${1:-}" != "--test-scenarios" ]]; then
        return
    fi
    
    log_info "Testing timeout scenarios (this may take several minutes)..."
    
    # Create a test HelmRelease with short timeout
    cat <<EOF | kubectl apply -f -
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: timeout-test
  namespace: default
spec:
  interval: 1m
  timeout: 30s
  install:
    timeout: 30s
    remediation:
      retries: 1
  chart:
    spec:
      chart: nginx
      version: "1.0.0"
      sourceRef:
        kind: HelmRepository
        name: bitnami
        namespace: flux-system
EOF
    
    log_info "Created test HelmRelease with short timeout"
    
    # Wait and check if it times out as expected
    sleep 60
    
    local status
    status=$(kubectl get helmrelease timeout-test -n default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    
    if [[ "$status" == "False" ]]; then
        log_success "Timeout test worked - HelmRelease failed as expected"
    else
        log_warning "Timeout test inconclusive - HelmRelease status: $status"
    fi
    
    # Cleanup
    kubectl delete helmrelease timeout-test -n default --ignore-not-found=true
    log_info "Cleaned up test resources"
}

# Generate summary report
generate_summary() {
    echo
    echo "=================================="
    echo "Flux Timeout Validation Summary"
    echo "=================================="
    echo "Total Checks: $TOTAL_CHECKS"
    echo -e "Passed: ${GREEN}$PASSED_CHECKS${NC}"
    echo -e "Warnings: ${YELLOW}$WARNING_CHECKS${NC}"
    echo -e "Failed: ${RED}$FAILED_CHECKS${NC}"
    echo
    
    if [[ $FAILED_CHECKS -eq 0 ]]; then
        echo -e "${GREEN}✓ All critical timeout configurations are in place${NC}"
        if [[ $WARNING_CHECKS -gt 0 ]]; then
            echo -e "${YELLOW}⚠ Some optional configurations could be improved${NC}"
        fi
        return 0
    else
        echo -e "${RED}✗ Some timeout configurations are missing or incorrect${NC}"
        echo "Please review the failed checks above and update configurations"
        return 1
    fi
}

# Main execution
main() {
    echo "Flux Timeout Configuration Validation"
    echo "====================================="
    echo
    
    check_kubectl
    check_flux
    
    validate_helmrelease_timeouts
    validate_kustomization_timeouts
    validate_gitrepository_timeouts
    validate_helmrepository_timeouts
    check_flux_controllers
    check_monitoring_config
    
    test_timeout_scenarios "$@"
    
    generate_summary
}

# Run main function with all arguments
main "$@"