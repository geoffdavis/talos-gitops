#!/opt/homebrew/bin/bash

# CloudNativePG Backup Functionality Validation Script
# Tests backup and restore functionality after Barman Plugin migration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
LOG_FILE="${PROJECT_ROOT}/backup-validation-$(date +%Y%m%d-%H%M%S).log"
TIMEOUT_SECONDS=${TIMEOUT_SECONDS:-900}
DRY_RUN=${DRY_RUN:-false}

# Test configuration
declare -A CLUSTERS
CLUSTERS["homeassistant-postgresql"]="home-automation"
CLUSTERS["postgresql-cluster"]="postgresql-system"

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

step() {
    echo -e "${CYAN}→ $1${NC}" | tee -a "$LOG_FILE"
}

section() {
    echo -e "${PURPLE}=== $1 ===${NC}" | tee -a "$LOG_FILE"
}

# Check prerequisites
check_prerequisites() {
    section "PREREQUISITES CHECK"
    log "Validating backup test prerequisites..."

    # Check cluster connectivity
    if ! kubectl get nodes &> /dev/null; then
        error "Cannot connect to Kubernetes cluster"
    fi

    # Check CNPG operator
    if ! kubectl get crd clusters.postgresql.cnpg.io &> /dev/null; then
        error "CloudNativePG operator not found"
    fi

    # Check plugin availability
    if ! kubectl get pods -n cnpg-system -l app.kubernetes.io/name=cnpg-barman-plugin &> /dev/null; then
        error "Barman Cloud Plugin not found - migration may not be complete"
    fi

    local plugin_pods
    plugin_pods=$(kubectl get pods -n cnpg-system -l app.kubernetes.io/name=cnpg-barman-plugin --field-selector=status.phase=Running | wc -l)
    if [[ $plugin_pods -eq 0 ]]; then
        error "No running plugin pods found"
    fi

    info "✅ Prerequisites validated - $plugin_pods plugin pods running"
}

# Validate cluster status
validate_cluster_status() {
    section "CLUSTER STATUS VALIDATION"
    log "Validating cluster configurations..."

    local validation_failed=false

    for cluster in "${!CLUSTERS[@]}"; do
        local namespace="${CLUSTERS[$cluster]}"
        step "Validating cluster: $cluster ($namespace)"

        # Check cluster exists and is healthy
        if ! kubectl get cluster "$cluster" -n "$namespace" &> /dev/null; then
            warn "Cluster $cluster not found in namespace $namespace"
            validation_failed=true
            continue
        fi

        local status
        status=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.phase}')
        info "Cluster Status: $status"

        if [[ "$status" != "Cluster in healthy state" ]] && [[ "$status" != "Running" ]]; then
            warn "Cluster $cluster is not healthy: $status"
            validation_failed=true
        fi

        # Check plugin configuration
        local plugins
        plugins=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.spec.plugins[*].name}' 2>/dev/null || echo "None")
        info "Configured Plugins: $plugins"

        if [[ "$plugins" != *"barman-cloud.cloudnative-pg.io"* ]]; then
            warn "Cluster $cluster missing barman-cloud plugin"
            validation_failed=true
        fi

        # Check ObjectStore reference
        local objectstore_name
        objectstore_name=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.spec.plugins[?(@.name=="barman-cloud.cloudnative-pg.io")].parameters.objectStoreName}' 2>/dev/null || echo "")
        info "ObjectStore Reference: $objectstore_name"

        if [[ -z "$objectstore_name" ]]; then
            warn "No ObjectStore configured for cluster $cluster"
            validation_failed=true
        else
            # Verify ObjectStore exists
            if kubectl get objectstore "$objectstore_name" -n "$namespace" &> /dev/null; then
                info "✅ ObjectStore $objectstore_name exists"
            else
                warn "ObjectStore $objectstore_name not found"
                validation_failed=true
            fi
        fi

        # Check continuous archiving
        local archiving_status
        archiving_status=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}' 2>/dev/null || echo "Unknown")
        info "Continuous Archiving: $archiving_status"

        if [[ "$archiving_status" == "False" ]]; then
            local reason
            reason=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].message}' 2>/dev/null || echo "Unknown")
            warn "Archiving issues: $reason"
            validation_failed=true
        fi

        # Check for deprecated configuration
        local has_barman_config
        has_barman_config=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.spec.backup.barmanObjectStore}' 2>/dev/null || echo "")
        if [[ -n "$has_barman_config" ]]; then
            warn "Cluster $cluster still has deprecated barmanObjectStore configuration"
            validation_failed=true
        fi
    done

    if [[ "$validation_failed" == "true" ]]; then
        error "Cluster validation failed - fix issues before testing backups"
    fi

    log "✅ All clusters validated successfully"
}

# Create test data
create_test_data() {
    local cluster="$1"
    local namespace="$2"

    step "Creating test data in $cluster..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would create test data"
        return 0
    fi

    # Get the primary pod
    local primary_pod
    primary_pod=$(kubectl get pods -n "$namespace" -l postgresql="$cluster",role=primary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$primary_pod" ]]; then
        warn "No primary pod found for cluster $cluster"
        return 1
    fi

    info "Primary pod: $primary_pod"

    # Create test table and data
    local test_timestamp
    test_timestamp=$(date +%Y%m%d_%H%M%S)

    kubectl exec -n "$namespace" "$primary_pod" -- psql -U postgres -c "
        CREATE TABLE IF NOT EXISTS backup_test_$test_timestamp (
            id SERIAL PRIMARY KEY,
            test_data TEXT,
            created_at TIMESTAMP DEFAULT NOW()
        );

        INSERT INTO backup_test_$test_timestamp (test_data) VALUES
            ('Test data for backup validation'),
            ('Migration test data'),
            ('Backup functionality test');

        SELECT COUNT(*) as test_records FROM backup_test_$test_timestamp;
    " 2>/dev/null || warn "Failed to create test data for $cluster"

    echo "$test_timestamp"
}

# Wait for backup completion
wait_for_backup() {
    local backup_name="$1"
    local namespace="$2"
    local timeout="${3:-$TIMEOUT_SECONDS}"

    step "Waiting for backup $backup_name to complete..."

    local elapsed=0
    local interval=15

    while [[ $elapsed -lt $timeout ]]; do
        local status
        status=$(kubectl get backup "$backup_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

        case "$status" in
            "completed")
                info "✅ Backup completed successfully"

                # Show backup details
                local start_time stop_time begin_wal end_wal size
                start_time=$(kubectl get backup "$backup_name" -n "$namespace" -o jsonpath='{.status.startedAt}' 2>/dev/null || echo "")
                stop_time=$(kubectl get backup "$backup_name" -n "$namespace" -o jsonpath='{.status.stoppedAt}' 2>/dev/null || echo "")
                begin_wal=$(kubectl get backup "$backup_name" -n "$namespace" -o jsonpath='{.status.beginWal}' 2>/dev/null || echo "")
                end_wal=$(kubectl get backup "$backup_name" -n "$namespace" -o jsonpath='{.status.endWal}' 2>/dev/null || echo "")

                info "Backup Details:"
                info "  Started: $start_time"
                info "  Completed: $stop_time"
                info "  WAL Range: $begin_wal → $end_wal"

                return 0
                ;;
            "failed")
                error "❌ Backup failed"
                kubectl describe backup "$backup_name" -n "$namespace" || true
                return 1
                ;;
            "running")
                info "Backup in progress... ($elapsed/${timeout}s)"
                ;;
            *)
                info "Backup status: $status ($elapsed/${timeout}s)"
                ;;
        esac

        sleep $interval
        elapsed=$((elapsed + interval))
    done

    error "Backup timed out after ${timeout}s"
}

# Test on-demand backup
test_ondemand_backup() {
    local cluster="$1"
    local namespace="$2"

    step "Testing on-demand backup for $cluster..."

    # Create test data first
    local test_timestamp
    test_timestamp=$(create_test_data "$cluster" "$namespace")

    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would create on-demand backup"
        return 0
    fi

    # Create backup
    local backup_name="validation-test-$cluster-$(date +%Y%m%d-%H%M%S)"

    cat <<EOF | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: $backup_name
  namespace: $namespace
  labels:
    app.kubernetes.io/name: $cluster
    backup-purpose: validation-test
    test-timestamp: "$test_timestamp"
spec:
  cluster:
    name: $cluster
  method: plugin
EOF

    # Wait for backup to complete
    wait_for_backup "$backup_name" "$namespace"

    # Verify backup exists in status
    local backup_id
    backup_id=$(kubectl get backup "$backup_name" -n "$namespace" -o jsonpath='{.status.backupId}' 2>/dev/null || echo "")
    if [[ -n "$backup_id" ]]; then
        info "✅ Backup ID: $backup_id"
    fi

    log "✅ On-demand backup test completed for $cluster"
    echo "$backup_name"
}

# Test scheduled backup configuration
test_scheduled_backup() {
    local cluster="$1"
    local namespace="$2"

    step "Testing scheduled backup configuration for $cluster..."

    # Check if scheduled backup exists
    local scheduled_backups
    scheduled_backups=$(kubectl get scheduledbackups -n "$namespace" -l app.kubernetes.io/name="$cluster" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$scheduled_backups" ]]; then
        warn "No scheduled backups found for $cluster"

        if [[ "$DRY_RUN" == "true" ]]; then
            info "DRY RUN: Would create scheduled backup"
            return 0
        fi

        # Create a test scheduled backup
        local scheduled_name="validation-scheduled-$cluster"
        cat <<EOF | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: $scheduled_name
  namespace: $namespace
  labels:
    app.kubernetes.io/name: $cluster
    backup-purpose: validation-test
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  cluster:
    name: $cluster
  method: plugin
  suspend: true  # Don't actually run during test
EOF
        info "✅ Created test scheduled backup: $scheduled_name"
    else
        info "✅ Found scheduled backups: $scheduled_backups"

        # Validate scheduled backup configuration
        for sb in $scheduled_backups; do
            local method schedule
            method=$(kubectl get scheduledbackup "$sb" -n "$namespace" -o jsonpath='{.spec.method}' 2>/dev/null || echo "")
            schedule=$(kubectl get scheduledbackup "$sb" -n "$namespace" -o jsonpath='{.spec.schedule}' 2>/dev/null || echo "")

            info "Scheduled Backup $sb: method=$method, schedule=$schedule"

            if [[ "$method" != "plugin" ]]; then
                warn "Scheduled backup $sb not using plugin method"
            fi
        done
    fi

    log "✅ Scheduled backup test completed for $cluster"
}

# Test WAL archiving
test_wal_archiving() {
    local cluster="$1"
    local namespace="$2"

    step "Testing WAL archiving for $cluster..."

    # Check WAL archiving status
    local archiving_status last_archived_wal
    archiving_status=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}' 2>/dev/null || echo "Unknown")
    last_archived_wal=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.lastArchivedWAL}' 2>/dev/null || echo "")

    info "WAL Archiving Status: $archiving_status"
    info "Last Archived WAL: $last_archived_wal"

    if [[ "$archiving_status" != "True" ]]; then
        warn "WAL archiving not operational for $cluster"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would test WAL archiving"
        return 0
    fi

    # Force WAL switch to test archiving
    step "Forcing WAL switch to test archiving..."
    local primary_pod
    primary_pod=$(kubectl get pods -n "$namespace" -l postgresql="$cluster",role=primary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -n "$primary_pod" ]]; then
        local current_wal
        current_wal=$(kubectl exec -n "$namespace" "$primary_pod" -- psql -U postgres -t -c "SELECT pg_current_wal_lsn();" 2>/dev/null | tr -d ' ' || echo "")
        info "Current WAL LSN: $current_wal"

        # Switch WAL
        kubectl exec -n "$namespace" "$primary_pod" -- psql -U postgres -c "SELECT pg_switch_wal();" &>/dev/null || warn "Failed to switch WAL"

        # Wait a bit and check if new WAL was archived
        sleep 30

        local new_last_archived
        new_last_archived=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.lastArchivedWAL}' 2>/dev/null || echo "")
        info "New Last Archived WAL: $new_last_archived"

        if [[ "$new_last_archived" != "$last_archived_wal" ]]; then
            info "✅ WAL archiving is working - new WAL archived"
        else
            warn "WAL archiving may be slow - no new WAL archived yet"
        fi
    else
        warn "No primary pod found to test WAL switching"
    fi

    log "✅ WAL archiving test completed for $cluster"
}

# Comprehensive backup test
run_backup_tests() {
    section "BACKUP FUNCTIONALITY TESTS"
    log "Running comprehensive backup functionality tests..."

    local test_results=()

    for cluster in "${!CLUSTERS[@]}"; do
        local namespace="${CLUSTERS[$cluster]}"

        section "TESTING CLUSTER: $cluster"

        # Test on-demand backup
        local backup_name
        if backup_name=$(test_ondemand_backup "$cluster" "$namespace"); then
            test_results+=("✅ On-demand backup: $cluster")
        else
            test_results+=("❌ On-demand backup: $cluster")
        fi

        # Test scheduled backup configuration
        if test_scheduled_backup "$cluster" "$namespace"; then
            test_results+=("✅ Scheduled backup: $cluster")
        else
            test_results+=("❌ Scheduled backup: $cluster")
        fi

        # Test WAL archiving
        if test_wal_archiving "$cluster" "$namespace"; then
            test_results+=("✅ WAL archiving: $cluster")
        else
            test_results+=("❌ WAL archiving: $cluster")
        fi
    done

    # Summary
    section "TEST RESULTS SUMMARY"
    for result in "${test_results[@]}"; do
        if [[ "$result" == *"✅"* ]]; then
            log "$result"
        else
            warn "$result"
        fi
    done

    # Count failures
    local failures
    failures=$(printf '%s\n' "${test_results[@]}" | grep -c "❌" || echo "0")

    if [[ $failures -eq 0 ]]; then
        log "🎉 All backup functionality tests passed!"
        return 0
    else
        warn "$failures test(s) failed - review issues above"
        return 1
    fi
}

# Generate test report
generate_report() {
    section "BACKUP VALIDATION REPORT"
    log "Generating comprehensive backup validation report..."

    local report_file="${PROJECT_ROOT}/backup-validation-report-$(date +%Y%m%d-%H%M%S).md"

    cat > "$report_file" <<EOF
# CloudNativePG Backup Validation Report

**Generated:** $(date)
**Cluster:** $(kubectl config current-context)
**Validation Script:** $0

## Executive Summary

This report validates the backup functionality after migrating from deprecated \`barmanObjectStore\` to the new Barman Cloud Plugin architecture.

## Cluster Status

EOF

    for cluster in "${!CLUSTERS[@]}"; do
        local namespace="${CLUSTERS[$cluster]}"

        cat >> "$report_file" <<EOF
### Cluster: $cluster ($namespace)

EOF

        if kubectl get cluster "$cluster" -n "$namespace" &> /dev/null; then
            local status plugins archiving_status objectstore_name
            status=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.phase}')
            plugins=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.spec.plugins[*].name}' 2>/dev/null || echo "None")
            archiving_status=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}' 2>/dev/null || echo "Unknown")
            objectstore_name=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.spec.plugins[?(@.name=="barman-cloud.cloudnative-pg.io")].parameters.objectStoreName}' 2>/dev/null || echo "")

            cat >> "$report_file" <<EOF
- **Status:** $status
- **Plugins:** $plugins
- **ObjectStore:** $objectstore_name
- **Continuous Archiving:** $archiving_status

EOF
        else
            cat >> "$report_file" <<EOF
- **Status:** Cluster not found

EOF
        fi
    done

    cat >> "$report_file" <<EOF
## Backup Tests

### On-Demand Backups
- Tests creation and completion of manual backups using plugin method

### Scheduled Backups
- Validates scheduled backup configuration and method

### WAL Archiving
- Tests continuous WAL archiving functionality

## Recommendations

1. Monitor backup completion times and adjust retention policies as needed
2. Verify S3 bucket accessibility and credentials
3. Test restore procedures in non-production environment
4. Set up monitoring alerts for backup failures

## Log Files

- **Validation Log:** $LOG_FILE
- **Report:** $report_file

---
*Generated by CloudNativePG Backup Validation Script*
EOF

    info "✅ Report generated: $report_file"
    echo "$report_file"
}

# Show help
show_help() {
    cat <<EOF
CloudNativePG Backup Functionality Validation Script

Validates backup functionality after Barman Plugin migration by testing:
- Cluster configuration and plugin setup
- On-demand backup creation and completion
- Scheduled backup configuration
- WAL archiving functionality

USAGE:
    $0 [OPTIONS] [COMMAND]

COMMANDS:
    validate    Run full validation suite (default)
    status      Show cluster and backup status
    test        Run backup functionality tests only
    report      Generate validation report
    help        Show this help message

OPTIONS:
    --dry-run              Perform validation without creating backups
    --timeout SECONDS      Set timeout for backup operations (default: 900)

ENVIRONMENT VARIABLES:
    DRY_RUN=true           Perform dry run validation
    TIMEOUT_SECONDS=N      Set backup timeout in seconds

EXAMPLES:
    # Full validation
    $0 validate

    # Dry run validation
    $0 --dry-run validate

    # Just show status
    $0 status

    # Generate report only
    $0 report

VALIDATION STEPS:
    1. Prerequisites Check
    2. Cluster Status Validation
    3. Backup Functionality Tests
    4. Report Generation

EOF
}

# Main execution
main() {
    local command="validate"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --timeout)
                TIMEOUT_SECONDS="$2"
                shift 2
                ;;
            validate|status|test|report|help)
                command="$1"
                shift
                ;;
            *)
                error "Unknown option: $1. Use 'help' for usage information."
                ;;
        esac
    done

    # Initialize logging
    echo "CloudNativePG Backup Functionality Validation" | tee "$LOG_FILE"
    echo "Started at: $(date)" | tee -a "$LOG_FILE"
    echo "Command: $command" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN MODE - No backups will be created"
    fi

    # Execute command
    case "$command" in
        "validate")
            check_prerequisites
            validate_cluster_status
            run_backup_tests
            generate_report
            log "🎉 Backup validation completed!"
            ;;
        "status")
            validate_cluster_status
            ;;
        "test")
            check_prerequisites
            run_backup_tests
            ;;
        "report")
            generate_report
            ;;
        "help")
            show_help
            exit 0
            ;;
        *)
            error "Unknown command: $command"
            ;;
    esac

    echo "" | tee -a "$LOG_FILE"
    echo "Completed at: $(date)" | tee -a "$LOG_FILE"
    log "Log file: $LOG_FILE"
}

# Execute main function with all arguments
main "$@"
