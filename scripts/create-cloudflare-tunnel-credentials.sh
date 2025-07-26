#!/bin/bash
# Targeted script to create only Cloudflare tunnel credentials
# Safe to run without affecting existing credentials or configurations

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
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites for Cloudflare tunnel credential creation..."

    # Check 1Password CLI
    if ! command -v op &> /dev/null; then
        error "1Password CLI (op) is not installed. Please install it first."
    fi

    if ! op account list &> /dev/null; then
        error "1Password CLI is not authenticated. Please run 'op signin' first."
    fi

    if [[ -z "${OP_ACCOUNT:-}" ]]; then
        error "OP_ACCOUNT environment variable is not set. Please export OP_ACCOUNT=your-account-name"
    fi

    # Check mise tool manager
    if ! command -v mise &> /dev/null; then
        error "mise is not installed. Please install it first."
    fi

    # Check cloudflared CLI via mise
    if ! mise exec -- cloudflared --version &> /dev/null; then
        error "cloudflared CLI not available via mise. Please ensure it's installed: mise install cloudflared"
    fi

    success "All prerequisites met"
}

# Check 1Password Connect connectivity
check_1password_connect() {
    log "Verifying 1Password Connect accessibility..."

    # Check if we can access the Automation vault
    if ! op vault list | grep -q "$VAULT_NAME"; then
        error "Cannot access '$VAULT_NAME' vault. Please check your 1Password permissions."
    fi

    # Test basic 1Password operations
    if ! op item list --vault="$VAULT_NAME" &> /dev/null; then
        error "Cannot list items in '$VAULT_NAME' vault. Please check your 1Password Connect setup."
    fi

    success "1Password Connect is accessible"
}

# Check if tunnel already exists
check_existing_tunnel() {
    log "Checking for existing tunnel: $TUNNEL_NAME"

    local tunnel_exists=false
    local credentials_exist=false

    # Check if tunnel exists in Cloudflare
    if mise exec -- cloudflared tunnel list 2>/dev/null | grep -q "$TUNNEL_NAME"; then
        tunnel_exists=true
        warn "Tunnel '$TUNNEL_NAME' already exists in Cloudflare"
    fi

    # Check if credentials exist in 1Password
    if op item get "$CREDENTIAL_TITLE" --vault="$VAULT_NAME" &> /dev/null; then
        credentials_exist=true
        warn "Credentials '$CREDENTIAL_TITLE' already exist in 1Password"
    fi

    if [[ "$tunnel_exists" == true && "$credentials_exist" == true ]]; then
        warn "Both tunnel and credentials already exist"
        echo ""
        read -r -p "Do you want to recreate the tunnel and credentials? (y/N): " confirm
        if [[ "$confirm" != "y" ]]; then
            log "Skipping tunnel creation - existing setup preserved"
            exit 0
        fi
        warn "Proceeding with tunnel recreation..."
    elif [[ "$tunnel_exists" == true ]]; then
        warn "Tunnel exists but credentials missing - will recreate both"
    elif [[ "$credentials_exist" == true ]]; then
        warn "Credentials exist but tunnel missing - will recreate both"
    else
        success "No existing tunnel or credentials found - proceeding with creation"
    fi
}

# Clean up existing tunnel if needed
cleanup_existing_tunnel() {
    log "Cleaning up existing tunnel if present..."

    # Remove old tunnel credentials from 1Password
    if op item get "$CREDENTIAL_TITLE" --vault="$VAULT_NAME" &> /dev/null; then
        log "Removing old tunnel credentials from 1Password..."
        if op item delete "$CREDENTIAL_TITLE" --vault="$VAULT_NAME" 2>/dev/null; then
            success "Removed old tunnel credentials from 1Password"
        else
            warn "Failed to remove old tunnel credentials (may not exist)"
        fi
    fi

    # Delete old tunnel from Cloudflare
    if mise exec -- cloudflared tunnel list 2>/dev/null | grep -q "$TUNNEL_NAME"; then
        log "Deleting old tunnel from Cloudflare: $TUNNEL_NAME"
        if mise exec -- cloudflared tunnel delete "$TUNNEL_NAME" --force 2>/dev/null; then
            success "Deleted old tunnel: $TUNNEL_NAME"
        else
            warn "Failed to delete old tunnel (may not exist or already deleted)"
        fi
    fi

    success "Cleanup completed"
}

# Create fresh Cloudflare tunnel and credentials
create_cloudflare_tunnel() {
    log "Creating fresh Cloudflare tunnel: $TUNNEL_NAME"

    # Create temporary directory for tunnel operations
    local temp_dir
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT

    # Create new tunnel
    log "Creating new Cloudflare tunnel..."
    if mise exec -- cloudflared tunnel create "$TUNNEL_NAME" > "$temp_dir/tunnel-create.log" 2>&1; then
        success "Created new Cloudflare tunnel: $TUNNEL_NAME"
    else
        error "Failed to create new Cloudflare tunnel. Check your Cloudflare API credentials."
    fi

    # Get tunnel ID and validate
    local tunnel_id
    tunnel_id=$(mise exec -- cloudflared tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}')

    if [[ -z "$tunnel_id" ]]; then
        error "Failed to get tunnel ID for $TUNNEL_NAME"
    fi

    if [[ ${#tunnel_id} -lt 30 ]]; then
        error "Tunnel ID appears invalid (length: ${#tunnel_id})"
    fi

    success "Tunnel created with ID: ${tunnel_id:0:8}..."

    # Find and validate credentials file
    local creds_file="$HOME/.cloudflared/$tunnel_id.json"
    if [[ ! -f "$creds_file" ]]; then
        error "Tunnel credentials file not found at $creds_file"
    fi

    # Validate credentials file format
    if ! jq . "$creds_file" >/dev/null 2>&1; then
        error "Invalid JSON in tunnel credentials file"
    fi

    # Check credentials file size
    local file_size
    file_size=$(wc -c < "$creds_file")
    if [[ $file_size -lt 100 ]]; then
        error "Credentials file appears too small ($file_size bytes)"
    fi

    success "Valid tunnel credentials generated ($file_size bytes)"

    # Store credentials in 1Password
    log "Storing tunnel credentials in 1Password..."
    local temp_creds_file="/tmp/cloudflare-tunnel-$tunnel_id.json"
    cp "$creds_file" "$temp_creds_file"

    if op document create "$temp_creds_file" \
        --title="$CREDENTIAL_TITLE" \
        --vault="$VAULT_NAME" > /dev/null 2>&1; then
        success "Tunnel credentials stored in 1Password"
        rm -f "$temp_creds_file"
    else
        rm -f "$temp_creds_file"
        error "Failed to store tunnel credentials in 1Password"
    fi

    # Return tunnel information
    echo "$tunnel_id"
}

# Validate credential storage and access
validate_credentials() {
    local tunnel_id="$1"

    log "Validating credential storage and access..."

    # Check if credentials exist in 1Password
    if ! op item get "$CREDENTIAL_TITLE" --vault="$VAULT_NAME" &> /dev/null; then
        error "Credentials not found in 1Password after creation"
    fi

    # Verify we can retrieve the credentials
    local temp_validation_file="/tmp/validate-tunnel-creds.json"
    if op document get "$CREDENTIAL_TITLE" --vault="$VAULT_NAME" --output="$temp_validation_file" 2>/dev/null; then
        # Validate JSON format
        if jq . "$temp_validation_file" >/dev/null 2>&1; then
            success "Credentials successfully stored and retrievable from 1Password"
        else
            error "Retrieved credentials are not valid JSON"
        fi
        rm -f "$temp_validation_file"
    else
        error "Cannot retrieve credentials from 1Password"
    fi

    # Check tunnel status
    if mise exec -- cloudflared tunnel list 2>/dev/null | grep -q "$tunnel_id"; then
        success "Tunnel is active in Cloudflare"
    else
        error "Tunnel not found in Cloudflare tunnel list"
    fi

    success "All credential validation checks passed"
}

# Test ExternalSecret access (if cluster is available)
test_external_secret_access() {
    log "Testing ExternalSecret access to credentials..."

    # Check if kubectl is available and cluster is accessible
    if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
        # Check if the ExternalSecret exists
        if kubectl get externalsecret cloudflare-tunnel-credentials -n cloudflare-tunnel &> /dev/null; then
            log "Checking ExternalSecret status..."
            local secret_status
            secret_status=$(kubectl get externalsecret cloudflare-tunnel-credentials -n cloudflare-tunnel -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")

            if [[ "$secret_status" == "True" ]]; then
                success "ExternalSecret is successfully syncing credentials"
            else
                warn "ExternalSecret status: $secret_status (may take a few minutes to sync)"
            fi
        else
            warn "ExternalSecret not found - cluster may not be fully deployed yet"
        fi
    else
        warn "Kubernetes cluster not accessible - skipping ExternalSecret validation"
    fi
}

# Display DNS configuration information
show_dns_configuration() {
    local tunnel_id="$1"

    echo ""
    echo "=============================================="
    echo "  DNS CONFIGURATION REQUIRED"
    echo "=============================================="
    echo ""
    echo "Tunnel ID: $tunnel_id"
    echo "CNAME Target: $tunnel_id.cfargotunnel.com"
    echo ""
    echo "Update the following DNS records in Cloudflare:"
    echo ""
    echo "  grafana.geoffdavis.com  → $tunnel_id.cfargotunnel.com"
    echo "  prometheus.geoffdavis.com → $tunnel_id.cfargotunnel.com"
    echo "  longhorn.geoffdavis.com → $tunnel_id.cfargotunnel.com"
    echo "  k8s.geoffdavis.com → $tunnel_id.cfargotunnel.com"
    echo "  alerts.geoffdavis.com → $tunnel_id.cfargotunnel.com"
    echo "  hubble.geoffdavis.com → $tunnel_id.cfargotunnel.com"
    echo ""
}

# Main execution
main() {
    echo "=============================================="
    echo "  Cloudflare Tunnel Credential Creator"
    echo "=============================================="
    echo ""
    echo "This script will:"
    echo "- Check prerequisites (cloudflared CLI, 1Password)"
    echo "- Verify existing tunnel/credential status"
    echo "- Create fresh Cloudflare tunnel if needed"
    echo "- Store credentials securely in 1Password"
    echo "- Validate credential access"
    echo "- Provide DNS configuration instructions"
    echo ""
    echo "⚠️  SAFETY: This script only affects Cloudflare tunnel credentials"
    echo "⚠️  SAFETY: No other credentials or configurations will be modified"
    echo ""

    read -r -p "Continue with Cloudflare tunnel credential creation? (y/N): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Aborted by user"
        exit 0
    fi

    echo ""

    check_prerequisites
    echo ""

    check_1password_connect
    echo ""

    check_existing_tunnel
    echo ""

    cleanup_existing_tunnel
    echo ""

    local tunnel_id
    tunnel_id=$(create_cloudflare_tunnel)
    echo ""

    validate_credentials "$tunnel_id"
    echo ""

    test_external_secret_access
    echo ""

    show_dns_configuration "$tunnel_id"

    echo "=============================================="
    echo "  CLOUDFLARE TUNNEL CREDENTIALS COMPLETE"
    echo "=============================================="
    echo ""
    echo "✅ Fresh Cloudflare tunnel created: $TUNNEL_NAME"
    echo "✅ Credentials stored in 1Password: $CREDENTIAL_TITLE"
    echo "✅ Tunnel ID: ${tunnel_id:0:8}..."
    echo "✅ Ready for Kubernetes deployment"
    echo ""
    echo "📋 NEXT STEPS:"
    echo ""
    echo "1. Update DNS records (see configuration above)"
    echo "2. Wait for ExternalSecret to sync (if cluster is running)"
    echo "3. Verify tunnel deployment recovery:"
    echo "   kubectl get pods -n cloudflare-tunnel"
    echo "4. Check tunnel connectivity:"
    echo "   kubectl logs -n cloudflare-tunnel -l app=cloudflare-tunnel"
    echo ""
    echo "🔒 Cloudflare tunnel credentials ready for deployment!"
    echo ""
}

# Change to repository root
cd "$(dirname "$0")/.."

# Run main function
main "$@"
