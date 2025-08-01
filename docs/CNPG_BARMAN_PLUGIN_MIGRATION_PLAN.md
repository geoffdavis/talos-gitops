# CloudNativePG Barman Cloud Plugin Migration Plan

## Overview

This document outlines the migration from deprecated `barmanObjectStore` configuration to the new Barman Cloud Plugin architecture in CloudNativePG.

## Background

- **Current Version**: CloudNativePG v1.26.1
- **Deprecation**: Native Barman Cloud support deprecated and will be **completely removed in v1.28.0**
- **Urgency**: Current backup failures make this migration critical

## Affected Clusters

### 1. `homeassistant-postgresql` (home-automation namespace)

- **Current Status**: ❌ ContinuousArchiving failing with barman-cloud-wal-archive exit status 4
- **Config**: Single instance, S3 backup to `s3://longhorn-backup/homeassistant-postgresql`
- **Schedule**: Daily backups at 3:00 AM
- **Retention**: 30 days

### 2. `postgresql-cluster` (postgresql-system namespace)

- **Current Status**: ✅ Operational but using deprecated config
- **Config**: 3-instance HA cluster, S3 backup to `s3://longhorn-backup/postgresql-cluster`
- **Retention**: WAL 30 days, data 7 days

## Migration Strategy

### Phase 1: Preparation

1. ✅ **Backup Current Configurations**
   - Document existing `barmanObjectStore` settings
   - Export current cluster configurations
   - Verify S3 credentials and accessibility

2. **Test S3 Connectivity**
   - Validate AWS credentials from 1Password
   - Test S3 bucket access from cluster pods
   - Verify backup destination paths exist

### Phase 2: Plugin Configuration Development

1. **Create New Plugin-Based Configurations**
   - Convert `barmanObjectStore` settings to plugin `parameters`
   - Maintain identical S3 settings (bucket, credentials, retention)
   - Add new `plugins` array with barman-cloud plugin

2. **Configuration Validation**
   - Dry-run validation of new configurations
   - Ensure no conflicts between old and new backup methods

### Phase 3: Migration Execution

1. **Home Assistant Cluster (Priority 1 - Failing Backups)**
   - Apply new plugin configuration
   - Remove deprecated `barmanObjectStore` configuration
   - Monitor backup status and WAL archiving
   - Verify first successful plugin-based backup

2. **PostgreSQL Cluster (Priority 2 - Stable)**
   - Apply new plugin configuration after Home Assistant success
   - Remove deprecated `barmanObjectStore` configuration
   - Monitor HA cluster backup across all 3 instances

### Phase 4: Validation & Documentation

1. **End-to-End Testing**
   - Verify backup creation with plugin
   - Test WAL archiving functionality
   - Validate restore capabilities (non-production test)
   - Confirm backup retention policies

2. **Documentation Updates**
   - Update operational procedures
   - Document new plugin architecture
   - Create troubleshooting guides

## Technical Details

### Plugin Configuration Structure

```yaml
spec:
  plugins:
    - name: "barman-cloud"
      enabled: true
      isWALArchiver: true
      parameters:
        destinationPath: "s3://longhorn-backup/cluster-name"
        s3Credentials:
          accessKeyId:
            name: "secret-name"
            key: "AWS_ACCESS_KEY_ID"
          secretAccessKey:
            name: "secret-name"
            key: "AWS_SECRET_ACCESS_KEY"
        # Additional parameters converted from barmanObjectStore
```

### Migration Constraints

- **Cannot run both**: `barmanObjectStore` and plugins simultaneously
- **WAL Archiver**: Only one plugin can be `isWALArchiver: true`
- **Backward compatibility**: New plugin must use same S3 paths for continuity

## Risk Mitigation

### Backup Continuity

- Maintain same S3 destinations to preserve existing backups
- Test restore from pre-migration backups before proceeding
- Keep manual backup before migration

### Rollback Plan

- Keep original configurations as backup files
- Document exact rollback steps
- Test rollback procedure in isolated environment

### Monitoring

- Enhanced monitoring during migration period
- Alert on backup failures or WAL archiving issues
- Validate backup metrics post-migration

## Timeline

### Immediate (Next 1-2 days)

- **Day 1**: Fix failing Home Assistant backups with plugin migration
- **Day 2**: Migrate stable PostgreSQL cluster

### Short-term (1 week)

- Complete end-to-end testing
- Update documentation and procedures
- Prepare for future CNPG operator upgrades

### Long-term (Before v1.28.0)

- Monitor plugin stability
- Optimize backup configurations
- Plan operator upgrade path

## Success Criteria

- ✅ All clusters migrated to plugin architecture
- ✅ No backup/restore functionality loss
- ✅ WAL archiving working correctly
- ✅ Existing backup history preserved
- ✅ Zero data loss during migration
- ✅ Ready for CNPG v1.28.0 upgrade

## Emergency Contacts

If issues arise during migration:

- **Cluster Status**: `kubectl get clusters.postgresql.cnpg.io -A`
- **Backup Status**: `kubectl get backups.postgresql.cnpg.io -A`
- **Plugin Status**: Check cluster status `.status.pluginStatus`
- **Logs**: `kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg`

---

**Next Steps**: Begin with plugin configuration development for Home Assistant cluster (failing backups priority).
