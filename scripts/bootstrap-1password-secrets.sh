#!/bin/bash
# Bootstrap 1Password Connect secrets for Talos Kubernetes cluster
# Retrieves credentials from "1password connect" entry in Automation vault
# Creates necessary Kubernetes secrets for fresh cluster bootstrap

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CLUSTER_NAME="home-ops"

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
    
    if [[ -z "${OP_ACCOUNT:-}" ]]; then
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

# Validate 1Password Connect entry exists
validate_1password_connect_entry() {
    log "Validating 1Password Connect entry..."
    
    # Check if the entry exists (case-insensitive search)
    local connect_item=""
    if op item get "1password connect" --vault="Automation" &> /dev/null; then
        connect_item="1password connect"
    elif op item get "1Password Connect" --vault="Automation" &> /dev/null; then
        connect_item="1Password Connect"
    else
        error "1Password Connect entry not found in Automation vault. Please create it with your Connect credentials."
    fi
    
    # Validate required fields exist
    local has_credentials=false
    local has_token=false
    
    if op item get "$connect_item" --vault="Automation" --fields label=credentials &> /dev/null; then
        has_credentials=true
    fi
    
    if op item get "$connect_item" --vault="Automation" --fields label=token &> /dev/null; then
        has_token=true
    fi
    
    if [[ "$has_credentials" == "false" ]]; then
        error "1Password Connect entry missing 'credentials' field (should contain 1password-credentials.json file)"
    fi
    
    if [[ "$has_token" == "false" ]]; then
        error "1Password Connect entry missing 'token' field (should contain Connect token)"
    fi
    
    success "1Password Connect entry validated: $connect_item"
    echo "$connect_item"
}

# Validate credentials format
validate_credentials_format() {
    local connect_item="$1"
    log "Validating credentials format..."
    
    # Create temporary directory for validation
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    # Extract credentials and validate format
    if op item get "$connect_item" --vault="Automation" --fields label=credentials --format json > "$temp_dir/op-credentials.json" 2>/dev/null; then
        local credentials_content
        credentials_content=$(jq -r '.value' "$temp_dir/op-credentials.json")
        echo "$credentials_content" > "$temp_dir/1password-credentials.json"
        
        # Validate it's proper JSON and has version field
        if jq -e '.version' "$temp_dir/1password-credentials.json" >/dev/null 2>&1; then
            local version
            version=$(jq -r '.version' "$temp_dir/1password-credentials.json")
            if [[ "$version" == "2" ]]; then
                success "Credentials are valid version 2 format"
            else
                error "Credentials are version $version, but version 2 is required"
            fi
        else
            error "Credentials file is not valid JSON or missing version field"
        fi
    else
        error "Cannot retrieve credentials from 1Password Connect entry"
    fi
}

# Validate token format
validate_token_format() {
    local connect_item="$1"
    log "Validating token format..."
    
    # Create temporary directory for validation
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    if op item get "$connect_item" --vault="Automation" --fields label=token --format json > "$temp_dir/op-token.json" 2>/dev/null; then
        local token
        token=$(jq -r '.value' "$temp_dir/op-token.json")
        
        # Basic token validation (should be a long JWT-like string)
        if [[ ${#token} -gt 100 ]]; then
            success "Connect token appears valid (length: ${#token})"
        else
            error "Connect token appears invalid or too short (length: ${#token})"
        fi
    else
        error "Cannot retrieve token from 1Password Connect entry"
    fi
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

# Create 1Password Connect secrets
create_1password_connect_secrets() {
    local connect_item="$1"
    log "Creating 1Password Connect secrets..."
    
    # Create temporary directory for secrets
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    # Create onepassword-connect namespace
    kubectl create namespace onepassword-connect --dry-run=client -o yaml | kubectl apply -f -
    success "Created/verified onepassword-connect namespace"
    
    # Get and create 1Password Connect credentials secret
    if op item get "$connect_item" --vault="Automation" --fields label=credentials --format json > "$temp_dir/op-credentials.json" 2>/dev/null; then
        local credentials_content
        credentials_content=$(jq -r '.value' "$temp_dir/op-credentials.json")
        echo "$credentials_content" > "$temp_dir/1password-credentials.json"
        
        kubectl create secret generic onepassword-connect-credentials \
            --namespace=onepassword-connect \
            --from-file=1password-credentials.json="$temp_dir/1password-credentials.json" \
            --dry-run=client -o yaml | kubectl apply -f -
        success "Created 1Password Connect credentials secret"
    else
        error "Failed to retrieve 1Password Connect credentials"
    fi
    
    # Get and create 1Password Connect token secret
    if op item get "$connect_item" --vault="Automation" --fields label=token --format json > "$temp_dir/op-token.json" 2>/dev/null; then
        local token
        token=$(jq -r '.value' "$temp_dir/op-token.json")
        kubectl create secret generic onepassword-connect-token \
            --namespace=onepassword-connect \
            --from-literal=token="$token" \
            --dry-run=client -o yaml | kubectl apply -f -
        success "Created 1Password Connect token secret"
    else
        error "Failed to retrieve 1Password Connect token"
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
            error "Credentials in secret are not version 2 format or invalid"
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

# Main execution
main() {
    log "Starting 1Password Connect secrets bootstrap for $CLUSTER_NAME cluster..."
    echo ""
    
    check_prerequisites
    
    # Validate 1Password Connect entry
    local connect_item
    connect_item=$(validate_1password_connect_entry)
    
    # Validate credentials and token format
    validate_credentials_format "$connect_item"
    validate_token_format "$connect_item"
    
    # Check if cluster is accessible
    if check_cluster_accessibility; then
        # Create the secrets
        create_1password_connect_secrets "$connect_item"
        validate_created_secrets
        
        log "1Password Connect secrets bootstrap completed successfully!"
        echo ""
        echo "Next steps:"
        echo "1. Deploy 1Password Connect: kubectl apply -k infrastructure/onepassword-connect/"
        echo "2. Wait for deployment: kubectl rollout status deployment -n onepassword-connect onepassword-connect"
        echo "3. Run validation: ./scripts/validate-1password-connect.sh"
        echo "4. Continue with infrastructure deployment"
    else
        warn "Cluster not accessible - secrets will be created when cluster is available"
        echo ""
        echo "To create secrets after cluster bootstrap:"
        echo "1. Ensure cluster is accessible: kubectl get namespaces"
        echo "2. Re-run this script: ./scripts/bootstrap-1password-secrets.sh"
    fi
}

# Change to repository root
cd "$(dirname "$0")/.."

# Run main function
main "$@"