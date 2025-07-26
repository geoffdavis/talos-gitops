#!/bin/bash
# Test script for validating cluster recovery functionality

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

# Configuration
CLUSTER_NODES=("172.29.51.11" "172.29.51.12" "172.29.51.13")
CLUSTER_VIP="172.29.51.10"

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
test_environment_setup() {
    log "Testing environment setup..."
    
    # Check for .env file
    if [[ -f ".env" ]]; then
        pass ".env file exists"
        
        # Check for OP_ACCOUNT variable
        if grep -q "OP_ACCOUNT=" .env; then
            pass "OP_ACCOUNT is defined in .env"
        else
            fail "OP_ACCOUNT is not defined in .env"
        fi
    else
        fail ".env file not found"
    fi
    
    # Check for 1Password CLI authentication
    if command -v op &> /dev/null; then
        if op account list &> /dev/null; then
            pass "1Password CLI is authenticated"
        else
            fail "1Password CLI is not authenticated"
        fi
    else
        fail "1Password CLI is not installed"
    fi
}

test_onepassword_secrets() {
    log "Testing 1Password secrets configuration..."
    
    # Source .env if it exists
    if [[ -f ".env" ]]; then
        source .env
    fi
    
    # Check for required 1Password entries
    local required_entries=(
        "talos - home-ops"
        "BGP Authentication - home-ops"
        "Cloudflare API Token"
        "1Password Connect"
        "Longhorn UI Credentials - home-ops"
    )
    
    for entry in "${required_entries[@]}"; do
        if op --account "${OP_ACCOUNT:-}" item get "$entry" --vault="Automation" &> /dev/null; then
            pass "1Password entry '$entry' exists"
        else
            warn "1Password entry '$entry' not found (may be using different name)"
        fi
    done
}

test_talos_configuration() {
    log "Testing Talos configuration generation..."
    
    # Check if talhelper is available
    if command -v talhelper &> /dev/null; then
        pass "talhelper is installed"
    else
        fail "talhelper is not installed"
    fi
    
    # Check if talosctl is available
    if command -v talosctl &> /dev/null; then
        pass "talosctl is installed"
    else
        fail "talosctl is not installed"
    fi
    
    # Check if secrets file exists
    if [[ -f "talos/talsecret.yaml" ]]; then
        pass "Talos secrets file exists"
        
        # Validate YAML syntax
        if yq eval '.' "talos/talsecret.yaml" &> /dev/null; then
            pass "Talos secrets file has valid YAML syntax"
        else
            fail "Talos secrets file has invalid YAML syntax"
        fi
    else
        warn "Talos secrets file not found (run 'task talos:restore-secrets')"
    fi
}

test_recovery_tasks() {
    log "Testing recovery tasks in Taskfile..."
    
    # Check if task CLI is available
    if command -v task &> /dev/null; then
        # Test if recovery tasks exist
        local recovery_tasks=(
            "talos:restore-secrets"
            "talos:recover-kubeconfig"
            "talos:fix-cilium"
            "cluster:recover"
        )
        
        for task_name in "${recovery_tasks[@]}"; do
            if task --list | grep -q "$task_name"; then
                pass "Recovery task '$task_name' exists"
            else
                fail "Recovery task '$task_name' not found"
            fi
        done
    else
        warn "task CLI not available, skipping recovery task tests"
    fi
}

test_cilium_configuration() {
    log "Testing Cilium configuration for Talos..."
    
    # Check if Cilium values are correct for Talos
    if kubectl get cm -n kube-system cilium-config &> /dev/null; then
        pass "Cilium config map exists"
        
        # Check for kube-proxy replacement
        if kubectl get cm -n kube-system cilium-config -o yaml | grep -q "kube-proxy-replacement.*true"; then
            pass "Cilium is configured for kube-proxy replacement"
        else
            fail "Cilium is not configured for kube-proxy replacement"
        fi
        
        # Check for k8s service configuration
        local cilium_config
        cilium_config=$(kubectl get cm -n kube-system cilium-config -o yaml 2>/dev/null || echo "")
        
        if echo "$cilium_config" | grep -q "k8s-service-host.*localhost"; then
            pass "Cilium has correct k8s-service-host (localhost)"
        else
            warn "Cilium k8s-service-host may not be configured correctly"
        fi
        
        if echo "$cilium_config" | grep -q "k8s-service-port.*7445"; then
            pass "Cilium has correct k8s-service-port (7445)"
        else
            warn "Cilium k8s-service-port may not be configured correctly"
        fi
    else
        warn "Cilium config map not found (cluster may not be running)"
    fi
}

