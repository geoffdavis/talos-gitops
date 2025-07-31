#!/bin/bash

# CNPG Barman Plugin Health Check Script
# This script performs comprehensive health checks for the CNPG Barman Plugin system
# and can be run continuously via cron or Kubernetes CronJob

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/var/log/cnpg-health-check.log}"
PROMETHEUS_GATEWAY="${PROMETHEUS_GATEWAY:-http://prometheus-pushgateway.monitoring.svc.cluster.local:9091}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-300}"
ALERT_ON_FAILURES="${ALERT_ON_FAILURES:-true}"

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

# Send metric to Prometheus Pushgateway
send_metric() {
    local metric_name="$1"
    local metric_value="$2"
    local labels="$3"
    
    if [[ -n "$PROMETHEUS_GATEWAY" ]]; then
        cat <<EOF | curl -s --data-binary @- "$PROMETHEUS_GATEWAY/metrics/job/cnpg-health-check/instance/$(hostname)"
# HELP $metric_name CNPG health check metric
# TYPE $metric_name gauge
${metric_name}{${labels}} $metric_value
EOF
    fi
}

# Send alert to Slack
send_alert() {
    local message="$1"
    local severity="${2:-warning}"
    
    if [[ -n "$SLACK_WEBHOOK" && "$ALERT_ON_FAILURES" == "true" ]]; then
        local color="warning"
        [[ "$severity" == "critical" ]] && color="danger"
        
        curl -s -X POST -H 'Content-type: application/json' \
            --data "{\"attachments\":[{\"color\":\"$color\",\"text\":\"$message\"}]}" \
            "$SLACK_WEBHOOK" || true
    fi
}

# Check if cluster exists and is accessible
check_cluster_accessibility() {
    local cluster_name="$1"
    local namespace="$2"
    
    log INFO "Checking accessibility of cluster $cluster_name in namespace $namespace"
    
    if ! kubectl get cluster "$cluster_name" -n "$namespace" &>/dev/null; then
        log ERROR "Cluster $cluster_name not found in namespace $namespace"
        send_metric "cnpg_cluster_accessible" 0 "cluster=\"$cluster_name\",namespace=\"$namespace\""
        return 1
    fi
    
    # Check cluster status
    local status=$(kubectl get cluster "$cluster_name" -n "$namespace" -o jsonpath='{.status.phase}')
    if [[ "$status" != "Cluster in healthy state" ]]; then
        log WARN "Cluster $cluster_name status: $status"
        send_metric "cnpg_cluster_healthy" 0 "cluster=\"$cluster_name\",namespace=\"$namespace\""
        return 1
    fi
    
    log INFO "Cluster $cluster_name is accessible and healthy"
    send_metric "cnpg_cluster_accessible" 1 "cluster=\"$cluster_name\",namespace=\"$namespace\""
    send_metric "cnpg_cluster_healthy" 1 "cluster=\"$cluster_name\",namespace=\"$namespace\""
    return 0
}

# Check ObjectStore connectivity
check_objectstore_connectivity() {
    local objectstore_name="$1"
    local namespace="$2"
    
    log INFO "Checking ObjectStore connectivity: $objectstore_name in namespace $namespace"
    
    if ! kubectl get objectstore "$objectstore_name" -n "$namespace" &>/dev/null; then
        log ERROR "ObjectStore $objectstore_name not found in namespace $namespace"
        send_metric "cnpg_objectstore_accessible" 0 "objectstore=\"$objectstore_name\",namespace=\"$namespace\""
        return 1
    fi
    
    # Test S3 connectivity by attempting to list objects
    local dest_path=$(kubectl get objectstore "$objectstore_name" -n "$namespace" -o jsonpath='{.spec.configuration.destinationPath}')
    local access_key_secret=$(kubectl get objectstore "$objectstore_name" -n "$namespace" -o jsonpath='{.spec.configuration.s3Credentials.accessKeyId.name}')
    local secret_key_secret=$(kubectl get objectstore "$objectstore_name" -n "$namespace" -o jsonpath='{.spec.configuration.s3Credentials.secretAccessKey.name}')
    
    # Create a test pod to check S3 connectivity
    local test_pod_name="objectstore-test-$(date +%s)"
    kubectl run "$test_pod_name" -n "$namespace" --rm -i --restart=Never \
        --image=amazon/aws-cli:latest \
        --env="AWS_ACCESS_KEY_ID=$(kubectl get secret "$access_key_secret" -n "$namespace" -o jsonpath='{.data.username}' | base64 -d)" \
        --env="AWS_SECRET_ACCESS_KEY=$(kubectl get secret "$secret_key_secret" -n "$namespace" -o jsonpath='{.data.password}' | base64 -d)" \
        --command -- aws s3 ls "${dest_path%/*}/" &>/dev/null
    
    local result=$?
    if [[ $result -eq 0 ]]; then
        log INFO "ObjectStore $objectstore_name connectivity test passed"
        send_metric "cnpg_objectstore_accessible" 1 "objectstore=\"$objectstore_name\",namespace=\"$namespace\""
        return 0
    else
        log ERROR "ObjectStore $objectstore_name connectivity test failed"
        send_metric "cnpg_objectstore_accessible" 0 "objectstore=\"$objectstore_name\",namespace=\"$namespace\""
        send_alert "ObjectStore $objectstore_name connectivity test failed" "critical"
        return 1
    fi
}

# Check backup freshness
check_backup_freshness() {
    local cluster_name="$1"
    local namespace="$2"
    local max_age_hours="${3:-24}"
    
    log INFO "Checking backup freshness for cluster $cluster_name (max age: ${max_age_hours}h)"
    
    # Get the last backup timestamp from the cluster status
    local last_backup_time=$(kubectl get cluster "$cluster_name" -n "$namespace" \
        -o jsonpath='{.status.firstRecoverabilityPoint}' 2>/dev/null)
    
    if [[ -z "$last_backup_time" ]]; then
        log WARN "No backup timestamp found for cluster $cluster_name"
        send_metric "cnpg_backup_fresh" 0 "cluster=\"$cluster_name\",namespace=\"$namespace\""
        return 1
    fi
    
    # Convert timestamp to seconds since epoch
    local backup_epoch=$(date -d "$last_backup_time" +%s 2>/dev/null || echo "0")
    local current_epoch=$(date +%s)
    local age_hours=$(( (current_epoch - backup_epoch) / 3600 ))
    
    if [[ $age_hours -gt $max_age_hours ]]; then
        log WARN "Backup for cluster $cluster_name is ${age_hours}h old (max: ${max_age_hours}h)"
        send_metric "cnpg_backup_fresh" 0 "cluster=\"$cluster_name\",namespace=\"$namespace\""
        send_metric "cnpg_backup_age_hours" "$age_hours" "cluster=\"$cluster_name\",namespace=\"$namespace\""
        send_alert "Backup for cluster $cluster_name is ${age_hours} hours old" "warning"
        return 1
    else
        log INFO "Backup for cluster $cluster_name is fresh (${age_hours}h old)"
        send_metric "cnpg_backup_fresh" 1 "cluster=\"$cluster_name\",namespace=\"$namespace\""
        send_metric "cnpg_backup_age_hours" "$age_hours" "cluster=\"$cluster_name\",namespace=\"$namespace\""
        return 0
    fi
}

# Check WAL archiving status
check_wal_archiving() {
    local cluster_name="$1"
    local namespace="$2"
    
    log INFO "Checking WAL archiving status for cluster $cluster_name"
    
    # Get the primary pod
    local primary_pod=$(kubectl get pods -n "$namespace" -l cnpg.io/cluster="$cluster_name",role=primary -o jsonpath='{.items[0].metadata.name}')
    
    if [[ -z "$primary_pod" ]]; then
        log ERROR "No primary pod found for cluster $cluster_name"
        send_metric "cnpg_wal_archiving_healthy" 0 "cluster=\"$cluster_name\",namespace=\"$namespace\""
        return 1
    fi
    
    # Check WAL archiving status
    local wal_status=$(kubectl exec -n "$namespace" "$primary_pod" -c postgres -- \
        psql -t -c "SELECT archived_count FROM pg_stat_archiver;" 2>/dev/null | tr -d ' ')
    
    if [[ -z "$wal_status" || "$wal_status" == "0" ]]; then
        log WARN "WAL archiving may not be working for cluster $cluster_name"
        send_metric "cnpg_wal_archiving_healthy" 0 "cluster=\"$cluster_name\",namespace=\"$namespace\""
        return 1
    else
        log INFO "WAL archiving is active for cluster $cluster_name (archived: $wal_status)"
        send_metric "cnpg_wal_archiving_healthy" 1 "cluster=\"$cluster_name\",namespace=\"$namespace\""
        return 0
    fi
}

# Check plugin health
check_plugin_health() {
    local cluster_name="$1"
    local namespace="$2"
    
    log INFO "Checking Barman plugin health for cluster $cluster_name"
    
    # Check if the plugin is configured
    local plugin_configured=$(kubectl get cluster "$cluster_name" -n "$namespace" \
        -o jsonpath='{.spec.plugins[?(@.name=="barman-cloud.cloudnative-pg.io")].name}')
    
    if [[ -z "$plugin_configured" ]]; then
        log ERROR "Barman plugin not configured for cluster $cluster_name"
        send_metric "cnpg_plugin_configured" 0 "cluster=\"$cluster_name\",namespace=\"$namespace\""
        return 1
    fi
    
    log INFO "Barman plugin is configured for cluster $cluster_name"
    send_metric "cnpg_plugin_configured" 1 "cluster=\"$cluster_name\",namespace=\"$namespace\""
    
    # Check if ObjectStore is referenced correctly
    local objectstore_ref=$(kubectl get cluster "$cluster_name" -n "$namespace" \
        -o jsonpath='{.spec.plugins[?(@.name=="barman-cloud.cloudnative-pg.io")].parameters.objectStoreName}')
    
    if [[ -n "$objectstore_ref" ]] && kubectl get objectstore "$objectstore_ref" -n "$namespace" &>/dev/null; then
        log INFO "ObjectStore reference is valid for cluster $cluster_name"
        send_metric "cnpg_plugin_objectstore_valid" 1 "cluster=\"$cluster_name\",namespace=\"$namespace\""
        return 0
    else
        log ERROR "ObjectStore reference is invalid for cluster $cluster_name"
        send_metric "cnpg_plugin_objectstore_valid" 0 "cluster=\"$cluster_name\",namespace=\"$namespace\""
        return 1
    fi
}

# Perform comprehensive backup test
test_backup_process() {
    local cluster_name="$1"
    local namespace="$2"
    
    log INFO "Testing backup process for cluster $cluster_name"
    
    # Create a test backup
    local backup_name="health-check-backup-$(date +%s)"
    
    cat <<EOF | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: $backup_name
  namespace: $namespace
spec:
  cluster:
    name: $cluster_name
  method: barmanObjectStore
EOF

    # Wait for backup to complete or timeout
    local timeout=$HEALTH_CHECK_TIMEOUT
    local elapsed=0
    local status=""
    
    while [[ $elapsed -lt $timeout ]]; do
        status=$(kubectl get backup "$backup_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        
        case "$status" in
            "completed")
                log INFO "Test backup completed successfully for cluster $cluster_name"
                send_metric "cnpg_backup_test_success" 1 "cluster=\"$cluster_name\",namespace=\"$namespace\""
                kubectl delete backup "$backup_name" -n "$namespace" &>/dev/null || true
                return 0
                ;;
            "failed")
                log ERROR "Test backup failed for cluster $cluster_name"
                send_metric "cnpg_backup_test_success" 0 "cluster=\"$cluster_name\",namespace=\"$namespace\""
                send_alert "Test backup failed for cluster $cluster_name" "critical"
                kubectl delete backup "$backup_name" -n "$namespace" &>/dev/null || true
                return 1
                ;;
            *)
                sleep 10
                elapsed=$((elapsed + 10))
                ;;
        esac
    done
    
    log ERROR "Test backup timed out for cluster $cluster_name"
    send_metric "cnpg_backup_test_success" 0 "cluster=\"$cluster_name\",namespace=\"$namespace\""
    send_alert "Test backup timed out for cluster $cluster_name" "critical"
    kubectl delete backup "$backup_name" -n "$namespace" &>/dev/null || true
    return 1
}

# Main health check function
run_health_checks() {
    log INFO "Starting CNPG Barman Plugin health checks"
    
    local overall_health=1
    local clusters=(
        "homeassistant-postgresql:home-automation"
        "postgresql-cluster:postgresql-system"
    )
    
    for cluster_info in "${clusters[@]}"; do
        IFS=':' read -r cluster_name namespace <<< "$cluster_info"
        
        log INFO "Processing cluster: $cluster_name in namespace: $namespace"
        
        # Run all health checks
        check_cluster_accessibility "$cluster_name" "$namespace" || overall_health=0
        check_plugin_health "$cluster_name" "$namespace" || overall_health=0
        check_backup_freshness "$cluster_name" "$namespace" 24 || overall_health=0
        check_wal_archiving "$cluster_name" "$namespace" || overall_health=0
        
        # Check ObjectStore for this cluster
        local objectstore_name=$(kubectl get cluster "$cluster_name" -n "$namespace" \
            -o jsonpath='{.spec.plugins[?(@.name=="barman-cloud.cloudnative-pg.io")].parameters.objectStoreName}' 2>/dev/null)
        
        if [[ -n "$objectstore_name" ]]; then
            check_objectstore_connectivity "$objectstore_name" "$namespace" || overall_health=0
        fi
        
        # Optional: Run full backup test (can be disabled for frequent checks)
        if [[ "${RUN_BACKUP_TEST:-false}" == "true" ]]; then
            test_backup_process "$cluster_name" "$namespace" || overall_health=0
        fi
        
        echo "---"
    done
    
    # Send overall health metric
    send_metric "cnpg_overall_health" "$overall_health" "instance=\"$(hostname)\""
    
    if [[ $overall_health -eq 1 ]]; then
        log INFO "All CNPG health checks passed"
    else
        log ERROR "Some CNPG health checks failed"
        send_alert "CNPG health check failures detected on $(hostname)" "warning"
    fi
    
    return $((1 - overall_health))
}

# Script execution
main() {
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log INFO "CNPG Barman Plugin Health Check starting on $(hostname)"
    log INFO "Timeout: ${HEALTH_CHECK_TIMEOUT}s, Alerts: $ALERT_ON_FAILURES"
    
    # Run health checks
    if run_health_checks; then
        log INFO "Health check completed successfully"
        exit 0
    else
        log ERROR "Health check completed with failures"
        exit 1
    fi
}

# Handle script termination
cleanup() {
    log INFO "Health check script terminated"
}

trap cleanup EXIT

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi