#!/bin/bash
# Test script for validating Talos GitOps configuration

# Remove strict error handling to allow script to continue on failures
# set -eo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] $1${NC}"
}

pass() {
    echo -e "${GREEN}✓ $1${NC}"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}✗ $1${NC}"
    ((TESTS_FAILED++))
}

warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Test functions
test_prerequisites() {
    log "Testing prerequisites..."
    
    # Check for required tools
    local tools=("talosctl" "kubectl" "flux" "kustomize" "helm" "cilium" "yq" "jq" "op")
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            pass "Tool $tool is available"
        else
            warn "Tool $tool is not available (may be optional)"
        fi
    done
}

test_talos_config() {
    log "Testing Talos configuration..."
    
    # Test if Talos config files exist
    local configs=("talos/patches/cluster.yaml" "talos/patches/controlplane.yaml" "talos/patches/worker.yaml")
    
    for config in "${configs[@]}"; do
        if [[ -f "$config" ]]; then
            pass "Talos config $config exists"
            
            # Validate YAML syntax
            if yq eval '.' "$config" &> /dev/null; then
                pass "Talos config $config has valid YAML syntax"
            else
                fail "Talos config $config has invalid YAML syntax"
            fi
        else
            fail "Talos config $config not found"
        fi
    done
    
    # Test if generated config directory exists
    if [[ -d "talos/generated" ]]; then
        pass "Talos generated config directory exists"
    else
        warn "Talos generated config directory not found (run 'task talos:generate-config')"
    fi
}

test_kubernetes_manifests() {
    log "Testing Kubernetes manifests..."
    
    # Find all YAML files in infrastructure and apps directories
    local yaml_files
    mapfile -t yaml_files < <(find infrastructure apps clusters -name "*.yaml" -o -name "*.yml" 2>/dev/null)
    
    for file in "${yaml_files[@]}"; do
        if [[ -f "$file" ]]; then
            # Test YAML syntax
            if yq eval '.' "$file" &> /dev/null; then
                pass "Manifest $file has valid YAML syntax"
                
                # Test Kubernetes resource validation (dry-run)
                if command -v kubectl &> /dev/null; then
                    if kubectl apply --dry-run=client -f "$file" &> /dev/null; then
                        pass "Manifest $file is valid Kubernetes resource"
                    else
                        warn "Manifest $file failed Kubernetes validation (may be template)"
                    fi
                else
                    warn "kubectl not available, skipping Kubernetes validation for $file"
                fi
            else
                fail "Manifest $file has invalid YAML syntax"
            fi
        fi
    done
}

test_flux_config() {
    log "Testing Flux configuration..."
    
    # Test if Flux system files exist
    local flux_files=(
        "clusters/home-ops/flux-system/gotk-sync.yaml"
        "clusters/home-ops/kustomization.yaml"
    )
    
    for file in "${flux_files[@]}"; do
        if [[ -f "$file" ]]; then
            pass "Flux config $file exists"
            
            # Validate with flux CLI
            if command -v flux &> /dev/null; then
                if flux check --pre &> /dev/null; then
                    pass "Flux prerequisites check passed"
                else
                    warn "Flux prerequisites check failed"
                fi
            else
                warn "flux CLI not available, skipping prerequisites check"
            fi
        else
            fail "Flux config $file not found"
        fi
    done
}

test_helm_charts() {
    log "Testing Helm chart configurations..."
    
    # Find all HelmRelease files
    local helm_releases
    mapfile -t helm_releases < <(find . -name "*.yaml" -exec grep -l "kind: HelmRelease" {} \; 2>/dev/null)
    
    for release in "${helm_releases[@]}"; do
        if [[ -f "$release" ]]; then
            pass "HelmRelease $release found"
            
            # Extract chart information
            local chart_name
            chart_name=$(yq eval '.spec.chart.spec.chart' "$release" 2>/dev/null)
            
            if [[ "$chart_name" != "null" && -n "$chart_name" ]]; then
                pass "HelmRelease $release has valid chart name: $chart_name"
            else
                fail "HelmRelease $release missing chart name"
            fi
        fi
    done
}

test_secrets_config() {
    log "Testing secrets configuration..."
    
    # Check for 1Password CLI
    if command -v op &> /dev/null; then
        pass "1Password CLI is available"
        
        # Test 1Password login status
        if op account list &> /dev/null; then
            pass "1Password CLI is authenticated"
        else
            warn "1Password CLI is not authenticated (run 'op signin')"
        fi
    else
        fail "1Password CLI is not available"
    fi
    
    # Check for secret store configurations
    local secret_stores
    mapfile -t secret_stores < <(find . -name "*.yaml" -exec grep -l "kind: SecretStore\|kind: ClusterSecretStore" {} \; 2>/dev/null)
    
    for store in "${secret_stores[@]}"; do
        if [[ -f "$store" ]]; then
            pass "Secret store configuration $store found"
        fi
    done
}

