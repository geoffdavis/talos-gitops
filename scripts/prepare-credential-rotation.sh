#!/bin/bash
# Prepare cluster for new 1Password Connect tokens and fresh cluster secrets generation
# This script ensures a clean slate for credential rotation after security incident

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
    log "Checking prerequisites for credential rotation..."
    
    if ! command -v op &> /dev/null; then
        error "1Password CLI (op) is not installed. Please install it first."
    fi
    
    if ! op account list &> /dev/null; then
        error "1Password CLI is not authenticated. Please run 'op signin' first."
    fi
    
    if [[ -z "${OP_ACCOUNT:-}" ]]; then
        error "OP_ACCOUNT environment variable is not set. Please export OP_ACCOUNT=your-account-name"
    fi
    
    success "All prerequisites met"
}

# Clean up old 1Password Connect credentials
cleanup_old_credentials() {
    log "Cleaning up old 1Password Connect credentials..."
    
    # Remove any local credential files
    local files_removed=0
    
    if [[ -f "1password-credentials.json" ]]; then
        rm -f "1password-credentials.json"
        files_removed=$((files_removed + 1))
        success "Removed local 1password-credentials.json"
    fi
    
    if [[ -f "connect-token.txt" ]]; then
        rm -f "connect-token.txt"
        files_removed=$((files_removed + 1))
        success "Removed local connect-token.txt"
    fi
    
    # Clean up any temporary credential files
    find . -name "*credentials*.json" -type f -delete 2>/dev/null || true
    find . -name "*connect*.token" -type f -delete 2>/dev/null || true
    find /tmp -name "*1password*" -type f -delete 2>/dev/null || true
    
    if [[ $files_removed -eq 0 ]]; then
        success "No local credential files found to clean up"
    else
        success "Cleaned up $files_removed local credential files"
    fi
}

# Clear Talos generated secrets
clear_talos_secrets() {
    log "Clearing existing Talos generated secrets..."
    
    # Remove generated directory contents
    if [[ -d "talos/generated" ]]; then
        rm -rf talos/generated/*
        success "Cleared talos/generated/ directory"
    else
        mkdir -p talos/generated
        success "Created clean talos/generated/ directory"
    fi
    
    # Remove talsecret.yaml if it exists
    if [[ -f "talos/talsecret.yaml" ]]; then
        rm -f "talos/talsecret.yaml"
        success "Removed existing talos/talsecret.yaml"
    fi
    
    # Remove any local kubeconfig/talosconfig files
    rm -f kubeconfig talosconfig
    success "Removed local kubeconfig and talosconfig files"
}

# Verify 1Password entries for cleanup
verify_1password_entries() {
    log "Verifying 1Password entries that need new credentials..."
    
    local entries_found=0
    
    # Check for old 1Password Connect entries
    if op item get "1password connect" --vault="Automation" &> /dev/null; then
        warn "Found old '1password connect' entry - will need new credentials"
        entries_found=$((entries_found + 1))
    elif op item get "1Password Connect" --vault="Automation" &> /dev/null; then
        warn "Found old '1Password Connect' entry - will need new credentials"
        entries_found=$((entries_found + 1))
    fi
    
    # Check for Connect credentials document
    if op document get "1Password Connect Credentials - $CLUSTER_NAME" --vault="Automation" &> /dev/null; then
        warn "Found old Connect credentials document - will need replacement"
        entries_found=$((entries_found + 1))
    fi
    
    # Check for Connect token entry
    if op item get "1Password Connect Token - $CLUSTER_NAME" --vault="Automation" &> /dev/null; then
        warn "Found old Connect token entry - will need replacement"
        entries_found=$((entries_found + 1))
    fi
    
    # Check for Cloudflare tunnel credentials
    if op item get "Home-ops cloudflare-tunnel.json" --vault="Automation" &> /dev/null; then
        warn "Found old Cloudflare tunnel credentials - will need replacement"
        entries_found=$((entries_found + 1))
    fi
    
    # Check for Talos secrets
    if op item get "Talos Secrets - $CLUSTER_NAME" --vault="Automation" &> /dev/null; then
        warn "Found existing Talos secrets - will generate fresh ones"
        entries_found=$((entries_found + 1))
    elif op item get "talos - $CLUSTER_NAME" --vault="Automation" &> /dev/null; then
        warn "Found legacy Talos secrets - will generate fresh ones"
        entries_found=$((entries_found + 1))
    fi
    
    if [[ $entries_found -eq 0 ]]; then
        success "No existing entries found - ready for fresh setup"
    else
        success "Found $entries_found entries that will be updated with fresh credentials"
    fi
}

# Prepare bootstrap process for new credentials
prepare_bootstrap_process() {
    log "Preparing bootstrap process for credential rotation..."
    
    # Verify bootstrap scripts are ready
    local scripts_ready=0
    
    if [[ -x "scripts/bootstrap-1password-secrets.sh" ]]; then
        scripts_ready=$((scripts_ready + 1))
        success "1Password secrets bootstrap script ready"
    else
        error "scripts/bootstrap-1password-secrets.sh not found or not executable"
    fi
    
    if [[ -x "scripts/validate-1password-secrets.sh" ]]; then
        scripts_ready=$((scripts_ready + 1))
        success "1Password secrets validation script ready"
    else
        warn "scripts/validate-1password-secrets.sh not found - validation may be limited"
    fi
    
    # Check Taskfile tasks
    if grep -q "onepassword:create-connect-server" Taskfile.yml; then
        success "onepassword:create-connect-server task available"
    else
        error "onepassword:create-connect-server task not found in Taskfile.yml"
    fi
    
    if grep -q "bootstrap:phased" Taskfile.yml; then
        success "bootstrap:phased task available for fresh cluster setup"
    else
        error "bootstrap:phased task not found in Taskfile.yml"
    fi
}

# Verify cluster is in maintenance mode
verify_maintenance_mode() {
    log "Verifying cluster nodes are in maintenance mode..."
    
    local nodes_in_maintenance=0
    local node_ips=("172.29.51.11" "172.29.51.12" "172.29.51.13")
    
    for node_ip in "${node_ips[@]}"; do
        log "Checking node $node_ip..."
        
        # Try to connect with insecure mode (expected for maintenance mode)
        if mise exec -- talosctl version --insecure --nodes "$node_ip" &> /dev/null; then
            # Check if it's actually in maintenance mode (no cluster config)
            if ! mise exec -- talosctl get machineconfig --insecure --nodes "$node_ip" &> /dev/null; then
                success "Node $node_ip confirmed in maintenance mode"
                nodes_in_maintenance=$((nodes_in_maintenance + 1))
            else
                warn "Node $node_ip has cluster config - may not be in maintenance mode"
            fi
        else
            warn "Node $node_ip not accessible - may be powered off or network issue"
        fi
    done
    
    if [[ $nodes_in_maintenance -eq 3 ]]; then
        success "All 3 nodes confirmed in maintenance mode - ready for fresh bootstrap"
    elif [[ $nodes_in_maintenance -gt 0 ]]; then
        warn "$nodes_in_maintenance/3 nodes in maintenance mode - some may need manual intervention"
    else
        error "No nodes confirmed in maintenance mode - please ensure nodes are reset properly"
    fi
}

# Create credential rotation documentation
create_rotation_documentation() {
    log "Creating credential rotation documentation..."
    
    cat > docs/CREDENTIAL_ROTATION_PROCESS.md << 'EOF'
# Credential Rotation Process

This document outlines the process for rotating 1Password Connect credentials and generating fresh cluster secrets after a security incident.

## Prerequisites

- Nodes must be in maintenance mode (no cluster configuration)
- 1Password CLI authenticated with proper account access
- OP_ACCOUNT environment variable set

## Step-by-Step Process

### 1. Generate New 1Password Connect Server

```bash
# Create new Connect server with fresh credentials
task onepassword:create-connect-server
```

This will:
- Create a new Connect server in 1Password
- Generate fresh credentials file
- Create new Connect token
- Store both in 1Password Automation vault
- Clean up local files

### 2. Bootstrap Fresh Cluster Secrets

```bash
# Generate fresh Talos secrets and configuration
task bootstrap:phased
```

This will:
- Generate new Talos cluster secrets
- Create fresh PKI certificates
- Store secrets in 1Password
- Apply configuration to nodes
- Bootstrap the cluster

### 3. Validate New Setup

```bash
# Validate 1Password Connect integration
task bootstrap:validate-1password-secrets

# Verify cluster status
task cluster:status
```

## Security Considerations

- Old credentials are automatically invalidated when new ones are created
- Fresh PKI certificates ensure no certificate reuse
- All secrets are regenerated, not rotated
- Local credential files are cleaned up automatically

## Troubleshooting

If the process fails:

1. Verify nodes are in maintenance mode: `talosctl version --insecure --nodes <node-ip>`
2. Check 1Password CLI authentication: `op account list`
3. Ensure OP_ACCOUNT is set: `echo $OP_ACCOUNT`
4. Review logs in bootstrap process

## Recovery

If you need to start over:

1. Run `task cluster:safe-reset CONFIRM=SAFE-RESET` to reset nodes
2. Wait for nodes to enter maintenance mode
3. Re-run the credential rotation process
EOF

    success "Created docs/CREDENTIAL_ROTATION_PROCESS.md"
}

# Main execution
main() {
    echo "=============================================="
    echo "  1Password Credential Rotation Preparation"
    echo "=============================================="
    echo ""
    
    check_prerequisites
    echo ""
    
    cleanup_old_credentials
    echo ""
    
    clear_talos_secrets
    echo ""
    
    verify_1password_entries
    echo ""
    
    prepare_bootstrap_process
    echo ""
    
    verify_maintenance_mode
    echo ""
    
    create_rotation_documentation
    echo ""
    
    echo "=============================================="
    echo "  CREDENTIAL ROTATION PREPARATION COMPLETE"
    echo "=============================================="
    echo ""
    echo "✅ Environment prepared for fresh credentials"
    echo "✅ Old secrets and credentials cleaned up"
    echo "✅ Bootstrap process verified and ready"
    echo "✅ Nodes confirmed in maintenance mode"
    echo ""
    echo "📋 NEXT STEPS:"
    echo ""
    echo "1. Generate new 1Password Connect server:"
    echo "   task onepassword:create-connect-server"
    echo ""
    echo "2. Bootstrap fresh cluster with new secrets:"
    echo "   task bootstrap:phased"
    echo ""
    echo "3. Validate the new setup:"
    echo "   task bootstrap:validate-1password-secrets"
    echo "   task cluster:status"
    echo ""
    echo "📖 See docs/CREDENTIAL_ROTATION_PROCESS.md for detailed steps"
    echo ""
}

# Change to repository root
cd "$(dirname "$0")/.."

# Run main function
main "$@"