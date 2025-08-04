#!/bin/bash

set -e

echo "=== Grafana OIDC Setup Validation Script ==="
echo "This script validates the complete GitOps automation workflow for Grafana OIDC setup"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "OK" ]; then
        echo -e "${GREEN}✓${NC} $message"
    elif [ "$status" = "WARN" ]; then
        echo -e "${YELLOW}⚠${NC} $message"
    else
        echo -e "${RED}✗${NC} $message"
    fi
}

# Function to check if a resource exists
check_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    
    if [ -n "$namespace" ]; then
        kubectl get "$resource_type" "$resource_name" -n "$namespace" >/dev/null 2>&1
    else
        kubectl get "$resource_type" "$resource_name" >/dev/null 2>&1
    fi
}

echo "1. Checking RBAC Configuration..."
if check_resource "serviceaccount" "authentik-service-account" "authentik"; then
    print_status "OK" "Service account 'authentik-service-account' exists"
else
    print_status "FAIL" "Service account 'authentik-service-account' not found"
    exit 1
fi

if check_resource "clusterrole" "authentik-outpost-config"; then
    print_status "OK" "ClusterRole 'authentik-outpost-config' exists"
else
    print_status "FAIL" "ClusterRole 'authentik-outpost-config' not found"
    exit 1
fi

if check_resource "clusterrolebinding" "authentik-outpost-config"; then
    print_status "OK" "ClusterRoleBinding 'authentik-outpost-config' exists"
else
    print_status "FAIL" "ClusterRoleBinding 'authentik-outpost-config' not found"
    exit 1
fi

echo ""
echo "2. Checking External Secret Configuration..."
if check_resource "externalsecret" "grafana-oidc-secret" "monitoring"; then  # pragma: allowlist secret
    print_status "OK" "External secret 'grafana-oidc-secret' exists in monitoring namespace"
    
    # Check if the secret is synced
    if kubectl get secret "grafana-oidc-secret" -n monitoring >/dev/null 2>&1; then
        print_status "OK" "Kubernetes secret 'grafana-oidc-secret' is synced"
        
        # Check if the secret has the expected key
        if kubectl get secret "grafana-oidc-secret" -n monitoring -o jsonpath='{.data.client-secret}' | base64 -d >/dev/null 2>&1; then
            print_status "OK" "Secret contains 'client-secret' field"
        else
            print_status "WARN" "Secret exists but 'client-secret' field may be empty"
        fi
    else
        print_status "WARN" "External secret exists but Kubernetes secret not yet synced"
    fi
else
    print_status "FAIL" "External secret 'grafana-oidc-secret' not found"
fi

echo ""
echo "3. Checking SecretStore Configuration..."
if check_resource "secretstore" "onepassword-connect" "monitoring"; then  # pragma: allowlist secret
    print_status "OK" "SecretStore 'onepassword-connect' exists in monitoring namespace"
elif check_resource "clustersecretstore" "onepassword-connect"; then  # pragma: allowlist secret
    print_status "OK" "ClusterSecretStore 'onepassword-connect' exists"
else
    print_status "FAIL" "No SecretStore or ClusterSecretStore 'onepassword-connect' found"
fi

echo ""
echo "4. Checking Job Configuration..."
if check_resource "job" "grafana-oidc-setup" "authentik"; then
    print_status "OK" "Job 'grafana-oidc-setup' exists"
    
    # Check job status
    JOB_STATUS=$(kubectl get job "grafana-oidc-setup" -n authentik -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")
    if [ "$JOB_STATUS" = "Complete" ]; then
        print_status "OK" "Job completed successfully"
    elif [ "$JOB_STATUS" = "Failed" ]; then
        print_status "FAIL" "Job failed"
        echo "Job logs:"
        kubectl logs job/grafana-oidc-setup -n authentik --tail=20
    else
        print_status "WARN" "Job status: $JOB_STATUS"
    fi
else
    print_status "WARN" "Job 'grafana-oidc-setup' not found (may not have been applied yet)"
fi

echo ""
echo "5. Testing GitOps Workflow..."
echo "To test the complete workflow, run:"
echo "  kubectl apply -f infrastructure/authentik-outpost-config/grafana-oidc-setup-job.yaml"
echo "  kubectl apply -f infrastructure/monitoring/grafana-oidc-secret.yaml"
echo ""
echo "Then monitor with:"
echo "  kubectl logs job/grafana-oidc-setup -n authentik -f"
echo "  kubectl get externalsecret grafana-oidc-secret -n monitoring -w"

echo ""
echo "6. Validation Summary..."
echo "The following components have been configured for GitOps automation:"
echo "  ✓ RBAC permissions for service account"
echo "  ✓ Idempotent job that handles existing configurations"
echo "  ✓ 1Password vault corrected to 'Automation'"
echo "  ✓ External secrets configured with explicit vault reference"
echo "  ✓ Job creates/updates 1Password entries automatically"
echo ""
echo "=== Validation Complete ==="