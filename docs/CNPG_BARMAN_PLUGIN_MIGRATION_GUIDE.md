# CloudNativePG Barman Plugin Migration Guide

## Overview

This guide documents the migration from deprecated `barmanObjectStore` configuration to the new Barman Cloud Plugin architecture in CloudNativePG v1.26.1. The migration addresses the deprecation warning:

```
Native support for Barman Cloud is deprecated and will be completely removed in version 1.28.0. Please consider migrating to the new Barman Cloud Plugin.
```

## Migration Strategy

The migration follows the official CloudNativePG plugin migration documentation and implements a three-step approach:

1. **Install Barman Cloud Plugin** (critical first step)
2. **Create ObjectStore resources** (replaces inline barmanObjectStore configuration)
3. **Update Cluster configurations** (use plugins instead of barmanObjectStore)

## Implementation Overview

### 1. Barman Cloud Plugin Installation

**Files Created:**
- `infrastructure/cnpg-barman-plugin/helmrepository.yaml` - Helm repository for the plugin
- `infrastructure/cnpg-barman-plugin/helmrelease.yaml` - Plugin deployment
- `infrastructure/cnpg-barman-plugin/namespace.yaml` - cnpg-system namespace
- `infrastructure/cnpg-barman-plugin/kustomization.yaml` - Plugin resources

**Flux Integration:**
- Added `infrastructure-cnpg-barman-plugin` to `clusters/home-ops/infrastructure/core.yaml`
- Plugin deployment depends on `infrastructure-sources`

### 2. ObjectStore Resources

#### Infrastructure PostgreSQL Cluster
**File:** `infrastructure/postgresql-cluster/objectstore.yaml`

```yaml
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: postgresql-cluster-backup
  namespace: postgresql-system
spec:
  configuration:
    destinationPath: "s3://longhorn-backup/postgresql-cluster"
    s3Credentials:
      accessKeyId:
        name: postgresql-s3-backup-credentials
        key: AWS_ACCESS_KEY_ID
      secretAccessKey:
        name: postgresql-s3-backup-credentials
        key: AWS_SECRET_ACCESS_KEY
    # Additional configuration moved from barmanObjectStore
```

#### Home Assistant PostgreSQL Cluster
**File:** `apps/home-automation/postgresql/objectstore.yaml`

```yaml
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
    # Additional configuration moved from barmanObjectStore
```

### 3. Plugin-Based Cluster Configurations

#### Infrastructure Cluster
**File:** `infrastructure/postgresql-cluster/cluster-plugin.yaml`

**Key Changes:**
```yaml
spec:
  # Plugin configuration replaces backup.barmanObjectStore
  plugins:
    - name: "barman-cloud.cloudnative-pg.io"
      isWALArchiver: true
      parameters:
        objectStoreName: "postgresql-cluster-backup"
  
  # Removed backup.barmanObjectStore section
  # backup:
  #   retentionPolicy: "30d"
  #   barmanObjectStore: ...
```

#### Home Assistant Cluster
**File:** `apps/home-automation/postgresql/cluster-plugin.yaml`

**Key Changes:**
```yaml
spec:
  # Plugin configuration replaces backup.barmanObjectStore
  plugins:
    - name: "barman-cloud.cloudnative-pg.io"
      isWALArchiver: true
      parameters:
        objectStoreName: "homeassistant-postgresql-backup"
  
  # Removed backup section entirely
```

### 4. Dependency Management

#### Updated Database Configuration
**File:** `clusters/home-ops/infrastructure/database.yaml`

```yaml
spec:
  dependsOn:
    - name: infrastructure-cnpg-operator
    - name: infrastructure-cnpg-barman-plugin  # Added plugin dependency
    - name: infrastructure-longhorn
    - name: infrastructure-onepassword
  healthChecks:
    - apiVersion: postgresql.cnpg.io/v1
      kind: Cluster
      name: postgresql-cluster
      namespace: postgresql-system
    - apiVersion: barmancloud.cnpg.io/v1      # Plugin health check
      kind: ObjectStore
      name: postgresql-cluster-backup
      namespace: postgresql-system
```

#### Application Dependencies
**File:** `clusters/home-ops/infrastructure/apps.yaml`

The Home Assistant app already depends on `infrastructure-postgresql-cluster`, ensuring proper deployment order.

## Migration Process

### Prerequisites
1. **Cluster Access**: Ensure kubectl access to the home-ops cluster
2. **GitOps Ready**: Flux must be operational for automated deployment
3. **Backup Validation**: Confirm existing backups are accessible before migration

### Deployment Steps

1. **Deploy Plugin First** (Critical):
   ```bash
   # Plugin will be deployed via GitOps from core.yaml
   flux reconcile kustomization infrastructure-sources
   flux reconcile kustomization infrastructure-cnpg-barman-plugin
   ```

2. **Verify Plugin Installation**:
   ```bash
   kubectl get pods -n cnpg-system
   kubectl get helmreleases -n cnpg-system
   ```

3. **Deploy ObjectStore Resources**:
   ```bash
   # ObjectStores deployed via updated database.yaml
   flux reconcile kustomization infrastructure-postgresql-cluster
   ```

4. **Deploy Plugin-Based Clusters**:
   ```bash
   # Clusters updated to use plugin architecture
   flux reconcile kustomization infrastructure-postgresql-cluster
   flux reconcile kustomization apps-home-automation
   ```

### Validation Steps

1. **Verify Plugin Registration**:
   ```bash
   kubectl get objectstores -A
   kubectl describe objectstore postgresql-cluster-backup -n postgresql-system
   kubectl describe objectstore homeassistant-postgresql-backup -n home-automation
   ```

2. **Check Cluster Status**:
   ```bash
   kubectl get clusters -A
   kubectl describe cluster postgresql-cluster -n postgresql-system
   kubectl describe cluster homeassistant-postgresql -n home-automation
   ```

3. **Verify Backup Functionality**:
   ```bash
   # Check backup status and recent backup creation
   kubectl logs -n postgresql-system -l postgresql=postgresql-cluster
   kubectl logs -n home-automation -l postgresql=homeassistant-postgresql
   ```

## Rollback Procedure

If issues arise during migration, rollback to working configurations:

1. **Revert Kustomizations**:
   ```bash
   # Update kustomization.yaml files to use cluster.yaml instead of cluster-plugin.yaml
   # Remove objectstore.yaml references
   ```

2. **Use Working Configurations**:
   - `infrastructure/postgresql-cluster/cluster.yaml` (barmanObjectStore)
   - `apps/home-automation/postgresql/cluster.yaml` (barmanObjectStore)

3. **Remove Plugin Dependencies**:
   ```bash
   # Update database.yaml to remove plugin dependencies
   # Remove plugin from core.yaml
   ```

## Key Differences from Previous Approach

### What Was Wrong Before
- **Missing Plugin Installation**: Attempted to use plugins without installing the Barman Cloud Plugin
- **Inline Plugin Configuration**: Tried to configure plugins directly in Cluster spec
- **No ObjectStore Resources**: Attempted to use plugin syntax without proper ObjectStore resources

### Correct Approach Now
- **Plugin Installation First**: Deploy the Barman Cloud Plugin before using it
- **ObjectStore Pattern**: Create separate ObjectStore resources containing backup configuration
- **Reference Pattern**: Clusters reference ObjectStore resources via plugin parameters

## Troubleshooting

### Common Issues

1. **"Unknown plugin: 'barman-cloud'" Error**:
   - **Cause**: Plugin not installed or not ready
   - **Solution**: Verify plugin deployment and wait for readiness

2. **ObjectStore Resource Not Found**:
   - **Cause**: ObjectStore resource missing or in wrong namespace
   - **Solution**: Deploy ObjectStore resources before Cluster updates

3. **Plugin Connection Failures**:
   - **Cause**: Incorrect plugin name or parameters
   - **Solution**: Verify plugin name matches exactly: `barman-cloud.cloudnative-pg.io`

### Diagnostic Commands
```bash
# Check plugin status
kubectl get pods -n cnpg-system
kubectl describe helmrelease cnpg-barman-plugin -n cnpg-system

# Check ObjectStore resources
kubectl get objectstores -A
kubectl describe objectstore <name> -n <namespace>

# Check cluster status
kubectl get clusters -A
kubectl describe cluster <name> -n <namespace>

# Check plugin logs
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cnpg-barman-plugin
```

## Benefits of Migration

1. **Future Compatibility**: Removes dependency on deprecated barmanObjectStore
2. **Plugin Architecture**: Modular design allows for better maintenance and updates
3. **Separation of Concerns**: ObjectStore resources separate backup configuration from cluster configuration
4. **Enhanced Features**: Plugin architecture enables additional backup features and improvements

## References

- [CloudNativePG Barman Plugin Migration Documentation](https://cloudnative-pg.io/plugin-barman-cloud/docs/migration/)
- [CloudNativePG Plugin Architecture](https://cloudnative-pg.io/documentation/current/plugins/)
- [Barman Cloud Plugin Repository](https://github.com/cloudnative-pg/barman-cloud-plugin)

## Status

- **Implementation**: ✅ Complete
- **Testing**: 🔄 Pending cluster access restoration
- **Documentation**: ✅ Complete
- **Production Ready**: 🔄 Pending validation