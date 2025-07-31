#!/bin/bash

# CNPG Barman Plugin Backup Restoration Testing Script
# This script performs automated backup restoration tests to verify backup integrity
# and restoration procedures for the CNPG Barman Plugin system

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/var/log/cnpg-restore-test.log}"
TEST_NAMESPACE="${TEST_NAMESPACE:-cnpg-restore-test}"
RESTORE_TIMEOUT="${RESTORE_TIMEOUT:-1800}"  # 30 minutes
CLEANUP_ON_SUCCESS="${CLEANUP_ON_SUCCESS:-true}"
PRESERVE_TEST_DATA="${PRESERVE_TEST_DATA:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)  echo -e "${GREEN}[INFO]${NC} ${timestamp}: $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} ${timestamp}: $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} ${timestamp}: $message" | tee -a "$LOG_FILE" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} ${timestamp}: $message" | tee -a "$LOG_FILE" ;;
    esac
}

# Create test namespace
create_test_namespace() {
    log INFO "Creating test namespace: $TEST_NAMESPACE"
    
    kubectl create namespace "$TEST_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Label namespace for monitoring
    kubectl label namespace "$TEST_NAMESPACE" \
        backup-test=true \
        cnpg-monitoring=enabled \
        --overwrite
}

# Cleanup test resources
cleanup_test_resources() {
    local preserve_data="$1"
    
    if [[ "$preserve_data" == "true" ]]; then
        log INFO "Preserving test data as requested"
        return 0
    fi
    
    log INFO "Cleaning up test resources in namespace $TEST_NAMESPACE"
    
    # Delete all CNPG clusters in test namespace
    kubectl delete clusters --all -n "$TEST_NAMESPACE" --timeout=300s || true
    
    # Delete all backups in test namespace
    kubectl delete backups --all -n "$TEST_NAMESPACE" --timeout=60s || true
    
    # Delete persistent volumes if they exist
    kubectl delete pvc --all -n "$TEST_NAMESPACE" --timeout=60s || true
    
    # Optionally delete the entire namespace
    if [[ "$CLEANUP_ON_SUCCESS" == "true" ]]; then
        kubectl delete namespace "$TEST_NAMESPACE" --timeout=120s || true
    fi
}

# Get available backups for a cluster
get_available_backups() {
    local source_cluster="$1"
    local source_namespace="$2"
    
    log INFO "Getting available backups for cluster $source_cluster in namespace $source_namespace"
    
    # Get ObjectStore name from the source cluster
    local objectstore_name=$(kubectl get cluster "$source_cluster" -n "$source_namespace" \
        -o jsonpath='{.spec.plugins[?(@.name=="barman-cloud.cloudnative-pg.io")].parameters.objectStoreName}')
    
    if [[ -z "$objectstore_name" ]]; then
        log ERROR "No ObjectStore found for cluster $source_cluster"
        return 1
    fi
    
    # Get the destination path from ObjectStore
    local dest_path=$(kubectl get objectstore "$objectstore_name" -n "$source_namespace" \
        -o jsonpath='{.spec.configuration.destinationPath}')
    
    log INFO "ObjectStore: $objectstore_name, Destination: $dest_path"
    
    # List available backups using barman-cloud-backup-list
    local credentials_secret=$(kubectl get objectstore "$objectstore_name" -n "$source_namespace" \
        -o jsonpath='{.spec.configuration.s3Credentials.accessKeyId.name}')
    
    local secret_key_secret=$(kubectl get objectstore "$objectstore_name" -n "$source_namespace" \
        -o jsonpath='{.spec.configuration.s3Credentials.secretAccessKey.name}')
    
    # Create a temporary pod to list backups
    local list_pod_name="backup-list-$(date +%s)"
    
    local backup_list=$(kubectl run "$list_pod_name" -n "$source_namespace" --rm -i --restart=Never \
        --image=ghcr.io/cloudnative-pg/barman-cloud:1.26.1 \
        --env="AWS_ACCESS_KEY_ID=$(kubectl get secret "$credentials_secret" -n "$source_namespace" -o jsonpath='{.data.username}' | base64 -d)" \
        --env="AWS_SECRET_ACCESS_KEY=$(kubectl get secret "$secret_key_secret" -n "$source_namespace" -o jsonpath='{.data.password}' | base64 -d)" \
        --command -- barman-cloud-backup-list "$dest_path" 2>/dev/null | tail -n +2 || echo "")
    
    if [[ -z "$backup_list" ]]; then
        log ERROR "No backups found for cluster $source_cluster"
        return 1
    fi
    
    log INFO "Available backups for $source_cluster:"
    echo "$backup_list" | while read -r backup_info; do
        log INFO "  $backup_info"
    done
    
    # Return the most recent backup ID
    echo "$backup_list" | tail -1 | awk '{print $1}'
}

# Create test data in source cluster
create_test_data() {
    local cluster_name="$1"
    local namespace="$2"
    local test_data_id="$3"
    
    log INFO "Creating test data in cluster $cluster_name"
    
    # Get primary pod
    local primary_pod=$(kubectl get pods -n "$namespace" \
        -l cnpg.io/cluster="$cluster_name",role=primary \
        -o jsonpath='{.items[0].metadata.name}')
    
    if [[ -z "$primary_pod" ]]; then
        log ERROR "No primary pod found for cluster $cluster_name"
        return 1
    fi
    
    # Create test table and insert data
    kubectl exec -n "$namespace" "$primary_pod" -c postgres -- \
        psql -c "
        CREATE TABLE IF NOT EXISTS backup_test_$test_data_id (
            id SERIAL PRIMARY KEY,
            created_at TIMESTAMP DEFAULT NOW(),
            test_data TEXT,
            backup_test_id TEXT
        );
        
        INSERT INTO backup_test_$test_data_id (test_data, backup_test_id) 
        VALUES 
            ('Test data before backup', '$test_data_id'),
            ('Another test record', '$test_data_id'),
            ('Backup verification data', '$test_data_id');
        
        SELECT COUNT(*) as inserted_records FROM backup_test_$test_data_id WHERE backup_test_id = '$test_data_id';
        "
    
    log INFO "Test data created successfully in cluster $cluster_name"
}

