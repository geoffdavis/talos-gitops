# Home Assistant Configuration Migration Guide

## Overview

This document provides a complete migration plan to move Home Assistant from static ConfigMap-based configuration to a user data volume approach that allows UI-based configuration management.

## Migration Strategy

### Current Issues

- Static ConfigMap overrides `configuration.yaml` preventing UI-based configuration
- Modern Home Assistant stores most configuration in database, making static approach inflexible
- Users cannot make persistent configuration changes through the web interface

### Solution

- Use minimal bootstrap configuration for essential system settings only
- Allow Home Assistant to manage its own configuration files in persistent volume
- Provide external access methods for advanced configuration editing

## Implementation Files

### 1. Bootstrap ConfigMap (apps/home-automation/home-assistant/bootstrap-configmap.yaml)

```yaml
---
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
    # This minimal configuration includes only essential system-level settings
    # All other configuration should be done through the Home Assistant UI

    # Load default set of integrations
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
      # Location configuration
      latitude: !env_var HOME_LATITUDE
      longitude: !env_var HOME_LONGITUDE
      elevation: !env_var HOME_ELEVATION
      unit_system: imperial
      time_zone: America/New_York
      country: US
      currency: USD
      # Internal/External URLs for proper proxy integration
      internal_url: "http://home-assistant.home-automation.svc.cluster.local:8123"
      external_url: "https://homeassistant.k8s.home.geoffdavis.com"
      # Allowlist for external URLs
      allowlist_external_dirs:
        - "/config"
        - "/tmp"
```

### 2. Configuration Initialization Job (apps/home-automation/home-assistant/config-init-job.yaml)

```yaml
---
apiVersion: batch/v1
kind: Job
metadata:
  name: home-assistant-config-init
  namespace: home-automation
  labels:
    app.kubernetes.io/name: home-assistant
    app.kubernetes.io/component: config-initialization
    app.kubernetes.io/part-of: home-automation-stack
  annotations:
    # This job should run before Home Assistant deployment
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
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
                echo "Configuration already exists, skipping initialization"
                exit 0
              fi

              echo "Creating initial configuration directory structure..."
              mkdir -p /config
              mkdir -p /config/custom_components
              mkdir -p /config/themes
              mkdir -p /config/www

              # Copy bootstrap configuration
              cp /bootstrap/bootstrap-configuration.yaml /config/configuration.yaml

              # Set proper ownership
              chown -R 1000:1000 /config
              chmod -R 755 /config
              chmod 644 /config/configuration.yaml

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
```

### 3. Updated Deployment (apps/home-automation/home-assistant/deployment.yaml)

Key changes to the existing deployment:

```yaml
# Remove these lines from volumeMounts:
# - name: home-assistant-configuration
#   mountPath: /config/configuration.yaml
#   subPath: configuration.yaml
#   readOnly: true

# Remove these lines from volumes:
# - name: home-assistant-configuration
#   configMap:
#     name: home-assistant-configuration
#     defaultMode: 0644

# Remove this annotation from pod template:
# checksum/config: '{{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}'

# The home-assistant-config volume mount at /config remains unchanged
```

### 4. Updated Kustomization (apps/home-automation/home-assistant/kustomization.yaml)

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

metadata:
  name: home-assistant
  namespace: home-automation

resources:
  - deployment.yaml
  - service.yaml
  - pvc.yaml
  - bootstrap-configmap.yaml # Changed from configmap.yaml
  - config-init-job.yaml # New initialization job
  - external-secret.yaml

labels:
  - pairs:
      app.kubernetes.io/name: home-assistant
      app.kubernetes.io/component: home-automation-core
      app.kubernetes.io/part-of: home-automation-stack

generatorOptions:
  disableNameSuffixHash: true
  labels:
    app.kubernetes.io/name: home-assistant
    app.kubernetes.io/component: home-automation-core
```

## Migration Process

### Step 1: Backup Current Configuration

```bash
# Create backup of current configuration
kubectl exec -n home-automation deployment/home-assistant -- tar -czf /tmp/ha-config-backup.tar.gz -C /config .
kubectl cp home-automation/$(kubectl get pod -n home-automation -l app.kubernetes.io/name=home-assistant -o jsonpath='{.items[0].metadata.name}'):/tmp/ha-config-backup.tar.gz ./ha-config-backup.tar.gz
```

### Step 2: Apply New Configuration

```bash
# Apply the new configuration files
kubectl apply -f apps/home-automation/home-assistant/bootstrap-configmap.yaml
kubectl apply -f apps/home-automation/home-assistant/config-init-job.yaml

