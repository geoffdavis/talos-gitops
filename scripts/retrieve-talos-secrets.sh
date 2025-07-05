#!/bin/bash
# Retrieve Talos secrets from 1Password and create a secrets bundle

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CLUSTER_NAME="home-ops"
SECRETS_BUNDLE="talos/generated/secrets.yaml"

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
    
    if ! command -v yq &> /dev/null; then
        error "yq is not installed. Please install it first."
    fi
    
    success "All prerequisites met"
}

# Create secrets bundle from 1Password data
create_secrets_bundle() {
    log "Creating Talos secrets bundle from 1Password..."
    
    # Create output directory
    mkdir -p talos/generated
    
    # Check if cluster secrets exist
    if ! op item get "Talos Cluster Secrets - $CLUSTER_NAME" &> /dev/null; then
        error "Talos Cluster Secrets - $CLUSTER_NAME not found in 1Password. Run 'task bootstrap:secrets' first."
    fi
    
    # Retrieve cluster secrets
    local cluster_secret bootstrap_token secretbox_key
    cluster_secret=$(op item get "Talos Cluster Secrets - $CLUSTER_NAME" --fields label=cluster-secret --format json | jq -r '.value')
    bootstrap_token=$(op item get "Talos Cluster Secrets - $CLUSTER_NAME" --fields label=bootstrap-token --format json | jq -r '.value')
    secretbox_key=$(op item get "Talos Cluster Secrets - $CLUSTER_NAME" --fields label=secretbox-key --format json | jq -r '.value')
    
    # Check if secrets bundle already exists and is valid
    local needs_generation=false
    
    if [[ ! -f "$SECRETS_BUNDLE" ]]; then
        log "Secrets bundle not found, will generate new one"
        needs_generation=true
    else
        # Check if the existing bundle has the correct cluster secrets
        local existing_cluster_id existing_cluster_secret
        existing_cluster_id=$(yq eval '.cluster.id' "$SECRETS_BUNDLE" 2>/dev/null || echo "")
        existing_cluster_secret=$(yq eval '.cluster.secret' "$SECRETS_BUNDLE" 2>/dev/null || echo "")
        
        if [[ "$existing_cluster_id" != "$CLUSTER_NAME" ]] || [[ "$existing_cluster_secret" != "$cluster_secret" ]]; then
            log "Existing secrets bundle has different cluster secrets, regenerating"
            needs_generation=true
        fi
    fi
    
    # Check if PKI certificates exist in 1Password
    local pki_exists=false
    if op item get "Talos PKI Certificates - $CLUSTER_NAME" --fields label=machine-ca-crt --format json &> /dev/null; then
        pki_exists=true
        log "Found existing PKI certificates in 1Password"
    else
        log "No PKI certificates found in 1Password"
        needs_generation=true
    fi
    
    # Generate secrets bundle only if needed
    if [[ "$needs_generation" == "true" ]]; then
        log "Generating new secrets bundle..."
        talosctl gen secrets --output-file "$SECRETS_BUNDLE" --force
        
        # Update the bundle with our cluster secrets
        yq eval ".cluster.id = \"$CLUSTER_NAME\"" -i "$SECRETS_BUNDLE"
        yq eval ".cluster.secret = \"$cluster_secret\"" -i "$SECRETS_BUNDLE"
        yq eval ".cluster.token = \"$bootstrap_token\"" -i "$SECRETS_BUNDLE"
        yq eval ".cluster.secretboxEncryptionSecret = \"$secretbox_key\"" -i "$SECRETS_BUNDLE"
        
        if [[ "$pki_exists" == "false" ]]; then
            log "Storing new PKI certificates in 1Password..."
            
            # Extract certificates from the generated bundle and store in 1Password
            local new_machine_ca_crt new_machine_ca_key new_cluster_ca_crt new_cluster_ca_key
            local new_etcd_ca_crt new_etcd_ca_key new_aggregator_ca_crt new_aggregator_ca_key new_service_account_key
            
            new_machine_ca_crt=$(yq eval '.machine.ca.crt' "$SECRETS_BUNDLE")
            new_machine_ca_key=$(yq eval '.machine.ca.key' "$SECRETS_BUNDLE")
            new_cluster_ca_crt=$(yq eval '.cluster.ca.crt' "$SECRETS_BUNDLE")
            new_cluster_ca_key=$(yq eval '.cluster.ca.key' "$SECRETS_BUNDLE")
            new_etcd_ca_crt=$(yq eval '.cluster.etcd.ca.crt' "$SECRETS_BUNDLE")
            new_etcd_ca_key=$(yq eval '.cluster.etcd.ca.key' "$SECRETS_BUNDLE")
            new_aggregator_ca_crt=$(yq eval '.cluster.aggregatorCA.crt' "$SECRETS_BUNDLE")
            new_aggregator_ca_key=$(yq eval '.cluster.aggregatorCA.key' "$SECRETS_BUNDLE")
            new_service_account_key=$(yq eval '.cluster.serviceAccount.key' "$SECRETS_BUNDLE")
            
            # Store new certificates in 1Password
            op item edit "Talos PKI Certificates - $CLUSTER_NAME" \
                "machine-ca-crt[password]=$new_machine_ca_crt" \
                "machine-ca-key[password]=$new_machine_ca_key" \
                "cluster-ca-crt[password]=$new_cluster_ca_crt" \
                "cluster-ca-key[password]=$new_cluster_ca_key" \
                "etcd-ca-crt[password]=$new_etcd_ca_crt" \
                "etcd-ca-key[password]=$new_etcd_ca_key" \
                "aggregator-ca-crt[password]=$new_aggregator_ca_crt" \
                "aggregator-ca-key[password]=$new_aggregator_ca_key" \
                "service-account-key[password]=$new_service_account_key"
            
            success "Stored new PKI certificates in 1Password"
        fi
    else
        log "Using existing secrets bundle"
    fi
    
    # If PKI certificates exist in 1Password, always restore them to the bundle
    if [[ "$pki_exists" == "true" ]]; then
        log "Restoring PKI certificates from 1Password..."
        
        # Retrieve PKI certificates from 1Password
        local machine_ca_crt machine_ca_key cluster_ca_crt cluster_ca_key
        local etcd_ca_crt etcd_ca_key aggregator_ca_crt aggregator_ca_key service_account_key
        
        machine_ca_crt=$(op item get "Talos PKI Certificates - $CLUSTER_NAME" --fields label=machine-ca-crt --format json | jq -r '.value' 2>/dev/null || echo "")
        machine_ca_key=$(op item get "Talos PKI Certificates - $CLUSTER_NAME" --fields label=machine-ca-key --format json | jq -r '.value' 2>/dev/null || echo "")
        cluster_ca_crt=$(op item get "Talos PKI Certificates - $CLUSTER_NAME" --fields label=cluster-ca-crt --format json | jq -r '.value' 2>/dev/null || echo "")
        cluster_ca_key=$(op item get "Talos PKI Certificates - $CLUSTER_NAME" --fields label=cluster-ca-key --format json | jq -r '.value' 2>/dev/null || echo "")
        etcd_ca_crt=$(op item get "Talos PKI Certificates - $CLUSTER_NAME" --fields label=etcd-ca-crt --format json | jq -r '.value' 2>/dev/null || echo "")
        etcd_ca_key=$(op item get "Talos PKI Certificates - $CLUSTER_NAME" --fields label=etcd-ca-key --format json | jq -r '.value' 2>/dev/null || echo "")
        aggregator_ca_crt=$(op item get "Talos PKI Certificates - $CLUSTER_NAME" --fields label=aggregator-ca-crt --format json | jq -r '.value' 2>/dev/null || echo "")
        aggregator_ca_key=$(op item get "Talos PKI Certificates - $CLUSTER_NAME" --fields label=aggregator-ca-key --format json | jq -r '.value' 2>/dev/null || echo "")
        service_account_key=$(op item get "Talos PKI Certificates - $CLUSTER_NAME" --fields label=service-account-key --format json | jq -r '.value' 2>/dev/null || echo "")
        
        # Validate that we got valid certificates (not empty or null)
        if [[ -n "$machine_ca_crt" && -n "$machine_ca_key" && -n "$cluster_ca_crt" && -n "$cluster_ca_key" &&
              -n "$etcd_ca_crt" && -n "$etcd_ca_key" && -n "$aggregator_ca_crt" && -n "$aggregator_ca_key" &&
              -n "$service_account_key" ]]; then
            
            # Replace certificates in the secrets bundle
            yq eval ".machine.ca.crt = \"$machine_ca_crt\"" -i "$SECRETS_BUNDLE"
            yq eval ".machine.ca.key = \"$machine_ca_key\"" -i "$SECRETS_BUNDLE"
            yq eval ".cluster.ca.crt = \"$cluster_ca_crt\"" -i "$SECRETS_BUNDLE"
            yq eval ".cluster.ca.key = \"$cluster_ca_key\"" -i "$SECRETS_BUNDLE"
            yq eval ".cluster.etcd.ca.crt = \"$etcd_ca_crt\"" -i "$SECRETS_BUNDLE"
            yq eval ".cluster.etcd.ca.key = \"$etcd_ca_key\"" -i "$SECRETS_BUNDLE"
            yq eval ".cluster.aggregatorCA.crt = \"$aggregator_ca_crt\"" -i "$SECRETS_BUNDLE"
            yq eval ".cluster.aggregatorCA.key = \"$aggregator_ca_key\"" -i "$SECRETS_BUNDLE"
            yq eval ".cluster.serviceAccount.key = \"$service_account_key\"" -i "$SECRETS_BUNDLE"
        else
            warn "Some PKI certificates from 1Password were empty or invalid, keeping generated ones"
        fi
        
        success "Restored existing PKI certificates from 1Password"
    fi
    
    success "Secrets bundle created: $SECRETS_BUNDLE"
}

# Main execution
main() {
    log "Starting Talos secrets bundle creation from 1Password..."
    
    check_prerequisites
    create_secrets_bundle
    
    log "Talos secrets bundle created successfully!"
    echo ""
    echo "Secrets bundle: $SECRETS_BUNDLE"
    echo "Use with: talosctl gen config --with-secrets $SECRETS_BUNDLE"
}

# Change to repository root
cd "$(dirname "$0")/.."

# Run main function
main "$@"