test_cluster_connectivity() {
    log "Testing cluster connectivity after recovery..."
    
    # Test kubeconfig - check both local file and default kubectl context
    local kubeconfig_found=false
    local kubectl_output
    
    if [[ -f "kubeconfig" ]]; then
        pass "Local kubeconfig file exists"
        kubeconfig_found=true
        
        # Test API connectivity with local kubeconfig
        kubectl_output=$(kubectl --kubeconfig=./kubeconfig get nodes 2>&1)
        
        if kubectl --kubeconfig=./kubeconfig get nodes &>/dev/null; then
            pass "Can connect to cluster API with local kubeconfig"
        elif echo "$kubectl_output" | grep -q "certificate"; then
            warn "Cannot connect to cluster API with local kubeconfig (certificate issues - run 'task talos:recover-kubeconfig')"
        elif echo "$kubectl_output" | grep -q "refused\|unreachable"; then
            warn "Cannot connect to cluster API (cluster may be powered off or unreachable)"
        else
            warn "Cannot connect to cluster API (unknown error)"
        fi
    else
        warn "Local kubeconfig file not found"
    fi
    
    # Also test default kubectl context
    kubectl_output=$(kubectl get nodes 2>&1)
    
    if kubectl get nodes &>/dev/null; then
        pass "Can connect to cluster API with default kubectl context"
    elif [[ "$kubeconfig_found" == "false" ]]; then
        fail "No working kubeconfig found (run 'task talos:recover-kubeconfig')"
    fi
    
    # Test Talos connectivity
    if [[ -f "clusterconfig/talosconfig" ]]; then
        pass "Talos config file exists"
        
        # Test Talos node connectivity
        for node in "${CLUSTER_NODES[@]}"; do
            if TALOSCONFIG=clusterconfig/talosconfig talosctl --nodes "$node" version &> /dev/null; then
                pass "Can connect to Talos node $node"
            else
                warn "Cannot connect to Talos node $node"
            fi
        done
    else
        warn "Talos config file not found"
    fi
}

test_recovery_documentation() {
    log "Testing recovery documentation..."
    
    # Check if recovery documentation exists
    if [[ -f "docs/CLUSTER_RECOVERY.md" ]]; then
        pass "Cluster recovery documentation exists"
        
        # Check for key sections
        local required_sections=(
            "Prerequisites"
            "Quick Recovery"
            "Manual Recovery Steps"
            "Troubleshooting"
        )
        
        for section in "${required_sections[@]}"; do
            if grep -q "## $section" "docs/CLUSTER_RECOVERY.md"; then
                pass "Documentation contains '$section' section"
            else
                fail "Documentation missing '$section' section"
            fi
        done
    else
        fail "Cluster recovery documentation not found"
    fi
}

# Main test runner
run_tests() {
    log "Starting cluster recovery tests..."
    echo "=========================================="
    
    test_environment_setup
    test_onepassword_secrets
    test_talos_configuration
    test_recovery_tasks
    test_cilium_configuration
    test_cluster_connectivity
    test_recovery_documentation
    
    echo "=========================================="
    log "Test Results:"
    echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All recovery tests passed! ✓${NC}"
        exit 0
    else
        echo -e "${YELLOW}Some recovery tests failed. Review the output above.${NC}"
        exit 1
    fi
}

# Run tests
cd "$(dirname "$0")/.." || exit
run_tests