test_network_config() {
    log "Testing network configuration..."
    
    # Test if Cilium configurations exist
    local cilium_configs=(
        "infrastructure/cilium/helmrelease.yaml"
        "infrastructure/cilium/bgp-policy.yaml"
        "infrastructure/cilium/loadbalancer-pool.yaml"
    )
    
    for config in "${cilium_configs[@]}"; do
        if [[ -f "$config" ]]; then
            pass "Cilium config $config exists"
        else
            fail "Cilium config $config not found"
        fi
    done
    
    # Test BGP configuration
    if [[ -f "scripts/unifi-bgp-config.sh" ]]; then
        pass "Unifi BGP configuration script exists"
        
        # Test script syntax
        if bash -n "scripts/unifi-bgp-config.sh"; then
            pass "Unifi BGP script has valid syntax"
        else
            fail "Unifi BGP script has syntax errors"
        fi
    else
        fail "Unifi BGP configuration script not found"
    fi
}

test_storage_config() {
    log "Testing storage configuration..."
    
    # Test Longhorn configurations
    local longhorn_configs=(
        "infrastructure/longhorn/helmrelease.yaml"
        "infrastructure/longhorn/storage-class.yaml"
        "infrastructure/longhorn/volume-snapshot-class.yaml"
    )
    
    for config in "${longhorn_configs[@]}"; do
        if [[ -f "$config" ]]; then
            pass "Longhorn config $config exists"
        else
            fail "Longhorn config $config not found"
        fi
    done
}

test_kustomization() {
    log "Testing Kustomization configurations..."
    
    # Find all kustomization files
    local kustomization_files
    mapfile -t kustomization_files < <(find . -name "kustomization.yaml" -o -name "kustomization.yml" 2>/dev/null)
    
    for file in "${kustomization_files[@]}"; do
        if [[ -f "$file" ]]; then
            pass "Kustomization $file exists"
            
            # Test kustomize build
            if command -v kustomize &> /dev/null; then
                local dir
                dir=$(dirname "$file")
                if kustomize build "$dir" &> /dev/null; then
                    pass "Kustomization $file builds successfully"
                else
                    warn "Kustomization $file failed to build (may need resources)"
                fi
            else
                warn "kustomize not available, skipping build test for $file"
            fi
        fi
    done
}

test_taskfile() {
    log "Testing Taskfile configuration..."
    
    if [[ -f "Taskfile.yml" ]]; then
        pass "Taskfile.yml exists"
        
        # Test task syntax
        if command -v task &> /dev/null; then
            if task --list &> /dev/null; then
                pass "Taskfile has valid syntax"
                
                # List available tasks
                log "Available tasks:"
                task --list | grep -E '^\*' | sed 's/\* /  - /' || true
            else
                fail "Taskfile has syntax errors"
            fi
        else
            warn "task CLI not available, skipping Taskfile validation"
        fi
    else
        fail "Taskfile.yml not found"
    fi
}

test_mise_config() {
    log "Testing mise configuration..."
    
    if [[ -f ".mise.toml" ]]; then
        pass ".mise.toml exists"
        
        # Test mise status
        if command -v mise &> /dev/null; then
            if mise --version &> /dev/null; then
                pass "mise is available"
                
                # Check if tools are installed
                if mise current &> /dev/null; then
                    pass "mise tools are configured"
                else
                    warn "mise tools may not be installed (run 'mise install')"
                fi
            else
                warn "mise command failed"
            fi
        else
            warn "mise is not available"
        fi
    else
        fail ".mise.toml not found"
    fi
}

# Main test runner
run_tests() {
    log "Starting Talos GitOps configuration tests..."
    echo "=========================================="
    
    test_prerequisites
    test_talos_config
    test_kubernetes_manifests
    test_flux_config
    test_helm_charts
    test_secrets_config
    test_network_config
    test_storage_config
    test_kustomization
    test_taskfile
    test_mise_config
    
    echo "=========================================="
    log "Test Results:"
    echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed! ✓${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed. Please review the output above.${NC}"
        exit 1
    fi
}

# Run tests
cd "$(dirname "$0")/.."
run_tests