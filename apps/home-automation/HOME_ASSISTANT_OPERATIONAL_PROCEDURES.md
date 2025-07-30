# Home Assistant Operational Procedures

## Overview

This document provides step-by-step operational procedures for managing the Home Assistant deployment in the Talos GitOps cluster, including the migration to user data volume configuration and ongoing maintenance tasks.

## Pre-Migration Checklist

### System Requirements Verification

- [ ] Kubernetes cluster is healthy and accessible
- [ ] Longhorn storage is operational
- [ ] PostgreSQL database cluster is running
- [ ] MQTT broker (Mosquitto) is operational
- [ ] External Authentik outpost is functioning
- [ ] Backup systems are operational

### Current State Documentation

```bash
# Document current Home Assistant version
kubectl get deployment home-assistant -n home-automation -o jsonpath='{.spec.template.spec.containers[0].image}'

# Document current configuration
kubectl get configmap home-assistant-configuration -n home-automation -o yaml > current-config-backup.yaml

# Document current PVC status
kubectl get pvc home-assistant-config -n home-automation -o yaml > current-pvc-backup.yaml

# Create full configuration backup
kubectl exec -n home-automation deployment/home-assistant -- tar -czf /tmp/pre-migration-backup.tar.gz -C /config .
kubectl cp home-automation/$(kubectl get pod -n home-automation -l app.kubernetes.io/name=home-assistant -o jsonpath='{.items[0].metadata.name}'):/tmp/pre-migration-backup.tar.gz ./pre-migration-backup.tar.gz
```

## Migration Execution Procedure

### Phase 1: Preparation and Backup

#### Step 1: Create Comprehensive Backup

```bash
# Set backup timestamp
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
echo "Migration backup timestamp: $BACKUP_TIMESTAMP"

# Backup current configuration
kubectl exec -n home-automation deployment/home-assistant -- tar -czf /tmp/migration-backup-${BACKUP_TIMESTAMP}.tar.gz -C /config .
kubectl cp home-automation/$(kubectl get pod -n home-automation -l app.kubernetes.io/name=home-assistant -o jsonpath='{.items[0].metadata.name}'):/tmp/migration-backup-${BACKUP_TIMESTAMP}.tar.gz ./migration-backup-${BACKUP_TIMESTAMP}.tar.gz

# Backup Kubernetes resources
kubectl get all,configmap,secret,pvc -n home-automation -o yaml > k8s-resources-backup-${BACKUP_TIMESTAMP}.yaml

# Verify backup integrity
tar -tzf migration-backup-${BACKUP_TIMESTAMP}.tar.gz | head -10
echo "Backup created: migration-backup-${BACKUP_TIMESTAMP}.tar.gz"
```

#### Step 2: Verify System Health

```bash
# Check Home Assistant health
kubectl get pods -n home-automation -l app.kubernetes.io/name=home-assistant
kubectl logs -n home-automation deployment/home-assistant --tail=20

# Check dependencies
kubectl get pods -n home-automation -l app.kubernetes.io/name=postgresql
kubectl get pods -n home-automation -l app.kubernetes.io/name=mosquitto
kubectl get pods -n home-automation -l app.kubernetes.io/name=redis

# Test web interface accessibility
curl -I https://homeassistant.k8s.home.geoffdavis.com
```

### Phase 2: Deploy New Configuration Resources

#### Step 1: Create Bootstrap ConfigMap

