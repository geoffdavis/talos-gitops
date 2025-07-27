# Home Assistant Stack Backup Strategy

## Overview

This document outlines the comprehensive backup strategy for the Home Assistant stack, integrating with the existing cluster backup infrastructure. The strategy covers PostgreSQL database backups, Longhorn volume backups, and recovery procedures.

## Backup Architecture

### Components Covered

1. **PostgreSQL Database** - Home Assistant configuration and historical data
2. **Home Assistant Config** - YAML configurations, automations, and custom components
3. **MQTT Data** - Mosquitto broker persistent data and retained messages
4. **Redis Cache** - Session data and temporary cache

### Backup Tiers

- **Critical Tier**: Home Assistant config (daily snapshots, 8-week S3 retention)
- **Important Tier**: PostgreSQL database, MQTT data, Redis cache (standard retention)

## Backup Schedules

### PostgreSQL Database (CNPG)

- **Schedule**: Daily at 3:00 AM
- **Method**: CNPG ScheduledBackup with barmanObjectStore
- **Retention**: 30 days WAL, 7 days full backups
- **Storage**: S3 bucket `s3://longhorn-backup/homeassistant-postgresql`
- **Compression**: gzip

### Longhorn Volume Backups

#### Home Assistant Config (Critical Tier)

- **Daily Snapshots**: 2:00 AM, retain 7 days
- **Weekly S3 Backups**: Sunday 3:30 AM, retain 8 weeks
- **Backup Group**: `home-assistant-critical`

#### MQTT Data (Important Tier)

- **Daily Snapshots**: 2:15 AM, retain 7 days
- **Weekly S3 Backups**: Sunday 4:15 AM, retain 4 weeks
- **Backup Group**: `mqtt-data`

#### Redis Cache (Important Tier)

- **Daily Snapshots**: 2:45 AM, retain 3 days
- **Weekly S3 Backups**: Sunday 4:45 AM, retain 2 weeks
- **Backup Group**: `redis-cache`

### Schedule Coordination

Backup times are staggered to avoid resource conflicts:

````yaml
2:00 AM - Home Assistant config snapshots (critical)
2:15 AM - MQTT data snapshots
2:30 AM - General home automation snapshots
2:45 AM - Redis cache snapshots
3:00 AM - PostgreSQL database backup
3:30 AM - Home Assistant config S3 backup
4:15 AM - MQTT data S3 backup
4:30 AM - General home automation S3 backup
4:45 AM - Redis cache S3 backup
```yaml

## S3 Integration

### Credentials

- **Secret**: `longhorn-s3-backup-credentials` (shared with cluster infrastructure)
- **Source**: 1Password Connect - "AWS Access Key - longhorn-s3-backup - home-ops"
- **Bucket**: `longhorn-backup`

### Storage Paths

- **PostgreSQL**: `s3://longhorn-backup/homeassistant-postgresql/`
- **Longhorn Volumes**: `s3://longhorn-backup/volumes/home-automation/`

## Recovery Procedures

### PostgreSQL Database Recovery

#### Full Database Restore

```bash
# 1. Scale down Home Assistant
kubectl scale deployment home-assistant -n home-automation --replicas=0

# 2. Create recovery cluster from backup
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: homeassistant-postgresql-recovery
  namespace: home-automation
spec:
  instances: 1
  bootstrap:
    recovery:
      source: homeassistant-postgresql
      recoveryTargetTime: "2024-01-01 12:00:00"
  externalClusters:
    - name: homeassistant-postgresql
      barmanObjectStore:
        destinationPath: "s3://longhorn-backup/homeassistant-postgresql"
        s3Credentials:
          accessKeyId:
            name: homeassistant-postgresql-s3-backup
            key: AWS_ACCESS_KEY_ID
          secretAccessKey:
            name: homeassistant-postgresql-s3-backup
            key: AWS_SECRET_ACCESS_KEY
EOF

# 3. Verify recovery and promote cluster
# 4. Update Home Assistant configuration to use recovery cluster
# 5. Scale up Home Assistant
kubectl scale deployment home-assistant -n home-automation --replicas=1
```yaml

#### Point-in-Time Recovery

```bash
# Recover to specific timestamp
kubectl patch cluster homeassistant-postgresql-recovery -n home-automation --type='merge' -p='
spec:
  bootstrap:
    recovery:
      recoveryTargetTime: "2024-01-01 15:30:00"
'
```yaml

### Longhorn Volume Recovery

#### Home Assistant Config Recovery

```bash
# 1. List available snapshots
kubectl get volumesnapshots -n home-automation -l app=home-assistant

# 2. Create PVC from snapshot
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: home-assistant-config-restored
  namespace: home-automation
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-ssd
  resources:
    requests:
      storage: 10Gi
  dataSource:
    name: home-assistant-config-snapshot-20240101
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF

# 3. Update Home Assistant deployment to use restored PVC
kubectl patch deployment home-assistant -n home-automation -p='
spec:
  template:
    spec:
      volumes:
      - name: config
        persistentVolumeClaim:
          claimName: home-assistant-config-restored
'
```yaml

#### S3 Backup Restore

