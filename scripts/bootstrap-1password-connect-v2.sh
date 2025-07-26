#!/bin/bash
# Enhanced 1Password Connect Bootstrap Script
# Supports both separate entries and legacy single entry formats
# Uses configuration system for flexible credential management

set -euo pipefail

# Load configuration
cd "$(dirname "$0")/.."
source scripts/bootstrap-config.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load configuration values
CLUSTER_NAME=$(get_cluster_name)
OP_ACCOUNT=$(get_op_account)

# Logging functions
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
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v op &> /dev/null; then
        error "1Password CLI (op) is not installed. Please install it first."
    fi
    
    if ! op account list &> /dev/null; then
        error "1Password CLI is not authenticated. Please run 'op signin' first."
    fi
    
    if [[ -z "$OP_ACCOUNT" ]]; then
        error "OP_ACCOUNT environment variable is not set. Please export OP_ACCOUNT=your-account-name"
    fi
    
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed. Please install it first."
    fi
    
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it first."
    fi
    
    success "All prerequisites met"
}

# Check cluster accessibility
check_cluster_accessibility() {
    log "Checking cluster accessibility..."
    
    if kubectl get namespaces &> /dev/null; then
        success "Kubernetes cluster is accessible"
        return 0
    else
        warn "Kubernetes cluster not accessible - this is expected for fresh bootstrap"
        return 1
    fi
}

# Create 1Password Connect secrets using new configuration system
create_1password_connect_secrets() {
    log "Creating 1Password Connect secrets using configuration system..."
    
    # Create temporary directory for secrets
    local temp_dir
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT
    
    # Create onepassword-connect namespace
    kubectl create namespace onepassword-connect --dry-run=client -o yaml | kubectl apply -f -
    success "Created/verified onepassword-connect namespace"
    
    # Try to get credentials using configured sources
    if try_get_connect_credentials "$temp_dir"; then
        success "Successfully retrieved 1Password Connect credentials"
    else
        error "Failed to retrieve 1Password Connect credentials from any configured source"
    fi
    
    # Create credentials secret
    if [[ -f "$temp_dir/1password-credentials.json" ]]; then
        kubectl create secret generic onepassword-connect-credentials \
            --namespace=onepassword-connect \
            --from-file=1password-credentials.json="$temp_dir/1password-credentials.json" \
            --dry-run=client -o yaml | kubectl apply -f -
        success "Created 1Password Connect credentials secret"
    else
        error "Credentials file not found after retrieval"
    fi
    
    # Create token secret
    if [[ -f "$temp_dir/connect-token.txt" ]]; then
        local token
        token=$(cat "$temp_dir/connect-token.txt")
        kubectl create secret generic onepassword-connect-token \
            --namespace=onepassword-connect \
            --from-literal=token="$token" \
            --dry-run=client -o yaml | kubectl apply -f -
        success "Created 1Password Connect token secret"
    else
        error "Connect token not found after retrieval"
    fi
}

# Validate created secrets
validate_created_secrets() {
    log "Validating created secrets..."
    
    # Check credentials secret
    if kubectl get secret -n onepassword-connect onepassword-connect-credentials &> /dev/null; then
        success "onepassword-connect-credentials secret exists"
        
        # Validate credentials format in secret
        if kubectl get secret -n onepassword-connect onepassword-connect-credentials -o jsonpath='{.data.1password-credentials\.json}' | base64 -d | jq -r '.version' 2>/dev/null | grep -q "2"; then
            success "Credentials in secret are version 2 format"
        else
            warn "Credentials in secret appear to be truncated or invalid"
            warn "This may be due to 1Password field size limits in legacy entries"
            warn "Consider using separate entries for credentials and token"
        fi
    else
        error "onepassword-connect-credentials secret not found"
    fi
    
    # Check token secret
    if kubectl get secret -n onepassword-connect onepassword-connect-token &> /dev/null; then
        success "onepassword-connect-token secret exists"
        
        # Validate token length
        local token_length
        token_length=$(kubectl get secret -n onepassword-connect onepassword-connect-token -o jsonpath='{.data.token}' | base64 -d | wc -c)
        if [[ "$token_length" -gt 100 ]]; then
            success "Connect token in secret appears valid (length: $token_length)"
        else
            error "Connect token in secret appears invalid or too short (length: $token_length)"
        fi
    else
        error "onepassword-connect-token secret not found"
    fi
}

# Show configuration summary
show_config_summary() {
    log "1Password Connect Configuration Summary:"
    echo "Cluster: $CLUSTER_NAME"
    echo "Account: $OP_ACCOUNT"
    echo ""
    echo "Configured credential sources:"
    
    local sources
    sources=$(get_op_connect_credential_sources)
    
    if [[ -z "$sources" ]]; then
        echo "  - Legacy single entry (fallback)"
    else
        local source_num=1
        for source in $sources; do
            local source_index="${source%%:*}"
            local source_type="${source##*:}"
            
            echo "  $source_num. $source_type"
            case "$source_type" in
                "separate_entries")
                    local credentials_item token_item
                    credentials_item=$(get_op_connect_source_config "$source_index" "credentials_item")
                    token_item=$(get_op_connect_source_config "$source_index" "token_item")
                    echo "     Credentials: $credentials_item"
                    echo "     Token: $token_item"
                    ;;
                "legacy_entry")
                    local legacy_item
                    legacy_item=$(get_op_connect_source_config "$source_index" "item")
                    echo "     Entry: $legacy_item"
                    ;;
            esac
            ((source_num++))
        done
    fi
    echo ""
}

# Main execution
main() {
    log "Starting enhanced 1Password Connect secrets bootstrap for $CLUSTER_NAME cluster..."
    echo ""
    
    check_prerequisites
    show_config_summary
    
    # Check if cluster is accessible
    if check_cluster_accessibility; then
        # Create the secrets
        create_1password_connect_secrets
        validate_created_secrets
        
        log "1Password Connect secrets bootstrap completed successfully!"
        echo ""
        echo "Next steps:"
        echo "1. Deploy 1Password Connect: kubectl apply -k infrastructure/onepassword-connect/"
        echo "2. Wait for deployment: kubectl rollout status deployment -n onepassword-connect onepassword-connect"
        echo "3. Run validation: ./scripts/validate-1password-secrets.sh"
        echo "4. Continue with infrastructure deployment"
    else
        warn "Cluster not accessible - secrets will be created when cluster is available"
        echo ""
        echo "To create secrets after cluster bootstrap:"
        echo "1. Ensure cluster is accessible: kubectl get namespaces"
        echo "2. Re-run this script: ./scripts/bootstrap-1password-connect-v2.sh"
    fi
}

# Run main function
main "$@"