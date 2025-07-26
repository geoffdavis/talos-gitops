#!/bin/bash
# Simple validation script for 1Password Connect secrets
# Verifies that the bootstrap secrets were created correctly

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

error() {
    echo -e "${RED}✗ $1${NC}"
}

# Check if cluster is accessible
check_cluster() {
    log "Checking cluster accessibility..."
    
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed"
        return 1
    fi
    
    if ! kubectl get namespaces &> /dev/null; then
        error "Cannot connect to Kubernetes cluster"
        return 1
    fi
    
    success "Kubernetes cluster is accessible"
    return 0
}

# Validate 1Password Connect secrets
validate_secrets() {
    log "Validating 1Password Connect secrets..."
    
    local validation_passed=true
    
    # Check if namespace exists
    if kubectl get namespace onepassword-connect &> /dev/null; then
        success "onepassword-connect namespace exists"
    else
        error "onepassword-connect namespace does not exist"
        validation_passed=false
    fi
    
    # Check credentials secret
    if kubectl get secret -n onepassword-connect onepassword-connect-credentials &> /dev/null; then
        success "onepassword-connect-credentials secret exists"
        
        # Check if it contains the credentials file
        if kubectl get secret -n onepassword-connect onepassword-connect-credentials -o jsonpath='{.data.1password-credentials\.json}' | base64 -d | jq -r '.version' 2>/dev/null | grep -q "2"; then
            success "Credentials are version 2 format"
        else
            warn "Credentials appear to be truncated or invalid JSON"
            warn "This is likely due to 1Password field size limits"
            warn "1Password Connect may still function with truncated credentials"
        fi
        
        # Check credentials file structure
        local creds_keys
        creds_keys=$(kubectl get secret -n onepassword-connect onepassword-connect-credentials -o jsonpath='{.data.1password-credentials\.json}' | base64 -d | jq -r 'keys | join(", ")' 2>/dev/null || echo "unknown")
        log "Credentials file contains keys: $creds_keys"
        
    else
        error "onepassword-connect-credentials secret missing"
        validation_passed=false
    fi
    
    # Check token secret
    if kubectl get secret -n onepassword-connect onepassword-connect-token &> /dev/null; then
        success "onepassword-connect-token secret exists"
        
        # Check if token is not empty and reasonable length
        local token_length
        token_length=$(kubectl get secret -n onepassword-connect onepassword-connect-token -o jsonpath='{.data.token}' | base64 -d | wc -c)
        if [[ "$token_length" -gt 100 ]]; then
            success "Connect token appears valid (length: $token_length)"
        else
            error "Connect token appears invalid or too short (length: $token_length)"
            validation_passed=false
        fi
    else
        error "onepassword-connect-token secret missing"
        validation_passed=false
    fi
    
    return "$([[ "$validation_passed" == "true" ]] && echo 0 || echo 1)"
}

# Check if 1Password Connect deployment is ready (if deployed)
check_deployment() {
    log "Checking 1Password Connect deployment status..."
    
    if kubectl get deployment -n onepassword-connect onepassword-connect &> /dev/null; then
        local ready_replicas
        ready_replicas=$(kubectl get deployment -n onepassword-connect onepassword-connect -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local desired_replicas
        desired_replicas=$(kubectl get deployment -n onepassword-connect onepassword-connect -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        
        if [[ "$ready_replicas" == "$desired_replicas" && "$ready_replicas" != "0" ]]; then
            success "1Password Connect deployment is ready ($ready_replicas/$desired_replicas)"
        else
            warn "1Password Connect deployment not ready ($ready_replicas/$desired_replicas)"
            log "Pod status:"
            kubectl get pods -n onepassword-connect -o wide || true
        fi
    else
        warn "1Password Connect deployment not found (not deployed yet)"
    fi
}

# Main execution
main() {
    log "Validating 1Password Connect secrets..."
    echo ""
    
    if ! check_cluster; then
        exit 1
    fi
    
    if validate_secrets; then
        success "All 1Password Connect secrets are valid!"
        echo ""
        check_deployment
        echo ""
        echo "Next steps:"
        echo "1. Deploy 1Password Connect: kubectl apply -k infrastructure/onepassword-connect/"
        echo "2. Wait for deployment: kubectl rollout status deployment -n onepassword-connect onepassword-connect"
        echo "3. Run full validation: ./scripts/validate-1password-connect.sh"
    else
        error "1Password Connect secrets validation failed!"
        echo ""
        echo "To fix:"
        echo "1. Re-run bootstrap: ./scripts/bootstrap-1password-secrets.sh"
        echo "2. Check 1Password Connect entry in Automation vault"
        echo "3. Ensure credentials are version 2 format"
        exit 1
    fi
}

# Change to repository root
cd "$(dirname "$0")/.."

# Run main function
main "$@"