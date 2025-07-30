# Home Assistant Configuration Management Guide

## Overview

This guide provides detailed instructions for managing Home Assistant configuration after migrating to the user data volume approach. It covers different scenarios and user preferences for configuration management.

## Configuration Philosophy

### GitOps vs UI Configuration

- **GitOps (Infrastructure)**: Database connections, MQTT settings, proxy configuration, system-level settings
- **UI Configuration (User)**: Integrations, automations, devices, dashboards, user preferences

### Best Practices

1. Use the Home Assistant UI for most configuration tasks
2. Only edit YAML files directly for advanced scenarios
3. Always backup before making significant changes
4. Test changes in a development environment when possible

## Configuration Access Methods

### Method 1: Home Assistant Web Interface (Recommended)

**Use for:**

- Adding integrations and devices
- Creating automations and scripts
- Configuring dashboards
- Managing users and access
- Setting up notifications

**Access:**

- Navigate to `https://homeassistant.k8s.home.geoffdavis.com`
- Use Configuration → Settings for most options
- Use Configuration → Automations & Scenes for automation management

### Method 2: Direct File Editing via kubectl

**Use for:**

- Advanced YAML configuration
- Custom component installation
- Theme customization
- Complex automation that's easier in YAML

**Quick Edit Process:**

```bash
# 1. Access the container
kubectl exec -it -n home-automation deployment/home-assistant -- /bin/bash

# 2. Navigate to config directory
cd /config

# 3. Edit files (nano is available in the container)
nano configuration.yaml

# 4. Check configuration
python -m homeassistant --script check_config --config /config

# 5. Exit and restart Home Assistant
exit
kubectl rollout restart deployment/home-assistant -n home-automation
```

### Method 3: Dedicated Configuration Management Pod

**Use for:**

- Extended editing sessions
- File management with a web interface
- Multiple file operations

**Setup:**

```bash
# Deploy file manager (run once)
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ha-config-manager
  namespace: home-automation
  labels:
    app.kubernetes.io/name: ha-config-manager
    app.kubernetes.io/part-of: home-automation-stack
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
      securityContext:
        fsGroup: 1000
      containers:
        - name: filebrowser
          image: filebrowser/filebrowser:v2.27.0
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
            - name: FB_ROOT
              value: /srv
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
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
  type: ClusterIP
EOF

# Access via port-forward
kubectl port-forward -n home-automation svc/ha-config-manager 8080:80

# Open browser to http://localhost:8080
# Default credentials: admin/admin (change on first login)
```

### Method 4: VS Code with Remote Development

**Use for:**

- Professional development environment
- Syntax highlighting and validation
- Git integration for custom components

**Setup:**

1. Install VS Code with Remote-Containers extension
2. Create development container configuration
3. Mount the Home Assistant config volume

**Dev Container Configuration (.devcontainer/devcontainer.json):**

```json
{
  "name": "Home Assistant Config",
  "image": "mcr.microsoft.com/vscode/devcontainers/python:3.11",
  "mounts": ["source=home-assistant-config,target=/config,type=volume"],
  "extensions": [
    "ms-python.python",
    "redhat.vscode-yaml",
    "esbenp.prettier-vscode"
  ],
  "settings": {
    "python.defaultInterpreterPath": "/usr/local/bin/python"
  }
}
```

## Common Configuration Tasks

### Adding a New Integration

**Via UI (Recommended):**

1. Go to Configuration → Integrations
2. Click "Add Integration"
3. Search and select your integration
4. Follow the setup wizard

**Via YAML (Advanced):**

```bash
# Edit configuration.yaml
kubectl exec -it -n home-automation deployment/home-assistant -- nano /config/configuration.yaml

# Add integration configuration
# Example for weather integration:
weather:
  - platform: openweathermap
    api_key: !secret openweather_api_key
    mode: daily

# Restart Home Assistant
kubectl rollout restart deployment/home-assistant -n home-automation
```

### Managing Secrets

**For UI-configured integrations:**

- Secrets are stored in the database automatically
- No manual secret management needed

**For YAML-configured integrations:**

```bash
# Edit secrets.yaml
kubectl exec -it -n home-automation deployment/home-assistant -- nano /config/secrets.yaml

# Add secrets (example):
openweather_api_key: your_api_key_here
mqtt_password: your_mqtt_password

# Reference in configuration.yaml:
api_key: !secret openweather_api_key
```

### Installing Custom Components

**Via HACS (Home Assistant Community Store):**

1. Install HACS through the UI
2. Use HACS to install custom components
3. Restart Home Assistant

**Manual Installation:**

```bash
# Access container
kubectl exec -it -n home-automation deployment/home-assistant -- /bin/bash

# Create custom components directory
mkdir -p /config/custom_components/my_component

# Copy component files (example using wget)
cd /config/custom_components/my_component
wget https://example.com/component.py

# Set permissions
chown -R 1000:1000 /config/custom_components
```

### Backup and Restore Configuration

**Create Backup:**

```bash
# Create timestamped backup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
kubectl exec -n home-automation deployment/home-assistant -- tar -czf /tmp/ha-config-${TIMESTAMP}.tar.gz -C /config .
kubectl cp home-automation/$(kubectl get pod -n home-automation -l app.kubernetes.io/name=home-assistant -o jsonpath='{.items[0].metadata.name}'):/tmp/ha-config-${TIMESTAMP}.tar.gz ./ha-config-${TIMESTAMP}.tar.gz
```

**Restore from Backup:**

```bash
# Stop Home Assistant
kubectl scale deployment home-assistant -n home-automation --replicas=0

# Clear existing config (be careful!)
kubectl exec -n home-automation deployment/home-assistant -- rm -rf /config/*

# Restore backup
kubectl cp ./ha-config-backup.tar.gz home-automation/$(kubectl get pod -n home-automation -l app.kubernetes.io/name=home-assistant -o jsonpath='{.items[0].metadata.name}'):/tmp/
kubectl exec -n home-automation deployment/home-assistant -- tar -xzf /tmp/ha-config-backup.tar.gz -C /config

# Fix permissions
kubectl exec -n home-automation deployment/home-assistant -- chown -R 1000:1000 /config

# Start Home Assistant
kubectl scale deployment home-assistant -n home-automation --replicas=1
```

## Configuration Validation

### Check Configuration Syntax

```bash
# Validate configuration before restart
kubectl exec -n home-automation deployment/home-assistant -- python -m homeassistant --script check_config --config /config
```

### Monitor Logs During Changes

```bash
# Watch logs in real-time
kubectl logs -n home-automation deployment/home-assistant -f

# Check for specific errors
kubectl logs -n home-automation deployment/home-assistant --tail=100 | grep -i error
```

## Troubleshooting

### Configuration Not Loading

1. Check file permissions: `kubectl exec -n home-automation deployment/home-assistant -- ls -la /config/`
2. Validate YAML syntax: `kubectl exec -n home-automation deployment/home-assistant -- python -m homeassistant --script check_config --config /config`
3. Check logs: `kubectl logs -n home-automation deployment/home-assistant --tail=50`

### Integration Not Working

1. Verify integration is properly configured in UI or YAML
2. Check network connectivity from pod
3. Validate credentials and API keys
4. Review Home Assistant logs for specific error messages

### Performance Issues

1. Monitor resource usage: `kubectl top pod -n home-automation`
2. Check database performance (PostgreSQL logs)
3. Review recorder configuration to exclude unnecessary entities
4. Consider increasing resource limits if needed

## Security Considerations

### File Permissions

- Configuration files should be owned by user 1000 (Home Assistant user)
- Sensitive files like `secrets.yaml` should have restricted permissions (600)

### Secret Management

- Never commit secrets to Git repositories
- Use Home Assistant's built-in secret management
- Consider using Kubernetes secrets for infrastructure-level credentials

### Network Security

- Home Assistant is protected by Authentik proxy
- Internal communication uses cluster DNS
- Database connections are encrypted

## Monitoring and Maintenance

### Regular Tasks

1. **Weekly**: Review Home Assistant logs for errors
2. **Monthly**: Update Home Assistant version via GitOps
3. **Quarterly**: Review and clean up unused integrations
4. **Annually**: Full configuration backup and restore test

### Monitoring Integration

- Home Assistant metrics are available via Prometheus
- Grafana dashboards show system health
- Alerts configured for critical failures

### Update Procedures

1. **Home Assistant Core**: Update image tag in deployment.yaml
2. **Custom Components**: Update via HACS or manual replacement
3. **Configuration**: Test changes in development environment first

This guide provides comprehensive coverage of configuration management scenarios while maintaining the flexibility that modern Home Assistant users expect.