```bash
# Apply the bootstrap configuration
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: home-assistant-bootstrap
  namespace: home-automation
  labels:
    app.kubernetes.io/name: home-assistant
    app.kubernetes.io/component: home-automation-core
    app.kubernetes.io/part-of: home-automation-stack
data:
  bootstrap-configuration.yaml: |
    # Home Assistant Bootstrap Configuration
    default_config:

    # Database configuration - PostgreSQL backend
    recorder:
      db_url: !env_var POSTGRES_DB_URL
      purge_keep_days: 30
      commit_interval: 1
      exclude:
        domains:
          - automation
          - updater
        entity_globs:
          - sensor.weather_*
        entities:
          - sun.sun
          - sensor.date
          - sensor.time

    # HTTP configuration for reverse proxy integration
    http:
      use_x_forwarded_for: true
      trusted_proxies:
        - 10.244.0.0/16  # Pod CIDR for Authentik proxy
        - 172.29.51.0/24 # Management network
        - 127.0.0.1
        - ::1
      ip_ban_enabled: true
      login_attempts_threshold: 5

    # MQTT Integration
    mqtt:
      broker: !env_var MQTT_HOST mosquitto.home-automation.svc.cluster.local
      port: !env_var MQTT_PORT 1883
      username: !env_var MQTT_USERNAME
      password: !env_var MQTT_PASSWORD
      discovery: true
      discovery_prefix: homeassistant
      birth_message:
        topic: "homeassistant/status"
        payload: "online"
      will_message:
        topic: "homeassistant/status"
        payload: "offline"

    # Logger configuration
    logger:
      default: info
      logs:
        homeassistant.core: info
        homeassistant.components.mqtt: info
        homeassistant.components.recorder: info
        homeassistant.components.http: warning

    # System configuration
    homeassistant:
      latitude: !env_var HOME_LATITUDE
      longitude: !env_var HOME_LONGITUDE
      elevation: !env_var HOME_ELEVATION
      unit_system: imperial
      time_zone: America/New_York
      country: US
      currency: USD
      internal_url: "http://home-assistant.home-automation.svc.cluster.local:8123"
      external_url: "https://homeassistant.k8s.home.geoffdavis.com"
      allowlist_external_dirs:
        - "/config"
        - "/tmp"
EOF

# Verify ConfigMap creation
kubectl get configmap home-assistant-bootstrap -n home-automation
```

#### Step 2: Deploy Configuration Initialization Job

```bash
# Apply the initialization job
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: home-assistant-config-init-$(date +%s)
  namespace: home-automation
  labels:
    app.kubernetes.io/name: home-assistant
    app.kubernetes.io/component: config-initialization
    app.kubernetes.io/part-of: home-automation-stack
spec:
  template:
    metadata:
      labels:
        app.kubernetes.io/name: home-assistant
        app.kubernetes.io/component: config-initialization
    spec:
      restartPolicy: OnFailure
      securityContext:
        fsGroup: 1000
        runAsNonRoot: false
        seccompProfile:
          type: RuntimeDefault

      containers:
        - name: config-init
          image: alpine:3.19
          imagePullPolicy: IfNotPresent

          securityContext:
            runAsUser: 0
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
              add:
                - CHOWN
                - FOWNER

          command:
            - /bin/sh
            - -c
            - |
              set -e
              echo "Initializing Home Assistant configuration..."

              # Check if configuration.yaml already exists
              if [ -f /config/configuration.yaml ]; then
                echo "Configuration already exists, creating backup..."
                cp /config/configuration.yaml /config/configuration.yaml.backup-$(date +%s)
              fi

              echo "Creating configuration directory structure..."
              mkdir -p /config
              mkdir -p /config/custom_components
              mkdir -p /config/themes
              mkdir -p /config/www

              # Copy bootstrap configuration as fallback
              cp /bootstrap/bootstrap-configuration.yaml /config/configuration.yaml.bootstrap

              # Only replace configuration.yaml if it doesn't exist or is empty
              if [ ! -f /config/configuration.yaml ] || [ ! -s /config/configuration.yaml ]; then
                echo "Creating new configuration.yaml from bootstrap"
                cp /bootstrap/bootstrap-configuration.yaml /config/configuration.yaml
              else
                echo "Existing configuration.yaml preserved"
              fi

              # Set proper ownership
              chown -R 1000:1000 /config
              chmod -R 755 /config
              chmod 644 /config/configuration.yaml*

              echo "Configuration initialization completed successfully"

          volumeMounts:
            - name: home-assistant-config
              mountPath: /config
            - name: bootstrap-config
              mountPath: /bootstrap
              readOnly: true
            - name: tmp
              mountPath: /tmp

      volumes:
        - name: home-assistant-config
          persistentVolumeClaim:
            claimName: home-assistant-config
        - name: bootstrap-config
          configMap:
            name: home-assistant-bootstrap
            defaultMode: 0644
        - name: tmp
          emptyDir:
            sizeLimit: 100Mi
EOF

# Wait for job completion
kubectl wait --for=condition=complete job -l app.kubernetes.io/component=config-initialization -n home-automation --timeout=300s

# Check job logs
kubectl logs -n home-automation -l app.kubernetes.io/component=config-initialization
```

### Phase 3: Update Home Assistant Deployment

#### Step 1: Scale Down Current Deployment

```bash
# Scale down to prevent conflicts during update
kubectl scale deployment home-assistant -n home-automation --replicas=0

# Wait for pods to terminate
kubectl wait --for=delete pod -l app.kubernetes.io/name=home-assistant -n home-automation --timeout=120s
```

#### Step 2: Update Deployment Configuration

```bash
# Get current deployment
kubectl get deployment home-assistant -n home-automation -o yaml > current-deployment.yaml

# Apply updated deployment (removing ConfigMap mount)
kubectl patch deployment home-assistant -n home-automation --type='json' -p='[
  {
    "op": "remove",
    "path": "/spec/template/spec/containers/0/volumeMounts/1"
  },
  {
    "op": "remove",
    "path": "/spec/template/spec/volumes/1"
  },
  {
    "op": "remove",
    "path": "/spec/template/metadata/annotations/checksum~1config"
  }
]'

# Scale back up
kubectl scale deployment home-assistant -n home-automation --replicas=1

# Wait for deployment to be ready
kubectl rollout status deployment/home-assistant -n home-automation --timeout=300s
```

### Phase 4: Verification and Testing

#### Step 1: Verify Deployment Health

```bash
# Check pod status
kubectl get pods -n home-automation -l app.kubernetes.io/name=home-assistant

# Check logs for startup issues
kubectl logs -n home-automation deployment/home-assistant --tail=50

# Verify configuration file structure
kubectl exec -n home-automation deployment/home-assistant -- ls -la /config/
kubectl exec -n home-automation deployment/home-assistant -- head -20 /config/configuration.yaml
```

#### Step 2: Test Functionality

```bash
# Test web interface
curl -I https://homeassistant.k8s.home.geoffdavis.com

# Test database connectivity
kubectl exec -n home-automation deployment/home-assistant -- python -c "
import os
import psycopg2
try:
    conn = psycopg2.connect(os.environ['POSTGRES_DB_URL'])
    print('Database connection: SUCCESS')
    conn.close()
except Exception as e:
    print(f'Database connection: FAILED - {e}')
"

# Test MQTT connectivity
kubectl exec -n home-automation deployment/home-assistant -- python -c "
import paho.mqtt.client as mqtt
import os
try:
    client = mqtt.Client()
    client.username_pw_set(os.environ['MQTT_USERNAME'], os.environ['MQTT_PASSWORD'])
    client.connect(os.environ['MQTT_HOST'], int(os.environ['MQTT_PORT']), 60)
    print('MQTT connection: SUCCESS')
    client.disconnect()
except Exception as e:
    print(f'MQTT connection: FAILED - {e}')
"
```

#### Step 3: Test Configuration Persistence

```bash
# Make a test configuration change
kubectl exec -n home-automation deployment/home-assistant -- /bin/sh -c "
echo '# Test configuration change - $(date)' >> /config/configuration.yaml
"

# Restart Home Assistant
kubectl rollout restart deployment/home-assistant -n home-automation
kubectl rollout status deployment/home-assistant -n home-automation

# Verify change persisted
kubectl exec -n home-automation deployment/home-assistant -- tail -5 /config/configuration.yaml
```

## Post-Migration Procedures

### Cleanup Old Resources

```bash
# Remove old ConfigMap (after successful migration)
kubectl delete configmap home-assistant-configuration -n home-automation

# Clean up completed initialization jobs
kubectl delete job -l app.kubernetes.io/component=config-initialization -n home-automation
```

### Update GitOps Repository

```bash
# Update kustomization.yaml to reflect new resources
# Remove: configmap.yaml
# Add: bootstrap-configmap.yaml, config-init-job.yaml

# Commit changes to Git
git add apps/home-automation/home-assistant/
git commit -m "Migrate Home Assistant to user data volume configuration"
git push origin main
```

## Rollback Procedures

### Emergency Rollback (if migration fails)

```bash
# Scale down current deployment
kubectl scale deployment home-assistant -n home-automation --replicas=0

# Restore original deployment configuration
kubectl apply -f current-deployment.yaml

# Restore original ConfigMap
kubectl apply -f current-config-backup.yaml

# Scale back up
kubectl scale deployment home-assistant -n home-automation --replicas=1

# Verify rollback
kubectl rollout status deployment/home-assistant -n home-automation
```

### Full Configuration Restore

