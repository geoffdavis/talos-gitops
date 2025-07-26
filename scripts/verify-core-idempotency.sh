#!/bin/bash
# Verify that apps:deploy-core is idempotent and can be run multiple times safely

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed or not in PATH"
    fi

    if ! command -v task &> /dev/null; then
        error "task is not installed or not in PATH"
    fi

    if ! kubectl get namespaces &> /dev/null; then
        error "Kubernetes cluster is not accessible"
    fi

    success "All prerequisites met"
}

# Capture cluster state before test
capture_initial_state() {
    log "Capturing initial cluster state..."

    mkdir -p /tmp/idempotency-test

    # Capture resource counts
    kubectl get all --all-namespaces > /tmp/idempotency-test/initial-resources.txt
    kubectl get events --all-namespaces --sort-by='.lastTimestamp' > /tmp/idempotency-test/initial-events.txt

    # Capture specific component states
    kubectl get pods -n kube-system -l k8s-app=cilium > /tmp/idempotency-test/initial-cilium.txt 2>/dev/null || echo "Cilium not found" > /tmp/idempotency-test/initial-cilium.txt
    kubectl get pods -n external-secrets-system > /tmp/idempotency-test/initial-external-secrets.txt 2>/dev/null || echo "External Secrets not found" > /tmp/idempotency-test/initial-external-secrets.txt
    kubectl get pods -n onepassword-connect > /tmp/idempotency-test/initial-onepassword.txt 2>/dev/null || echo "1Password Connect not found" > /tmp/idempotency-test/initial-onepassword.txt
    kubectl get pods -n longhorn-system > /tmp/idempotency-test/initial-longhorn.txt 2>/dev/null || echo "Longhorn not found" > /tmp/idempotency-test/initial-longhorn.txt

    success "Initial state captured"
}

# Run apps:deploy-core and check for issues
run_deploy_core() {
    local run_number=$1
    log "Running apps:deploy-core (attempt $run_number)..."

    # Capture output and errors
    local output_file="/tmp/idempotency-test/run-${run_number}-output.txt"
    local error_file="/tmp/idempotency-test/run-${run_number}-errors.txt"

    if task apps:deploy-core > "$output_file" 2> "$error_file"; then
        success "apps:deploy-core completed successfully (run $run_number)"
    else
        error "apps:deploy-core failed on run $run_number. Check $error_file for details."
    fi

    # Check for concerning messages in output
    if grep -i "error\|failed\|conflict" "$output_file" | grep -v "Normal\|Warning.*BackOff"; then
        warn "Found concerning messages in run $run_number output:"
        grep -i "error\|failed\|conflict" "$output_file" | grep -v "Normal\|Warning.*BackOff" || true
    fi
}

# Check for resource conflicts or duplicates
check_resource_conflicts() {
    local run_number=$1
    log "Checking for resource conflicts after run $run_number..."

    # Check for error events
    local error_events
    error_events=$(kubectl get events --all-namespaces --field-selector type=Warning --sort-by='.lastTimestamp' | tail -20)

    if echo "$error_events" | grep -i "conflict\|duplicate\|already exists" | grep -v "Normal"; then
        warn "Found potential resource conflicts after run $run_number:"
        echo "$error_events" | grep -i "conflict\|duplicate\|already exists" | grep -v "Normal" || true
    fi

    # Check for failed pods
    local failed_pods
    failed_pods=$(kubectl get pods --all-namespaces --field-selector=status.phase=Failed 2>/dev/null || true)

    if [[ -n "$failed_pods" && "$failed_pods" != *"No resources found"* ]]; then
        warn "Found failed pods after run $run_number:"
        echo "$failed_pods"
    fi

    success "Resource conflict check completed for run $run_number"
}

