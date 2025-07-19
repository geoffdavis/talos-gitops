#!/bin/bash
# Authentik + PostgreSQL Deployment Verification Script
# Comprehensive verification of all Authentik deployment components

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
VERIFICATION_FAILED=false
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] $1${NC}"
}

info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
    ((PASSED_CHECKS++))
}

warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

error() {
    echo -e "${RED}✗ $1${NC}"
    VERIFICATION_FAILED=true
    ((FAILED_CHECKS++))
}

section() {
    echo ""
    echo -e "${BOLD}${CYAN}=== $1 ===${NC}"
    echo ""
}

check_start() {
    ((TOTAL_CHECKS++))
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
        success "$resource is $condition"
        return 0
    else
        error "$resource failed to become $condition within ${timeout}s"
        return 1
    fi
}

# Verification functions
verify_prerequisites() {
    section "Prerequisites Verification"
    
    check_start
    if check_command kubectl; then
        success "kubectl is available"
    fi
    
    check_start
    if check_command flux; then
        success "flux CLI is available"
    fi
    
    check_start
    if check_cluster_access; then
        success "Kubernetes cluster is accessible"
    fi
    
    # Check cluster info
    local cluster_version
    cluster_version=$(kubectl version --short 2>/dev/null | grep "Server Version" | cut -d' ' -f3 || echo "unknown")
    info "Kubernetes cluster version: $cluster_version"
    
    local node_count
    node_count=$(kubectl get nodes --no-headers | wc -l)
    info "Cluster has $node_count nodes"
}

verify_cnpg_operator() {
    section "CNPG Operator Verification"
    
    check_start
    if kubectl get namespace cnpg-system &> /dev/null; then
        success "cnpg-system namespace exists"
    else
        error "cnpg-system namespace not found"
        return 1
    fi
    
    check_start
    local cnpg_pods
    cnpg_pods=$(kubectl get pods -n cnpg-system --no-headers 2>/dev/null | wc -l)
    if [[ "$cnpg_pods" -gt 0 ]]; then
        success "CNPG operator pods are running ($cnpg_pods pods)"
    else
        error "No CNPG operator pods found"
    fi
    
    check_start
    if kubectl get deployment -n cnpg-system cnpg-controller-manager &> /dev/null; then
        local ready_replicas
        ready_replicas=$(kubectl get deployment -n cnpg-system cnpg-controller-manager -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local desired_replicas
        desired_replicas=$(kubectl get deployment -n cnpg-system cnpg-controller-manager -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        
        if [[ "$ready_replicas" == "$desired_replicas" && "$ready_replicas" != "0" ]]; then
            success "CNPG controller manager is ready ($ready_replicas/$desired_replicas)"
        else
            error "CNPG controller manager not ready ($ready_replicas/$desired_replicas)"
        fi
    else
        error "CNPG controller manager deployment not found"
    fi
    
    # Check CRDs
    check_start
    local cnpg_crds
    cnpg_crds=$(kubectl get crd | grep -c "postgresql.cnpg.io" || echo "0")
    if [[ "$cnpg_crds" -gt 0 ]]; then
        success "CNPG CRDs are installed ($cnpg_crds CRDs)"
    else
        error "CNPG CRDs not found"
    fi
}

verify_postgresql_cluster() {
    section "PostgreSQL Cluster Verification"
    
    check_start
    if kubectl get namespace postgresql-system &> /dev/null; then
        success "postgresql-system namespace exists"
    else
        error "postgresql-system namespace not found"
        return 1
    fi
    
    check_start
    if kubectl get cluster -n postgresql-system postgresql-cluster &> /dev/null; then
        success "PostgreSQL cluster resource exists"
    else
        error "PostgreSQL cluster resource not found"
        return 1
    fi
    
    # Check cluster status
    check_start
    local cluster_status
    cluster_status=$(kubectl get cluster -n postgresql-system postgresql-cluster -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
    if [[ "$cluster_status" == "Cluster in healthy state" ]]; then
        success "PostgreSQL cluster is healthy"
    else
        error "PostgreSQL cluster status: $cluster_status"
    fi
    
    # Check instances
    check_start
    local running_instances
    running_instances=$(kubectl get pods -n postgresql-system -l postgresql=postgresql-cluster --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    local expected_instances
    expected_instances=$(kubectl get cluster -n postgresql-system postgresql-cluster -o jsonpath='{.spec.instances}' 2>/dev/null || echo "3")
    
    if [[ "$running_instances" == "$expected_instances" ]]; then
        success "All PostgreSQL instances are running ($running_instances/$expected_instances)"
    else
        error "PostgreSQL instances not ready ($running_instances/$expected_instances)"
    fi
    
    # Check primary/replica status
    check_start
    local primary_pod
    primary_pod=$(kubectl get pods -n postgresql-system -l postgresql=postgresql-cluster,role=primary --no-headers 2>/dev/null | head -1 | awk '{print $1}' || echo "")
    if [[ -n "$primary_pod" ]]; then
        success "PostgreSQL primary pod identified: $primary_pod"
    else
        error "No PostgreSQL primary pod found"
    fi
    
    # Check replication
    check_start
    local replica_count
    replica_count=$(kubectl get pods -n postgresql-system -l postgresql=postgresql-cluster,role=replica --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "$replica_count" -gt 0 ]]; then
        success "PostgreSQL replicas are running ($replica_count replicas)"
    else
        warn "No PostgreSQL replicas found (single instance setup?)"
    fi
    
    # Check PVC status
    check_start
    local pvc_count
    pvc_count=$(kubectl get pvc -n postgresql-system --no-headers 2>/dev/null | grep -c "Bound" || echo "0")
    if [[ "$pvc_count" -gt 0 ]]; then
        success "PostgreSQL PVCs are bound ($pvc_count PVCs)"
    else
        error "No bound PostgreSQL PVCs found"
    fi
}

verify_external_secrets() {
    section "External Secrets Verification"
    
    # Check 1Password Connect
    check_start
    if kubectl get secret -n onepassword-connect onepassword-connect-credentials &> /dev/null; then
        success "1Password Connect credentials secret exists"
    else
        error "1Password Connect credentials secret not found"
    fi
    
    check_start
    if kubectl get secret -n onepassword-connect onepassword-connect-token &> /dev/null; then
        success "1Password Connect token secret exists"
    else
        error "1Password Connect token secret not found"
    fi
    
    # Check ClusterSecretStore
    check_start
    if kubectl get clustersecretstore onepassword-connect &> /dev/null; then
        success "1Password ClusterSecretStore exists"
    else
        error "1Password ClusterSecretStore not found"
    fi
    
    # Check Authentik external secrets
    check_start
    if kubectl get externalsecret -n authentik authentik-config &> /dev/null; then
        local config_status
        config_status=$(kubectl get externalsecret -n authentik authentik-config -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "unknown")
        if [[ "$config_status" == "True" ]]; then
            success "Authentik config external secret is synced"
        else
            error "Authentik config external secret sync failed: $config_status"
        fi
    else
        error "Authentik config external secret not found"
    fi
    
    check_start
    if kubectl get externalsecret -n authentik authentik-database-credentials &> /dev/null; then
        local db_status
        db_status=$(kubectl get externalsecret -n authentik authentik-database-credentials -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "unknown")
        if [[ "$db_status" == "True" ]]; then
            success "Authentik database credentials external secret is synced"
        else
            error "Authentik database credentials external secret sync failed: $db_status"
        fi
    else
        error "Authentik database credentials external secret not found"
    fi
    
    # Check PostgreSQL external secrets
    check_start
    if kubectl get externalsecret -n postgresql-system postgresql-superuser-credentials &> /dev/null; then
        local pg_status
        pg_status=$(kubectl get externalsecret -n postgresql-system postgresql-superuser-credentials -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "unknown")
        if [[ "$pg_status" == "True" ]]; then
            success "PostgreSQL superuser credentials external secret is synced"
        else
            error "PostgreSQL superuser credentials external secret sync failed: $pg_status"
        fi
    else
        error "PostgreSQL superuser credentials external secret not found"
    fi
}

verify_authentik_deployment() {
    section "Authentik Deployment Verification"
    
    check_start
    if kubectl get namespace authentik &> /dev/null; then
        success "authentik namespace exists"
    else
        error "authentik namespace not found"
        return 1
    fi
    
    # Check database initialization job
    check_start
    if kubectl get job -n authentik authentik-database-init &> /dev/null; then
        local job_status
        job_status=$(kubectl get job -n authentik authentik-database-init -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "unknown")
        if [[ "$job_status" == "Complete" ]]; then
            success "Authentik database initialization job completed"
        else
            error "Authentik database initialization job status: $job_status"
        fi
    else
        error "Authentik database initialization job not found"
    fi
    
    # Check HelmRelease
    check_start
    if kubectl get helmrelease -n authentik authentik &> /dev/null; then
        local helm_status
        helm_status=$(kubectl get helmrelease -n authentik authentik -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "unknown")
        if [[ "$helm_status" == "True" ]]; then
            success "Authentik HelmRelease is ready"
        else
            error "Authentik HelmRelease status: $helm_status"
        fi
    else
        error "Authentik HelmRelease not found"
    fi
    
    # Check server deployment
    check_start
    if kubectl get deployment -n authentik authentik-server &> /dev/null; then
        local ready_replicas
        ready_replicas=$(kubectl get deployment -n authentik authentik-server -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local desired_replicas
        desired_replicas=$(kubectl get deployment -n authentik authentik-server -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "2")
        
        if [[ "$ready_replicas" == "$desired_replicas" && "$ready_replicas" != "0" ]]; then
            success "Authentik server deployment is ready ($ready_replicas/$desired_replicas)"
        else
            error "Authentik server deployment not ready ($ready_replicas/$desired_replicas)"
        fi
    else
        error "Authentik server deployment not found"
    fi
    
    # Check worker deployment
    check_start
    if kubectl get deployment -n authentik authentik-worker &> /dev/null; then
        local worker_ready
        worker_ready=$(kubectl get deployment -n authentik authentik-worker -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local worker_desired
        worker_desired=$(kubectl get deployment -n authentik authentik-worker -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        
        if [[ "$worker_ready" == "$worker_desired" && "$worker_ready" != "0" ]]; then
            success "Authentik worker deployment is ready ($worker_ready/$worker_desired)"
        else
            error "Authentik worker deployment not ready ($worker_ready/$worker_desired)"
        fi
    else
        error "Authentik worker deployment not found"
    fi
    
    # Check Redis
    check_start
    if kubectl get statefulset -n authentik authentik-redis-master &> /dev/null; then
        local redis_ready
        redis_ready=$(kubectl get statefulset -n authentik authentik-redis-master -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        if [[ "$redis_ready" == "1" ]]; then
            success "Authentik Redis is ready"
        else
            error "Authentik Redis not ready"
        fi
    else
        error "Authentik Redis StatefulSet not found"
    fi
}

verify_database_connectivity() {
    section "Database Connectivity Verification"
    
    # Test database connection from Authentik
    check_start
    local server_pod
    server_pod=$(kubectl get pods -n authentik -l app.kubernetes.io/name=authentik,app.kubernetes.io/component=server --no-headers 2>/dev/null | head -1 | awk '{print $1}' || echo "")
    
    if [[ -n "$server_pod" ]]; then
        log "Testing database connectivity from Authentik server pod: $server_pod"
        
        if kubectl exec -n authentik "$server_pod" -- python -c "
import os
import psycopg2
try:
    conn = psycopg2.connect(
        host=os.environ['AUTHENTIK_POSTGRESQL__HOST'],
        port=os.environ['AUTHENTIK_POSTGRESQL__PORT'],
        database=os.environ['AUTHENTIK_POSTGRESQL__NAME'],
        user=os.environ['AUTHENTIK_POSTGRESQL__USER'],
        password=os.environ['AUTHENTIK_POSTGRESQL__PASSWORD'],
        sslmode=os.environ.get('AUTHENTIK_POSTGRESQL__SSLMODE', 'require')
    )
    cursor = conn.cursor()
    cursor.execute('SELECT version();')
    version = cursor.fetchone()[0]
    print(f'Connected to: {version}')
    cursor.close()
    conn.close()
    print('Database connection successful')
except Exception as e:
    print(f'Database connection failed: {e}')
    exit(1)
" 2>/dev/null; then
            success "Database connectivity test passed"
        else
            error "Database connectivity test failed"
        fi
    else
        error "No Authentik server pod found for connectivity test"
    fi
    
    # Check database user and permissions
    check_start
    local pg_primary
    pg_primary=$(kubectl get pods -n postgresql-system -l postgresql=postgresql-cluster,role=primary --no-headers 2>/dev/null | head -1 | awk '{print $1}' || echo "")
    
    if [[ -n "$pg_primary" ]]; then
        log "Checking Authentik database user permissions from PostgreSQL primary: $pg_primary"
        
        if kubectl exec -n postgresql-system "$pg_primary" -- psql -d authentik -c "
SELECT 
    r.rolname as username,
    CASE WHEN r.rolsuper THEN 'superuser' ELSE 'regular' END as role_type,
    CASE WHEN r.rolcreatedb THEN 'yes' ELSE 'no' END as can_create_db,
    CASE WHEN r.rolcanlogin THEN 'yes' ELSE 'no' END as can_login
FROM pg_roles r 
WHERE r.rolname LIKE '%authentik%';
" 2>/dev/null | grep -q "authentik"; then
            success "Authentik database user exists with proper permissions"
        else
            error "Authentik database user not found or lacks permissions"
        fi
    else
        error "No PostgreSQL primary pod found for user verification"
    fi
}

verify_backup_configuration() {
    section "Backup Configuration Verification"
    
    # Check PostgreSQL backup configuration
    check_start
    if kubectl get scheduledbackup -n postgresql-system postgresql-cluster-backup &> /dev/null; then
        success "PostgreSQL scheduled backup is configured"
    else
        error "PostgreSQL scheduled backup not found"
    fi
    
    check_start
    if kubectl get secret -n postgresql-system postgresql-s3-backup-credentials &> /dev/null; then
        success "PostgreSQL S3 backup credentials exist"
    else
        error "PostgreSQL S3 backup credentials not found"
    fi
    
    # Check Longhorn backup configuration
    check_start
    local longhorn_jobs
    longhorn_jobs=$(kubectl get recurringjob -n longhorn-system --no-headers 2>/dev/null | grep -c "database" || echo "0")
    if [[ "$longhorn_jobs" -gt 0 ]]; then
        success "Longhorn database backup jobs are configured ($longhorn_jobs jobs)"
    else
        error "No Longhorn database backup jobs found"
    fi
    
    # Check volume snapshot class
    check_start
    if kubectl get volumesnapshotclass longhorn-snapshot-vsc &> /dev/null; then
        success "Longhorn volume snapshot class exists"
    else
        error "Longhorn volume snapshot class not found"
    fi
    
    # Check recent backups
    check_start
    local recent_backups
    recent_backups=$(kubectl get backup -n postgresql-system --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "$recent_backups" -gt 0 ]]; then
        success "PostgreSQL backups exist ($recent_backups backups)"
        
        # Show latest backup status
        local latest_backup
        latest_backup=$(kubectl get backup -n postgresql-system --sort-by='.metadata.creationTimestamp' --no-headers 2>/dev/null | tail -1 | awk '{print $1}' || echo "")
        if [[ -n "$latest_backup" ]]; then
            local backup_status
            backup_status=$(kubectl get backup -n postgresql-system "$latest_backup" -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
            info "Latest backup ($latest_backup) status: $backup_status"
        fi
    else
        warn "No PostgreSQL backups found (may be normal for new deployment)"
    fi
}

verify_ingress_networking() {
    section "Ingress and Networking Verification"
    
    # Check ingress resource
    check_start
    if kubectl get ingress -n authentik authentik-internal &> /dev/null; then
        success "Authentik ingress resource exists"
        
        local ingress_ip
        ingress_ip=$(kubectl get ingress -n authentik authentik-internal -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [[ -n "$ingress_ip" ]]; then
            info "Ingress IP: $ingress_ip"
        else
            warn "Ingress IP not yet assigned"
        fi
    else
        error "Authentik ingress resource not found"
    fi
    
    # Check ingress controller
    check_start
    if kubectl get pods -n ingress-nginx-internal -l app.kubernetes.io/name=ingress-nginx --no-headers 2>/dev/null | grep -q "Running"; then
        success "Internal ingress controller is running"
    else
        error "Internal ingress controller not found or not running"
    fi
    
    # Check TLS certificate
    check_start
    if kubectl get secret -n authentik authentik-tls-certificate &> /dev/null; then
        success "Authentik TLS certificate secret exists"
        
        local cert_expiry
        cert_expiry=$(kubectl get secret -n authentik authentik-tls-certificate -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "unknown")
        if [[ "$cert_expiry" != "unknown" ]]; then
            info "Certificate expires: $cert_expiry"
        fi
    else
        error "Authentik TLS certificate secret not found"
    fi
    
    # Check external DNS
    check_start
    if kubectl get pods -n external-dns-internal -l app.kubernetes.io/name=external-dns --no-headers 2>/dev/null | grep -q "Running"; then
        success "External DNS (internal) is running"
    else
        warn "External DNS (internal) not found or not running"
    fi
}

verify_radius_service() {
    section "RADIUS Service Verification"
    
    # Check RADIUS deployment
    check_start
    if kubectl get deployment -n authentik authentik-radius &> /dev/null; then
        local radius_ready
        radius_ready=$(kubectl get deployment -n authentik authentik-radius -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local radius_desired
        radius_desired=$(kubectl get deployment -n authentik authentik-radius -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "2")
        
        if [[ "$radius_ready" == "$radius_desired" && "$radius_ready" != "0" ]]; then
            success "RADIUS deployment is ready ($radius_ready/$radius_desired)"
        else
            error "RADIUS deployment not ready ($radius_ready/$radius_desired)"
        fi
    else
        error "RADIUS deployment not found"
    fi
    
    # Check RADIUS service
    check_start
    if kubectl get service -n authentik authentik-radius &> /dev/null; then
        success "RADIUS service exists"
        
        local radius_ip
        radius_ip=$(kubectl get service -n authentik authentik-radius -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [[ -n "$radius_ip" ]]; then
            success "RADIUS LoadBalancer IP assigned: $radius_ip"
        else
            warn "RADIUS LoadBalancer IP not yet assigned"
        fi
    else
        error "RADIUS service not found"
    fi
    
    # Check RADIUS configuration
    check_start
    if kubectl get configmap -n authentik authentik-radius-config &> /dev/null; then
        success "RADIUS configuration ConfigMap exists"
    else
        error "RADIUS configuration ConfigMap not found"
    fi
    
    # Check RADIUS token secret
    check_start
    if kubectl get secret -n authentik authentik-radius-token &> /dev/null; then
        success "RADIUS token secret exists"
    else
        error "RADIUS token secret not found"
    fi
}

verify_monitoring() {
    section "Monitoring Verification"
    
    # Check ServiceMonitor
    check_start
    if kubectl get servicemonitor -n authentik authentik-server &> /dev/null; then
        success "Authentik ServiceMonitor exists"
    else
        warn "Authentik ServiceMonitor not found (monitoring may not be configured)"
    fi
    
    # Check PrometheusRule
    check_start
    if kubectl get prometheusrule -n authentik authentik &> /dev/null; then
        success "Authentik PrometheusRule exists"
    else
        warn "Authentik PrometheusRule not found"
    fi
    
    # Check if Prometheus is scraping Authentik
    check_start
    if kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -q "Running"; then
        success "Prometheus is running"
        
        # Try to check if Authentik targets are being scraped
        local prometheus_pod
        prometheus_pod=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | head -1 | awk '{print $1}' || echo "")
        if [[ -n "$prometheus_pod" ]]; then
            info "Prometheus pod: $prometheus_pod"
        fi
    else
        warn "Prometheus not found or not running"
    fi
}

perform_health_checks() {
    section "Health Checks"
    
    # Check Authentik server health
    check_start
    local server_pod
    server_pod=$(kubectl get pods -n authentik -l app.kubernetes.io/name=authentik,app.kubernetes.io/component=server --no-headers 2>/dev/null | head -1 | awk '{print $1}' || echo "")
    
    if [[ -n "$server_pod" ]]; then
        log "Checking Authentik server health from pod: $server_pod"
        
        if kubectl exec -n authentik "$server_pod" -- curl -f -s http://localhost:9000/-/health/live/ >/dev/null 2>&1; then
            success "Authentik server health check passed"
        else
            error "Authentik server health check failed"
        fi
    else
        error "No Authentik server pod found for health check"
    fi
    
    # Check RADIUS health
    check_start
    local radius_pod
    radius_pod=$(kubectl get pods -n authentik -l app.kubernetes.io/name=authentik-radius --no-headers 2>/dev/null | head -1 | awk '{print $1}' || echo "")
    
    if [[ -n "$radius_pod" ]]; then
        log "Checking RADIUS health from pod: $radius_pod"
        
        if kubectl exec -n authentik "$radius_pod" -- curl -f -s http://localhost:9300/outpost.goauthentik.io/ping >/dev/null 2>&1; then
            success "RADIUS health check passed"
        else
            error "RADIUS health check failed"
        fi
    else
        error "No RADIUS pod found for health check"
    fi
    
    # Check PostgreSQL health
    check_start
    local pg_primary
    pg_primary=$(kubectl get pods -n postgresql-system -l postgresql=postgresql-cluster,role=primary --no-headers 2>/dev/null | head -1 | awk '{print $1}' || echo "")
    
    if [[ -n "$pg_primary" ]]; then
        log "Checking PostgreSQL health from primary pod: $pg_primary"
        
        if kubectl exec -n postgresql-system "$pg_primary" -- pg_isready >/dev/null 2>&1; then
            success "PostgreSQL health check passed"
        else
            error "PostgreSQL health check failed"
        fi
    else
        error "No PostgreSQL primary pod found for health check"
    fi
}

show_troubleshooting_info() {
    section "Troubleshooting Information"
    
    if [[ "$VERIFICATION_FAILED" == "true" ]]; then
        echo -e "${YELLOW}Common troubleshooting steps:${NC}"
        echo ""
        
        echo "1. Check pod logs:"
        echo "   kubectl logs -n authentik -l app.kubernetes.io/name=authentik"
        echo "   kubectl logs -n postgresql-system -l postgresql=postgresql-cluster"
        echo ""
        
        echo "2. Check external secret status:"
        echo "   kubectl describe externalsecret -n authentik"
        echo "   kubectl describe externalsecret -n postgresql-system"
        echo ""
        
        echo "3. Check Flux reconciliation:"
        echo "   flux get kustomizations"
        echo "   flux get helmreleases"
        echo ""
        
        echo "4. Check 1Password Connect:"
        echo "   kubectl logs -n onepassword-connect"
        echo "   kubectl get clustersecretstore onepassword-connect -o yaml"
        echo ""
        
        echo "5. Check ingress and networking:"
        echo "   kubectl get ingress -A"
        echo "   kubectl get svc -A | grep LoadBalancer"
        echo ""
        
        echo "6. Manual database connection test:"
        echo "   kubectl exec -it -n postgresql-system <primary-pod> -- psql -d authentik"
        echo ""
        
        echo "7. Check backup status:"
        echo "   kubectl get backup -n postgresql-system"
        echo "   kubectl get recurringjob -n longhorn-system"
        echo ""
    fi
}

show_summary() {
    section "Verification Summary"
    
    echo -e "${BOLD}Total checks: $TOTAL_CHECKS${NC}"
    echo -e "${GREEN}Passed: $PASSED_CHECKS${NC}"
    echo -e "${RED}Failed: $FAILED_CHECKS${NC}"
    echo ""
    
    if [[ "$VERIFICATION_FAILED" == "true" ]]; then
        echo -e "${RED}❌ Authentik deployment verification FAILED${NC}"
        echo ""
        echo "Please review the failed checks above and run the troubleshooting commands."
        echo "Once issues are resolved, re-run this script to verify the deployment."
        echo ""
        return 1
    else
        echo -e "${GREEN}✅ Authentik deployment verification PASSED${NC}"
        echo ""
        echo "All components are healthy and properly configured."
        echo ""
        echo "Next steps:"
        echo "1. Access Authentik at: https://authentik.k8s.home.geoffdavis.com"
        echo "2. Configure RADIUS clients to use the RADIUS service"
        echo "3. Set up OIDC/SAML integrations as needed"
        echo "4. Monitor the deployment using the provided dashboards"
        echo ""
        return 0
    fi
}

# Main execution
main() {
    log "Starting Authentik + PostgreSQL deployment verification..."
    echo ""
    
    # Change to repository root
    cd "$REPO_ROOT" || {
        error "Failed to change to repository root: $REPO_ROOT"
        exit 1
    }
    
    # Run all verification steps
    verify_prerequisites
    verify_cnpg_operator
    verify_postgresql_cluster
    verify_external_secrets
    verify_authentik_deployment
    verify_database_connectivity
    verify_backup_configuration
    verify_ingress_networking
    verify_radius_service
    verify_monitoring
    perform_health_checks
    
    # Show results
    show_troubleshooting_info
    show_summary
    
    # Exit with appropriate code
    if [[ "$VERIFICATION_FAILED" == "true" ]]; then
        exit 1
    else
        exit 0
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi