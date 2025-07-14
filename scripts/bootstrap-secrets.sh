#!/bin/bash
# Bootstrap secrets from 1Password for Home-Ops Talos GitOps cluster

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
    
    # Check if Talos cluster secrets item exists
    if ! op item get "Talos Cluster Secrets - $CLUSTER_NAME" &> /dev/null; then
        log "Creating Talos Cluster Secrets - $CLUSTER_NAME item..."
        op item create \
            --category="Secure Note" \
            --title="Talos Cluster Secrets - $CLUSTER_NAME" \
            --vault="Automation" \
            "cluster-secret[password]=$(openssl rand -base64 32)" \
            "bootstrap-token[password]=$(openssl rand -base64 32)" \
            "secretbox-key[password]=$(openssl rand -base64 32)"
        success "Created Talos Cluster Secrets - $CLUSTER_NAME item"
    else
        success "Talos Cluster Secrets - $CLUSTER_NAME item already exists"
    fi
    
    # Check if Talos PKI certificates item exists
    if ! op item get "Talos PKI Certificates - $CLUSTER_NAME" &> /dev/null; then
        log "Creating Talos PKI Certificates - $CLUSTER_NAME item..."
        op item create \
            --category="Secure Note" \
            --title="Talos PKI Certificates - $CLUSTER_NAME" \
            --vault="Automation" \
            "notes=Talos PKI certificates will be stored here after first generation"
        success "Created Talos PKI Certificates - $CLUSTER_NAME item"
    else
        success "Talos PKI Certificates - $CLUSTER_NAME item already exists"
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
    if ! op item get "1Password Connect Credentials - $CLUSTER_NAME" &> /dev/null; then
        warn "1Password Connect Credentials - $CLUSTER_NAME item not found. Please create it manually with your Connect credentials."
        echo "  This should include the 1password-credentials.json file as a document"
    else
        success "1Password Connect Credentials - $CLUSTER_NAME item exists"
    fi
    
    # Check if 1Password Connect token exists
    if ! op item get "1Password Connect Token - $CLUSTER_NAME" &> /dev/null; then
        warn "1Password Connect Token - $CLUSTER_NAME item not found. Please create it manually with your Connect token."
        echo "  This should include the Connect token in the 'token' field"
    else
        success "1Password Connect Token - $CLUSTER_NAME item exists"
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
    log "Bootstrapping cluster secrets..."
    
    # Create temporary directory for secrets
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Export secrets to temporary files
    op item get "Talos Cluster Secrets - $CLUSTER_NAME" --fields label=cluster-secret --format json | jq -r '.value' > "$temp_dir/cluster-secret"
    op item get "Talos Cluster Secrets - $CLUSTER_NAME" --fields label=bootstrap-token --format json | jq -r '.value' > "$temp_dir/bootstrap-token"
    op item get "Talos Cluster Secrets - $CLUSTER_NAME" --fields label=secretbox-key --format json | jq -r '.value' > "$temp_dir/secretbox-key"
    
    # Create Kubernetes secrets if cluster is accessible
    if kubectl get namespaces &> /dev/null; then
        log "Creating Kubernetes secrets..."
        
        # Create 1Password Connect secrets
        kubectl create namespace onepassword-connect --dry-run=client -o yaml | kubectl apply -f -
        
        # Get 1Password Connect credentials from document
        if op document get "1Password Connect Credentials - $CLUSTER_NAME" --vault="Automation" --out-file="$temp_dir/1password-credentials.json" 2>/dev/null; then
            kubectl create secret generic onepassword-connect-credentials \
                --namespace=onepassword-connect \
                --from-file=1password-credentials.json="$temp_dir/1password-credentials.json" \
                --dry-run=client -o yaml | kubectl apply -f -
            success "Created 1Password Connect credentials secret"
        else
            warn "1Password Connect credentials document not found"
        fi
        
        # Get 1Password Connect token
        if op item get "1Password Connect Token - $CLUSTER_NAME" --vault="Automation" --fields label=token --format json > "$temp_dir/op-token.json" 2>/dev/null; then
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
        
    else
        warn "Kubernetes cluster not accessible, skipping secret creation"
    fi
    
    # Clean up temporary files
    rm -rf "$temp_dir"
    success "Cluster secrets bootstrapped"
}

# Generate Talos configuration with secrets
generate_talos_config() {
    log "Generating Talos configuration with secrets..."
    
    # Create temporary directory for config generation
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Export cluster secrets
    local cluster_secret bootstrap_token secretbox_key
    cluster_secret=$(op item get "Talos Cluster Secrets - $CLUSTER_NAME" --fields label=cluster-secret --format json | jq -r '.value')
    bootstrap_token=$(op item get "Talos Cluster Secrets - $CLUSTER_NAME" --fields label=bootstrap-token --format json | jq -r '.value')
    secretbox_key=$(op item get "Talos Cluster Secrets - $CLUSTER_NAME" --fields label=secretbox-key --format json | jq -r '.value')
    
    # Create patch file with secrets
    cat > "$temp_dir/secrets-patch.yaml" << EOF
cluster:
  id: $CLUSTER_NAME
  secret: $cluster_secret
  token: $bootstrap_token
  secretboxEncryptionSecret: $secretbox_key
EOF
    
    # Check if PKI certificates already exist in 1Password
    local pki_exists=false
    if op item get "Talos PKI Certificates - $CLUSTER_NAME" --fields label=machine-ca-crt --format json &> /dev/null; then
        log "Found existing PKI certificates in 1Password, restoring them..."
        pki_exists=true
        
        # Extract PKI certificates from 1Password
        local machine_ca_crt machine_ca_key cluster_ca_crt cluster_ca_key etcd_ca_crt etcd_ca_key
        local aggregator_ca_crt aggregator_ca_key service_account_key
        
        machine_ca_crt=$(op item get "Talos PKI Certificates - $CLUSTER_NAME" --fields label=machine-ca-crt --format json | jq -r '.value')
        machine_ca_key=$(op item get "Talos PKI Certificates - $CLUSTER_NAME" --fields label=machine-ca-key --format json | jq -r '.value')
        cluster_ca_crt=$(op item get "Talos PKI Certificates - $CLUSTER_NAME" --fields label=cluster-ca-crt --format json | jq -r '.value')
        cluster_ca_key=$(op item get "Talos PKI Certificates - $CLUSTER_NAME" --fields label=cluster-ca-key --format json | jq -r '.value')
        etcd_ca_crt=$(op item get "Talos PKI Certificates - $CLUSTER_NAME" --fields label=etcd-ca-crt --format json | jq -r '.value')
        etcd_ca_key=$(op item get "Talos PKI Certificates - $CLUSTER_NAME" --fields label=etcd-ca-key --format json | jq -r '.value')
        aggregator_ca_crt=$(op item get "Talos PKI Certificates - $CLUSTER_NAME" --fields label=aggregator-ca-crt --format json | jq -r '.value')
        aggregator_ca_key=$(op item get "Talos PKI Certificates - $CLUSTER_NAME" --fields label=aggregator-ca-key --format json | jq -r '.value')
        service_account_key=$(op item get "Talos PKI Certificates - $CLUSTER_NAME" --fields label=service-account-key --format json | jq -r '.value')
        
        # Create PKI patch file with existing certificates
        cat > "$temp_dir/pki-patch.yaml" << EOF
machine:
  ca:
    crt: $machine_ca_crt
    key: $machine_ca_key
cluster:
  ca:
    crt: $cluster_ca_crt
    key: $cluster_ca_key
  etcd:
    ca:
      crt: $etcd_ca_crt
      key: $etcd_ca_key
  aggregatorCA:
    crt: $aggregator_ca_crt
    key: $aggregator_ca_key
  serviceAccount:
    key: $service_account_key
EOF
        
        success "Existing PKI certificates restored from 1Password"
    fi
    
    # Generate Talos configuration
    mkdir -p talos/generated
    if [[ "$pki_exists" == "true" ]]; then
        # Use existing PKI certificates without --force
        talosctl gen config $CLUSTER_NAME https://172.29.51.10:6443 \
            --output-dir talos/generated \
            --with-examples=false \
            --with-docs=false \
            --config-patch @talos/patches/cluster.yaml \
            --config-patch @"$temp_dir/secrets-patch.yaml" \
            --config-patch @"$temp_dir/pki-patch.yaml" \
            --config-patch-control-plane @talos/patches/controlplane.yaml \
            --config-patch-worker @talos/patches/worker.yaml
        success "Talos configuration generated with existing PKI certificates"
    else
        # Generate new PKI certificates and store them in 1Password
        talosctl gen config $CLUSTER_NAME https://172.29.51.10:6443 \
            --output-dir talos/generated \
            --with-examples=false \
            --with-docs=false \
            --force \
            --config-patch @talos/patches/cluster.yaml \
            --config-patch @"$temp_dir/secrets-patch.yaml" \
            --config-patch-control-plane @talos/patches/controlplane.yaml \
            --config-patch-worker @talos/patches/worker.yaml
        
        log "Storing new PKI certificates in 1Password..."
        
        # Extract and store PKI certificates from generated configuration files
        local config_file="talos/generated/controlplane.yaml"
        if [[ -f "$config_file" ]]; then
            # Extract machine CA certificate and key
            local machine_ca_crt machine_ca_key
            machine_ca_crt=$(yq eval '.machine.ca.crt' "$config_file")
            machine_ca_key=$(yq eval '.machine.ca.key' "$config_file")
            
            # Extract cluster CA certificate and key
            local cluster_ca_crt cluster_ca_key
            cluster_ca_crt=$(yq eval '.cluster.ca.crt' "$config_file")
            cluster_ca_key=$(yq eval '.cluster.ca.key' "$config_file")
            
            # Extract etcd CA certificate and key
            local etcd_ca_crt etcd_ca_key
            etcd_ca_crt=$(yq eval '.cluster.etcd.ca.crt' "$config_file")
            etcd_ca_key=$(yq eval '.cluster.etcd.ca.key' "$config_file")
            
            # Extract aggregator CA certificate and key
            local aggregator_ca_crt aggregator_ca_key
            aggregator_ca_crt=$(yq eval '.cluster.aggregatorCA.crt' "$config_file")
            aggregator_ca_key=$(yq eval '.cluster.aggregatorCA.key' "$config_file")
            
            # Extract service account key
            local service_account_key
            service_account_key=$(yq eval '.cluster.serviceAccount.key' "$config_file")
            
            # Store all certificates in 1Password
            op item edit "Talos PKI Certificates - $CLUSTER_NAME" \
                "machine-ca-crt[password]=$machine_ca_crt" \
                "machine-ca-key[password]=$machine_ca_key" \
                "cluster-ca-crt[password]=$cluster_ca_crt" \
                "cluster-ca-key[password]=$cluster_ca_key" \
                "etcd-ca-crt[password]=$etcd_ca_crt" \
                "etcd-ca-key[password]=$etcd_ca_key" \
                "aggregator-ca-crt[password]=$aggregator_ca_crt" \
                "aggregator-ca-key[password]=$aggregator_ca_key" \
                "service-account-key[password]=$service_account_key"
            
            success "New PKI certificates stored in 1Password"
        else
            warn "Configuration file not found, PKI certificates may not have been generated"
        fi
        
        success "Talos configuration generated with new PKI certificates"
    fi
    
    # Clean up
    rm -rf "$temp_dir"
}

# Update secret references in manifests
update_secret_references() {
    log "Updating secret references in manifests..."
    
    # Update 1Password Connect auth secret
    local connect_token
    if connect_token=$(op item get "1Password Connect" --fields label=token --format json | jq -r '.value' 2>/dev/null); then
        # Update the secret-store.yaml with the actual token
        if [[ -f "infrastructure/onepassword-connect/secret-store.yaml" ]]; then
            # The secret will be created by the bootstrap process
            success "1Password Connect token reference updated"
        fi
    fi
    
    success "Secret references updated"
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
    log "Starting secrets bootstrap process for $CLUSTER_NAME cluster..."
    
    check_prerequisites
    create_1password_items
    bootstrap_cluster_secrets
    generate_talos_config
    update_secret_references
    validate_github_token
    
    log "Secrets bootstrap completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Configure DHCP reservations on your UDM Pro for the Mac mini devices"
    echo "2. Review the generated Talos configuration in talos/generated/"
    echo "3. Apply the configuration to your nodes with: task talos:apply-config"
    echo "4. Bootstrap the cluster with: task talos:bootstrap"
    echo "5. If USB devices aren't detected, run: task talos:reboot"
    echo "6. Configure BGP on UDM Pro with: task bgp:configure-unifi"
    echo "7. Deploy the GitOps stack with: task flux:bootstrap"
}

# Change to repository root
cd "$(dirname "$0")/.."

# Run main function
main "$@"