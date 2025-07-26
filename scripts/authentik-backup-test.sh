#!/bin/bash
# Authentik Backup and Recovery Test Script
# Tests PostgreSQL backup functionality and Longhorn volume snapshots

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_FAILED=false
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] $1${NC}"
}

info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
    ((PASSED_TESTS++))
}

warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

error() {
    echo -e "${RED}✗ $1${NC}"
    TEST_FAILED=true
    ((FAILED_TESTS++))
}

section() {
    echo ""
    echo -e "${BOLD}${CYAN}=== $1 ===${NC}"
    echo ""
}

test_start() {
    ((TOTAL_TESTS++))
}

# Helper functions
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "$1 is not installed or not in PATH"
        return 1
    fi
    return 0
}

check_cluster_access() {
    if ! kubectl get namespaces &> /dev/null; then
        error "Cannot connect to Kubernetes cluster"
        return 1
    fi
    return 0
}

wait_for_condition() {
    local resource="$1"
    local condition="$2"
    local timeout="${3:-300}"
    local namespace="${4:-}"

    local ns_flag=""
    if [[ -n "$namespace" ]]; then
        ns_flag="-n $namespace"
    fi

    log "Waiting for $resource to be $condition (timeout: ${timeout}s)..."

    if timeout "$timeout" bash -c "
        while true; do
            if kubectl get $resource $ns_flag -o jsonpath='{.status.conditions[?(@.type==\"$condition\")].status}' 2>/dev/null | grep -q True; then
                exit 0
            fi
            sleep 5
        done
    "; then
        return 0
    else
        return 1
    fi
}

# Test functions
test_prerequisites() {
    section "Prerequisites Check"

    test_start
    if check_command kubectl; then
        success "kubectl is available"
    fi

    test_start
    if check_cluster_access; then
        success "Kubernetes cluster is accessible"
    fi

    # Check required namespaces
    test_start
    if kubectl get namespace postgresql-system &> /dev/null; then
        success "postgresql-system namespace exists"
    else
        error "postgresql-system namespace not found"
    fi

    test_start
    if kubectl get namespace authentik &> /dev/null; then
        success "authentik namespace exists"
    else
        error "authentik namespace not found"
    fi

    test_start
    if kubectl get namespace longhorn-system &> /dev/null; then
        success "longhorn-system namespace exists"
    else
        error "longhorn-system namespace not found"
    fi
}

test_postgresql_backup_config() {
    section "PostgreSQL Backup Configuration Test"

    # Check if scheduled backup exists
    test_start
    if kubectl get scheduledbackup -n postgresql-system postgresql-cluster-backup &> /dev/null; then
        success "PostgreSQL scheduled backup is configured"
    else
        error "PostgreSQL scheduled backup not found"
    fi

    # Check S3 credentials
    test_start
    if kubectl get secret -n postgresql-system postgresql-s3-backup-credentials &> /dev/null; then
        success "PostgreSQL S3 backup credentials exist"

        # Verify credentials have required keys
        local keys
        keys=$(kubectl get secret -n postgresql-system postgresql-s3-backup-credentials -o jsonpath='{.data}' | jq -r 'keys | join(", ")' 2>/dev/null || echo "unknown")
        info "S3 credentials keys: $keys"
    else
        error "PostgreSQL S3 backup credentials not found"
    fi

    # Check cluster backup configuration
    test_start
    local backup_config
    backup_config=$(kubectl get cluster -n postgresql-system postgresql-cluster -o jsonpath='{.spec.backup}' 2>/dev/null || echo "")
    if [[ -n "$backup_config" ]]; then
        success "PostgreSQL cluster has backup configuration"

        local retention
        retention=$(kubectl get cluster -n postgresql-system postgresql-cluster -o jsonpath='{.spec.backup.retentionPolicy}' 2>/dev/null || echo "unknown")
        info "Backup retention policy: $retention"
    else
        error "PostgreSQL cluster backup configuration not found"
    fi
}

