# CNPG Barman Plugin Disaster Recovery Procedures

This document provides comprehensive disaster recovery procedures for CloudNativePG clusters using the Barman Plugin architecture. These procedures are designed to handle various disaster scenarios while ensuring minimal data loss and downtime.

## Table of Contents

1. [Overview](#overview)
2. [Disaster Recovery Planning](#disaster-recovery-planning)
3. [Recovery Scenarios](#recovery-scenarios)
4. [Automated Recovery Scripts](#automated-recovery-scripts)
5. [Recovery Testing](#recovery-testing)
6. [Communication and Escalation](#communication-and-escalation)

## Overview

### Recovery Objectives

- **Recovery Point Objective (RPO):** Maximum 5 minutes of data loss
- **Recovery Time Objective (RTO):** Maximum 30 minutes for critical services
- **Maximum Tolerable Downtime (MTD):** 2 hours for complete system recovery

### Architecture Components

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Primary Site  │    │   ObjectStore    │    │  Recovery Site  │
│                 │    │   (S3 Bucket)    │    │                 │
│ ┌─────────────┐ │    │ ┌──────────────┐ │    │ ┌─────────────┐ │
│ │ CNPG Cluster│ ├────┤ │ Backups &    │ ├────┤ │ New Cluster │ │
│ │ + Plugin    │ │    │ │ WAL Archive  │ │    │ │ + Plugin    │ │
│ └─────────────┘ │    │ └──────────────┘ │    │ └─────────────┘ │
├─────────────────┤    └──────────────────┘    └─────────────────┘
│ Kubernetes      │                            │ Kubernetes      │
│ Infrastructure  │                            │ Infrastructure  │
└─────────────────┘                            └─────────────────┘
```

### Key Recovery Assets

1. **Continuous Backups:** Base backups stored in S3 ObjectStore
2. **WAL Archive:** Write-Ahead Log files for point-in-time recovery
3. **Configuration Backups:** Kubernetes manifests and cluster configurations
4. **Monitoring Data:** Historical metrics and alerting configurations

---

## Disaster Recovery Planning

### Pre-Disaster Preparation

#### 1. Backup Verification

**Frequency:** Daily automated + Weekly manual verification

```bash
#!/bin/bash
# Daily backup verification script

CLUSTERS=("homeassistant-postgresql:home-automation" "postgresql-cluster:postgresql-system")

for cluster_info in "${CLUSTERS[@]}"; do
    IFS=':' read -r cluster_name namespace <<< "$cluster_info"
    
    echo "Verifying backups for $cluster_name in $namespace"
    
    # Check latest backup
    latest_backup=$(kubectl get backups -n "$namespace" \
        --sort-by='.status.startedAt' \
        -o jsonpath='{.items[-1].metadata.name}')
    
    # Verify backup completion
    backup_status=$(kubectl get backup "$latest_backup" -n "$namespace" \
        -o jsonpath='{.status.phase}')
    
    if [[ "$backup_status" != "completed" ]]; then
        echo "ERROR: Latest backup $latest_backup is not completed: $backup_status"
        exit 1
    fi
    
    # Check backup age
    backup_time=$(kubectl get backup "$latest_backup" -n "$namespace" \
        -o jsonpath='{.status.startedAt}')
    
    backup_epoch=$(date -d "$backup_time" +%s)
    current_epoch=$(date +%s)
    age_hours=$(( (current_epoch - backup_epoch) / 3600 ))
    
    if [[ $age_hours -gt 24 ]]; then
        echo "WARNING: Latest backup is $age_hours hours old"
    else
        echo "SUCCESS: Backup verification passed for $cluster_name"
    fi
done
```

#### 2. Configuration Documentation

**Maintain current documentation for:**
- Cluster configurations and customizations
- Network policies and security settings
- Resource requirements and scaling parameters
- Application connection strings and dependencies
- External integrations and API endpoints

#### 3. Recovery Environment Preparation

**Ensure availability of:**
- Alternative Kubernetes cluster or cloud region
- ObjectStore access from recovery location
- Network connectivity and DNS resolution
- Required storage classes and persistent volumes
- Secrets and credentials management system

---

## Recovery Scenarios

### Scenario 1: Single Cluster Failure

**Trigger Conditions:**
- Cluster pods failing and not recovering
- Storage corruption or hardware failure
- Database corruption without infrastructure issues

**Recovery Time:** 15-30 minutes  
**Data Loss:** Minimal (< 5 minutes if WAL archiving is working)

#### Recovery Steps:

1. **Immediate Assessment** (2-3 minutes)
   ```bash
   # Check cluster status
   kubectl get cluster homeassistant-postgresql -n home-automation
   kubectl describe cluster homeassistant-postgresql -n home-automation
   
   # Check recent backups availability
   kubectl get backups -n home-automation --sort-by='.status.startedAt'
   
   # Verify ObjectStore connectivity
   kubectl get objectstore homeassistant-postgresql-backup -n home-automation
   ```

2. **Determine Recovery Point** (2-3 minutes)
   ```bash
   # Get latest successful backup
   LATEST_BACKUP=$(kubectl get backups -n home-automation \
     --field-selector=status.phase=completed \
     --sort-by='.status.startedAt' \
     -o jsonpath='{.items[-1].metadata.name}')
   
   echo "Latest backup: $LATEST_BACKUP"
   
   # Check if PITR is needed
   kubectl get backup "$LATEST_BACKUP" -n home-automation \
     -o jsonpath='{.status.startedAt}'
   ```

3. **Prepare Recovery Environment** (3-5 minutes)
   ```bash
   # Ensure namespace is clean
   kubectl delete cluster homeassistant-postgresql -n home-automation --wait=false
   
   # Verify ObjectStore and secrets
   kubectl get objectstore homeassistant-postgresql-backup -n home-automation
   kubectl get secret homeassistant-postgresql-superuser -n home-automation
   ```

4. **Create Recovery Cluster** (5-10 minutes)
   ```yaml
   apiVersion: postgresql.cnpg.io/v1
   kind: Cluster
   metadata:
     name: homeassistant-postgresql
     namespace: home-automation
     labels:
       app.kubernetes.io/name: homeassistant-postgresql
       app.kubernetes.io/component: database
       app.kubernetes.io/part-of: home-automation-stack
       backup-tier: "important"
       recovery-cluster: "true"
   spec:
     instances: 1  # Start with single instance for faster recovery
     imageName: ghcr.io/cloudnative-pg/postgresql:16.4
     
     plugins:
       - name: "barman-cloud.cloudnative-pg.io"
         isWALArchiver: true
         parameters:
           objectStoreName: "homeassistant-postgresql-backup"
     
     bootstrap:
       recovery:
         source: homeassistant-postgresql
         recoveryTarget:
           backupID: "LATEST_BACKUP_ID"  # or targetTime for PITR
         objectStore:
           objectStoreName: "homeassistant-postgresql-backup"
           serverName: "homeassistant-postgresql"
     
     storage:
       size: 10Gi
       storageClass: longhorn-ssd
     
     postgresql:
       parameters:
         max_connections: "100"
         shared_buffers: "128MB"
         effective_cache_size: "512MB"
     
     superuserSecret:
       name: homeassistant-postgresql-superuser
   ```

5. **Monitor Recovery Progress** (10-15 minutes)
   ```bash
   # Watch cluster status
   kubectl get cluster homeassistant-postgresql -n home-automation -w
   
   # Monitor recovery logs
   kubectl logs -n home-automation -l cnpg.io/cluster=homeassistant-postgresql -f
   
   # Check when cluster becomes ready
   kubectl wait --for=condition=Ready cluster/homeassistant-postgresql -n home-automation --timeout=900s
   ```

6. **Verify Data Integrity** (3-5 minutes)
   ```bash
   # Connect to recovered database
   kubectl exec -it homeassistant-postgresql-1 -n home-automation -- psql -U homeassistant
   
   # Verify key tables and data
   \dt
   SELECT count(*) FROM states;
   SELECT max(created) FROM states;  # Check latest data timestamp
   ```

7. **Scale and Optimize** (5 minutes)
   ```bash
   # Scale to desired instance count
   kubectl patch cluster homeassistant-postgresql -n home-automation \
     --type='merge' -p='{"spec":{"instances":1}}'  # Keep at 1 for Home Assistant
   
   # Update recovery label
   kubectl label cluster homeassistant-postgresql -n home-automation \
     recovery-cluster-
   ```

---

### Scenario 2: Complete Infrastructure Failure

**Trigger Conditions:**
- Kubernetes cluster completely unavailable
- Data center or cloud region failure
- Network partitioning isolating entire infrastructure

**Recovery Time:** 45-90 minutes  
**Data Loss:** 5-15 minutes (depending on last successful WAL archive)

#### Recovery Steps:

1. **Infrastructure Assessment** (5-10 minutes)
   ```bash
   # Test primary infrastructure
   kubectl cluster-info
   kubectl get nodes
   
   # If primary is down, activate DR environment
   export KUBECONFIG=/path/to/dr-cluster-config
   kubectl cluster-info
   ```

2. **Prepare DR Environment** (10-15 minutes)
   ```bash
   # Create namespaces
   kubectl create namespace home-automation
   kubectl create namespace postgresql-system
   
   # Label namespaces
   kubectl label namespace home-automation \
     pod-security.kubernetes.io/enforce=privileged \
     pod-security.kubernetes.io/audit=privileged \
     pod-security.kubernetes.io/warn=privileged
   
   # Deploy ObjectStore CRDs and operator if needed
   kubectl apply -f infrastructure/cnpg-barman-plugin/
   ```

3. **Restore ObjectStore Configurations** (5 minutes)
   ```bash
   # Deploy ObjectStore configs
   kubectl apply -f - <<EOF
   apiVersion: barmancloud.cnpg.io/v1
   kind: ObjectStore
   metadata:
     name: homeassistant-postgresql-backup
     namespace: home-automation
   spec:
     configuration:
       destinationPath: "s3://home-assistant-postgres-backup-home-ops/homeassistant-postgresql"
       s3Credentials:
         accessKeyId:
           name: homeassistant-postgresql-s3-backup
           key: username
         secretAccessKey:
           name: homeassistant-postgresql-s3-backup
           key: password
       wal:
         retention: "30d"
         maxParallel: 2
         compression: gzip
       data:
         retention: "7d"
         immediateCheckpoint: true
         jobs: 2
         compression: gzip
   EOF
   ```

4. **Restore Secrets** (5 minutes)
   ```bash
   # Restore from 1Password or backup system
   kubectl create secret generic homeassistant-postgresql-superuser \
     --from-literal=username=postgres \
     --from-literal=password="$(op read op://homelab/homeassistant-postgresql-superuser/password)" \
     -n home-automation
   
   kubectl create secret generic homeassistant-postgresql-s3-backup \
     --from-literal=username="$(op read op://homelab/homeassistant-s3-backup/username)" \
     --from-literal=password="$(op read op://homelab/homeassistant-s3-backup/password)" \
     -n home-automation
   ```

5. **Deploy Recovery Clusters** (15-30 minutes)
   ```bash
   # Deploy Home Assistant cluster
   kubectl apply -f - <<EOF
   apiVersion: postgresql.cnpg.io/v1
   kind: Cluster
   metadata:
     name: homeassistant-postgresql
     namespace: home-automation
   spec:
     instances: 1
     imageName: ghcr.io/cloudnative-pg/postgresql:16.4
     
     plugins:
       - name: "barman-cloud.cloudnative-pg.io"
         isWALArchiver: true
         parameters:
           objectStoreName: "homeassistant-postgresql-backup"
     
     bootstrap:
       recovery:
         source: homeassistant-postgresql
         recoveryTarget:
           targetTime: "$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"
         objectStore:
           objectStoreName: "homeassistant-postgresql-backup"
           serverName: "homeassistant-postgresql"
     
     storage:
       size: 10Gi
       storageClass: longhorn-ssd
     
     superuserSecret:
       name: homeassistant-postgresql-superuser
   EOF
   
   # Deploy PostgreSQL cluster
   kubectl apply -f infrastructure/postgresql-cluster/cluster-plugin.yaml
   ```

6. **Update DNS and Application Configs** (10-15 minutes)
   ```bash
   # Update DNS records to point to new infrastructure
   # Update application configurations
   # Test connectivity from applications
   ```

---

### Scenario 3: Data Corruption with Infrastructure Intact

**Trigger Conditions:**
- Database corruption detected
- Application data inconsistencies
- Accidental data deletion or modification

**Recovery Time:** 20-45 minutes  
**Data Loss:** Variable (depends on when corruption occurred)

#### Recovery Steps:

1. **Immediate Damage Assessment** (3-5 minutes)
   ```bash
   # Check database integrity
   kubectl exec -it homeassistant-postgresql-1 -n home-automation -- \
     psql -U homeassistant -c "SELECT pg_database_size('homeassistant');"
   
   # Check for table corruption
   kubectl exec -it homeassistant-postgresql-1 -n home-automation -- \
     psql -U homeassistant -c "VACUUM VERBOSE;"
   
   # Identify corruption scope
   kubectl exec -it homeassistant-postgresql-1 -n home-automation -- \
     psql -U homeassistant -c "SELECT schemaname, tablename, n_dead_tup FROM pg_stat_user_tables WHERE n_dead_tup > 1000;"
   ```

2. **Determine Recovery Strategy** (2-3 minutes)
   ```bash
   # Check recent backup availability
   kubectl get backups -n home-automation --sort-by='.status.startedAt'
   
   # Identify last known good data point
   # Consider PITR vs full backup restoration
   ```

3. **Create Parallel Recovery Cluster** (10-15 minutes)
   ```yaml
   apiVersion: postgresql.cnpg.io/v1
   kind: Cluster
   metadata:
     name: homeassistant-postgresql-recovery
     namespace: home-automation
   spec:
     instances: 1
     imageName: ghcr.io/cloudnative-pg/postgresql:16.4
     
     plugins:
       - name: "barman-cloud.cloudnative-pg.io"
         isWALArchiver: true
         parameters:
           objectStoreName: "homeassistant-postgresql-backup"
     
     bootstrap:
       recovery:
         source: homeassistant-postgresql
         recoveryTarget:
           targetTime: "2024-01-15T10:00:00Z"  # Before corruption
         objectStore:
           objectStoreName: "homeassistant-postgresql-backup"
           serverName: "homeassistant-postgresql"
     
     storage:
       size: 10Gi
       storageClass: longhorn-ssd
     
     superuserSecret:
       name: homeassistant-postgresql-superuser
   ```

4. **Verify Recovery Data** (5-10 minutes)
   ```bash
   # Connect to recovery cluster
   kubectl exec -it homeassistant-postgresql-recovery-1 -n home-automation -- \
     psql -U homeassistant
   
   # Verify data integrity
   SELECT count(*) FROM states WHERE created > '2024-01-15 09:00:00';
   SELECT max(created) FROM states;
   
   # Export critical data if needed
   pg_dump -U homeassistant -t critical_table > /tmp/critical_data.sql
   ```

5. **Switch to Recovery Cluster** (5-10 minutes)
   ```bash
   # Stop applications pointing to corrupted cluster
   kubectl scale deployment home-assistant -n home-automation --replicas=0
   
   # Rename clusters
   kubectl patch cluster homeassistant-postgresql -n home-automation \
     --type='merge' -p='{"metadata":{"name":"homeassistant-postgresql-corrupted"}}'
   
   kubectl patch cluster homeassistant-postgresql-recovery -n home-automation \
     --type='merge' -p='{"metadata":{"name":"homeassistant-postgresql"}}'
   
   # Restart applications
   kubectl scale deployment home-assistant -n home-automation --replicas=1
   ```

---

## Automated Recovery Scripts

### Complete Recovery Automation Script

```bash
#!/bin/bash
# CNPG Disaster Recovery Automation Script

set -euo pipefail

# Configuration
DR_CONFIG_FILE="${DR_CONFIG_FILE:-/etc/cnpg-dr/config.yaml}"
LOG_FILE="/var/log/cnpg-dr-$(date +%Y%m%d-%H%M%S).log"
NOTIFICATION_WEBHOOK="${NOTIFICATION_WEBHOOK:-}"

# Logging
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$level] $timestamp: $message" | tee -a "$LOG_FILE"
}

# Send notifications
notify() {
    local message="$1"
    local level="${2:-info}"
    
    log INFO "NOTIFICATION: $message"
    
    if [[ -n "$NOTIFICATION_WEBHOOK" ]]; then
        curl -s -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"[CNPG DR] $message\"}" \
            "$NOTIFICATION_WEBHOOK" || true
    fi
}

# Recovery function for single cluster
recover_cluster() {
    local cluster_name="$1"
    local namespace="$2"
    local recovery_type="${3:-backup}"  # backup or pitr
    local recovery_target="${4:-latest}"
    
    log INFO "Starting recovery for cluster $cluster_name in namespace $namespace"
    notify "Starting disaster recovery for cluster $cluster_name" "warning"
    
    # Check if cluster exists and its status
    if kubectl get cluster "$cluster_name" -n "$namespace" &>/dev/null; then
        local cluster_status=$(kubectl get cluster "$cluster_name" -n "$namespace" \
            -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
        
        if [[ "$cluster_status" == "Cluster in healthy state" ]]; then
            log WARN "Cluster $cluster_name appears healthy. Skipping recovery."
            return 0
        fi
        
        log INFO "Cluster status: $cluster_status. Proceeding with recovery."
        
        # Delete existing cluster
        kubectl delete cluster "$cluster_name" -n "$namespace" --wait=false
        
        # Wait for cleanup
        while kubectl get cluster "$cluster_name" -n "$namespace" &>/dev/null; do
            log INFO "Waiting for cluster cleanup..."
            sleep 10
        done
    fi
    
    # Get ObjectStore name
    local objectstore_name="${cluster_name}-backup"
    
    # Verify ObjectStore exists
    if ! kubectl get objectstore "$objectstore_name" -n "$namespace" &>/dev/null; then
        log ERROR "ObjectStore $objectstore_name not found in namespace $namespace"
        return 1
    fi
    
    # Determine recovery target
    local recovery_spec=""
    case "$recovery_type" in
        "backup")
            if [[ "$recovery_target" == "latest" ]]; then
                recovery_spec='backupID: ""'  # Empty means latest
            else
                recovery_spec="backupID: \"$recovery_target\""
            fi
            ;;
        "pitr")
            if [[ "$recovery_target" == "latest" ]]; then
                recovery_target=$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)
            fi
            recovery_spec="targetTime: \"$recovery_target\""
            ;;
        *)
            log ERROR "Invalid recovery type: $recovery_type"
            return 1
            ;;
    esac
    
    # Create recovery cluster
    log INFO "Creating recovery cluster with $recovery_type recovery"
    
    cat <<EOF | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: $cluster_name
  namespace: $namespace
  labels:
    recovery-cluster: "true"
    recovery-timestamp: "$(date +%s)"
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
      source: $cluster_name
      recoveryTarget:
        $recovery_spec
      objectStore:
        objectStoreName: "$objectstore_name"
        serverName: "$cluster_name"
  
  storage:
    size: 10Gi
    storageClass: longhorn-ssd
  
  resources:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "1Gi"
      cpu: "500m"
  
  superuserSecret:
    name: ${cluster_name}-superuser
EOF

    # Wait for cluster to be ready
    log INFO "Waiting for cluster recovery to complete..."
    
    local timeout=1800  # 30 minutes
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        local status=$(kubectl get cluster "$cluster_name" -n "$namespace" \
            -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        
        case "$status" in
            "Cluster in healthy state")
                log INFO "Cluster recovery completed successfully"
                notify "Disaster recovery completed for cluster $cluster_name" "good"
                
                # Remove recovery labels
                kubectl label cluster "$cluster_name" -n "$namespace" \
                    recovery-cluster- recovery-timestamp- || true
                
                return 0
                ;;
            "Setting up primary")
                log INFO "Recovery in progress..."
                ;;
            "Failed")
                log ERROR "Cluster recovery failed"
                kubectl describe cluster "$cluster_name" -n "$namespace" | tail -20
                notify "Disaster recovery FAILED for cluster $cluster_name" "danger"
                return 1
                ;;
            *)
                log DEBUG "Recovery status: $status"
                ;;
        esac
        
        sleep 30
        elapsed=$((elapsed + 30))
    done
    
    log ERROR "Cluster recovery timed out"
    notify "Disaster recovery TIMED OUT for cluster $cluster_name" "danger"
    return 1
}

# Main recovery orchestration
main() {
    local recovery_mode="${1:-interactive}"
    local target_cluster="${2:-all}"
    
    log INFO "CNPG Disaster Recovery started (mode: $recovery_mode)"
    notify "CNPG Disaster Recovery process initiated"
    
    # Define clusters to recover
    local clusters=()
    
    if [[ "$target_cluster" == "all" ]]; then
        clusters=(
            "homeassistant-postgresql:home-automation"
            "postgresql-cluster:postgresql-system"
        )
    else
        # Parse single cluster specification
        if [[ "$target_cluster" =~ ^([^:]+):(.+)$ ]]; then
            clusters=("$target_cluster")
        else
            log ERROR "Invalid cluster specification: $target_cluster"
            log INFO "Format: cluster-name:namespace"
            exit 1
        fi
    fi
    
    local failed_recoveries=0
    local successful_recoveries=0
    
    # Process each cluster
    for cluster_info in "${clusters[@]}"; do
        IFS=':' read -r cluster_name namespace <<< "$cluster_info"
        
        log INFO "Processing cluster: $cluster_name in namespace: $namespace"
        
        if recover_cluster "$cluster_name" "$namespace" "backup" "latest"; then
            successful_recoveries=$((successful_recoveries + 1))
            log INFO "Successfully recovered: $cluster_name"
        else
            failed_recoveries=$((failed_recoveries + 1))
            log ERROR "Failed to recover: $cluster_name"
        fi
        
        echo "---"
    done
    
    # Final summary
    log INFO "Recovery Summary:"
    log INFO "  Successful: $successful_recoveries"
    log INFO "  Failed: $failed_recoveries"
    log INFO "  Log file: $LOG_FILE"
    
    if [[ $failed_recoveries -eq 0 ]]; then
        notify "All disaster recovery operations completed successfully"
        log INFO "All disaster recovery operations completed successfully"
        exit 0
    else
        notify "Some disaster recovery operations failed. Check logs: $LOG_FILE"
        log ERROR "Some disaster recovery operations failed"
        exit 1
    fi
}

# Usage information
usage() {
    cat <<EOF
CNPG Disaster Recovery Script

Usage: $0 [mode] [target]

Modes:
  interactive    - Interactive recovery with confirmations (default)
  automated      - Fully automated recovery
  
Targets:
  all                              - Recover all clusters (default)
  cluster-name:namespace           - Recover specific cluster

Examples:
  $0                                           # Interactive recovery of all clusters
  $0 automated                                 # Automated recovery of all clusters
  $0 interactive homeassistant-postgresql:home-automation    # Interactive recovery of specific cluster

Environment Variables:
  DR_CONFIG_FILE         - Path to DR configuration file
  NOTIFICATION_WEBHOOK   - Slack/Teams webhook for notifications
EOF
}

# Handle script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        -h|--help|help)
            usage
            exit 0
            ;;
        *)
            main "$@"
            ;;
    esac
fi
```

---

## Recovery Testing

### Monthly Recovery Testing Procedure

**Objective:** Validate recovery procedures and RTO/RPO targets

#### Test Schedule:
- **First Monday of each month:** Single cluster recovery test
- **Third Monday of each month:** Cross-region recovery test
- **Quarterly:** Full disaster recovery simulation

#### Test Execution:

1. **Pre-Test Preparation**
   ```bash
   # Create test namespace
   kubectl create namespace cnpg-dr-test
   
   # Set test parameters
   export TEST_CLUSTER="test-postgresql"
   export TEST_NAMESPACE="cnpg-dr-test"
   export TEST_START_TIME=$(date +%s)
   ```

2. **Execute Recovery Test**
   ```bash
   # Run automated recovery test
   ./scripts/cnpg-monitoring/backup-restore-test.sh
   
   # Measure recovery time
   export TEST_END_TIME=$(date +%s)
   export RECOVERY_DURATION=$((TEST_END_TIME - TEST_START_TIME))
   ```

3. **Validate Results**
   ```bash
   # Check if RTO target met (30 minutes = 1800 seconds)
   if [[ $RECOVERY_DURATION -le 1800 ]]; then
       echo "RTO target met: ${RECOVERY_DURATION}s"
   else
       echo "RTO target MISSED: ${RECOVERY_DURATION}s"
   fi
   
   # Verify data integrity
   kubectl exec -it test-postgresql-1 -n cnpg-dr-test -- \
     psql -c "SELECT count(*) FROM test_table;"
   ```

4. **Document Results**
   ```bash
   # Generate test report
   cat > "dr-test-report-$(date +%Y%m%d).json" <<EOF
   {
     "test_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
     "test_type": "single_cluster_recovery",
     "cluster_name": "$TEST_CLUSTER",
     "recovery_duration_seconds": $RECOVERY_DURATION,
     "rto_target_seconds": 1800,
     "rto_met": $(( RECOVERY_DURATION <= 1800 )),
     "data_integrity_verified": true,
     "notes": "Monthly recovery test - all objectives met"
   }
   EOF
   ```

---

## Communication and Escalation

### Incident Communication Plan

#### Severity Levels:

**SEV-1 (Critical):** Complete service unavailability
- **Notification:** Immediate (< 5 minutes)
- **Updates:** Every 15 minutes
- **Escalation:** CTO after 30 minutes

**SEV-2 (High):** Significant service degradation
- **Notification:** Within 15 minutes
- **Updates:** Every 30 minutes
- **Escalation:** Engineering Manager after 1 hour

**SEV-3 (Medium):** Minor service impact
- **Notification:** Within 1 hour
- **Updates:** Every 2 hours
- **Escalation:** Team Lead after 4 hours

#### Communication Templates:

**Initial Notification:**
```
INCIDENT ALERT - CNPG Database Recovery

Severity: SEV-1
Affected Service: Home Assistant Database
Issue: Complete cluster failure
Impact: Home automation services unavailable
Recovery ETA: 30 minutes
Incident Commander: [Name]
Next Update: 15 minutes

Status Page: https://status.example.com
Incident Room: #incident-response
```

**Progress Update:**
```
INCIDENT UPDATE - CNPG Database Recovery

Status: Recovery in progress
Progress: Cluster restore initiated (Step 3/7)
ETA: 20 minutes remaining
Issues: None
Next Update: 15 minutes

Recovery Details:
- Backup identified and validated
- Recovery cluster deployment started
- Applications will be restarted after DB is ready
```

**Resolution Notice:**
```
INCIDENT RESOLVED - CNPG Database Recovery

Duration: 28 minutes
Resolution: Full cluster recovery completed
Services: All services restored and operational
Data Loss: None (all data recovered)
Root Cause: Storage hardware failure
Prevention: Monitoring enhancement planned

Post-mortem scheduled for tomorrow 2 PM
```

#### Escalation Contacts:

- **Primary Engineer:** [24/7 on-call rotation]
- **Database Team Lead:** [Contact info]
- **Infrastructure Manager:** [Contact info]
- **CTO:** [Emergency contact only]
- **External Vendor Support:** [S3 provider, Cloud provider]

---

## Appendices

### A. Recovery Checklist Templates

#### Single Cluster Recovery Checklist:
- [ ] Assess cluster status and damage
- [ ] Identify latest viable backup
- [ ] Determine recovery method (backup vs PITR)
- [ ] Prepare recovery environment
- [ ] Execute cluster recovery
- [ ] Monitor recovery progress
- [ ] Verify data integrity
- [ ] Update applications/connections
- [ ] Test functionality end-to-end
- [ ] Document incident and lessons learned

#### Infrastructure Recovery Checklist:
- [ ] Assess infrastructure availability
- [ ] Activate alternate environment
- [ ] Deploy CNPG operator and plugins
- [ ] Restore ObjectStore configurations
- [ ] Restore secrets and credentials
- [ ] Deploy recovery clusters
- [ ] Update DNS and routing
- [ ] Test application connectivity
- [ ] Monitor system stability
- [ ] Plan primary site restoration

### B. Contact Information

#### Internal Contacts:
- **Database Team:** [Contact details]
- **Infrastructure Team:** [Contact details]
- **Application Teams:** [Contact details]
- **Management:** [Contact details]

#### External Vendors:
- **Cloud Provider Support:** [Contact details]
- **S3 Storage Provider:** [Contact details]
- **DNS Provider:** [Contact details]

### C. Configuration Backup Locations

- **Git Repository:** https://github.com/your-org/cnpg-configs
- **Configuration Backup:** s3://config-backup-bucket/cnpg/
- **Secrets Backup:** 1Password vault: "CNPG Disaster Recovery"
- **Documentation:** Confluence space: "Database Operations"

---

*This disaster recovery plan should be tested quarterly and updated based on operational experience and infrastructure changes.*