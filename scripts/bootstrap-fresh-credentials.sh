#!/bin/bash
# Bootstrap fresh 1Password Connect credentials and cluster secrets after security incident
# This script coordinates the complete credential rotation process

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
    log "Checking prerequisites for fresh credential bootstrap..."

    if ! command -v op &> /dev/null; then
        error "1Password CLI (op) is not installed. Please install it first."
    fi

    if ! op account list &> /dev/null; then
        error "1Password CLI is not authenticated. Please run 'op signin' first."
    fi

    if [[ -z "${OP_ACCOUNT:-}" ]]; then
        error "OP_ACCOUNT environment variable is not set. Please export OP_ACCOUNT=your-account-name"
    fi

    if ! command -v mise &> /dev/null; then
        error "mise is not installed. Please install it first."
    fi

    success "All prerequisites met"
}

# Delete all old 1Password Connect servers to prevent duplicates
delete_all_old_connect_servers() {
    log "Checking for old 1Password Connect servers to delete..."

    # List all Connect servers
    local servers_found=0
    local all_server_ids

    # Get server IDs that match our cluster name or contain "home-ops"
    all_server_ids=$(op connect server list --format=json 2>/dev/null | jq -r ".[] | select(.name | contains(\"$CLUSTER_NAME\") or contains(\"home-ops\")) | .id" 2>/dev/null || echo "")

    if [[ -n "$all_server_ids" ]]; then
        warn "Found existing Connect server(s) for $CLUSTER_NAME - deleting to prevent duplicates"

        while IFS= read -r server_id; do
            if [[ -n "$server_id" ]]; then
                # Get server name for logging
                local server_name
                server_name=$(op connect server list --format=json 2>/dev/null | jq -r ".[] | select(.id == \"$server_id\") | .name" 2>/dev/null || echo "unknown")

                log "Deleting old Connect server: $server_id ($server_name)"
                if op connect server delete "$server_id" 2>/dev/null; then
                    success "Deleted old Connect server: $server_id ($server_name)"
                    servers_found=$((servers_found + 1))
                else
                    warn "Failed to delete server $server_id (may already be deleted)"
                fi
            fi
        done <<< "$all_server_ids"

        # Wait a moment for deletion to propagate
        if [[ $servers_found -gt 0 ]]; then
            log "Waiting for server deletion to propagate..."
            sleep 2
        fi
    fi

    # Verify no servers remain
    local remaining_servers
    remaining_servers=$(op connect server list 2>/dev/null | wc -l || echo "0")

    if [[ $remaining_servers -le 1 ]]; then  # Header line counts as 1
        success "All old Connect servers deleted successfully"
    else
        warn "Some Connect servers may still exist - continuing anyway"
    fi

    if [[ $servers_found -eq 0 ]]; then
        success "No old Connect servers found to delete"
    else
        success "Deleted $servers_found old Connect server(s)"
    fi
}

# Clean up old 1Password entries
cleanup_old_1password_entries() {
    log "Cleaning up old 1Password entries..."

    local entries_cleaned=0

    # Remove old Connect credentials document
    if op document get "1Password Connect Credentials - $CLUSTER_NAME" --vault="Automation" &> /dev/null; then
        log "Removing old Connect credentials document..."
        if op item delete "1Password Connect Credentials - $CLUSTER_NAME" --vault="Automation" 2>/dev/null; then
            success "Removed old Connect credentials document"
            entries_cleaned=$((entries_cleaned + 1))
        else
            warn "Failed to remove old Connect credentials document"
        fi
    fi

    # Remove old Connect token entry
    if op item get "1Password Connect Token - $CLUSTER_NAME" --vault="Automation" &> /dev/null; then
        log "Removing old Connect token entry..."
        if op item delete "1Password Connect Token - $CLUSTER_NAME" --vault="Automation" 2>/dev/null; then
            success "Removed old Connect token entry"
            entries_cleaned=$((entries_cleaned + 1))
        else
            warn "Failed to remove old Connect token entry"
        fi
    fi

    # Remove old generic "1password connect" entries
    for entry_name in "1password connect" "1Password Connect"; do
        if op item get "$entry_name" --vault="Automation" &> /dev/null; then
            log "Removing old generic Connect entry: $entry_name"
            if op item delete "$entry_name" --vault="Automation" 2>/dev/null; then
                success "Removed old Connect entry: $entry_name"
                entries_cleaned=$((entries_cleaned + 1))
            else
                warn "Failed to remove old Connect entry: $entry_name"
            fi
        fi
    done

    # Remove old Cloudflare tunnel credentials
    if op item get "Home-ops cloudflare-tunnel.json" --vault="Automation" &> /dev/null; then
        log "Removing old Cloudflare tunnel credentials..."
        if op item delete "Home-ops cloudflare-tunnel.json" --vault="Automation" 2>/dev/null; then
            success "Removed old Cloudflare tunnel credentials"
            entries_cleaned=$((entries_cleaned + 1))
        else
            warn "Failed to remove old Cloudflare tunnel credentials"
        fi
    fi

    if [[ $entries_cleaned -eq 0 ]]; then
        success "No old 1Password entries found to clean up"
    else
        success "Cleaned up $entries_cleaned old 1Password entries"
    fi
}

# Create fresh 1Password Connect server and credentials (without Kubernetes updates)
create_fresh_connect_server() {
    log "Creating fresh 1Password Connect server and credentials..."

    # Create Connect server with proper vault access
    log "Creating Connect server for home-ops cluster..."
    if op connect server create "home-ops-cluster" --vaults "Automation,Services" > /dev/null; then
        success "Connect server created successfully"
    else
        error "Failed to create Connect server"
    fi

    # Verify credentials file was created
    if [[ ! -f "1password-credentials.json" ]]; then
        error "Credentials file not created"
    fi

    # Validate JSON format
    if ! jq . 1password-credentials.json > /dev/null; then
        error "Invalid credentials JSON format"
    fi

    local file_size
    file_size=$(wc -c < 1password-credentials.json)
    success "Valid credentials file created ($file_size bytes)"

    # Store credentials as document in 1Password
    log "Storing credentials in 1Password as document..."
    if op document create 1password-credentials.json \
        --title="1Password Connect Credentials - $CLUSTER_NAME" \
        --vault="Automation" > /dev/null; then
        success "Credentials stored as document in 1Password"
    else
        error "Failed to store credentials document in 1Password"
    fi

    # Create Connect token
    log "Creating Connect token..."
    local connect_token
    connect_token=$(op connect token create "home-ops-token" \
        --server "home-ops-cluster" \
        --vault "Automation" \
        --expires-in 8760h)

    if [[ ${#connect_token} -lt 100 ]]; then
        error "Connect token appears invalid (length: ${#connect_token})"
    fi

    success "Connect token created (length: ${#connect_token})"

    # Store token in 1Password
    log "Storing Connect token in 1Password..."
    if op item create \
        --category="API Credential" \
        --title="1Password Connect Token - $CLUSTER_NAME" \
        --vault="Automation" \
        "token[password]=$connect_token" > /dev/null 2>&1; then
        success "Connect token stored in 1Password (new entry)"
    elif op item edit "1Password Connect Token - $CLUSTER_NAME" \
        "token[password]=$connect_token" \
        --vault="Automation" > /dev/null 2>&1; then
        success "Connect token stored in 1Password (updated existing)"
    else
        error "Failed to store Connect token in 1Password"
    fi

    # Clean up local files
    log "Cleaning up local credential files..."
    rm -f 1password-credentials.json connect-token.txt
    success "Local credential files cleaned up"

    success "Fresh 1Password Connect server and credentials created successfully"
}

# Create fresh Cloudflare tunnel credentials
create_fresh_cloudflare_tunnel() {
    log "Creating fresh Cloudflare tunnel credentials..."

    # Check if cloudflared CLI is available
    if ! mise exec -- cloudflared --version &> /dev/null; then
        warn "cloudflared CLI not found - skipping tunnel credential rotation"
        warn "You will need to manually rotate Cloudflare tunnel credentials"
        return 0
    fi

    # Create temporary directory for tunnel operations
    local temp_dir
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT

    # Delete old tunnel if it exists
    log "Checking for existing tunnel: home-ops-tunnel"
    if mise exec -- cloudflared tunnel list | grep -q "home-ops-tunnel"; then
        log "Deleting old tunnel: home-ops-tunnel"
        if mise exec -- cloudflared tunnel delete home-ops-tunnel --force 2>/dev/null; then
            success "Deleted old tunnel: home-ops-tunnel"
        else
            warn "Failed to delete old tunnel (may not exist or already deleted)"
        fi
    fi

    # Create new tunnel
    log "Creating new Cloudflare tunnel: home-ops-tunnel"
    if mise exec -- cloudflared tunnel create home-ops-tunnel > "$temp_dir/tunnel-create.log" 2>&1; then
        success "Created new Cloudflare tunnel: home-ops-tunnel"
    else
        error "Failed to create new Cloudflare tunnel"
    fi

    # Get tunnel credentials
    local tunnel_id
    tunnel_id=$(mise exec -- cloudflared tunnel list | grep "home-ops-tunnel" | awk '{print $1}')

    if [[ -z "$tunnel_id" ]]; then
        error "Failed to get tunnel ID for home-ops-tunnel"
    fi

    # Find credentials file (cloudflared creates it automatically)
    local creds_file="$HOME/.cloudflared/$tunnel_id.json"
    if [[ ! -f "$creds_file" ]]; then
        error "Tunnel credentials file not found at $creds_file"
    fi

    # Validate credentials file
    if ! jq . "$creds_file" >/dev/null 2>&1; then
        error "Invalid JSON in tunnel credentials file"
    fi

    success "Fresh tunnel credentials generated (ID: ${tunnel_id:0:8}...)"

    # Store credentials in 1Password
    log "Storing fresh tunnel credentials in 1Password..."
    # Create a temporary file for the document
    local temp_creds_file="/tmp/cloudflare-tunnel-$tunnel_id.json"
    cp "$creds_file" "$temp_creds_file"

    if op document create "$temp_creds_file" \
        --title="Home-ops cloudflare-tunnel.json" \
        --vault="Automation" > /dev/null 2>&1; then
        success "Fresh tunnel credentials stored in 1Password"
        rm -f "$temp_creds_file"
    else
        rm -f "$temp_creds_file"
        error "Failed to store tunnel credentials in 1Password"
    fi

    # Update DNS records (informational - requires manual action)
    log "Tunnel DNS configuration:"
    echo "  Tunnel ID: $tunnel_id"
    echo "  CNAME Target: $tunnel_id.cfargotunnel.com"
    echo ""
    warn "MANUAL ACTION REQUIRED:"
    warn "Update your Cloudflare DNS records to point to: $tunnel_id.cfargotunnel.com"
    warn "The following hostnames need to be updated:"
    warn "  - grafana.geoffdavis.com"
    warn "  - prometheus.geoffdavis.com"
    warn "  - longhorn.geoffdavis.com"
    warn "  - k8s.geoffdavis.com"
    warn "  - alerts.geoffdavis.com"
    warn "  - hubble.geoffdavis.com"
}

# Generate fresh Talos secrets
generate_fresh_talos_secrets() {
    log "Generating fresh Talos cluster secrets..."

    # Remove any existing Talos secrets from 1Password first
    for entry_name in "Talos Secrets - $CLUSTER_NAME" "talos - $CLUSTER_NAME"; do
        if op item get "$entry_name" --vault="Automation" &> /dev/null; then
            log "Removing old Talos secrets entry: $entry_name"
            if op item delete "$entry_name" --vault="Automation" 2>/dev/null; then
                success "Removed old Talos secrets: $entry_name"
            else
                warn "Failed to remove old Talos secrets: $entry_name"
            fi
        fi
    done

    # Generate fresh Talos configuration with new secrets
    log "Generating fresh Talos configuration..."
    if mise exec -- task talos:generate-config; then
        success "Fresh Talos secrets and configuration generated"
    else
        error "Failed to generate fresh Talos configuration"
    fi
}

# Validate the fresh setup
validate_fresh_setup() {
    log "Validating fresh credential setup..."

    # Check that new 1Password entries exist
    local validation_passed=0
    local total_checks=5

    # Check for new Connect credentials document
    if op document get "1Password Connect Credentials - $CLUSTER_NAME" --vault="Automation" &> /dev/null; then
        success "New Connect credentials document found"
        validation_passed=$((validation_passed + 1))
    else
        error "New Connect credentials document not found"
    fi

    # Check for new Connect token entry
    if op item get "1Password Connect Token - $CLUSTER_NAME" --vault="Automation" &> /dev/null; then
        success "New Connect token entry found"
        validation_passed=$((validation_passed + 1))
    else
        error "New Connect token entry not found"
    fi

    # Check for new Talos secrets
    if op item get "Talos Secrets - $CLUSTER_NAME" --vault="Automation" &> /dev/null; then
        success "New Talos secrets found"
        validation_passed=$((validation_passed + 1))
    else
        error "New Talos secrets not found"
    fi

    # Check for new Cloudflare tunnel credentials
    if op item get "Home-ops cloudflare-tunnel.json" --vault="Automation" &> /dev/null; then
        success "New Cloudflare tunnel credentials found"
        validation_passed=$((validation_passed + 1))
    else
        warn "New Cloudflare tunnel credentials not found (may have been skipped)"
        # Don't fail validation if cloudflared CLI wasn't available
        total_checks=$((total_checks - 1))
    fi

    # Check that local files are generated
    if [[ -f "clusterconfig/talosconfig" ]]; then
        success "Fresh talosconfig generated"
        validation_passed=$((validation_passed + 1))
    elif [[ -f "talos/generated/talosconfig" ]]; then
        success "Fresh talosconfig generated (legacy path)"
        validation_passed=$((validation_passed + 1))
    else
        error "Fresh talosconfig not found in clusterconfig/ or talos/generated/"
    fi

    if [[ $validation_passed -eq $total_checks ]]; then
        success "All fresh credentials validated successfully"
    else
        error "Fresh credential validation failed ($validation_passed/$total_checks checks passed)"
    fi
}

# Main execution
main() {
    echo "=============================================="
    echo "  Fresh 1Password Credential Bootstrap"
    echo "=============================================="
    echo ""
    echo "This script will:"
    echo "- Revoke old 1Password Connect servers"
    echo "- Clean up old credential entries"
    echo "- Create fresh Connect server and credentials"
    echo "- Create fresh Cloudflare tunnel credentials"
    echo "- Generate fresh Talos cluster secrets"
    echo "- Validate the new setup"
    echo ""

    read -r -p "Continue with fresh credential bootstrap? (y/N): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Aborted by user"
        exit 0
    fi

    echo ""

    check_prerequisites
    echo ""

    delete_all_old_connect_servers
    echo ""

    cleanup_old_1password_entries
    echo ""

    create_fresh_connect_server
    echo ""

    create_fresh_cloudflare_tunnel
    echo ""

    generate_fresh_talos_secrets
    echo ""

    validate_fresh_setup
    echo ""

    echo "=============================================="
    echo "  FRESH CREDENTIAL BOOTSTRAP COMPLETE"
    echo "=============================================="
    echo ""
    echo "✅ Old credentials revoked and cleaned up"
    echo "✅ Fresh 1Password Connect server created"
    echo "✅ Fresh Cloudflare tunnel credentials created"
    echo "✅ Fresh Talos cluster secrets generated"
    echo "✅ All credentials stored in 1Password"
    echo ""
    echo "📋 NEXT STEPS:"
    echo ""
    echo "1. Apply fresh configuration to nodes:"
    echo "   task talos:apply-config"
    echo ""
    echo "2. Bootstrap the cluster:"
    echo "   task talos:bootstrap"
    echo ""
    echo "3. Deploy 1Password Connect to cluster:"
    echo "   task bootstrap:1password-secrets"
    echo ""
    echo "4. Continue with full bootstrap:"
    echo "   task bootstrap:phased"
    echo ""
    echo "🔒 Security incident response complete!"
    echo ""
}

# Change to repository root
cd "$(dirname "$0")/.."

# Run main function
main "$@"
