#!/bin/bash

set -e

echo "=== Testing GitOps Deployment for OIDC Setup ==="
echo ""

# Function to check kustomization status
check_kustomization() {
    local name=$1
    echo "Checking kustomization: $name"
    
    if flux get kustomization "$name" --no-header | grep -q "True.*Ready"; then
        echo "✅ $name is ready"
        return 0
    else
        echo "❌ $name is not ready"
        flux get kustomization "$name"
        return 1
    fi
}

# Function to check job completion
check_job() {
    local name=$1
    local namespace=$2
    echo "Checking job: $name in namespace $namespace"
    
    if kubectl get job "$name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null | grep -q "True"; then
        echo "✅ Job $name completed successfully"
        return 0
    elif kubectl get job "$name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null | grep -q "True"; then
        echo "❌ Job $name failed"
        kubectl describe job "$name" -n "$namespace"
        return 1
    else
        echo "⏳ Job $name is still running or not found"
        return 1
    fi
}

# Function to check secret exists
check_secret() {
    local name=$1
    local namespace=$2
    echo "Checking secret: $name in namespace $namespace"
    
    if kubectl get secret "$name" -n "$namespace" >/dev/null 2>&1; then
        echo "✅ Secret $name exists"
        return 0
    else
        echo "❌ Secret $name does not exist"
        return 1
    fi
}

echo "1. Checking Flux kustomization status..."
echo "----------------------------------------"

# Check core dependencies first
check_kustomization "infrastructure-sources" || exit 1
check_kustomization "infrastructure-external-secrets" || exit 1
check_kustomization "infrastructure-onepassword" || exit 1
check_kustomization "infrastructure-authentik" || exit 1

# Check outpost config kustomization
check_kustomization "infrastructure-authentik-outpost-config" || exit 1

# Check monitoring kustomization
check_kustomization "infrastructure-monitoring" || exit 1

echo ""
echo "2. Checking OIDC setup jobs..."
echo "------------------------------"

# Wait a bit for jobs to be created
sleep 5

# Check enhanced token setup job
check_job "authentik-enhanced-token-setup" "authentik"

# Check OIDC setup jobs
check_job "grafana-oidc-setup" "authentik"
check_job "dashboard-oidc-setup" "authentik"

echo ""
echo "3. Checking secrets..."
echo "---------------------"

# Check that OIDC secrets are created
check_secret "grafana-oidc-secret" "monitoring"
check_secret "dashboard-oidc-secret" "kubernetes-dashboard"

echo ""
echo "4. Checking 1Password integration..."
echo "------------------------------------"

# Check if 1Password entries were created (requires op CLI)
if command -v op >/dev/null 2>&1; then
    echo "Checking 1Password entries..."
    
    if op item get "home-ops-grafana-oidc-client-secret" --vault="Automation" >/dev/null 2>&1; then
        echo "✅ Grafana OIDC client secret exists in 1Password"
    else
        echo "❌ Grafana OIDC client secret not found in 1Password"
    fi
    
    if op item get "home-ops-dashboard-oidc-client-secret" --vault="Automation" >/dev/null 2>&1; then
        echo "✅ Dashboard OIDC client secret exists in 1Password"
    else
        echo "❌ Dashboard OIDC client secret not found in 1Password"
    fi
else
    echo "⚠️  op CLI not available, skipping 1Password checks"
fi

echo ""
echo "5. Summary..."
echo "-------------"

# Final status check
if flux get kustomizations | grep -E "(authentik-outpost-config|monitoring)" | grep -q "False"; then
    echo "❌ Some kustomizations are not ready. Check Flux status:"
    flux get kustomizations | grep -E "(authentik-outpost-config|monitoring)"
    exit 1
else
    echo "✅ All GitOps deployments are ready!"
    echo ""
    echo "Next steps:"
    echo "- OIDC applications should be configured in Authentik"
    echo "- Client secrets should be stored in 1Password"
    echo "- External secrets should sync the client secrets to Kubernetes"
    echo "- Applications can now use native OIDC authentication"
fi