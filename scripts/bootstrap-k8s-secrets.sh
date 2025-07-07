#!/bin/bash
# Bootstrap Kubernetes secrets from 1Password for Home-Ops Talos GitOps cluster

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
    
    success "All prerequisites met"
}

# Create 1Password items if they don't exist
create_1password_items() {
    log "Creating 1Password items..."
    
    # Check if Cloudflare Tunnel credentials exist
    if ! op item get "Cloudflare Tunnel Credentials" &> /dev/null; then
        warn "Cloudflare Tunnel Credentials item not found. Please create it manually with your tunnel credentials."
        echo "  This should include fields: 'credentials.json' (the JSON credentials file) and 'tunnel-token' (the tunnel token)"
    else
        success "Cloudflare Tunnel Credentials item exists"
    fi
    
    # Check if BGP authentication exists
    if ! op item get "BGP Authentication - $CLUSTER_NAME" &> /dev/null; then
        log "Creating BGP Authentication - $CLUSTER_NAME item..."
        op item create \
            --category="Secure Note" \
            --title="BGP Authentication - $CLUSTER_NAME" \
            --vault="Automation" \
            "password[password]=$(openssl rand -base64 16)"
        success "Created BGP Authentication - $CLUSTER_NAME item"
    else
        success "BGP Authentication - $CLUSTER_NAME item exists"
    fi
    
    # Check if Cloudflare API token exists
    if ! op item get "Cloudflare API Token" &> /dev/null; then
        warn "Cloudflare API Token item not found. Please create it manually with your Cloudflare API token."
        echo "  op item create --category='API Credential' --title='Cloudflare API Token' --vault='Automation' 'token[password]=YOUR_TOKEN_HERE'"
    else
        success "Cloudflare API Token item exists"
    fi
    
    # Check if 1Password Connect credentials exist
    if ! op item get "1Password Connect" &> /dev/null; then
        warn "1Password Connect item not found. Please create it manually with your Connect credentials."
        echo "  This should include the 1password-credentials.json file and Connect token"
    else
        success "1Password Connect item exists"
    fi
    
    # Check if Longhorn UI credentials exist
    if ! op item get "Longhorn UI Credentials - $CLUSTER_NAME" &> /dev/null; then
        log "Creating Longhorn UI Credentials - $CLUSTER_NAME item..."
        local password
        password=$(openssl rand -base64 16)
        local auth_string
        auth_string=$(htpasswd -nb admin "$password" | base64 -w 0)
        
        op item create \
            --category="Login" \
            --title="Longhorn UI Credentials - $CLUSTER_NAME" \
            --vault="Automation" \
            "username=admin" \
            "password=$password" \
            "auth[password]=$auth_string"
        success "Created Longhorn UI Credentials - $CLUSTER_NAME item"
    else
        success "Longhorn UI Credentials - $CLUSTER_NAME item exists"
    fi
}

# Bootstrap cluster secrets
bootstrap_cluster_secrets() {
    log "Bootstrapping Kubernetes secrets..."
    
    # Check if cluster is accessible
    if ! kubectl get namespaces &> /dev/null; then
        error "Kubernetes cluster not accessible. Please ensure you have a valid kubeconfig."
    fi
    
    # Create temporary directory for secrets
    local temp_dir
    temp_dir=$(mktemp -d)
    
    log "Creating Kubernetes secrets..."
    
    # Create 1Password Connect secrets
    kubectl create namespace onepassword-connect --dry-run=client -o yaml | kubectl apply -f -
    
    # Get 1Password Connect credentials
    if op item get "1Password Connect" --fields label=credentials --format json > "$temp_dir/op-credentials.json" 2>/dev/null; then
        kubectl create secret generic onepassword-connect-credentials \
            --namespace=onepassword-connect \
            --from-file=1password-credentials.json="$temp_dir/op-credentials.json" \
            --dry-run=client -o yaml | kubectl apply -f -
        success "Created 1Password Connect credentials secret"
    else
        warn "1Password Connect credentials not found"
    fi
    
    # Get 1Password Connect token
    if op item get "1Password Connect" --fields label=token --format json > "$temp_dir/op-token.json" 2>/dev/null; then
        local token
        token=$(jq -r '.value' "$temp_dir/op-token.json")
        kubectl create secret generic onepassword-connect-token \
            --namespace=onepassword-connect \
            --from-literal=token="$token" \
            --dry-run=client -o yaml | kubectl apply -f -
        success "Created 1Password Connect token secret"
    else
        warn "1Password Connect token not found"
    fi
    
    # Create BGP authentication secret
    kubectl create namespace cilium-system --dry-run=client -o yaml | kubectl apply -f -
    
    if op item get "BGP Authentication - $CLUSTER_NAME" --fields label=password --format json > "$temp_dir/bgp-auth.json" 2>/dev/null; then
        local bgp_password
        bgp_password=$(jq -r '.value' "$temp_dir/bgp-auth.json")
        kubectl create secret generic cilium-bgp-auth \
            --namespace=cilium-system \
            --from-literal=password="$bgp_password" \
            --dry-run=client -o yaml | kubectl apply -f -
        success "Created BGP authentication secret"
    else
        warn "BGP authentication password not found"
    fi
    
    # Create Cloudflare API token secret
    kubectl create namespace external-dns-system --dry-run=client -o yaml | kubectl apply -f -
    
    if op item get "Cloudflare API Token" --fields label=token --format json > "$temp_dir/cf-token.json" 2>/dev/null; then
        local cf_token
        cf_token=$(jq -r '.value' "$temp_dir/cf-token.json")
        kubectl create secret generic cloudflare-api-token \
            --namespace=external-dns-system \
            --from-literal=api-token="$cf_token" \
            --dry-run=client -o yaml | kubectl apply -f -
        success "Created Cloudflare API token secret"
    else
        warn "Cloudflare API token not found"
    fi
    
    # Create Longhorn auth secret
    kubectl create namespace longhorn-system --dry-run=client -o yaml | kubectl apply -f -
    
    if op item get "Longhorn UI Credentials - $CLUSTER_NAME" --fields label=auth --format json > "$temp_dir/longhorn-auth.json" 2>/dev/null; then
        local auth_string
        auth_string=$(jq -r '.value' "$temp_dir/longhorn-auth.json")
        kubectl create secret generic longhorn-auth \
            --namespace=longhorn-system \
            --from-literal=auth="$auth_string" \
            --dry-run=client -o yaml | kubectl apply -f -
        success "Created Longhorn auth secret"
    else
        warn "Longhorn auth credentials not found"
    fi
    
    # Clean up temporary files
    rm -rf "$temp_dir"
    success "Kubernetes secrets bootstrapped"
}

# Validate GitHub token for Renovate
validate_github_token() {
    log "Validating GitHub token for Renovate..."
    
    if op item get "GitHub Personal Access Token" &> /dev/null; then
        # Try different possible field names for the token
        local token_found=false
        for field in "token" "password" "credential"; do
            if op read "op://Private/GitHub Personal Access Token/$field" &> /dev/null 2>&1; then
                success "GitHub token validated for Renovate (field: $field)"
                token_found=true
                break
            fi
        done
        
        if [[ "$token_found" == "false" ]]; then
            warn "GitHub Personal Access Token item exists but no valid token field found"
            warn "Expected fields: token, password, or credential"
        fi
    else
        warn "GitHub Personal Access Token item not found in 1Password"
        warn "Create it with: op item create --category='API Credential' --title='GitHub Personal Access Token' --vault='Private' 'token[password]=YOUR_TOKEN_HERE'"
    fi
}

# Main execution
main() {
    log "Starting Kubernetes secrets bootstrap process for $CLUSTER_NAME cluster..."
    
    check_prerequisites
    create_1password_items
    bootstrap_cluster_secrets
    validate_github_token
    
    log "Kubernetes secrets bootstrap completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Deploy 1Password Connect: task apps:deploy-onepassword-connect"
    echo "2. Force Flux reconciliation: task flux:reconcile"
    echo "3. Check Flux kustomizations: flux get kustomizations"
}

# Change to repository root
cd "$(dirname "$0")/.."

# Run main function
main "$@"