```bash
# 1. Create restore job
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: restore-home-assistant-config
  namespace: home-automation
spec:
  template:
    spec:
      containers:
      - name: restore
        image: longhorn/longhorn-manager:latest
        command:
        - /bin/bash
        - -c
        - |
          # Download backup from S3 and restore to volume
          longhorn backup restore s3://longhorn-backup/volumes/home-automation/home-assistant-config-backup-20240101
      restartPolicy: OnFailure
EOF
```yaml

### MQTT Data Recovery

#### Snapshot Recovery

```bash
# 1. Scale down Mosquitto
kubectl scale deployment mosquitto -n home-automation --replicas=0

# 2. Restore from snapshot (similar to Home Assistant process)
# 3. Scale up Mosquitto
kubectl scale deployment mosquitto -n home-automation --replicas=1
```yaml

### Redis Cache Recovery

#### Cache Rebuild

```bash
# Redis cache can be rebuilt from scratch if needed
# 1. Delete existing PVC
kubectl delete pvc redis-data -n home-automation

# 2. Recreate PVC (will be empty)
kubectl apply -f redis/pvc.yaml

# 3. Restart Redis deployment
kubectl rollout restart deployment redis -n home-automation
```yaml

## Monitoring and Alerting

### Backup Health Checks

#### PostgreSQL Backup Monitoring

```bash
# Check CNPG backup status
kubectl get backups -n home-automation
kubectl get schedulebackups -n home-automation

# Check backup logs
kubectl logs -n home-automation -l cnpg.io/cluster=homeassistant-postgresql
```yaml

#### Longhorn Backup Monitoring

```bash
# Check recurring job status
kubectl get recurringjobs -n longhorn-system | grep home-automation

# Check backup volumes
kubectl get backupvolumes -n longhorn-system
```yaml

### Alert Conditions

1. **Backup Failure**: Any backup job fails for 2 consecutive attempts
2. **Storage Space**: S3 bucket usage exceeds 80% of quota
3. **Retention Policy**: Backups older than retention policy still present
4. **Recovery Test**: Monthly recovery test failures

## Backup Validation

### Monthly Recovery Tests

1. **Database Recovery Test**: Restore PostgreSQL to test cluster
2. **Config Recovery Test**: Restore Home Assistant config to test environment
3. **End-to-End Test**: Full stack recovery in isolated namespace

### Backup Integrity Checks

```bash
# Verify PostgreSQL backup integrity
kubectl exec -n home-automation homeassistant-postgresql-1 -- \
  barman check homeassistant-postgresql

# Verify Longhorn backup checksums
kubectl get backupvolumes -n longhorn-system -o yaml | grep checksum
```yaml

## Disaster Recovery Scenarios

### Complete Cluster Loss

1. **Rebuild cluster** using existing Talos/GitOps procedures
2. **Restore PostgreSQL** from S3 backup using recovery cluster
3. **Restore volumes** from S3 backups using Longhorn restore jobs
4. **Validate services** and perform smoke tests

### Partial Data Loss

1. **Identify affected components** (database, config, or cache)
2. **Scale down affected services** to prevent data corruption
3. **Restore from most recent backup** using appropriate procedure
4. **Validate data integrity** before scaling services back up

### Corruption Recovery

1. **Stop all Home Assistant stack services**
2. **Assess corruption scope** (database vs. filesystem)
3. **Restore from last known good backup**
4. **Replay recent changes** from logs if possible

## Best Practices

### Backup Management

1. **Regular Testing**: Monthly recovery drills
2. **Documentation**: Keep recovery procedures updated
3. **Monitoring**: Automated backup success/failure alerts
4. **Retention**: Follow 3-2-1 backup rule (3 copies, 2 different media, 1 offsite)

### Security

1. **Encryption**: All backups encrypted in transit and at rest
2. **Access Control**: Limit backup access to authorized personnel
3. **Audit Trail**: Log all backup and recovery operations

### Performance

1. **Schedule Coordination**: Stagger backup times to avoid resource conflicts
2. **Resource Limits**: Set appropriate CPU/memory limits for backup jobs
3. **Network Bandwidth**: Monitor S3 transfer impact on cluster network

## Troubleshooting

### Common Issues

#### PostgreSQL Backup Failures

```bash
# Check CNPG operator logs
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg

# Check cluster status
kubectl get cluster homeassistant-postgresql -n home-automation -o yaml
```yaml

#### Longhorn Backup Failures

```bash
# Check Longhorn manager logs
kubectl logs -n longhorn-system -l app=longhorn-manager

# Check backup target connectivity
kubectl exec -n longhorn-system <longhorn-manager-pod> -- \
  curl -I https://s3.amazonaws.com/longhorn-backup
```yaml

#### S3 Connectivity Issues

```bash
# Test S3 credentials
kubectl get secret longhorn-s3-backup-credentials -n longhorn-system -o yaml

# Test S3 access from cluster
kubectl run s3-test --rm -i --tty --image=amazon/aws-cli -- \
  aws s3 ls s3://longhorn-backup/
```yaml

This backup strategy ensures comprehensive protection for the Home Assistant stack while integrating seamlessly with the existing cluster backup infrastructure.
````