# Verify test data in restored cluster
verify_test_data() {
    local cluster_name="$1"
    local namespace="$2"
    local test_data_id="$3"
    
    log INFO "Verifying test data in restored cluster $cluster_name"
    
    # Wait for cluster to be ready
    local timeout=300
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        local status=$(kubectl get cluster "$cluster_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [[ "$status" == "Cluster in healthy state" ]]; then
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    if [[ $elapsed -ge $timeout ]]; then
        log ERROR "Timeout waiting for restored cluster to be ready"
        return 1
    fi
    
    # Get primary pod from restored cluster
    local primary_pod=$(kubectl get pods -n "$namespace" \
        -l cnpg.io/cluster="$cluster_name",role=primary \
        -o jsonpath='{.items[0].metadata.name}')
    
    if [[ -z "$primary_pod" ]]; then
        log ERROR "No primary pod found for restored cluster $cluster_name"
        return 1
    fi
    
    # Verify test data exists
    local record_count=$(kubectl exec -n "$namespace" "$primary_pod" -c postgres -- \
        psql -t -c "SELECT COUNT(*) FROM backup_test_$test_data_id WHERE backup_test_id = '$test_data_id';" 2>/dev/null | tr -d ' ' || echo "0")
    
    if [[ "$record_count" -ge "3" ]]; then
        log INFO "Test data verification successful: $record_count records found"
        
        # Show sample data
        kubectl exec -n "$namespace" "$primary_pod" -c postgres -- \
            psql -c "SELECT * FROM backup_test_$test_data_id WHERE backup_test_id = '$test_data_id' LIMIT 3;"
        
        return 0
    else
        log ERROR "Test data verification failed: expected 3+ records, found $record_count"
        return 1
    fi
}

# Perform Point-in-Time Recovery test
test_pitr_recovery() {
    local source_cluster="$1"
    local source_namespace="$2"
    local recovery_time="$3"
    
    log INFO "Testing Point-in-Time Recovery for cluster $source_cluster to time $recovery_time"
    
    local test_cluster_name="pitr-test-$(date +%s)"
    local objectstore_name=$(kubectl get cluster "$source_cluster" -n "$source_namespace" \
        -o jsonpath='{.spec.plugins[?(@.name=="barman-cloud.cloudnative-pg.io")].parameters.objectStoreName}')
    
    # Copy ObjectStore configuration to test namespace
    kubectl get objectstore "$objectstore_name" -n "$source_namespace" -o yaml | \
        sed "s/namespace: $source_namespace/namespace: $TEST_NAMESPACE/" | \
        kubectl apply -f -
    
    # Create PITR cluster
    cat <<EOF | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: $test_cluster_name
  namespace: $TEST_NAMESPACE
  labels:
    backup-test: "pitr"
    test-cluster: "true"
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:16.4
  
  plugins:
    - name: "barman-cloud.cloudnative-pg.io"
      isWALArchiver: true
      parameters:
        objectStoreName: "$objectstore_name"
  
  bootstrap:
    recovery:
      source: $source_cluster
      recoveryTarget:
        targetTime: "$recovery_time"
      objectStore:
        objectStoreName: "$objectstore_name"
        serverName: "$source_cluster"
  
  storage:
    size: 5Gi
    storageClass: longhorn-ssd
  
  resources:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "500m"
      
  superuserSecret:
    name: "${source_cluster}-superuser"
EOF

    # Wait for PITR recovery to complete
    log INFO "Waiting for PITR recovery to complete (timeout: ${RESTORE_TIMEOUT}s)"
    
    local timeout=$RESTORE_TIMEOUT
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        local status=$(kubectl get cluster "$test_cluster_name" -n "$TEST_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        
        case "$status" in
            "Cluster in healthy state")
                log INFO "PITR recovery completed successfully"
                return 0
                ;;
            "Setting up primary")
                log DEBUG "PITR recovery in progress..."
                ;;
            "Failed")
                log ERROR "PITR recovery failed"
                kubectl describe cluster "$test_cluster_name" -n "$TEST_NAMESPACE" | tail -20
                return 1
                ;;
            *)
                log DEBUG "PITR recovery status: $status"
                ;;
        esac
        
        sleep 30
        elapsed=$((elapsed + 30))
    done
    
    log ERROR "PITR recovery timed out"
    return 1
}

# Test full backup restoration
test_backup_restoration() {
    local source_cluster="$1"
    local source_namespace="$2"
    local backup_id="$3"
    
    log INFO "Testing backup restoration for cluster $source_cluster, backup $backup_id"
    
    local test_cluster_name="restore-test-$(date +%s)"
    local objectstore_name=$(kubectl get cluster "$source_cluster" -n "$source_namespace" \
        -o jsonpath='{.spec.plugins[?(@.name=="barman-cloud.cloudnative-pg.io")].parameters.objectStoreName}')
    
    # Copy ObjectStore configuration to test namespace
    kubectl get objectstore "$objectstore_name" -n "$source_namespace" -o yaml | \
        sed "s/namespace: $source_namespace/namespace: $TEST_NAMESPACE/" | \
        kubectl apply -f -
    
    # Copy superuser secret to test namespace
    kubectl get secret "${source_cluster}-superuser" -n "$source_namespace" -o yaml | \
        sed "s/namespace: $source_namespace/namespace: $TEST_NAMESPACE/" | \
        kubectl apply -f -
    
    # Create restored cluster
    cat <<EOF | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: $test_cluster_name
  namespace: $TEST_NAMESPACE
  labels:
    backup-test: "restore"
    test-cluster: "true"
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:16.4
  
  plugins:
    - name: "barman-cloud.cloudnative-pg.io"
      isWALArchiver: true
      parameters:
        objectStoreName: "$objectstore_name"
  
  bootstrap:
    recovery:
      source: $source_cluster
      recoveryTarget:
        backupID: "$backup_id"
      objectStore:
        objectStoreName: "$objectstore_name"
        serverName: "$source_cluster"
  
  storage:
    size: 5Gi
    storageClass: longhorn-ssd
  
  resources:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "500m"
      
  superuserSecret:
    name: "${source_cluster}-superuser"
EOF

    # Wait for restoration to complete
    log INFO "Waiting for backup restoration to complete (timeout: ${RESTORE_TIMEOUT}s)"
    
    local timeout=$RESTORE_TIMEOUT
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        local status=$(kubectl get cluster "$test_cluster_name" -n "$TEST_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        
        case "$status" in
            "Cluster in healthy state")
                log INFO "Backup restoration completed successfully"
                echo "$test_cluster_name"  # Return cluster name for verification
                return 0
                ;;
            "Setting up primary")
                log DEBUG "Backup restoration in progress..."
                ;;
            "Failed")
                log ERROR "Backup restoration failed"
                kubectl describe cluster "$test_cluster_name" -n "$TEST_NAMESPACE" | tail -20
                return 1
                ;;
            *)
                log DEBUG "Backup restoration status: $status"
                ;;
        esac
        
        sleep 30
        elapsed=$((elapsed + 30))
    done
    
    log ERROR "Backup restoration timed out"
    return 1
}

# Generate comprehensive test report
generate_test_report() {
    local test_results="$1"
    local report_file="${LOG_FILE%.log}-report-$(date +%Y%m%d-%H%M%S).json"
    
    log INFO "Generating test report: $report_file"
    
    cat > "$report_file" <<EOF
{
  "test_run": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "hostname": "$(hostname)",
    "test_namespace": "$TEST_NAMESPACE",
    "timeout_seconds": $RESTORE_TIMEOUT
  },
  "results": $test_results,
  "summary": {
    "total_tests": $(echo "$test_results" | jq length),
    "passed": $(echo "$test_results" | jq '[.[] | select(.status == "PASSED")] | length'),
    "failed": $(echo "$test_results" | jq '[.[] | select(.status == "FAILED")] | length')
  }
}
EOF

    log INFO "Test report generated: $report_file"
    
    # Display summary
    local total=$(echo "$test_results" | jq length)
    local passed=$(echo "$test_results" | jq '[.[] | select(.status == "PASSED")] | length')
    local failed=$(echo "$test_results" | jq '[.[] | select(.status == "FAILED")] | length')
    
    log INFO "Test Summary - Total: $total, Passed: $passed, Failed: $failed"
    
    return $failed
}

# Main testing function
run_restoration_tests() {
    log INFO "Starting CNPG backup restoration tests"
    
    local test_results="[]"
    local overall_result=0
    
    # Create test namespace
    create_test_namespace
    
    # Test clusters to verify
    local clusters=(
        "homeassistant-postgresql:home-automation"
        "postgresql-cluster:postgresql-system"
    )
    
    for cluster_info in "${clusters[@]}"; do
        IFS=':' read -r cluster_name namespace <<< "$cluster_info"
        
        log INFO "Testing restoration for cluster: $cluster_name in namespace: $namespace"
        
        # Generate unique test data ID
        local test_data_id="test-$(date +%s)-$$"
        
        # Create test data in source cluster
        if create_test_data "$cluster_name" "$namespace" "$test_data_id"; then
            log INFO "Test data created successfully"
        else
            log WARN "Failed to create test data, continuing with existing backups"
        fi
        
        # Get available backups
        local latest_backup
        if latest_backup=$(get_available_backups "$cluster_name" "$namespace"); then
            log INFO "Latest backup found: $latest_backup"
            
            # Test backup restoration
            local restored_cluster
            if restored_cluster=$(test_backup_restoration "$cluster_name" "$namespace" "$latest_backup"); then
                log INFO "Backup restoration test passed"
                
                # Verify data integrity
                if verify_test_data "$restored_cluster" "$TEST_NAMESPACE" "$test_data_id"; then
                    log INFO "Data integrity verification passed"
                    
                    test_results=$(echo "$test_results" | jq --arg cluster "$cluster_name" --arg test "backup_restore" \
                        '. += [{"cluster": $cluster, "test": $test, "status": "PASSED", "details": "Backup restoration and data verification successful"}]')
                else
                    log ERROR "Data integrity verification failed"
                    test_results=$(echo "$test_results" | jq --arg cluster "$cluster_name" --arg test "backup_restore" \
                        '. += [{"cluster": $cluster, "test": $test, "status": "FAILED", "details": "Data integrity verification failed"}]')
                    overall_result=1
                fi
            else
                log ERROR "Backup restoration test failed"
                test_results=$(echo "$test_results" | jq --arg cluster "$cluster_name" --arg test "backup_restore" \
                    '. += [{"cluster": $cluster, "test": $test, "status": "FAILED", "details": "Backup restoration failed"}]')
                overall_result=1
            fi
            
            # Test PITR (optional, if enabled)
            if [[ "${TEST_PITR:-false}" == "true" ]]; then
                local recovery_time=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)
                
                if test_pitr_recovery "$cluster_name" "$namespace" "$recovery_time"; then
                    log INFO "PITR test passed"
                    test_results=$(echo "$test_results" | jq --arg cluster "$cluster_name" --arg test "pitr" \
                        '. += [{"cluster": $cluster, "test": $test, "status": "PASSED", "details": "PITR recovery successful"}]')
                else
                    log ERROR "PITR test failed"
                    test_results=$(echo "$test_results" | jq --arg cluster "$cluster_name" --arg test "pitr" \
                        '. += [{"cluster": $cluster, "test": $test, "status": "FAILED", "details": "PITR recovery failed"}]')
                    overall_result=1
                fi
            fi
            
        else
            log ERROR "No backups available for cluster $cluster_name"
            test_results=$(echo "$test_results" | jq --arg cluster "$cluster_name" --arg test "backup_availability" \
                '. += [{"cluster": $cluster, "test": $test, "status": "FAILED", "details": "No backups available"}]')
            overall_result=1
        fi
        
        echo "---"
    done
    
    # Generate test report
    generate_test_report "$test_results"
    local report_result=$?
    
    # Cleanup
    cleanup_test_resources "$PRESERVE_TEST_DATA"
    
    if [[ $overall_result -eq 0 && $report_result -eq 0 ]]; then
        log INFO "All restoration tests completed successfully"
        return 0
    else
        log ERROR "Some restoration tests failed"
        return 1
    fi
}

# Main execution
main() {
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log INFO "CNPG Backup Restoration Testing starting on $(hostname)"
    log INFO "Test namespace: $TEST_NAMESPACE, Timeout: ${RESTORE_TIMEOUT}s"
    log INFO "Cleanup on success: $CLEANUP_ON_SUCCESS, Preserve test data: $PRESERVE_TEST_DATA"
    
    # Check prerequisites
    if ! command -v kubectl &> /dev/null; then
        log ERROR "kubectl not found"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log ERROR "jq not found"
        exit 1
    fi
    
    # Run restoration tests
    if run_restoration_tests; then
        log INFO "Restoration testing completed successfully"
        exit 0
    else
        log ERROR "Restoration testing completed with failures"
        exit 1
    fi
}

# Handle script termination
cleanup() {
    log INFO "Restoration test script terminated"
    if [[ "${PRESERVE_TEST_DATA:-false}" != "true" ]]; then
        cleanup_test_resources false
    fi
}

trap cleanup EXIT

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi