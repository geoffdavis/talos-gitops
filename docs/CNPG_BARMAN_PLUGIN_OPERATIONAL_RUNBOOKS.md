# CNPG Barman Plugin Operational Runbooks

**Status**: 🎉 **PRODUCTION READY - MIGRATION COMPLETE**
**Last Updated**: August 1, 2025
**Migration Completion**: All systems operational with plugin architecture

This document provides comprehensive operational runbooks for maintaining CloudNativePG clusters with the Barman Plugin architecture. These runbooks cover common maintenance tasks, troubleshooting procedures, and best practices for the successfully deployed production system.

## Migration Completion Status

### ✅ Production Deployment Confirmed

- **Plugin Version**: v0.5.0 deployed and operational
- **Cluster Status**: Home Assistant PostgreSQL cluster using plugin architecture
- **Backup Operations**: ScheduledBackup running daily at 3:00 AM
- **Monitoring**: Complete Prometheus alerting system active
- **GitOps**: All Flux kustomizations reconciling successfully

### Current System Configuration

- **Plugin Deployment**: `cnpg-system` namespace with barman-cloud deployment
- **ObjectStore**: `homeassistant-postgresql-backup` in `home-automation` namespace
- **Backup Schedule**: Daily at 3:00 AM UTC (11:00 PM ET)
- **Retention Policy**: As configured in ObjectStore specification
- **Monitoring**: 15+ Prometheus alerts covering all failure scenarios

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Backup Management](#backup-management)
3. [Monitoring and Alerting](#monitoring-and-alerting)
4. [Troubleshooting](#troubleshooting)
5. [Emergency Procedures](#emergency-procedures)
6. [Performance Optimization](#performance-optimization)
7. [Security Maintenance](#security-maintenance)

## Daily Operations

### Daily Health Check Procedure

**Frequency:** Daily  
**Duration:** 10-15 minutes  
**Tools Required:** kubectl, monitoring dashboards

#### Steps:

1. **Check Cluster Health**

   ```bash
   # Check all CNPG clusters (currently: homeassistant-postgresql)
   kubectl get clusters -A

   # Verify Home Assistant cluster status (primary cluster with plugin)
   kubectl get cluster homeassistant-postgresql -n home-automation -o yaml | grep phase

   # Check plugin configuration
   kubectl get cluster homeassistant-postgresql -n home-automation -o yaml | grep -A 5 plugins
   ```

   **Expected Output:**
   - `phase: Cluster in healthy state`
   - Plugin: `barman-cloud.cloudnative-pg.io` configured and enabled

2. **Verify Backup Operations**

   ```bash
   # Check recent backups (Home Assistant cluster)
   kubectl get backups -n home-automation --sort-by='.metadata.creationTimestamp'

   # Check scheduled backup status
   kubectl get scheduledbackup homeassistant-postgresql-backup -n home-automation

   # Verify ObjectStore connectivity
   kubectl get objectstore homeassistant-postgresql-backup -n home-automation

   # Check plugin deployment status
   kubectl get pods -n cnpg-system -l app.kubernetes.io/name=barman-cloud
   ```

   **Expected Output:**
   - Recent backups show `Completed` status
   - ScheduledBackup shows active schedule (daily at 3:00 AM)
   - ObjectStore shows ready status with S3 connectivity
   - Plugin pods running in `cnpg-system` namespace

3. **Monitor Key Metrics**
   - Open Grafana dashboard: "CNPG Barman Plugin Monitoring" (if available)
   - Check Prometheus metrics for backup success rates
   - Verify WAL archiving operations via cluster status
   - Confirm latest backup completion times

   ```bash
   # Check cluster continuous archiving status
   kubectl get cluster homeassistant-postgresql -n home-automation -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}'

   # Expected: "True"
   ```

4. **Review Alerts**

   ```bash
   # Check CNPG monitoring alerts (deployed in cnpg-monitoring namespace)
   kubectl get prometheusrules -n cnpg-monitoring cnpg-barman-plugin-alerts

   # Check if monitoring namespace exists
   kubectl get namespace cnpg-monitoring

   # View alert rules
   kubectl describe prometheusrules cnpg-barman-plugin-alerts -n cnpg-monitoring
   ```

#### Success Criteria:

- [ ] Home Assistant cluster shows "healthy state"
- [ ] Plugin deployment running in cnpg-system namespace
- [ ] ObjectStore connectivity confirmed
- [ ] No critical alerts firing (if monitoring deployed)
- [ ] ScheduledBackup active and executing
- [ ] Latest backup completed successfully
- [ ] Continuous archiving status shows "True"

---

### Weekly Maintenance Tasks

**Frequency:** Weekly  
**Duration:** 30-45 minutes

#### Steps:

1. **Performance Review**

   ```bash
   # Run performance monitoring
   ./scripts/cnpg-monitoring/performance-monitor.sh historical homeassistant-postgresql home-automation 7d
   ./scripts/cnpg-monitoring/performance-monitor.sh historical postgresql-cluster postgresql-system 7d
   ```

2. **Backup Integrity Test**

   ```bash
   # Run restore test (optional - can be monthly)
   RUN_BACKUP_TEST=true ./scripts/cnpg-monitoring/health-check.sh
   ```

3. **Storage Cleanup**

   ```bash
   # Check ObjectStore usage
   kubectl get objectstores -A -o yaml | grep -A 5 retention

   # Verify retention policies are being enforced
   ```

4. **Security Updates**
   - Review and apply any PostgreSQL security updates
   - Check for Barman plugin updates
   - Verify TLS certificates are not expiring

---

## Backup Management

### Manual Backup Creation

**When to use:** Before major changes, emergency backups

#### Steps:

1. **Create Immediate Backup**

   ```bash
   # Create backup for Home Assistant cluster
   cat <<EOF | kubectl apply -f -
   apiVersion: postgresql.cnpg.io/v1
   kind: Backup
   metadata:
     name: manual-backup-$(date +%Y%m%d-%H%M%S)
     namespace: home-automation
   spec:
     cluster:
       name: homeassistant-postgresql
     method: barmanObjectStore
   EOF
   ```

2. **Monitor Backup Progress**

   ```bash
   # Check backup status
   kubectl get backups -n home-automation -w

   # Check logs if needed
   kubectl logs -n home-automation -l cnpg.io/cluster=homeassistant-postgresql
   ```

3. **Verify Backup Completion**
   ```bash
   # Confirm backup is completed
   kubectl get backup manual-backup-YYYYMMDD-HHMMSS -n home-automation -o yaml | grep phase
   ```

**Expected Result:** `phase: completed`

---

### Backup Restoration Process

**When to use:** Disaster recovery, data corruption, point-in-time recovery

#### Prerequisites:

- Source cluster backup information
- Target recovery time (for PITR)
- Storage class availability
- Network connectivity to ObjectStore

#### Steps:

1. **Identify Recovery Point**

   ```bash
   # List available backups
   kubectl get backups -n SOURCE_NAMESPACE --sort-by='.metadata.creationTimestamp'

   # Get backup details
   kubectl describe backup BACKUP_NAME -n SOURCE_NAMESPACE
   ```

2. **Prepare Recovery Environment**

   ```bash
   # Ensure ObjectStore access
   kubectl get objectstore OBJECTSTORE_NAME -n SOURCE_NAMESPACE

   # Verify secrets are available
   kubectl get secrets -n TARGET_NAMESPACE | grep postgresql
   ```

3. **Create Recovery Cluster**

   ```yaml
   apiVersion: postgresql.cnpg.io/v1
   kind: Cluster
   metadata:
     name: recovered-cluster-$(date +%s)
     namespace: TARGET_NAMESPACE
   spec:
     instances: 1
     imageName: ghcr.io/cloudnative-pg/postgresql:16.4

     plugins:
       - name: "barman-cloud.cloudnative-pg.io"
         isWALArchiver: true
         parameters:
           objectStoreName: "OBJECTSTORE_NAME"

     bootstrap:
       recovery:
         source: SOURCE_CLUSTER_NAME
         recoveryTarget:
           # For specific backup:
           backupID: "BACKUP_ID"
           # OR for PITR:
           # targetTime: "2024-01-15T10:30:00Z"
         objectStore:
           objectStoreName: "OBJECTSTORE_NAME"
           serverName: "SOURCE_CLUSTER_NAME"

     storage:
       size: 10Gi
       storageClass: longhorn-ssd

     superuserSecret:
       name: postgresql-superuser-credentials
   ```

4. **Monitor Recovery Process**

   ```bash
   # Watch cluster status
   kubectl get cluster recovered-cluster-TIMESTAMP -n TARGET_NAMESPACE -w

   # Check recovery logs
   kubectl logs -n TARGET_NAMESPACE -l cnpg.io/cluster=recovered-cluster-TIMESTAMP -f
   ```

5. **Verify Data Integrity**

   ```bash
   # Connect to recovered cluster
   kubectl exec -it -n TARGET_NAMESPACE recovered-cluster-TIMESTAMP-1 -- psql

   # Verify data
   \dt
   SELECT count(*) FROM your_important_table;
   ```

---

## Monitoring and Alerting

### Alert Response Procedures

#### Critical Alert: CNPGBackupFailed

**Severity:** Critical  
**Response Time:** Immediate (< 15 minutes)

**Investigation Steps:**

1. **Check Backup Status**

   ```bash
   kubectl get backups -A | grep -i failed
   kubectl describe backup FAILED_BACKUP_NAME -n NAMESPACE
   ```

2. **Verify ObjectStore Connectivity**

   ```bash
   kubectl get objectstore -A
   kubectl describe objectstore OBJECTSTORE_NAME -n NAMESPACE
   ```

3. **Check Plugin Health**
   ```bash
   kubectl get pods -A -l app=cnpg-barman-plugin
   kubectl logs -l app=cnpg-barman-plugin -n cnpg-system
   ```

**Resolution Actions:**

- Verify S3 credentials are valid
- Check network connectivity to ObjectStore
- Restart failed backup if transient issue
- Create manual backup to verify system health

---

#### Warning Alert: CNPGBackupTooOld

**Severity:** Warning  
**Response Time:** 1 hour

**Investigation Steps:**

1. **Check Last Successful Backup**

   ```bash
   kubectl get backups -A --sort-by='.status.startedAt' | tail -5
   ```

2. **Verify Scheduled Backups**
   ```bash
   kubectl get clusters -A -o yaml | grep -A 10 backup
   ```

**Resolution Actions:**

- Trigger immediate manual backup
- Review backup scheduling configuration
- Check for resource constraints preventing backups

---

#### Critical Alert: CNPGWALArchivingFailed

**Severity:** Critical  
**Response Time:** Immediate (< 10 minutes)

**Investigation Steps:**

1. **Check WAL Archiving Status**

   ```bash
   # Get primary pod
   kubectl get pods -n NAMESPACE -l role=primary

   # Check WAL status
   kubectl exec -n NAMESPACE PRIMARY_POD -- psql -c "SELECT * FROM pg_stat_archiver;"
   ```

2. **Verify Plugin Configuration**
   ```bash
   kubectl get cluster CLUSTER_NAME -n NAMESPACE -o yaml | grep -A 10 plugins
   ```

**Resolution Actions:**

- Check ObjectStore connectivity
- Verify WAL archiving configuration
- Monitor disk space on PostgreSQL pods
- Consider emergency maintenance if WAL accumulation is severe

---

## Troubleshooting

### Common Issues and Solutions

#### Issue: Plugin Not Starting

**Symptoms:**

- Plugin pods in CrashLoopBackOff
- Backup operations failing
- Missing metrics

**Diagnosis:**

```bash
# Check barman-cloud plugin pods
kubectl get pods -n cnpg-system -l app.kubernetes.io/name=barman-cloud

# Check plugin logs
kubectl logs -n cnpg-system -l app.kubernetes.io/name=barman-cloud

# Verify plugin deployment via Flux
kubectl get kustomization infrastructure-cnpg-barman-plugin -n flux-system

# Check ObjectStore connectivity
kubectl get objectstore homeassistant-postgresql-backup -n home-automation
```

**Solutions:**

1. **Resource Issues:**

   ```bash
   # Increase resource limits
   kubectl patch helmrelease cnpg-barman-plugin -n cnpg-system --type='merge' -p='{
     "spec": {
       "values": {
         "resources": {
           "limits": {
             "memory": "256Mi",
             "cpu": "200m"
           }
         }
       }
     }
   }'
   ```

2. **Configuration Issues:**
   ```bash
   # Verify and fix configuration
   kubectl get objectstore -A
   kubectl describe objectstore OBJECTSTORE_NAME -n NAMESPACE
   ```

---

#### Issue: Slow Backup Performance

**Symptoms:**

- Backup duration > 30 minutes
- Low backup throughput
- High resource usage during backups

**Diagnosis:**

```bash
# Run performance monitoring
./scripts/cnpg-monitoring/performance-monitor.sh benchmark CLUSTER_NAME NAMESPACE 3600

# Check resource usage
kubectl top pods -n NAMESPACE
kubectl describe nodes
```

**Solutions:**

1. **Increase Parallelism:**

   ```yaml
   # Update ObjectStore configuration
   spec:
     configuration:
       data:
         jobs: 4 # Increase from 2
         compression: gzip
   ```

2. **Optimize Storage:**

   ```bash
   # Check storage performance
   kubectl get storageclass
   kubectl describe pv
   ```

3. **Network Optimization:**
   ```bash
   # Verify network policies
   kubectl get networkpolicies -A
   kubectl describe networkpolicy -n NAMESPACE
   ```

---

#### Issue: ObjectStore Connection Failures

**Symptoms:**

- Backup failures with connection errors
- WAL archiving failures
- ObjectStore connection status = 0

**Diagnosis:**

```bash
# Test S3 connectivity
kubectl run s3-test --rm -i --restart=Never \
  --image=amazon/aws-cli:latest \
  --env="AWS_ACCESS_KEY_ID=$(kubectl get secret S3_SECRET -n NAMESPACE -o jsonpath='{.data.username}' | base64 -d)" \
  --env="AWS_SECRET_ACCESS_KEY=$(kubectl get secret S3_SECRET -n NAMESPACE -o jsonpath='{.data.password}' | base64 -d)" \
  -- aws s3 ls s3://BUCKET_NAME/
```

**Solutions:**

1. **Credential Issues:**

   ```bash
   # Update S3 credentials
   kubectl delete secret S3_SECRET_NAME -n NAMESPACE
   kubectl create secret generic S3_SECRET_NAME -n NAMESPACE \
     --from-literal=username=NEW_ACCESS_KEY \
     --from-literal=password=NEW_SECRET_KEY
   ```

2. **Network Issues:**
   ```bash
   # Check DNS resolution
   kubectl run dns-test --rm -i --restart=Never \
     --image=busybox \
     -- nslookup s3.amazonaws.com
   ```

---

## Emergency Procedures

### Complete Cluster Failure Recovery

**When to use:** Primary cluster completely unavailable, data center failure

#### Prerequisites:

- Valid backups in ObjectStore
- Alternative infrastructure available
- Recovery point objective (RPO) determined

#### Steps:

1. **Assess Damage and Recovery Point**

   ```bash
   # List available backups
   aws s3 ls s3://BACKUP_BUCKET/CLUSTER_NAME/ --recursive

   # Determine latest recoverable point
   ./scripts/cnpg-monitoring/backup-restore-test.sh list-backups CLUSTER_NAME NAMESPACE
   ```

2. **Prepare Recovery Environment**

   ```bash
   # Ensure target cluster/namespace exists
   kubectl create namespace recovery-CLUSTER_NAME

   # Copy ObjectStore configuration
   kubectl get objectstore OBJECTSTORE_NAME -n SOURCE_NS -o yaml | \
     sed 's/namespace: SOURCE_NS/namespace: recovery-CLUSTER_NAME/' | \
     kubectl apply -f -

   # Copy secrets
   kubectl get secret POSTGRES_SECRET -n SOURCE_NS -o yaml | \
     sed 's/namespace: SOURCE_NS/namespace: recovery-CLUSTER_NAME/' | \
     kubectl apply -f -
   ```

3. **Create Recovery Cluster**

   ```yaml
   apiVersion: postgresql.cnpg.io/v1
   kind: Cluster
   metadata:
     name: emergency-recovery-cluster
     namespace: recovery-CLUSTER_NAME
   spec:
     instances: 3 # Start with HA setup
     imageName: ghcr.io/cloudnative-pg/postgresql:16.4

     plugins:
       - name: "barman-cloud.cloudnative-pg.io"
         isWALArchiver: true
         parameters:
           objectStoreName: "OBJECTSTORE_NAME"

     bootstrap:
       recovery:
         source: ORIGINAL_CLUSTER_NAME
         recoveryTarget:
           targetTime: "LATEST_SAFE_TIME" # or backupID
         objectStore:
           objectStoreName: "OBJECTSTORE_NAME"
           serverName: "ORIGINAL_CLUSTER_NAME"

     storage:
       size: 20Gi
       storageClass: longhorn-ssd

     resources:
       requests:
         memory: "512Mi"
         cpu: "250m"
       limits:
         memory: "2Gi"
         cpu: "1000m"
   ```

4. **Monitor Recovery Progress**

   ```bash
   # Watch recovery
   kubectl get cluster emergency-recovery-cluster -n recovery-CLUSTER_NAME -w

   # Monitor logs
   kubectl logs -n recovery-CLUSTER_NAME -l cnpg.io/cluster=emergency-recovery-cluster -f
   ```

5. **Validate Data Integrity**

   ```bash
   # Connect and verify data
   kubectl exec -it -n recovery-CLUSTER_NAME emergency-recovery-cluster-1 -- psql

   # Run data validation queries
   # Check row counts, key tables, recent transactions
   ```

6. **Update Application Connections**
   ```bash
   # Update application configurations to point to new cluster
   # Update DNS records if necessary
   # Test application connectivity
   ```

---

### WAL Accumulation Emergency

**When to use:** WAL files accumulating rapidly, disk space critical

#### Immediate Actions (< 5 minutes):

1. **Assess Disk Space**

   ```bash
   kubectl exec -n NAMESPACE PRIMARY_POD -- df -h /var/lib/postgresql/data
   ```

2. **Check WAL Archiving Status**

   ```bash
   kubectl exec -n NAMESPACE PRIMARY_POD -- psql -c "
   SELECT
     archived_count,
     failed_count,
     last_archived_wal,
     last_failed_wal,
     last_failed_time
   FROM pg_stat_archiver;"
   ```

3. **Emergency WAL Cleanup (if disk critical)**

   ```bash
   # DANGER: Only if disk is > 90% full
   kubectl exec -n NAMESPACE PRIMARY_POD -- psql -c "SELECT pg_switch_wal();"

   # Monitor space
   kubectl exec -n NAMESPACE PRIMARY_POD -- du -sh /var/lib/postgresql/data/pg_wal/
   ```

#### Resolution Actions:

1. **Fix ObjectStore Connectivity**

   ```bash
   # Test and fix S3 connection
   # Restart plugin if necessary
   kubectl rollout restart deployment cnpg-barman-plugin -n cnpg-system
   ```

2. **Increase Archive Timeout** (temporary)

   ```bash
   kubectl exec -n NAMESPACE PRIMARY_POD -- psql -c "
   ALTER SYSTEM SET archive_timeout = '1min';
   SELECT pg_reload_conf();"
   ```

3. **Monitor Recovery**
   ```bash
   # Watch WAL archiving resume
   kubectl exec -n NAMESPACE PRIMARY_POD -- psql -c "
   SELECT * FROM pg_stat_archiver;" --watch
   ```

---

## Performance Optimization

### Backup Performance Tuning

#### Identify Performance Bottlenecks

1. **Analyze Current Performance**

   ```bash
   # Run comprehensive performance analysis
   ./scripts/cnpg-monitoring/performance-monitor.sh benchmark CLUSTER_NAME NAMESPACE 3600
   ```

2. **Review Historical Trends**
   ```bash
   # Get 30-day performance history
   ./scripts/cnpg-monitoring/performance-monitor.sh historical CLUSTER_NAME NAMESPACE 30d
   ```

#### Optimization Strategies

1. **Increase Backup Parallelism**

   ```yaml
   # Optimize ObjectStore configuration
   spec:
     configuration:
       data:
         jobs: 4 # Increase parallel backup jobs
         immediateCheckpoint: true
         compression: gzip # Balance between speed and space
       wal:
         maxParallel: 4 # Increase WAL parallel uploads
         compression: gzip
         retention: "30d"
   ```

2. **Storage Optimization**

   ```bash
   # Use high-performance storage class
   kubectl patch cluster CLUSTER_NAME -n NAMESPACE --type='merge' -p='{
     "spec": {
       "storage": {
         "storageClass": "longhorn-ssd"
       }
     }
   }'
   ```

3. **Resource Allocation**
   ```yaml
   # Increase cluster resources during backup windows
   spec:
     resources:
       requests:
         memory: "1Gi"
         cpu: "500m"
       limits:
         memory: "4Gi"
         cpu: "2000m"
   ```

---

### Monitoring Performance Metrics

#### Key Performance Indicators (KPIs)

1. **Backup Performance KPIs**
   - Backup duration: < 30 minutes (target)
   - Backup throughput: > 50 MB/s (target)
   - Backup success rate: > 99% (target)

2. **WAL Archiving KPIs**
   - WAL archiving success rate: > 99.9% (target)
   - Pending WAL files: < 10 (target)
   - WAL archive rate: Consistent with write rate

3. **Storage KPIs**
   - ObjectStore free space: > 20% (target)
   - Compression ratio: > 3:1 (typical)
   - Storage I/O latency: < 100ms (target)

#### Regular Performance Reviews

**Monthly Performance Review Checklist:**

- [ ] Analyze backup duration trends
- [ ] Review storage utilization and growth
- [ ] Assess network performance to ObjectStore
- [ ] Compare performance against SLA targets
- [ ] Identify optimization opportunities
- [ ] Update performance baselines

---

## Security Maintenance

### Regular Security Tasks

#### Monthly Security Review

1. **Certificate Management**

   ```bash
   # Check TLS certificate expiration
   kubectl get certificates -A
   kubectl describe certificate -A | grep "Not After"
   ```

2. **Secret Rotation**

   ```bash
   # List secrets and check age
   kubectl get secrets -A --sort-by='.metadata.creationTimestamp'

   # Rotate PostgreSQL passwords (quarterly)
   kubectl delete secret postgresql-superuser-credentials -n NAMESPACE
   # Recreate with new credentials
   ```

3. **Access Review**
   ```bash
   # Review RBAC permissions
   kubectl get rolebindings,clusterrolebindings -A | grep cnpg
   kubectl describe rolebinding -A | grep cnpg
   ```

#### Security Hardening

1. **Network Policies**

   ```yaml
   # Restrict PostgreSQL cluster network access
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: cnpg-cluster-policy
     namespace: TARGET_NAMESPACE
   spec:
     podSelector:
       matchLabels:
         cnpg.io/cluster: CLUSTER_NAME
     policyTypes:
       - Ingress
       - Egress
     ingress:
       - from:
           - namespaceSelector:
               matchLabels:
                 name: application-namespace
         ports:
           - protocol: TCP
             port: 5432
     egress:
       - to:
           - namespaceSelector:
               matchLabels:
                 name: cnpg-system
         ports:
           - protocol: TCP
             port: 443 # ObjectStore access
   ```

2. **Pod Security Standards**
   ```bash
   # Ensure restricted pod security
   kubectl label namespace NAMESPACE pod-security.kubernetes.io/enforce=restricted
   kubectl label namespace NAMESPACE pod-security.kubernetes.io/audit=restricted
   kubectl label namespace NAMESPACE pod-security.kubernetes.io/warn=restricted
   ```

---

## Appendices

### A. Useful Commands Reference

#### Cluster Management

```bash
# Get cluster status
kubectl get clusters -A

# Describe cluster details
kubectl describe cluster CLUSTER_NAME -n NAMESPACE

# Get cluster configuration
kubectl get cluster CLUSTER_NAME -n NAMESPACE -o yaml

# Check cluster pods
kubectl get pods -n NAMESPACE -l cnpg.io/cluster=CLUSTER_NAME
```

#### Backup Operations

```bash
# List backups
kubectl get backups -A

# Create manual backup
kubectl create -f manual-backup.yaml

# Check backup status
kubectl describe backup BACKUP_NAME -n NAMESPACE

# Delete old backup
kubectl delete backup BACKUP_NAME -n NAMESPACE
```

#### Monitoring

```bash
# Check ServiceMonitors
kubectl get servicemonitors -n monitoring

# View PrometheusRules
kubectl get prometheusrules -n monitoring

# Check metrics
curl -s "http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query?query=up"
```

### B. Troubleshooting Decision Tree

```
Backup Failure?
├── Check ObjectStore connectivity
│   ├── SUCCESS: Check plugin health
│   └── FAIL: Fix S3 credentials/network
├── Plugin issues?
│   ├── Restart plugin deployment
│   └── Check resource constraints
└── Storage issues?
    ├── Check disk space
    └── Verify storage class
```

### C. Emergency Contact Information

- **Primary On-Call:** [Contact Information]
- **Backup On-Call:** [Contact Information]
- **Infrastructure Team:** [Contact Information]
- **Escalation Manager:** [Contact Information]

### D. External Dependencies

- **S3 Storage Provider:** [Provider details and SLA]
- **DNS Provider:** [Provider details]
- **Certificate Authority:** [Let's Encrypt/Internal CA]
- **Monitoring System:** [Prometheus/Grafana URLs]

---

_This runbook should be reviewed quarterly and updated based on operational experience and system changes._
