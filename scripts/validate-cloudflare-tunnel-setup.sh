#!/bin/bash
# Validation script for Cloudflare tunnel credential setup
# This script validates that the tunnel credentials are properly configured

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CLUSTER_NAME="home-ops"
TUNNEL_NAME="home-ops-tunnel"
VAULT_NAME="Automation"
CREDENTIAL_TITLE="Home-ops cloudflare-tunnel.json"

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

# Validate 1Password credentials
validate_1password_credentials() {
    log "Validating 1Password tunnel credentials..."

    if op item get "$CREDENTIAL_TITLE" --vault="$VAULT_NAME" &> /dev/null; then
        success "Tunnel credentials found in 1Password"

        # Test credential retrieval
        local temp_file="/tmp/validate-tunnel-creds.json"
        if op document get "$CREDENTIAL_TITLE" --vault="$VAULT_NAME" --output="$temp_file" 2>/dev/null; then
            if jq . "$temp_file" >/dev/null 2>&1; then
                local file_size
                file_size=$(wc -c < "$temp_file")
                success "Credentials are valid JSON ($file_size bytes)"
                rm -f "$temp_file"
            else
                error "Credentials are not valid JSON"
                rm -f "$temp_file"
                return 1
            fi
        else
            error "Cannot retrieve credentials from 1Password"
            return 1
        fi
    else
        error "Tunnel credentials not found in 1Password"
        return 1
    fi
}

# Validate Cloudflare tunnel
validate_cloudflare_tunnel() {
    log "Validating Cloudflare tunnel..."

    if command -v mise &> /dev/null && mise exec -- cloudflared --version &> /dev/null; then
        if mise exec -- cloudflared tunnel list 2>/dev/null | grep -q "$TUNNEL_NAME"; then
            local tunnel_id
            tunnel_id=$(mise exec -- cloudflared tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}')
            success "Tunnel '$TUNNEL_NAME' exists (ID: ${tunnel_id:0:8}...)"
            echo "$tunnel_id"
        else
            error "Tunnel '$TUNNEL_NAME' not found in Cloudflare"
            return 1
        fi
    else
        warn "cloudflared CLI not available - skipping tunnel validation"
        return 0
    fi
}

# Validate Kubernetes ExternalSecret
validate_external_secret() {
    log "Validating Kubernetes ExternalSecret..."

    if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
        # Check if namespace exists
        if kubectl get namespace cloudflare-tunnel &> /dev/null; then
            success "Cloudflare tunnel namespace exists"

            # Check ExternalSecret
            if kubectl get externalsecret cloudflare-tunnel-credentials -n cloudflare-tunnel &> /dev/null; then
                local secret_status
                secret_status=$(kubectl get externalsecret cloudflare-tunnel-credentials -n cloudflare-tunnel -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")

                if [[ "$secret_status" == "True" ]]; then
                    success "ExternalSecret is successfully syncing"

                    # Check if secret exists
                    if kubectl get secret cloudflare-tunnel-credentials -n cloudflare-tunnel &> /dev/null; then
                        success "Tunnel credentials secret exists in cluster"
                    else
                        warn "ExternalSecret syncing but secret not found"
                    fi
                else
                    warn "ExternalSecret status: $secret_status"
                fi
            else
                warn "ExternalSecret not found"
            fi
        else
            warn "Cloudflare tunnel namespace not found"
        fi
    else
        warn "Kubernetes cluster not accessible - skipping ExternalSecret validation"
    fi
}

# Validate tunnel deployment
validate_tunnel_deployment() {
    log "Validating tunnel deployment..."

    if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
        if kubectl get deployment cloudflare-tunnel -n cloudflare-tunnel &> /dev/null; then
            local ready_replicas
            ready_replicas=$(kubectl get deployment cloudflare-tunnel -n cloudflare-tunnel -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            local desired_replicas
            desired_replicas=$(kubectl get deployment cloudflare-tunnel -n cloudflare-tunnel -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

            if [[ "$ready_replicas" == "$desired_replicas" && "$ready_replicas" -gt 0 ]]; then
                success "Tunnel deployment is healthy ($ready_replicas/$desired_replicas replicas ready)"
            else
                warn "Tunnel deployment not fully ready ($ready_replicas/$desired_replicas replicas ready)"
            fi

            # Check pod status
            local pod_count
            pod_count=$(kubectl get pods -n cloudflare-tunnel -l app=cloudflare-tunnel --field-selector=status.phase=Running 2>/dev/null | wc -l || echo "0")
            if [[ $pod_count -gt 1 ]]; then  # Account for header line
                success "Tunnel pods are running"
            else
                warn "No running tunnel pods found"
            fi
        else
            warn "Tunnel deployment not found"
        fi
    else
        warn "Kubernetes cluster not accessible - skipping deployment validation"
    fi
}

# Main validation
main() {
    echo "=============================================="
    echo "  Cloudflare Tunnel Setup Validation"
    echo "=============================================="
    echo ""

    local validation_passed=0
    local total_checks=4

    # Validate 1Password credentials
    if validate_1password_credentials; then
        validation_passed=$((validation_passed + 1))
    fi
    echo ""

    # Validate Cloudflare tunnel
    local tunnel_id=""
    if tunnel_id=$(validate_cloudflare_tunnel); then
        validation_passed=$((validation_passed + 1))
    fi
    echo ""

    # Validate ExternalSecret
    validate_external_secret
    echo ""

    # Validate deployment
    validate_tunnel_deployment
    echo ""

    # Summary
    echo "=============================================="
    echo "  VALIDATION SUMMARY"
    echo "=============================================="
    echo ""

    if [[ $validation_passed -eq 2 ]]; then
        success "Core validation passed ($validation_passed/2 critical checks)"
        echo ""
        echo "✅ Tunnel credentials are properly configured"
        echo "✅ Ready for Kubernetes deployment"

        if [[ -n "$tunnel_id" ]]; then
            echo ""
            echo "📋 Tunnel Information:"
            echo "  Name: $TUNNEL_NAME"
            echo "  ID: ${tunnel_id:0:8}..."
            echo "  CNAME Target: $tunnel_id.cfargotunnel.com"
        fi
    else
        error "Validation failed ($validation_passed/2 critical checks passed)"
        echo ""
        echo "❌ Tunnel credentials need attention"
        echo "💡 Run: ./scripts/create-cloudflare-tunnel-credentials.sh"
    fi
    echo ""
}

# Change to repository root
cd "$(dirname "$0")/.."

# Run main function
main "$@"
