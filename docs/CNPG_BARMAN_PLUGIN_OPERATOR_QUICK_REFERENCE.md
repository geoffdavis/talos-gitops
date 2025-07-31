# CNPG Barman Plugin - Operator Quick Reference Card

## 🚀 Migration Deployment Commands

### Deploy Migration
```bash
# Check current status
./scripts/deploy-cnpg-barman-plugin-migration.sh status

# Test deployment (no changes)
./scripts/deploy-cnpg-barman-plugin-migration.sh --dry-run deploy

# Full migration deployment
./scripts/deploy-cnpg-barman-plugin-migration.sh deploy

# Validate migration success
./scripts/deploy-cnpg-barman-plugin-migration.sh validate

# Test backup functionality
./scripts/deploy-cnpg-barman-plugin-migration.sh test
```

### Emergency Rollback
```bash
# Rollback migration if issues occur
./scripts/deploy-cnpg-barman-plugin-migration.sh rollback
```

---

## 📊 Daily Operations Commands

### Health Checks
```bash
# Check all cluster status
kubectl get clusters -A -o custom-columns="NAME:.metadata.name,NAMESPACE:.metadata.namespace,STATUS:.status.phase,ARCHIVING:.status.conditions[?(@.type=='ContinuousArchiving')].status"

# Check plugin status
kubectl get pods -n cnpg-system -l app.kubernetes.io/name=cnpg-barman-plugin
kubectl get helmrelease cnpg-barman-plugin -n cnpg-system

# Check ObjectStore resources
kubectl get objectstores -A

# Check recent backups
kubectl get backups -A --sort-by='.status.startedAt' | tail -10
```

### Plugin Health
```bash
# Plugin pod status
kubectl get pods -n cnpg-system

# Plugin logs
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cnpg-barman-plugin --tail=50

# Plugin resource usage
kubectl top pods -n cnpg-system

# HelmRelease status
kubectl describe helmrelease cnpg-barman-plugin -n cnpg-system
```

---

## 🗄️ Backup Operations

### Manual Backup Creation
```bash
# Home Assistant cluster backup
kubectl create -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: homeassistant-manual-$(date +%Y%m%d-%H%M%S)
  namespace: home-automation
spec:
  cluster:
    name: homeassistant-postgresql
  method: plugin
EOF

# Infrastructure cluster backup
kubectl create -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: postgresql-manual-$(date +%Y%m%d-%H%M%S)
  namespace: postgresql-system
spec:
  cluster:
    name: postgresql-cluster
  method: plugin
EOF
```

### Backup Status Monitoring
```bash
# Monitor backup progress
kubectl get backup <backup-name> -n <namespace> -w

# Check backup details
kubectl describe backup <backup-name> -n <namespace>

# List all backups by age
kubectl get backups -A --sort-by='.status.startedAt'

# Check backup failure reasons
kubectl get backups -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.namespace}{"\t"}{.status.phase}{"\t"}{.status.error}{"\n"}{end}' | grep -i failed
```

---

## 🔧 Troubleshooting Commands

### Cluster Issues
```bash
# Detailed cluster status
kubectl describe cluster homeassistant-postgresql -n home-automation
kubectl describe cluster postgresql-cluster -n postgresql-system

# Check cluster logs
kubectl logs -n home-automation -l cnpg.io/cluster=homeassistant-postgresql --tail=100
kubectl logs -n postgresql-system -l cnpg.io/cluster=postgresql-cluster --tail=100

# Check cluster events
kubectl get events -n home-automation --sort-by='.lastTimestamp' | tail -20
kubectl get events -n postgresql-system --sort-by='.lastTimestamp' | tail -20
```

### Plugin Connectivity
```bash
# Test S3 connectivity from plugin
kubectl exec -n cnpg-system deployment/cnpg-barman-plugin -- \
  sh -c 'curl -I https://s3.amazonaws.com || echo "S3 connectivity check"'

# Check ObjectStore configuration
kubectl describe objectstore homeassistant-postgresql-backup -n home-automation
kubectl describe objectstore postgresql-cluster-backup -n postgresql-system

# Verify secrets exist
kubectl get secret homeassistant-postgresql-s3-backup -n home-automation
kubectl get secret postgresql-s3-backup-credentials -n postgresql-system
```

### WAL Archiving Issues
```bash
# Check WAL archiving status
kubectl get clusters -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.namespace}{"\t"}{.status.conditions[?(@.type=="ContinuousArchiving")].status}{"\t"}{.status.conditions[?(@.type=="ContinuousArchiving")].message}{"\n"}{end}'

# Force WAL archive
kubectl exec -n home-automation homeassistant-postgresql-1 -- \
  psql -U postgres -c "SELECT pg_switch_wal();"

# Check WAL files
kubectl exec -n home-automation homeassistant-postgresql-1 -- \
  ls -la /var/lib/postgresql/data/pg_wal/
```

---

## 🔄 Maintenance Operations

### Plugin Updates
```bash
# Check current plugin version
kubectl get helmrelease cnpg-barman-plugin -n cnpg-system -o jsonpath='{.spec.chart.spec.version}'

# Force plugin reconciliation
flux reconcile helmrelease cnpg-barman-plugin -n cnpg-system

# Update plugin (modify helmrelease.yaml and commit)
git add infrastructure/cnpg-barman-plugin/helmrelease.yaml
git commit -m "Update CNPG Barman Plugin to vX.X.X"
git push
```

### Configuration Updates
```bash
# Reconcile plugin infrastructure
flux reconcile kustomization infrastructure-cnpg-barman-plugin

# Reconcile database configurations
flux reconcile kustomization infrastructure-postgresql-cluster
flux reconcile kustomization apps-home-automation

# Check Flux status
flux get kustomizations | grep -E "(cnpg|postgresql)"
```

---

## 📈 Monitoring & Metrics

### Performance Metrics
```bash
# Backup duration trends
kubectl get backups -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.startedAt}{"\t"}{.status.stoppedAt}{"\n"}{end}' | grep -v "null"

# Plugin resource usage
kubectl top pods -n cnpg-system -l app.kubernetes.io/name=cnpg-barman-plugin

# Storage usage (if available)
kubectl exec -n cnpg-system deployment/cnpg-barman-plugin -- df -h

# WAL archiving metrics
kubectl logs -n home-automation -l cnpg.io/cluster=homeassistant-postgresql | grep -i "wal.*archive" | tail -10
```

### Alerting Checks
```bash
# Check backup failures in last 24h
kubectl get backups -A --field-selector status.phase=failed

# Check clusters with archiving issues
kubectl get clusters -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.namespace}{"\t"}{.status.conditions[?(@.type=="ContinuousArchiving" && @.status=="False")]}{"\n"}{end}'

# Check plugin availability
kubectl get pods -n cnpg-system -l app.kubernetes.io/name=cnpg-barman-plugin --field-selector status.phase!=Running
```

---

## 🚨 Emergency Procedures

### Plugin Restart
```bash
# Restart plugin deployment
kubectl rollout restart deployment cnpg-barman-plugin -n cnpg-system

# Wait for rollout
kubectl rollout status deployment cnpg-barman-plugin -n cnpg-system

# Verify health
kubectl get pods -n cnpg-system -l app.kubernetes.io/name=cnpg-barman-plugin
```

### Backup Recovery
```bash
# List available backups for recovery
kubectl get backups -n home-automation --sort-by='.status.startedAt'

# Create recovery cluster (modify as needed)
kubectl apply -f - <<EOF
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
        backupID: "BACKUP_ID_HERE"  # Get from kubectl get backups
      objectStore:
        objectStoreName: "homeassistant-postgresql-backup"
        serverName: "homeassistant-postgresql"
  
  storage:
    size: 10Gi
    storageClass: longhorn-ssd
  
  superuserSecret:
    name: homeassistant-postgresql-superuser
EOF
```

### Critical Failure Response
```bash
# 1. Assess situation
kubectl get all -n cnpg-system
kubectl get clusters -A

# 2. Check logs for errors
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cnpg-barman-plugin --previous

# 3. Emergency backup if clusters are healthy
kubectl create backup emergency-$(date +%Y%m%d-%H%M%S) --cluster=homeassistant-postgresql -n home-automation

# 4. Contact escalation if unresolved within 30 minutes
```

---

## 📋 Common Issues & Solutions

### Issue: Plugin Not Ready
```bash
# Check plugin status
kubectl describe helmrelease cnpg-barman-plugin -n cnpg-system

# Common causes:
# - Helm repository not accessible
# - Resource limits too restrictive
# - Network policies blocking access

# Solution: Reconcile and check events
flux reconcile source helm cnpg-barman-plugin -n cnpg-system
kubectl get events -n cnpg-system --sort-by='.lastTimestamp'
```

### Issue: Backup Failures
```bash
# Check backup status
kubectl describe backup <backup-name> -n <namespace>

# Common causes:
# - S3 credentials invalid/expired
# - Network connectivity to S3
# - Plugin not running

# Solution: Verify credentials and connectivity
kubectl get secret <s3-secret> -n <namespace> -o yaml
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cnpg-barman-plugin
```

### Issue: WAL Archiving Stopped
```bash
# Check archiving status
kubectl get cluster <cluster-name> -n <namespace> -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")]}'

# Common causes:
# - Plugin connectivity issues
# - S3 storage full/permissions
# - PostgreSQL configuration issues

# Solution: Restart archiving
kubectl exec -n <namespace> <cluster-pod> -- psql -U postgres -c "SELECT pg_switch_wal();"
```

---

## 📚 Key File Locations

### Configuration Files
- **Plugin**: `infrastructure/cnpg-barman-plugin/`
- **ObjectStores**: `infrastructure/postgresql-cluster/objectstore.yaml`, `apps/home-automation/postgresql/objectstore.yaml`
- **Clusters**: `infrastructure/postgresql-cluster/cluster-plugin.yaml`, `apps/home-automation/postgresql/cluster-plugin.yaml`

### Scripts
- **Migration**: `scripts/deploy-cnpg-barman-plugin-migration.sh`
- **Validation**: `scripts/validate-cnpg-backup-functionality.sh`

### Documentation
- **Migration Guide**: `docs/CNPG_BARMAN_PLUGIN_MIGRATION_GUIDE.md`
- **Disaster Recovery**: `docs/CNPG_BARMAN_PLUGIN_DISASTER_RECOVERY_PROCEDURES.md`
- **Project Summary**: `docs/CNPG_BARMAN_PLUGIN_MIGRATION_PROJECT_SUMMARY.md`

---

## 🆘 Emergency Contacts & Resources

### Escalation Path
1. **Primary Engineer**: [On-call rotation]
2. **Database Team Lead**: [Contact info]
3. **Infrastructure Manager**: [Contact info]

### External Resources
- **CloudNativePG Docs**: https://cloudnative-pg.io/documentation/
- **Plugin Documentation**: https://cloudnative-pg.io/plugin-barman-cloud/
- **GitHub Issues**: https://github.com/cloudnative-pg/cloudnative-pg/issues

### Internal Resources
- **Monitoring**: Grafana dashboards for CNPG metrics
- **Logs**: Centralized logging system
- **Documentation**: Internal wiki/confluence pages

---

**Last Updated**: July 31, 2025  
**Version**: 1.0  
**Applies to**: CloudNativePG v1.26.1 + Barman Plugin v1.26.1