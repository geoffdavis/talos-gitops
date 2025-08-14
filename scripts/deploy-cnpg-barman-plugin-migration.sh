#!/opt/homebrew/bin/bash

# CloudNativePG Barman Plugin Migration Deployment Script
# Deploys the complete migration following correct order: Plugin → ObjectStores → Clusters
# Provides validation, rollback capability, and comprehensive logging

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
BACKUP_DIR="${PROJECT_ROOT}/migration-backups-$(date +%Y%m%d-%H%M%S)"
DRY_RUN=${DRY_RUN:-false}
SKIP_VALIDATIONS=${SKIP_VALIDATIONS:-false}
TIMEOUT_SECONDS=${TIMEOUT_SECONDS:-600}
LOG_FILE="${PROJECT_ROOT}/cnpg-migration-$(date +%Y%m%d-%H%M%S).log"

# Migration phases
PHASE_PLUGIN="plugin"
PHASE_OBJECTSTORES="objectstores"
PHASE_CLUSTERS="clusters"
PHASE_VALIDATION="validation"
CURRENT_PHASE=""

# Cluster definitions
declare -A CLUSTERS
CLUSTERS["homeassistant-postgresql"]="home-automation"
CLUSTERS["postgresql-cluster"]="postgresql-system"

# Logging functions
log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] [$CURRENT_PHASE] $1"
    echo -e "${GREEN}${msg}${NC}" | tee -a "$LOG_FILE"
}

warn() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] [$CURRENT_PHASE] WARNING: $1"
    echo -e "${YELLOW}${msg}${NC}" | tee -a "$LOG_FILE"
}

error() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] [$CURRENT_PHASE] ERROR: $1"
    echo -e "${RED}${msg}${NC}" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] [$CURRENT_PHASE] $1"
    echo -e "${BLUE}${msg}${NC}" | tee -a "$LOG_FILE"
}

phase() {
    CURRENT_PHASE="$1"
    echo -e "${PURPLE}=== PHASE: ${1^^} ===${NC}" | tee -a "$LOG_FILE"
}

step() {
    echo -e "${CYAN}→ $1${NC}" | tee -a "$LOG_FILE"
}

# Check prerequisites
check_prerequisites() {
    phase "$PHASE_PLUGIN"
    log "Checking deployment prerequisites..."

    # Check required commands
    local required_commands=("kubectl" "flux" "yq" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            error "Required command '$cmd' is not installed or not in PATH"
        fi
    done

    # Check cluster connectivity
    step "Testing cluster connectivity..."
    if ! kubectl get nodes &> /dev/null; then
        error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
    fi

    local node_count
    node_count=$(kubectl get nodes --no-headers | wc -l)
    info "Connected to cluster with $node_count nodes"

    # Check CNPG operator
    step "Verifying CloudNativePG operator..."
    if ! kubectl get crd clusters.postgresql.cnpg.io &> /dev/null; then
        error "CloudNativePG operator CRDs not found. Ensure operator is installed."
    fi

    # Check operator version and status
    local operator_version operator_status
    if kubectl get pods -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg &> /dev/null; then
        operator_version=$(kubectl get pods -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg -o jsonpath='{.items[0].spec.containers[0].image}' | grep -o 'v[0-9.]*' || echo "unknown")
        operator_status=$(kubectl get pods -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg -o jsonpath='{.items[0].status.phase}')
        info "CloudNativePG operator version: $operator_version (status: $operator_status)"

        if [[ "$operator_status" != "Running" ]]; then
            error "CloudNativePG operator is not running"
        fi
    else
        error "CloudNativePG operator pods not found"
    fi

    # Check Flux system
    step "Verifying Flux GitOps system..."
    if ! kubectl get pods -n flux-system &> /dev/null; then
        error "Flux system not found. Ensure Flux is properly installed."
    fi

    local flux_ready
    flux_ready=$(kubectl get pods -n flux-system --field-selector=status.phase=Running | wc -l)
    info "Flux system operational with $flux_ready running pods"

    # Check current cluster status
    step "Checking current cluster status..."
    for cluster in "${!CLUSTERS[@]}"; do
        local namespace="${CLUSTERS[$cluster]}"
        local status

        if kubectl get cluster "$cluster" -n "$namespace" &> /dev/null; then
            status=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            info "Cluster $cluster ($namespace): $status"

            # Check for backup issues (this is why we're migrating)
            local backup_status
            backup_status=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}' 2>/dev/null || echo "Unknown")
            if [[ "$backup_status" == "False" ]]; then
                warn "Cluster $cluster has backup issues - migration is critical!"
                local reason
                reason=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].message}' 2>/dev/null || echo "Unknown")
                info "Issue: $reason"
            fi
        else
            warn "Cluster $cluster not found in namespace $namespace"
        fi
    done

    log "Prerequisites check completed successfully"
}

# Create comprehensive backup
create_backup() {
    phase "BACKUP"
    log "Creating comprehensive backup in: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"

    # Backup cluster configurations
    for cluster in "${!CLUSTERS[@]}"; do
        local namespace="${CLUSTERS[$cluster]}"
        step "Backing up cluster $cluster..."

        # Cluster configuration
        kubectl get cluster "$cluster" -n "$namespace" -o yaml > "$BACKUP_DIR/${cluster}-cluster.yaml" 2>/dev/null || warn "Could not backup cluster $cluster"

        # Backup all related resources
        kubectl get backups -n "$namespace" -o yaml > "$BACKUP_DIR/${namespace}-backups.yaml" 2>/dev/null || true
        kubectl get scheduledbackups -n "$namespace" -o yaml > "$BACKUP_DIR/${namespace}-scheduledbackups.yaml" 2>/dev/null || true
        kubectl get secrets -n "$namespace" -o yaml > "$BACKUP_DIR/${namespace}-secrets.yaml" 2>/dev/null || true
        kubectl get externalsecrets -n "$namespace" -o yaml > "$BACKUP_DIR/${namespace}-externalsecrets.yaml" 2>/dev/null || true
    done

    # Backup current kustomization files
    step "Backing up GitOps configurations..."
    cp -r "${PROJECT_ROOT}/apps/home-automation/postgresql" "$BACKUP_DIR/apps-home-automation-postgresql" 2>/dev/null || true
    cp -r "${PROJECT_ROOT}/infrastructure/postgresql-cluster" "$BACKUP_DIR/infrastructure-postgresql-cluster" 2>/dev/null || true
    cp "${PROJECT_ROOT}/clusters/home-ops/infrastructure/database.yaml" "$BACKUP_DIR/database.yaml" 2>/dev/null || true

    log "Backup completed successfully"
}

# Wait for resource with timeout
wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="$3"
    local condition="${4:-Ready}"
    local timeout="${5:-$TIMEOUT_SECONDS}"

    step "Waiting for $resource_type/$resource_name in $namespace to be $condition..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would wait for $resource_type/$resource_name"
        return 0
    fi

    local elapsed=0
    local interval=10

    while [[ $elapsed -lt $timeout ]]; do
        local status

        case "$resource_type" in
            "cluster")
                status=$(kubectl get cluster "$resource_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
                if [[ "$status" == "Cluster in healthy state" ]] || [[ "$status" == "Running" ]]; then
                    info "✅ Cluster $resource_name is healthy"
                    return 0
                fi
                ;;
            "objectstore")
                if kubectl get objectstore "$resource_name" -n "$namespace" &> /dev/null; then
                    info "✅ ObjectStore $resource_name exists"
                    return 0
                fi
                ;;
            "helmrelease")
                status=$(kubectl get helmrelease "$resource_name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")
                if [[ "$status" == "True" ]]; then
                    info "✅ HelmRelease $resource_name is ready"
                    return 0
                fi
                ;;
            "deployment")
                if kubectl rollout status deployment/"$resource_name" -n "$namespace" --timeout=30s &> /dev/null; then
                    info "✅ Deployment $resource_name is ready"
                    return 0
                fi
                ;;
        esac

        if [[ $((elapsed % 60)) -eq 0 ]]; then
            info "Still waiting... ($elapsed/${timeout}s) - Status: $status"
        fi

        sleep $interval
        elapsed=$((elapsed + interval))
    done

    error "Timeout waiting for $resource_type/$resource_name (${timeout}s)"
}

# Deploy Barman Cloud Plugin
deploy_plugin() {
    phase "$PHASE_PLUGIN"
    log "Deploying Barman Cloud Plugin..."

    # Check if plugin is already deployed
    step "Checking existing plugin deployment..."
    if kubectl get helmrelease cnpg-barman-plugin -n cnpg-system &> /dev/null; then
        local status
        status=$(kubectl get helmrelease cnpg-barman-plugin -n cnpg-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
        if [[ "$status" == "True" ]]; then
            info "Plugin already deployed and ready"
            return 0
        else
            warn "Plugin exists but not ready, will redeploy"
        fi
    fi

    # Deploy plugin via Flux
    step "Deploying plugin via Flux reconciliation..."
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would reconcile infrastructure-sources"
        info "DRY RUN: Would reconcile infrastructure-cnpg-barman-plugin"
        return 0
    fi

    # Reconcile sources first (Helm repositories)
    flux reconcile kustomization infrastructure-sources --timeout=5m

    # Reconcile plugin deployment
    flux reconcile kustomization infrastructure-cnpg-barman-plugin --timeout=10m

    # Wait for plugin to be ready
    wait_for_resource "helmrelease" "cnpg-barman-plugin" "cnpg-system"
    wait_for_resource "deployment" "cnpg-barman-plugin" "cnpg-system"

    # Verify plugin is available
    step "Verifying plugin availability..."
    local plugin_pods
    plugin_pods=$(kubectl get pods -n cnpg-system -l app.kubernetes.io/name=cnpg-barman-plugin --field-selector=status.phase=Running | wc -l)
    if [[ $plugin_pods -gt 0 ]]; then
        info "✅ Plugin deployed successfully with $plugin_pods running pods"
    else
        error "Plugin deployment failed - no running pods found"
    fi

    log "Plugin deployment completed successfully"
}

# Deploy ObjectStore resources
deploy_objectstores() {
    phase "$PHASE_OBJECTSTORES"
    log "Deploying ObjectStore resources..."

    # Deploy infrastructure ObjectStore first
    step "Deploying infrastructure ObjectStore..."
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would reconcile infrastructure-postgresql-cluster"
    else
        flux reconcile kustomization infrastructure-postgresql-cluster --timeout=10m
        wait_for_resource "objectstore" "postgresql-cluster-backup" "postgresql-system"
    fi

    # Deploy Home Assistant ObjectStore
    step "Deploying Home Assistant ObjectStore..."
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would reconcile apps-home-automation"
    else
        flux reconcile kustomization apps-home-automation --timeout=10m
        wait_for_resource "objectstore" "homeassistant-postgresql-backup" "home-automation"
    fi

    # Verify ObjectStores
    step "Verifying ObjectStore resources..."
    for cluster in "${!CLUSTERS[@]}"; do
        local namespace="${CLUSTERS[$cluster]}"
        local objectstore_name

        if [[ "$cluster" == "homeassistant-postgresql" ]]; then
            objectstore_name="homeassistant-postgresql-backup"
        else
            objectstore_name="postgresql-cluster-backup"
        fi

        if kubectl get objectstore "$objectstore_name" -n "$namespace" &> /dev/null; then
            info "✅ ObjectStore $objectstore_name exists in $namespace"
        else
            error "ObjectStore $objectstore_name not found in $namespace"
        fi
    done

    log "ObjectStore deployment completed successfully"
}

# Deploy plugin-based cluster configurations
deploy_clusters() {
    phase "$PHASE_CLUSTERS"
    log "Deploying plugin-based cluster configurations..."

    # Deploy Home Assistant cluster first (it has the failing backups)
    step "Deploying Home Assistant cluster with plugin configuration..."
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would reconcile apps-home-automation cluster"
    else
        flux reconcile kustomization apps-home-automation --timeout=15m
        wait_for_resource "cluster" "homeassistant-postgresql" "home-automation"
    fi

    # Deploy infrastructure cluster
    step "Deploying infrastructure cluster with plugin configuration..."
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would reconcile infrastructure-postgresql-cluster"
    else
        flux reconcile kustomization infrastructure-postgresql-cluster --timeout=15m
        wait_for_resource "cluster" "postgresql-cluster" "postgresql-system"
    fi

    # Allow time for clusters to stabilize
    if [[ "$DRY_RUN" != "true" ]]; then
        step "Allowing clusters to stabilize..."
        sleep 30
    fi

    log "Cluster deployment completed successfully"
}

# Validate migration success
validate_migration() {
    phase "$PHASE_VALIDATION"
    log "Validating migration success..."

    if [[ "$SKIP_VALIDATIONS" == "true" ]]; then
        warn "Skipping validations as requested"
        return 0
    fi

    local validation_failed=false

    for cluster in "${!CLUSTERS[@]}"; do
        local namespace="${CLUSTERS[$cluster]}"
        step "Validating cluster: $cluster"

        # Check cluster status
        local status
        status=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
        info "Cluster Status: $status"

        if [[ "$status" != "Cluster in healthy state" ]] && [[ "$status" != "Running" ]]; then
            warn "Cluster $cluster is not in healthy state: $status"
            validation_failed=true
        fi

        # Check plugin configuration
        local plugins
        plugins=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.spec.plugins[*].name}' 2>/dev/null || echo "None")
        info "Configured Plugins: $plugins"

        if [[ "$plugins" != *"barman-cloud.cloudnative-pg.io"* ]]; then
            warn "Cluster $cluster does not have barman-cloud plugin configured"
            validation_failed=true
        fi

        # Check that barmanObjectStore is removed
        local has_barman_config
        has_barman_config=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.spec.backup.barmanObjectStore}' 2>/dev/null || echo "")
        if [[ -n "$has_barman_config" ]]; then
            warn "Cluster $cluster still has deprecated barmanObjectStore configuration"
            validation_failed=true
        else
            info "✅ Deprecated barmanObjectStore configuration removed"
        fi

        # Check continuous archiving status
        local archiving_status archiving_message
        archiving_status=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}' 2>/dev/null || echo "Unknown")
        archiving_message=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].message}' 2>/dev/null || echo "No message")

        info "Continuous Archiving: $archiving_status"
        if [[ "$archiving_status" == "False" ]]; then
            warn "Continuous archiving issues: $archiving_message"
            validation_failed=true
        elif [[ "$archiving_status" == "True" ]]; then
            info "✅ Continuous archiving operational"
        fi

        # Check ObjectStore exists
        local objectstore_name
        if [[ "$cluster" == "homeassistant-postgresql" ]]; then
            objectstore_name="homeassistant-postgresql-backup"
        else
            objectstore_name="postgresql-cluster-backup"
        fi

        if kubectl get objectstore "$objectstore_name" -n "$namespace" &> /dev/null; then
            info "✅ ObjectStore $objectstore_name exists"
        else
            warn "ObjectStore $objectstore_name not found"
            validation_failed=true
        fi
    done

    if [[ "$validation_failed" == "true" ]]; then
        warn "Some validation checks failed - review the issues above"
        return 1
    else
        log "✅ All validation checks passed!"
        return 0
    fi
}

# Test backup functionality
test_backup_functionality() {
    phase "BACKUP_TEST"
    log "Testing backup functionality..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would create test backup"
        return 0
    fi

    # Create test backup for Home Assistant cluster
    local test_backup_name="homeassistant-postgresql-migration-test-$(date +%Y%m%d-%H%M%S)"

    step "Creating test backup: $test_backup_name"

    cat <<EOF | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: $test_backup_name
  namespace: home-automation
  labels:
    app.kubernetes.io/name: homeassistant-postgresql
    backup-purpose: migration-test
spec:
  cluster:
    name: homeassistant-postgresql
  method: plugin
EOF

    # Monitor backup progress
    step "Monitoring backup progress..."
    local timeout=600  # 10 minutes
    local elapsed=0
    local interval=15

    while [[ $elapsed -lt $timeout ]]; do
        local backup_status
        backup_status=$(kubectl get backup "$test_backup_name" -n home-automation -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

        case "$backup_status" in
            "completed")
                info "✅ Test backup completed successfully!"

                # Show backup details
                local backup_info
                backup_info=$(kubectl get backup "$test_backup_name" -n home-automation -o jsonpath='{.status.startedAt},{.status.stoppedAt},{.status.beginWal},{.status.endWal}' 2>/dev/null || echo "")
                info "Backup details: $backup_info"

                return 0
                ;;
            "failed")
                error "❌ Test backup failed!"
                kubectl describe backup "$test_backup_name" -n home-automation || true
                return 1
                ;;
            "running")
                info "Backup in progress... ($elapsed/${timeout}s)"
                ;;
            *)
                info "Backup status: $backup_status ($elapsed/${timeout}s)"
                ;;
        esac

        sleep $interval
        elapsed=$((elapsed + interval))
    done

    warn "Test backup timed out after ${timeout}s"
    return 1
}

# Rollback migration if needed
rollback_migration() {
    phase "ROLLBACK"
    warn "Initiating migration rollback..."

    if [[ ! -d "$BACKUP_DIR" ]]; then
        error "Backup directory not found: $BACKUP_DIR"
    fi

    # Restore cluster configurations
    for cluster in "${!CLUSTERS[@]}"; do
        local namespace="${CLUSTERS[$cluster]}"
        step "Rolling back cluster $cluster..."

        if [[ -f "$BACKUP_DIR/${cluster}-cluster.yaml" ]]; then
            kubectl apply -f "$BACKUP_DIR/${cluster}-cluster.yaml"
            wait_for_resource "cluster" "$cluster" "$namespace"
        else
            warn "No backup found for cluster $cluster"
        fi
    done

    # Wait for clusters to stabilize
    sleep 60

    log "Rollback completed - please verify cluster status"
}

# Cleanup obsolete files
cleanup_obsolete_files() {
    phase "CLEANUP"
    log "Cleaning up obsolete files..."

    local cleanup_files=(
        # These are the old barmanObjectStore method files that are now obsolete
        # Note: we keep them for now until migration is fully validated
    )

    # For now, just log what would be cleaned up
    info "Files that can be cleaned up after successful migration:"
    info "- apps/home-automation/postgresql/cluster.yaml (old barmanObjectStore method)"
    info "- infrastructure/postgresql-cluster/cluster.yaml (old barmanObjectStore method)"
    info "- Any old backup configurations using barmanObjectStore method"

    log "Manual cleanup recommended after migration validation"
}

# Show migration status
show_status() {
    phase "STATUS"
    log "Current migration status:"

    # Plugin status
    step "Plugin Status:"
    if kubectl get helmrelease cnpg-barman-plugin -n cnpg-system &> /dev/null; then
        local plugin_status
        plugin_status=$(kubectl get helmrelease cnpg-barman-plugin -n cnpg-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
        info "Barman Plugin: $plugin_status"
    else
        info "Barman Plugin: Not Deployed"
    fi

    # ObjectStore status
    step "ObjectStore Status:"
    kubectl get objectstores -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,AGE:.metadata.creationTimestamp" 2>/dev/null || info "No ObjectStores found"

    # Cluster status
    step "Cluster Status:"
    for cluster in "${!CLUSTERS[@]}"; do
        local namespace="${CLUSTERS[$cluster]}"
        if kubectl get cluster "$cluster" -n "$namespace" &> /dev/null; then
            local status archiving_status
            status=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.phase}')
            archiving_status=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}' 2>/dev/null || echo "Unknown")
            info "$cluster ($namespace): $status, Archiving: $archiving_status"
        else
            info "$cluster ($namespace): Not Found"
        fi
    done
}

# Show help
show_help() {
    cat <<EOF
CloudNativePG Barman Plugin Migration Deployment Script

This script automates the complete migration from deprecated barmanObjectStore
to the new Barman Cloud Plugin architecture following the correct deployment order:
Plugin → ObjectStores → Clusters

USAGE:
    $0 [OPTIONS] [COMMAND]

COMMANDS:
    deploy      Full migration deployment (default)
    status      Show current migration status
    validate    Validate migration state
    test        Test backup functionality
    rollback    Rollback migration (requires backup)
    help        Show this help message

OPTIONS:
    --dry-run              Perform a dry run without making changes
    --skip-validations     Skip validation steps
    --timeout SECONDS      Set timeout for waiting operations (default: 600)

ENVIRONMENT VARIABLES:
    DRY_RUN=true           Perform a dry run
    SKIP_VALIDATIONS=true  Skip validation steps
    TIMEOUT_SECONDS=N      Set timeout in seconds

EXAMPLES:
    # Full deployment with dry run
    $0 --dry-run deploy

    # Deploy with custom timeout
    $0 --timeout 900 deploy

    # Just show status
    $0 status

    # Validate existing migration
    $0 validate

    # Test backup functionality
    $0 test

    # Rollback if needed
    $0 rollback

DEPLOYMENT ORDER:
    1. Prerequisites Check
    2. Backup Current State
    3. Deploy Barman Cloud Plugin
    4. Deploy ObjectStore Resources
    5. Deploy Plugin-based Clusters
    6. Validate Migration
    7. Test Backup Functionality

EOF
}

# Main execution
main() {
    local command="deploy"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-validations)
                SKIP_VALIDATIONS=true
                shift
                ;;
            --timeout)
                TIMEOUT_SECONDS="$2"
                shift 2
                ;;
            deploy|status|validate|test|rollback|help)
                command="$1"
                shift
                ;;
            *)
                error "Unknown option: $1. Use 'help' for usage information."
                ;;
        esac
    done

    # Initialize logging
    echo "CloudNativePG Barman Plugin Migration Deployment" | tee "$LOG_FILE"
    echo "Started at: $(date)" | tee -a "$LOG_FILE"
    echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN MODE - No changes will be made"
    fi

    # Execute command
    case "$command" in
        "deploy")
            check_prerequisites
            create_backup
            deploy_plugin
            deploy_objectstores
            deploy_clusters
            validate_migration
            test_backup_functionality
            cleanup_obsolete_files

            log "🎉 Migration deployed successfully!"
            log "Log file: $LOG_FILE"
            log "Backup directory: $BACKUP_DIR"
            ;;
        "status")
            show_status
            ;;
        "validate")
            CURRENT_PHASE="VALIDATE"
            validate_migration
            ;;
        "test")
            CURRENT_PHASE="TEST"
            test_backup_functionality
            ;;
        "rollback")
            rollback_migration
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
}

# Execute main function with all arguments
main "$@"
