#!/bin/bash

# create-long-lived-token.sh
# Creates a long-lived Authentik API token with 1-year expiry
# Usage: ./create-long-lived-token.sh [--dry-run] [--force]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="authentik"
TOKEN_DESCRIPTION="Long-lived RADIUS Outpost Token (1 year)"
EXPIRY_DAYS=365

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Creates a long-lived Authentik API token with 1-year expiry.

OPTIONS:
    --dry-run       Show what would be done without making changes
    --force         Force creation even if valid tokens exist
    --help          Show this help message

EXAMPLES:
    $0                    # Create token normally
    $0 --dry-run          # Preview what would be done
    $0 --force            # Force new token creation

REQUIREMENTS:
    - kubectl configured for the cluster
    - Authentik deployed in '$NAMESPACE' namespace
    - Proper RBAC permissions for token operations

EOF
}

# Parse command line arguments
DRY_RUN=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validation functions
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check namespace exists
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_error "Namespace '$NAMESPACE' does not exist"
        exit 1
    fi
    
    # Check Authentik deployment
    if ! kubectl get deployment authentik-server -n "$NAMESPACE" &> /dev/null; then
        log_error "Authentik server deployment not found in namespace '$NAMESPACE'"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Wait for Authentik to be ready
wait_for_authentik() {
    log_info "Waiting for Authentik server to be ready..."
    
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if kubectl exec -n "$NAMESPACE" deployment/authentik-server -- \
           curl -f -s http://localhost:9000/if/flow/initial-setup/ > /dev/null 2>&1; then
            log_success "Authentik server is ready"
            return 0
        fi
        
        log_info "Attempt $attempt/$max_attempts: Authentik not ready, waiting 10 seconds..."
        sleep 10
        ((attempt++))
    done
    
    log_error "Authentik server did not become ready within $((max_attempts * 10)) seconds"
    exit 1
}

# Create the long-lived token
create_token() {
    log_info "Creating long-lived API token..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would create token with $EXPIRY_DAYS days expiry"
        return 0
    fi
    
    # Create a temporary job to run the token creation
    local job_name
    job_name="create-long-lived-token-$(date +%s)"
    local job_manifest
    job_manifest=$(cat << EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: $job_name
  namespace: $NAMESPACE
spec:
  backoffLimit: 3
  activeDeadlineSeconds: 300
  template:
    spec:
      restartPolicy: OnFailure
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        runAsGroup: 65534
      containers:
        - name: create-token
          image: ghcr.io/goauthentik/server:2024.8.3
          securityContext:
            allowPrivilegeEscalation: false
            runAsNonRoot: true
            runAsUser: 65534
            runAsGroup: 65534
            capabilities:
              drop:
                - ALL
          env:
            - name: AUTHENTIK_REDIS__HOST
              value: "authentik-redis-master.authentik.svc.cluster.local"
            - name: AUTHENTIK_POSTGRESQL__HOST
              valueFrom:
                secretKeyRef:
                  name: authentik-database-credentials
                  key: AUTHENTIK_POSTGRESQL__HOST
            - name: AUTHENTIK_POSTGRESQL__NAME
              valueFrom:
                secretKeyRef:
                  name: authentik-database-credentials
                  key: AUTHENTIK_POSTGRESQL__NAME
            - name: AUTHENTIK_POSTGRESQL__USER
              valueFrom:
                secretKeyRef:
                  name: authentik-database-credentials
                  key: AUTHENTIK_POSTGRESQL__USER
            - name: AUTHENTIK_POSTGRESQL__PASSWORD
              valueFrom:
                secretKeyRef:
                  name: authentik-database-credentials
                  key: AUTHENTIK_POSTGRESQL__PASSWORD
            - name: AUTHENTIK_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: authentik-config
                  key: AUTHENTIK_SECRET_KEY
            - name: FORCE_CREATE
              value: "$FORCE"
          command:
            - /bin/bash
            - -c
            - |
              set -e
              ak shell -c "
              from authentik.core.models import User, Token
              from datetime import datetime, timedelta
              import secrets
              import base64
              import json
              import os
              
              force_create = os.environ.get('FORCE_CREATE', 'false').lower() == 'true'
              
              # Get admin user
              try:
                  user = User.objects.get(username='akadmin')
                  print(f'Found admin user: {user.username}')
              except User.DoesNotExist:
                  print('ERROR: Admin user akadmin not found')
                  exit(1)
              
              # Calculate expiry
              expiry_date = datetime.now() + timedelta(days=$EXPIRY_DAYS)
              
              # Check existing tokens
              existing_tokens = Token.objects.filter(user=user, intent='api')
              valid_long_term_tokens = []
              
              for token in existing_tokens:
                  if token.expires and token.expires > datetime.now():
                      days_remaining = (token.expires - datetime.now()).days
                      if days_remaining > 300:  # Consider long-term if > 300 days
                          valid_long_term_tokens.append(token)
                          print(f'Found valid long-term token: {token.key[:8]}... (expires in {days_remaining} days)')
              
              # Create new token if needed
              if not valid_long_term_tokens or force_create:
                  if force_create and valid_long_term_tokens:
                      print('FORCE mode: Creating new token despite existing valid tokens')
                  
                  # Generate new token
                  token_key = secrets.token_hex(32)
                  token = Token.objects.create(
                      user=user,
                      intent='api',
                      key=token_key,
                      description='$TOKEN_DESCRIPTION - Created ' + datetime.now().strftime('%Y-%m-%d'),
                      expires=expiry_date,
                      expiring=True
                  )
                  
                  print(f'SUCCESS: Created new token {token.key[:8]}... expires {expiry_date.strftime(\"%Y-%m-%d\")}')
                  print(f'TOKEN_KEY={token.key}')
                  print(f'TOKEN_B64=' + base64.b64encode(token.key.encode()).decode())
                  print(f'EXPIRES={expiry_date.isoformat()}')
              else:
                  token = valid_long_term_tokens[0]
                  print(f'SUCCESS: Using existing valid token {token.key[:8]}...')
                  print(f'TOKEN_KEY={token.key}')
                  print(f'TOKEN_B64=' + base64.b64encode(token.key.encode()).decode())
                  print(f'EXPIRES={token.expires.isoformat()}')
              "
EOF
)
    
    # Apply the job
    echo "$job_manifest" | kubectl apply -f -
    
    # Wait for job completion
    log_info "Waiting for token creation job to complete..."
    kubectl wait --for=condition=complete job/"$job_name" -n "$NAMESPACE" --timeout=300s
    
    # Get the job output
    local pod_name
    pod_name=$(kubectl get pods -n "$NAMESPACE" -l job-name="$job_name" -o jsonpath='{.items[0].metadata.name}')
    local job_output
    job_output=$(kubectl logs -n "$NAMESPACE" "$pod_name")
    
    # Parse output
    if echo "$job_output" | grep -q "SUCCESS:"; then
        log_success "Token creation completed successfully"
        
        # Extract token information
        local token_key
        token_key=$(echo "$job_output" | grep "TOKEN_KEY=" | cut -d'=' -f2)
        local token_b64
        token_b64=$(echo "$job_output" | grep "TOKEN_B64=" | cut -d'=' -f2)
        local expires
        expires=$(echo "$job_output" | grep "EXPIRES=" | cut -d'=' -f2)
        
        echo ""
        log_info "Token Information:"
        echo "  Token: ${token_key:0:8}...${token_key: -8}"
        echo "  Expires: $expires"
        echo "  Base64: $token_b64"
        echo ""
        log_info "Next steps:"
        echo "  1. Update 1Password entry 'Authentik RADIUS Token - home-ops'"
        echo "  2. Set token field to: $token_key"
        echo "  3. External Secrets will sync automatically"
    else
        log_error "Token creation failed"
        echo "$job_output"
        exit 1
    fi
    
    # Cleanup job
    kubectl delete job "$job_name" -n "$NAMESPACE" --ignore-not-found=true
}

# Main execution
main() {
    log_info "Starting long-lived token creation..."
    
    check_prerequisites
    wait_for_authentik
    create_token
    
    log_success "Long-lived token creation completed!"
}

# Run main function
main "$@"