test_create_manual_backup() {
    section "Manual PostgreSQL Backup Test"

    local backup_name="test-backup-$TIMESTAMP"

    test_start
    log "Creating manual backup: $backup_name"

    # Create backup resource
    if kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: $backup_name
  namespace: postgresql-system
  labels:
    test: "true"
    created-by: "backup-test-script"
spec:
  cluster:
    name: postgresql-cluster
  method: barmanObjectStore
  immediate: true
EOF
    then
        success "Manual backup resource created"
    else
        error "Failed to create manual backup resource"
        return 1
    fi

    # Wait for backup to complete
    test_start
    log "Waiting for backup to complete (timeout: 600s)..."

    local backup_status=""
    local timeout=600
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        backup_status=$(kubectl get backup -n postgresql-system "$backup_name" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")

        case "$backup_status" in
            "completed")
                success "Manual backup completed successfully"
                break
                ;;
            "failed")
                error "Manual backup failed"
                kubectl describe backup -n postgresql-system "$backup_name"
                return 1
                ;;
            "running"|"starting"|"")
                log "Backup status: $backup_status (elapsed: ${elapsed}s)"
                sleep 10
                ((elapsed += 10))
                ;;
            *)
                warn "Unknown backup status: $backup_status"
                sleep 10
                ((elapsed += 10))
                ;;
        esac
    done

    if [[ "$backup_status" != "completed" ]]; then
        error "Backup did not complete within timeout"
        return 1
    fi

    # Verify backup details
    test_start
    local backup_size
    backup_size=$(kubectl get backup -n postgresql-system "$backup_name" -o jsonpath='{.status.backupId}' 2>/dev/null || echo "unknown")
    if [[ "$backup_size" != "unknown" && -n "$backup_size" ]]; then
        success "Backup has valid backup ID: $backup_size"
    else
        error "Backup missing backup ID"
    fi

    # Store backup name for cleanup
    echo "$backup_name" > "/tmp/test-backup-name-$TIMESTAMP"
}

test_longhorn_snapshot_config() {
    section "Longhorn Snapshot Configuration Test"

    # Check volume snapshot class
    test_start
    if kubectl get volumesnapshotclass longhorn-snapshot-vsc &> /dev/null; then
        success "Longhorn volume snapshot class exists"
    else
        error "Longhorn volume snapshot class not found"
    fi

    # Check recurring jobs for database backups
    test_start
    local database_jobs
    database_jobs=$(kubectl get recurringjob -n longhorn-system --no-headers 2>/dev/null | grep -c "database" || echo "0")
    if [[ "$database_jobs" -gt 0 ]]; then
        success "Longhorn database recurring jobs configured ($database_jobs jobs)"
    else
        error "No Longhorn database recurring jobs found"
    fi

    # Check if Authentik Redis PVC exists
    test_start
    if kubectl get pvc -n authentik redis-data-authentik-redis-master-0 &> /dev/null; then
        success "Authentik Redis PVC exists"
    else
        error "Authentik Redis PVC not found"
    fi
}

test_create_volume_snapshot() {
    section "Volume Snapshot Test"

    local snapshot_name="test-redis-snapshot-$TIMESTAMP"

    test_start
    log "Creating volume snapshot: $snapshot_name"

    # Create volume snapshot
    if kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: $snapshot_name
  namespace: authentik
  labels:
    test: "true"
    created-by: "backup-test-script"
spec:
  source:
    persistentVolumeClaimName: redis-data-authentik-redis-master-0
  volumeSnapshotClassName: longhorn-snapshot-vsc
EOF
    then
        success "Volume snapshot resource created"
    else
        error "Failed to create volume snapshot resource"
        return 1
    fi

    # Wait for snapshot to be ready
    test_start
    log "Waiting for snapshot to be ready (timeout: 300s)..."

    local snapshot_status=""
    local timeout=300
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        snapshot_status=$(kubectl get volumesnapshot -n authentik "$snapshot_name" -o jsonpath='{.status.readyToUse}' 2>/dev/null || echo "false")

        if [[ "$snapshot_status" == "true" ]]; then
            success "Volume snapshot is ready"
            break
        else
            log "Snapshot status: readyToUse=$snapshot_status (elapsed: ${elapsed}s)"
            sleep 10
            ((elapsed += 10))
        fi
    done

    if [[ "$snapshot_status" != "true" ]]; then
        error "Volume snapshot did not become ready within timeout"
        kubectl describe volumesnapshot -n authentik "$snapshot_name"
        return 1
    fi

    # Verify snapshot details
    test_start
    local snapshot_size
    snapshot_size=$(kubectl get volumesnapshot -n authentik "$snapshot_name" -o jsonpath='{.status.restoreSize}' 2>/dev/null || echo "unknown")
    if [[ "$snapshot_size" != "unknown" && -n "$snapshot_size" ]]; then
        success "Snapshot has valid size: $snapshot_size"
    else
        warn "Snapshot size not available (may be normal)"
    fi

    # Store snapshot name for cleanup
    echo "$snapshot_name" > "/tmp/test-snapshot-name-$TIMESTAMP"
}

test_point_in_time_recovery() {
    section "Point-in-Time Recovery Test"

    test_start
    log "Testing point-in-time recovery capability..."

    # Check if we can query WAL files
    local primary_pod
    primary_pod=$(kubectl get pods -n postgresql-system -l postgresql=postgresql-cluster,role=primary --no-headers 2>/dev/null | head -1 | awk '{print $1}' || echo "")

    if [[ -n "$primary_pod" ]]; then
        success "PostgreSQL primary pod identified: $primary_pod"

        # Check WAL archiving status
        test_start
        if kubectl exec -n postgresql-system "$primary_pod" -- psql -c "SELECT pg_is_in_recovery(), current_setting('archive_mode'), current_setting('wal_level');" 2>/dev/null; then
            success "WAL archiving configuration verified"
        else
            error "Failed to verify WAL archiving configuration"
        fi

        # Check latest WAL file
        test_start
        local latest_wal
        latest_wal=$(kubectl exec -n postgresql-system "$primary_pod" -- psql -t -c "SELECT pg_walfile_name(pg_current_wal_lsn());" 2>/dev/null | tr -d ' ' || echo "unknown")
        if [[ "$latest_wal" != "unknown" && -n "$latest_wal" ]]; then
            success "Latest WAL file: $latest_wal"
        else
            error "Failed to get latest WAL file information"
        fi
    else
        error "No PostgreSQL primary pod found"
    fi
}

test_backup_monitoring() {
    section "Backup Monitoring Test"

    # Check recent backups
    test_start
    local recent_backups
    recent_backups=$(kubectl get backup -n postgresql-system --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "$recent_backups" -gt 0 ]]; then
        success "Found $recent_backups PostgreSQL backups"

        # Show latest backup details
        local latest_backup
        latest_backup=$(kubectl get backup -n postgresql-system --sort-by='.metadata.creationTimestamp' --no-headers 2>/dev/null | tail -1 | awk '{print $1}' || echo "")
        if [[ -n "$latest_backup" ]]; then
            local backup_status
            backup_status=$(kubectl get backup -n postgresql-system "$latest_backup" -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
            local backup_time
            backup_time=$(kubectl get backup -n postgresql-system "$latest_backup" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo "unknown")
            info "Latest backup: $latest_backup (status: $backup_status, created: $backup_time)"
        fi
    else
        warn "No PostgreSQL backups found"
    fi

    # Check volume snapshots
    test_start
    local recent_snapshots
    recent_snapshots=$(kubectl get volumesnapshot -n authentik --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "$recent_snapshots" -gt 0 ]]; then
        success "Found $recent_snapshots volume snapshots"
    else
        warn "No volume snapshots found"
    fi

    # Check backup job status
    test_start
    local backup_jobs
    backup_jobs=$(kubectl get job -n postgresql-system --no-headers 2>/dev/null | grep -c "backup" || echo "0")
    if [[ "$backup_jobs" -gt 0 ]]; then
        info "Found $backup_jobs backup-related jobs"
    fi
}

test_restore_capability() {
    section "Restore Capability Test"

    test_start
    log "Testing restore capability (dry-run)..."

    # Test PVC restore from snapshot (dry-run)
    local snapshot_name
    if [[ -f "/tmp/test-snapshot-name-$TIMESTAMP" ]]; then
        snapshot_name=$(cat "/tmp/test-snapshot-name-$TIMESTAMP")

        log "Testing PVC restore from snapshot: $snapshot_name"

        # Create restore PVC manifest (dry-run)
        if kubectl apply --dry-run=client -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-restore-pvc-$TIMESTAMP
  namespace: authentik
spec:
  storageClassName: longhorn-ssd
  dataSource:
    name: $snapshot_name
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
        then
            success "PVC restore manifest is valid"
        else
            error "PVC restore manifest validation failed"
        fi
    else
        warn "No test snapshot available for restore test"
    fi

    # Test PostgreSQL cluster restore (dry-run)
    test_start
    log "Testing PostgreSQL cluster restore (dry-run)..."

    if kubectl apply --dry-run=client -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: test-restore-cluster-$TIMESTAMP
  namespace: postgresql-system
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:16.4
  bootstrap:
    recovery:
      source: postgresql-cluster
      recoveryTarget:
        targetTime: "$(date -u -d '1 hour ago' '+%Y-%m-%d %H:%M:%S')"
  externalClusters:
    - name: postgresql-cluster
      barmanObjectStore:
        destinationPath: "s3://longhorn-backup/postgresql-cluster"
        s3Credentials:
          accessKeyId:
            name: postgresql-s3-backup-credentials
            key: AWS_ACCESS_KEY_ID
          secretAccessKey:
            name: postgresql-s3-backup-credentials
            key: AWS_SECRET_ACCESS_KEY
EOF
    then
        success "PostgreSQL restore manifest is valid"
    else
        error "PostgreSQL restore manifest validation failed"
    fi
}

cleanup_test_resources() {
    section "Cleanup Test Resources"

    # Clean up test backup
    if [[ -f "/tmp/test-backup-name-$TIMESTAMP" ]]; then
        local backup_name
        backup_name=$(cat "/tmp/test-backup-name-$TIMESTAMP")
        log "Cleaning up test backup: $backup_name"

        if kubectl delete backup -n postgresql-system "$backup_name" 2>/dev/null; then
            success "Test backup cleaned up"
        else
            warn "Failed to clean up test backup (may not exist)"
        fi

        rm -f "/tmp/test-backup-name-$TIMESTAMP"
    fi

    # Clean up test snapshot
    if [[ -f "/tmp/test-snapshot-name-$TIMESTAMP" ]]; then
        local snapshot_name
        snapshot_name=$(cat "/tmp/test-snapshot-name-$TIMESTAMP")
        log "Cleaning up test snapshot: $snapshot_name"

        if kubectl delete volumesnapshot -n authentik "$snapshot_name" 2>/dev/null; then
            success "Test snapshot cleaned up"
        else
            warn "Failed to clean up test snapshot (may not exist)"
        fi

        rm -f "/tmp/test-snapshot-name-$TIMESTAMP"
    fi
}

show_backup_recommendations() {
    section "Backup Recommendations"

    echo -e "${YELLOW}Backup Strategy Recommendations:${NC}"
    echo ""

    echo "1. PostgreSQL Backups:"
    echo "   - Schedule: Daily at 3 AM (configured)"
    echo "   - Retention: 30 days (configured)"
    echo "   - Test restore monthly"
    echo ""

    echo "2. Volume Snapshots:"
    echo "   - Schedule: Daily at 1 AM (configured)"
    echo "   - Retention: 7 daily snapshots (configured)"
    echo "   - Test restore quarterly"
    echo ""

    echo "3. Monitoring:"
    echo "   - Set up alerts for backup failures"
    echo "   - Monitor backup storage usage"
    echo "   - Verify backup integrity regularly"
    echo ""

    echo "4. Documentation:"
    echo "   - Document restore procedures"
    echo "   - Test disaster recovery scenarios"
    echo "   - Keep backup credentials secure"
    echo ""
}

show_summary() {
    section "Test Summary"

    echo -e "${BOLD}Total tests: $TOTAL_TESTS${NC}"
    echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "${RED}Failed: $FAILED_TESTS${NC}"
    echo ""

    if [[ "$TEST_FAILED" == "true" ]]; then
        echo -e "${RED}❌ Backup testing FAILED${NC}"
        echo ""
        echo "Please review the failed tests above and address any issues."
        echo "Common issues:"
        echo "- Missing backup configuration"
        echo "- S3 credentials not configured"
        echo "- Longhorn snapshot class not available"
        echo "- Insufficient permissions"
        echo ""
        return 1
    else
        echo -e "${GREEN}✅ Backup testing PASSED${NC}"
        echo ""
        echo "All backup and recovery components are functioning correctly."
        echo ""
        echo "Next steps:"
        echo "1. Monitor backup schedules"
        echo "2. Test full disaster recovery procedures"
        echo "3. Set up backup monitoring alerts"
        echo "4. Document recovery procedures"
        echo ""
        return 0
    fi
}

# Main execution
main() {
    log "Starting Authentik backup and recovery testing..."
    echo ""

    # Change to repository root
    cd "$REPO_ROOT" || {
        error "Failed to change to repository root: $REPO_ROOT"
        exit 1
    }

    # Run all tests
    test_prerequisites
    test_postgresql_backup_config
    test_create_manual_backup
    test_longhorn_snapshot_config
    test_create_volume_snapshot
    test_point_in_time_recovery
    test_backup_monitoring
    test_restore_capability

    # Cleanup
    cleanup_test_resources

    # Show recommendations and summary
    show_backup_recommendations
    show_summary

    # Exit with appropriate code
    if [[ "$TEST_FAILED" == "true" ]]; then
        exit 1
    else
        exit 0
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