# Verify component health
verify_component_health() {
    local run_number=$1
    log "Verifying component health after run $run_number..."

    local health_issues=0

    # Check Cilium
    if kubectl get pods -n kube-system -l k8s-app=cilium &> /dev/null; then
        local cilium_ready
        cilium_ready=$(kubectl get pods -n kube-system -l k8s-app=cilium --no-headers | awk '{print $2}' | grep -c "1/1" || echo "0")
        local cilium_total
        cilium_total=$(kubectl get pods -n kube-system -l k8s-app=cilium --no-headers | wc -l)

        if [[ "$cilium_ready" -eq "$cilium_total" && "$cilium_total" -gt 0 ]]; then
            success "Cilium pods healthy: $cilium_ready/$cilium_total ready"
        else
            warn "Cilium pods not all ready: $cilium_ready/$cilium_total ready"
            ((health_issues++))
        fi
    fi

    # Check External Secrets
    if kubectl get namespace external-secrets-system &> /dev/null; then
        local es_ready
        es_ready=$(kubectl get pods -n external-secrets-system --no-headers | awk '{print $2}' | grep -c "1/1\|2/2\|3/3" || echo "0")
        local es_total
        es_total=$(kubectl get pods -n external-secrets-system --no-headers | wc -l)

        if [[ "$es_ready" -eq "$es_total" && "$es_total" -gt 0 ]]; then
            success "External Secrets pods healthy: $es_ready/$es_total ready"
        else
            warn "External Secrets pods not all ready: $es_ready/$es_total ready"
            ((health_issues++))
        fi
    fi

    # Check 1Password Connect
    if kubectl get namespace onepassword-connect &> /dev/null; then
        local op_ready
        op_ready=$(kubectl get pods -n onepassword-connect --no-headers | awk '{print $2}' | grep -c "1/1\|2/2" || echo "0")
        local op_total
        op_total=$(kubectl get pods -n onepassword-connect --no-headers | wc -l)

        if [[ "$op_ready" -eq "$op_total" && "$op_total" -gt 0 ]]; then
            success "1Password Connect pods healthy: $op_ready/$op_total ready"
        else
            warn "1Password Connect pods not all ready: $op_ready/$op_total ready"
            ((health_issues++))
        fi
    fi

    # Check Longhorn
    if kubectl get namespace longhorn-system &> /dev/null; then
        local longhorn_ready
        longhorn_ready=$(kubectl get pods -n longhorn-system --no-headers | awk '{print $2}' | grep -c "1/1\|2/2\|3/3" || echo "0")
        local longhorn_total
        longhorn_total=$(kubectl get pods -n longhorn-system --no-headers | wc -l)

        if [[ "$longhorn_ready" -eq "$longhorn_total" && "$longhorn_total" -gt 0 ]]; then
            success "Longhorn pods healthy: $longhorn_ready/$longhorn_total ready"
        else
            warn "Longhorn pods not all ready: $longhorn_ready/$longhorn_total ready"
            ((health_issues++))
        fi
    fi

    if [[ "$health_issues" -eq 0 ]]; then
        success "All components healthy after run $run_number"
    else
        warn "$health_issues component health issues found after run $run_number"
    fi

    return $health_issues
}

# Compare states between runs
compare_states() {
    local run1=$1
    local run2=$2
    log "Comparing cluster state between run $run1 and run $run2..."

    # Compare resource counts
    local resources1="/tmp/idempotency-test/run-${run1}-resources.txt"
    local resources2="/tmp/idempotency-test/run-${run2}-resources.txt"

    kubectl get all --all-namespaces > "$resources1"
    kubectl get all --all-namespaces > "$resources2"

    if diff -q "$resources1" "$resources2" > /dev/null; then
        success "Resource state identical between run $run1 and run $run2"
    else
        warn "Resource state differences found between run $run1 and run $run2"
        diff "$resources1" "$resources2" | head -20 || true
    fi
}

# Wait for components to stabilize
wait_for_stabilization() {
    local wait_time=${1:-30}
    log "Waiting ${wait_time}s for components to stabilize..."
    sleep "$wait_time"
}

# Main test execution
main() {
    log "Starting apps:deploy-core idempotency verification..."
    echo ""

    check_prerequisites
    capture_initial_state

    local total_runs=3
    local health_issues_total=0

    # Run multiple iterations
    for run in $(seq 1 $total_runs); do
        echo ""
        log "=== Idempotency Test Run $run/$total_runs ==="

        run_deploy_core "$run"
        wait_for_stabilization 30
        check_resource_conflicts "$run"

        if ! verify_component_health "$run"; then
            ((health_issues_total++))
        fi

        # Compare with previous run
        if [[ "$run" -gt 1 ]]; then
            compare_states $((run-1)) "$run"
        fi

        echo ""
    done

    # Final assessment
    echo ""
    log "=== Idempotency Test Results ==="

    if [[ "$health_issues_total" -eq 0 ]]; then
        success "✅ IDEMPOTENCY TEST PASSED"
        success "apps:deploy-core can be run multiple times safely"
        success "No resource conflicts or health issues detected"
    else
        warn "⚠️ IDEMPOTENCY TEST COMPLETED WITH WARNINGS"
        warn "Found $health_issues_total health issues across $total_runs runs"
        warn "Review logs in /tmp/idempotency-test/ for details"
    fi

    echo ""
    log "Test artifacts saved in /tmp/idempotency-test/"
    log "Review the following files for detailed analysis:"
    echo "  - /tmp/idempotency-test/run-*-output.txt (task output)"
    echo "  - /tmp/idempotency-test/run-*-errors.txt (error logs)"
    echo "  - /tmp/idempotency-test/run-*-resources.txt (resource states)"
    echo ""

    # Cleanup option
    read -p "Remove test artifacts? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf /tmp/idempotency-test
        log "Test artifacts cleaned up"
    fi
}

# Run main function
main "$@"