# Wait for initialization job to complete
kubectl wait --for=condition=complete job/home-assistant-config-init -n home-automation --timeout=300s

# Update the deployment (remove ConfigMap mount)
kubectl apply -f apps/home-automation/home-assistant/deployment.yaml
```

### Step 3: Verify Migration

```bash
# Check that Home Assistant starts successfully
kubectl rollout status deployment/home-assistant -n home-automation

# Verify configuration file exists in volume
kubectl exec -n home-automation deployment/home-assistant -- ls -la /config/

# Check Home Assistant logs
kubectl logs -n home-automation deployment/home-assistant --tail=50
```

## External Configuration Access Methods

### Method 1: kubectl exec (Quick Edits)

```bash
# Access Home Assistant container directly
kubectl exec -it -n home-automation deployment/home-assistant -- /bin/bash

# Edit configuration files
vi /config/configuration.yaml

# Restart Home Assistant to apply changes
kubectl rollout restart deployment/home-assistant -n home-automation
```

### Method 2: Debug Pod with Shared Volume

```bash
# Create temporary pod with access to configuration volume
kubectl run -it --rm debug-ha-config \
  --image=alpine:latest \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "debug",
        "image": "alpine:latest",
        "command": ["sh"],
        "volumeMounts": [{
          "name": "config",
          "mountPath": "/config"
        }]
      }],
      "volumes": [{
        "name": "config",
        "persistentVolumeClaim": {
          "claimName": "home-assistant-config"
        }
      }]
    }
  }' \
  -n home-automation

# Install editor and edit files
apk add --no-cache nano
nano /config/configuration.yaml
```

### Method 3: VS Code with Kubernetes Extension

1. Install the Kubernetes extension in VS Code
2. Connect to your cluster
3. Navigate to the `home-automation` namespace
4. Find the `home-assistant-config` PVC
5. Browse and edit files directly through the VS Code interface

### Method 4: File Manager Pod (Long-term Access)

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ha-config-manager
  namespace: home-automation
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ha-config-manager
  template:
    metadata:
      labels:
        app: ha-config-manager
    spec:
      containers:
        - name: filebrowser
          image: filebrowser/filebrowser:latest
          ports:
            - containerPort: 80
          volumeMounts:
            - name: config
              mountPath: /srv
            - name: database
              mountPath: /database
          env:
            - name: FB_DATABASE
              value: /database/filebrowser.db
      volumes:
        - name: config
          persistentVolumeClaim:
            claimName: home-assistant-config
        - name: database
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: ha-config-manager
  namespace: home-automation
spec:
  selector:
    app: ha-config-manager
  ports:
    - port: 80
      targetPort: 80
```

## Benefits of This Approach

1. **UI-First Configuration**: Users can configure Home Assistant through the web interface
2. **Persistent Changes**: Configuration changes survive pod restarts and updates
3. **GitOps Compatibility**: Essential infrastructure settings remain version-controlled
4. **Flexibility**: Multiple methods for advanced configuration editing
5. **Backup Integration**: Configuration included in existing Longhorn backup strategy
6. **Non-Destructive Migration**: Existing configuration is preserved during migration

## Rollback Procedure

If issues occur, you can rollback by:

1. Restore the original `configmap.yaml`
2. Update the deployment to re-add the ConfigMap mount
3. Remove the initialization job and bootstrap ConfigMap
4. Restart the deployment

```bash
# Rollback commands
kubectl apply -f apps/home-automation/home-assistant/configmap.yaml  # Original
# Update deployment.yaml to restore ConfigMap mount
kubectl apply -f apps/home-automation/home-assistant/deployment.yaml
kubectl delete job home-assistant-config-init -n home-automation
kubectl delete configmap home-assistant-bootstrap -n home-automation
```

## Testing Checklist

- [ ] Home Assistant starts successfully after migration
- [ ] Database connection works (PostgreSQL)
- [ ] MQTT integration functions properly
- [ ] Web interface is accessible via Authentik proxy
- [ ] Configuration changes through UI persist after pod restart
- [ ] External configuration editing methods work
- [ ] Backup and restore procedures include configuration
- [ ] Logs show no configuration-related errors

## Maintenance Notes

- The bootstrap configuration should only be updated for infrastructure-level changes
- User-specific configuration should be done through the Home Assistant UI
- Regular backups will automatically include the configuration directory
- Monitor disk usage as configuration files and custom components may grow over time