```bash
# If configuration corruption occurs
kubectl scale deployment home-assistant -n home-automation --replicas=0

# Clear corrupted configuration
kubectl exec -n home-automation deployment/home-assistant -- rm -rf /config/*

# Restore from backup
kubectl cp ./migration-backup-${BACKUP_TIMESTAMP}.tar.gz home-automation/$(kubectl get pod -n home-automation -l app.kubernetes.io/name=home-assistant -o jsonpath='{.items[0].metadata.name}'):/tmp/
kubectl exec -n home-automation deployment/home-assistant -- tar -xzf /tmp/migration-backup-${BACKUP_TIMESTAMP}.tar.gz -C /config

# Fix permissions
kubectl exec -n home-automation deployment/home-assistant -- chown -R 1000:1000 /config

# Scale back up
kubectl scale deployment home-assistant -n home-automation --replicas=1
```

## Ongoing Maintenance Procedures

### Weekly Health Checks

```bash
# Check deployment status
kubectl get deployment home-assistant -n home-automation

# Review logs for errors
kubectl logs -n home-automation deployment/home-assistant --tail=100 | grep -i error

# Check resource usage
kubectl top pod -n home-automation -l app.kubernetes.io/name=home-assistant

# Verify external access
curl -I https://homeassistant.k8s.home.geoffdavis.com
```

### Monthly Configuration Backup

```bash
# Create monthly backup
MONTHLY_BACKUP=$(date +%Y%m_monthly)
kubectl exec -n home-automation deployment/home-assistant -- tar -czf /tmp/config-backup-${MONTHLY_BACKUP}.tar.gz -C /config .
kubectl cp home-automation/$(kubectl get pod -n home-automation -l app.kubernetes.io/name=home-assistant -o jsonpath='{.items[0].metadata.name}'):/tmp/config-backup-${MONTHLY_BACKUP}.tar.gz ./config-backup-${MONTHLY_BACKUP}.tar.gz

# Store backup securely (example: upload to cloud storage)
echo "Monthly backup created: config-backup-${MONTHLY_BACKUP}.tar.gz"
```

### Configuration Validation

```bash
# Validate current configuration
kubectl exec -n home-automation deployment/home-assistant -- python -m homeassistant --script check_config --config /config

# Check for deprecated features
kubectl logs -n home-automation deployment/home-assistant --tail=500 | grep -i deprecat
```

### Performance Monitoring

```bash
# Monitor database performance
kubectl exec -n home-automation -c postgres homeassistant-postgresql-1 -- psql -U postgres -d homeassistant -c "
SELECT schemaname,tablename,attname,n_distinct,correlation
FROM pg_stats
WHERE schemaname = 'public'
ORDER BY n_distinct DESC LIMIT 10;
"

# Check Home Assistant performance metrics
kubectl exec -n home-automation deployment/home-assistant -- python -c "
import requests
import os
try:
    response = requests.get('http://localhost:8123/api/system_health')
    print('System health check: SUCCESS')
except Exception as e:
    print(f'System health check: FAILED - {e}')
"
```

## Troubleshooting Guide

### Common Issues and Solutions

#### Issue: Home Assistant won't start after migration

```bash
# Check logs for specific errors
kubectl logs -n home-automation deployment/home-assistant --tail=100

# Validate configuration syntax
kubectl exec -n home-automation deployment/home-assistant -- python -m homeassistant --script check_config --config /config

# Check file permissions
kubectl exec -n home-automation deployment/home-assistant -- ls -la /config/
```

#### Issue: Configuration changes not persisting

```bash
# Verify PVC is properly mounted
kubectl describe pod -n home-automation -l app.kubernetes.io/name=home-assistant

# Check volume permissions
kubectl exec -n home-automation deployment/home-assistant -- ls -la /config/

# Verify no ConfigMap override
kubectl get deployment home-assistant -n home-automation -o yaml | grep -A 10 volumeMounts
```

#### Issue: Database connection failures

```bash
# Check PostgreSQL cluster status
kubectl get cluster homeassistant-postgresql -n home-automation

# Verify database credentials
kubectl get secret homeassistant-database-credentials -n home-automation -o yaml

# Test connection from Home Assistant pod
kubectl exec -n home-automation deployment/home-assistant -- python -c "
import os, psycopg2
conn = psycopg2.connect(os.environ['POSTGRES_DB_URL'])
print('Database connection successful')
conn.close()
"
```

This comprehensive operational guide ensures smooth migration and ongoing maintenance of the Home Assistant deployment with user data volume configuration.
