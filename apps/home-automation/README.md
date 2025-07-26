# Home Assistant Stack Documentation

## Overview

The Home Assistant stack is a comprehensive home automation platform deployed on the Talos GitOps cluster. This deployment provides a complete smart home solution with integrated authentication, database storage, MQTT messaging, and caching capabilities.

### Key Features and Capabilities

- **Complete Home Automation Platform**: Full-featured Home Assistant 2025.7 deployment
- **Integrated Authentication**: Seamless SSO integration via external Authentik outpost
- **Persistent Data Storage**: PostgreSQL database with automated backups
- **IoT Device Integration**: MQTT broker (Mosquitto) for device communication
- **Performance Optimization**: Redis caching for improved response times
- **High Availability**: Distributed storage with Longhorn and comprehensive backup strategy
- **Security-First Design**: Pod security standards, encrypted communications, and secret management

### Integration with Talos GitOps Cluster

The Home Assistant stack is fully integrated with the cluster's GitOps workflow:

- **Flux Management**: Deployed and managed via Flux GitOps with dependency ordering
- **1Password Integration**: All secrets managed through 1Password Connect
- **Longhorn Storage**: Persistent volumes backed by distributed USB SSD storage
- **BGP Load Balancing**: External access via BGP-advertised ingress controller
- **Monitoring Integration**: Prometheus metrics and Grafana dashboards
- **Backup Integration**: Automated backups to S3 with retention policies

## Architecture & Components

```
┌─────────────────────────────────────────────────────────────────┐
│                    Home Assistant Stack                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌──────────────┐ │
│  │  Home Assistant │    │   PostgreSQL    │    │  Mosquitto   │ │
│  │    (Core)       │◄──►│   (Database)    │    │   (MQTT)     │ │
│  │   Port: 8123    │    │   Port: 5432    │    │  Port: 1883  │ │
│  └─────────────────┘    └─────────────────┘    └──────────────┘ │
│           │                       │                      │      │
│           │              ┌─────────────────┐             │      │
│           └─────────────►│     Redis       │◄────────────┘      │
│                          │    (Cache)      │                    │
│                          │   Port: 6379    │                    │
│                          └─────────────────┘                    │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                    External Access Layer                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌──────────────┐ │
│  │ Authentik Proxy │    │ Ingress Nginx   │    │ BGP Load     │ │
│  │  (External)     │◄──►│   (Internal)    │◄──►│  Balancer    │ │
│  │ Authentication  │    │  k8s.home.*     │    │172.29.52.200 │ │
│  └─────────────────┘    └─────────────────┘    └──────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Component Details

#### Home Assistant Core (v2025.7)
- **Purpose**: Main home automation platform and web interface
- **Image**: `ghcr.io/home-assistant/home-assistant:2025.7`
- **Resources**: 500m-2000m CPU, 1Gi-4Gi memory
- **Storage**: 10Gi persistent volume for configuration files
- **Health Checks**: HTTP probes on port 8123 with startup, liveness, and readiness checks

#### PostgreSQL Database (v16.4)
- **Purpose**: Persistent storage for Home Assistant data and history
- **Operator**: CloudNativePG (CNPG) for enterprise-grade PostgreSQL management
- **Configuration**: Single instance with 10Gi storage, optimized for Home Assistant workload
- **Backup**: Automated daily backups to S3 with 30-day WAL retention
- **Security**: TLS encryption, dedicated service account, and restricted pod security

#### Mosquitto MQTT Broker (v2.0.18)
- **Purpose**: IoT device communication and message routing
- **Ports**: 1883 (MQTT), 8883 (MQTT-TLS), 9001 (WebSockets)
- **Authentication**: Username/password authentication with encrypted password file
- **Storage**: Persistent volume for broker data and retained messages
- **Security**: Non-root execution, read-only root filesystem, capability dropping

#### Redis Cache (Latest)
- **Purpose**: Session storage and performance caching
- **Configuration**: Single instance with persistent storage
- **Integration**: Used by Home Assistant for improved performance
- **Resources**: Lightweight resource allocation for caching workload

### Resource Requirements

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage |
|-----------|-------------|-----------|----------------|--------------|---------|
| Home Assistant | 500m | 2000m | 1Gi | 4Gi | 10Gi |
| PostgreSQL | 100m | 500m | 256Mi | 1Gi | 10Gi |
| Mosquitto | 100m | 500m | 128Mi | 512Mi | 5Gi |
| Redis | 100m | 200m | 64Mi | 256Mi | 1Gi |

### Storage Allocation

- **Total Storage**: ~26Gi across all components
- **Storage Class**: `longhorn-ssd` (distributed USB SSD storage)
- **Backup Strategy**: Automated snapshots and S3 backups with tiered retention
- **Performance**: Optimized for Samsung Portable SSD T5 devices

## Component Connections & Data Flow

### Service Discovery Patterns

All components use Kubernetes cluster DNS for service discovery:

```yaml
# Home Assistant → PostgreSQL
POSTGRES_HOST: homeassistant-postgresql-rw.home-automation.svc.cluster.local:5432

# Home Assistant → MQTT
MQTT_HOST: mosquitto.home-automation.svc.cluster.local:1883

# Home Assistant → Redis
REDIS_HOST: redis.home-automation.svc.cluster.local:6379

# External Access
External URL: https://homeassistant.k8s.home.geoffdavis.com
Internal URL: http://home-assistant.home-automation.svc.cluster.local:8123
```

### Database Connections

Home Assistant connects to PostgreSQL using:
- **Connection String**: `postgresql://username:password@homeassistant-postgresql-rw.home-automation.svc.cluster.local:5432/homeassistant`
- **SSL**: Enabled with cluster-generated certificates
- **Connection Pooling**: Managed by CNPG operator
- **Credentials**: Stored in 1Password and synchronized via ExternalSecret

### MQTT Messaging Flow

```
IoT Devices ──MQTT──► Mosquitto Broker ──Internal──► Home Assistant
     │                       │                           │
     │                   Retained                    Discovery
     │                   Messages                    Topics
     │                       │                           │
     └──────────── WebSocket/MQTT-TLS ──────────────────┘
```

- **Discovery**: Home Assistant uses MQTT discovery for automatic device integration
- **Retained Messages**: Mosquitto stores device states for reliability
- **Authentication**: Shared credentials between Home Assistant and Mosquitto

### Authentication Flow

```
User Browser ──HTTPS──► BGP Load Balancer ──► Ingress Nginx ──► Authentik Proxy
                                                                      │
                                                                 Authenticate
                                                                      │
                                                                      ▼
                                                              Home Assistant
```

1. **User Access**: Browser requests `https://homeassistant.k8s.home.geoffdavis.com`
2. **Load Balancing**: BGP-advertised IP (172.29.52.200) routes to ingress controller
3. **Proxy Authentication**: External Authentik outpost handles authentication
4. **Forward Auth**: Authenticated requests forwarded to Home Assistant
5. **Trusted Proxy**: Home Assistant trusts proxy headers for user identification

## Authentication & Access

### External Authentik Outpost Integration

The Home Assistant deployment integrates with the cluster's external Authentik outpost system:

- **Outpost ID**: `3f0970c5-d6a3-43b2-9a36-d74665c6b24e`
- **Provider**: `homeassistant-proxy` (forward auth mode)
- **Cookie Domain**: `k8s.home.geoffdavis.com`
- **Skip Paths**: `^/api/.*$` (API endpoints bypass authentication)

### SSO Authentication Flow

1. **Initial Request**: User navigates to Home Assistant URL
2. **Authentication Check**: Authentik proxy validates session
3. **Login Redirect**: Unauthenticated users redirected to Authentik login
4. **Session Creation**: Successful login creates authenticated session
5. **Service Access**: Authenticated requests forwarded to Home Assistant
6. **Session Persistence**: Redis-backed session storage for reliability

### Access URL and User Experience

- **Primary URL**: https://homeassistant.k8s.home.geoffdavis.com
- **Authentication**: Seamless SSO with cluster identity provider
- **Mobile Access**: Compatible with Home Assistant mobile apps
- **API Access**: Direct API access available for automation and integrations

### Trusted Proxy Configuration

Home Assistant is configured to trust proxy headers from:
- **Pod CIDR**: `10.244.0.0/16` (Authentik proxy pods)
- **Management Network**: `172.29.51.0/24` (cluster management)
- **Localhost**: `127.0.0.1` and `::1` for internal health checks

## Expected Usage & Features

### Home Automation Capabilities

- **Device Integration**: Support for 2000+ device types and platforms
- **Automation Engine**: Visual automation editor and YAML-based configurations
- **Scene Management**: Predefined device states for different scenarios
- **Energy Monitoring**: Track energy usage and costs
- **Security Integration**: Cameras, sensors, and alarm systems
- **Climate Control**: Thermostat and HVAC system integration

### IoT Device Integration via MQTT

- **Auto-Discovery**: Devices automatically appear in Home Assistant
- **Retained Messages**: Device states persist across restarts
- **QoS Support**: Quality of Service levels for reliable messaging
- **WebSocket Support**: Browser-based MQTT clients on port 9001
- **TLS Encryption**: Secure MQTT communication on port 8883

### Web Interface Features

- **Responsive Design**: Optimized for desktop, tablet, and mobile
- **Dashboard Customization**: Drag-and-drop interface builder
- **Real-time Updates**: Live device status and sensor data
- **Historical Data**: Charts and graphs for sensor trends
- **User Management**: Multiple user accounts with role-based access
- **Theme Support**: Light/dark themes and custom styling

### Mobile App Compatibility

- **Official Apps**: iOS and Android Home Assistant Companion apps
- **Push Notifications**: Real-time alerts and automation triggers
- **Location Services**: Presence detection and geofencing
- **Device Controls**: Full control of connected devices
- **Camera Integration**: Live camera feeds and snapshots

### Integration Possibilities

- **Voice Assistants**: Google Assistant, Amazon Alexa, Apple Siri
- **Cloud Services**: Weather, calendar, and notification services
- **Media Players**: Spotify, Plex, Chromecast, and smart TVs
- **Network Devices**: Routers, switches, and network monitoring
- **Custom Components**: Python-based custom integrations

## Configuration Management

### Home Assistant YAML Configuration Files

Configuration is managed through a hybrid approach:

#### ConfigMap Configuration (Read-Only)
- **File**: [`home-assistant/configmap.yaml`](home-assistant/configmap.yaml)
- **Purpose**: Base configuration template
- **Contents**: Core integrations, database settings, MQTT configuration
- **Updates**: Requires pod restart to apply changes

#### Persistent Volume Configuration (Read-Write)
- **Location**: `/config` directory in Home Assistant pod
- **Purpose**: User-customizable configurations
- **Contents**: Automations, scenes, scripts, custom components
- **Updates**: Hot-reloaded by Home Assistant

### Configuration File Structure

```
/config/
├── configuration.yaml      # Main configuration (from ConfigMap)
├── automations.yaml        # Automation definitions
├── scripts.yaml           # Script definitions
├── scenes.yaml            # Scene definitions
├── sensors.yaml           # Custom sensor configurations
├── switches.yaml          # Switch configurations
├── customize.yaml         # Entity customizations
├── secrets.yaml           # Local secrets (not used - 1Password preferred)
├── themes/                # Custom themes
├── custom_components/     # Custom integrations
└── www/                   # Static web assets
```

### Safe Configuration Update Procedures

#### ConfigMap Updates (Base Configuration)
```bash
# 1. Edit the ConfigMap
kubectl edit configmap home-assistant-configuration -n home-automation

# 2. Restart Home Assistant to apply changes
kubectl rollout restart deployment home-assistant -n home-automation

# 3. Verify configuration is valid
kubectl logs -n home-automation -l app.kubernetes.io/name=home-assistant
```

#### Persistent Configuration Updates
```bash
# 1. Access Home Assistant web interface
# 2. Use built-in configuration editor or file editor add-on
# 3. Configuration is automatically reloaded (no restart required)

# Alternative: Direct file editing via kubectl
kubectl exec -it -n home-automation deployment/home-assistant -- vi /config/automations.yaml
```

### Backup and Restore of Configurations

#### Automated Backup Strategy
- **ConfigMap**: Backed up as part of GitOps repository
- **Persistent Config**: Daily Longhorn snapshots and weekly S3 backups
- **Database**: CNPG automated backups with point-in-time recovery

#### Manual Configuration Backup
```bash
# Backup entire configuration directory
kubectl exec -n home-automation deployment/home-assistant -- \
  tar czf /tmp/config-backup.tar.gz -C /config .

# Copy backup to local machine
kubectl cp home-automation/home-assistant-pod:/tmp/config-backup.tar.gz ./config-backup.tar.gz
```

#### Configuration Restore
```bash
# Restore from backup
kubectl cp ./config-backup.tar.gz home-automation/home-assistant-pod:/tmp/

kubectl exec -n home-automation deployment/home-assistant -- \
  tar xzf /tmp/config-backup.tar.gz -C /config

# Restart Home Assistant to reload configuration
kubectl rollout restart deployment home-assistant -n home-automation
```

## Operational Procedures

### Deployment and Upgrade Procedures

#### Initial Deployment
```bash
# Deploy via GitOps (automatic via Flux)
git add apps/home-automation/
git commit -m "Deploy Home Assistant stack"
git push

# Monitor deployment
flux get kustomizations --watch
kubectl get pods -n home-automation -w
```

#### Component Upgrades
```bash
# Update Home Assistant version
kubectl patch deployment home-assistant -n home-automation -p='
spec:
  template:
    spec:
      containers:
      - name: home-assistant
        image: ghcr.io/home-assistant/home-assistant:2025.8
'

# Update PostgreSQL version (via CNPG operator)
kubectl patch cluster homeassistant-postgresql -n home-automation -p='
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:16.5
'
```

### Monitoring and Health Checks

#### Service Health Monitoring
```bash
# Check all pods status
kubectl get pods -n home-automation

# Check service endpoints
kubectl get endpoints -n home-automation

# Check persistent volumes
kubectl get pvc -n home-automation

# Check database cluster status
kubectl get cluster homeassistant-postgresql -n home-automation
```

#### Application-Level Health Checks
```bash
# Home Assistant health check
curl -f http://home-assistant.home-automation.svc.cluster.local:8123/

# MQTT broker health check
kubectl exec -n home-automation deployment/mosquitto -- \
  mosquitto_pub -h localhost -t test/health -m "ok"

# PostgreSQL health check
kubectl exec -n home-automation homeassistant-postgresql-1 -- \
  pg_isready -h localhost -p 5432
```

#### Monitoring Integration
- **Prometheus Metrics**: All components expose metrics for monitoring
- **Grafana Dashboards**: Pre-configured dashboards for stack monitoring
- **Alerting**: Automated alerts for service failures and resource issues

### Backup and Recovery Procedures

#### Database Backup and Recovery
```bash
# Manual database backup
kubectl exec -n home-automation homeassistant-postgresql-1 -- \
  pg_dump -h localhost -U postgres homeassistant > homeassistant-backup.sql

# Database recovery (see BACKUP_STRATEGY.md for detailed procedures)
kubectl apply -f recovery-cluster.yaml
```

#### Volume Backup and Recovery
```bash
# Create manual snapshot
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: home-assistant-config-manual
  namespace: home-automation
spec:
  source:
    persistentVolumeClaimName: home-assistant-config
  volumeSnapshotClassName: longhorn-snapshot-vsc
EOF

# Restore from snapshot (see BACKUP_STRATEGY.md for procedures)
```

### Troubleshooting Common Issues

#### Home Assistant Won't Start
```bash
# Check pod logs
kubectl logs -n home-automation -l app.kubernetes.io/name=home-assistant

# Common issues:
# - Configuration syntax errors
# - Database connection failures
# - Missing secrets or environment variables

# Validate configuration
kubectl exec -n home-automation deployment/home-assistant -- \
  python -m homeassistant --script check_config --config /config
```

#### Database Connection Issues
```bash
# Check PostgreSQL cluster status
kubectl get cluster homeassistant-postgresql -n home-automation -o yaml

# Check database connectivity
kubectl exec -n home-automation deployment/home-assistant -- \
  pg_isready -h homeassistant-postgresql-rw.home-automation.svc.cluster.local -p 5432

# Check credentials
kubectl get secret homeassistant-database-credentials -n home-automation -o yaml
```

#### MQTT Communication Problems
```bash
# Check Mosquitto logs
kubectl logs -n home-automation -l app.kubernetes.io/name=mosquitto

# Test MQTT connectivity
kubectl exec -n home-automation deployment/mosquitto -- \
  mosquitto_sub -h localhost -t '#' -v

# Check authentication
kubectl get secret mosquitto-credentials -n home-automation -o yaml
```

#### Authentication Issues
```bash
# Check Authentik proxy configuration
kubectl logs -n authentik-proxy -l app.kubernetes.io/name=authentik-proxy

# Verify proxy provider configuration
kubectl exec -n home-automation deployment/home-assistant -- \
  curl -I http://authentik-server.authentik.svc.cluster.local/api/v3/providers/proxy/

# Test authentication flow
curl -I https://homeassistant.k8s.home.geoffdavis.com
```

## Security Considerations

### 1Password Integration for Secrets

All sensitive configuration is managed through 1Password Connect:

#### Secret Categories
- **Database Credentials**: PostgreSQL username/password
- **MQTT Credentials**: Mosquitto broker authentication
- **API Keys**: Weather, Google, and other service integrations
- **Location Data**: Home coordinates and elevation
- **Security Keys**: Home Assistant secret key for encryption

#### Secret Synchronization
```yaml
# ExternalSecret automatically syncs from 1Password
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: home-assistant-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: onepassword-connect
    kind: ClusterSecretStore
```

### Network Security and Isolation

#### Pod Security Standards
- **Security Context**: Non-root execution, read-only root filesystem where possible
- **Capabilities**: All unnecessary capabilities dropped
- **Seccomp**: Runtime default seccomp profile applied
- **Network Policies**: Restricted inter-pod communication

#### Network Segmentation
- **Namespace Isolation**: Dedicated `home-automation` namespace
- **Service Mesh**: Cilium CNI provides network security
- **Ingress Control**: Only authorized traffic via Authentik proxy
- **Internal Communication**: Cluster DNS for service-to-service communication

### TLS Encryption and Certificates

#### Certificate Management
- **Cert-Manager**: Automated certificate provisioning and renewal
- **Let's Encrypt**: Free TLS certificates for external access
- **Internal CA**: Cluster-generated certificates for internal communication
- **PostgreSQL TLS**: Database connections encrypted with TLS

#### Encryption in Transit
- **HTTPS**: All external communication encrypted
- **Database TLS**: PostgreSQL connections use TLS encryption
- **MQTT TLS**: Secure MQTT available on port 8883
- **Internal Services**: Service-to-service communication secured

### Pod Security Standards

All components follow restricted pod security standards:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault

containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true  # where possible
  capabilities:
    drop:
      - ALL
```

## Development & Customization

### Adding Custom Integrations

#### Custom Component Installation
```bash
# Method 1: Via Home Assistant web interface
# 1. Navigate to Settings → Add-ons → Add-on Store
# 2. Install "File editor" or "Studio Code Server" add-on
# 3. Create custom_components directory
# 4. Add custom integration files

# Method 2: Via kubectl
kubectl exec -it -n home-automation deployment/home-assistant -- \
  mkdir -p /config/custom_components/my_integration

kubectl cp ./my_integration/ home-automation/home-assistant-pod:/config/custom_components/
```

#### Custom Component Development
```python
# Example custom component structure
/config/custom_components/my_integration/
├── __init__.py          # Component initialization
├── manifest.json        # Component metadata
├── config_flow.py       # Configuration flow
├── sensor.py           # Sensor platform
└── services.yaml       # Service definitions
```

### Modifying Component Configurations

#### PostgreSQL Tuning
```yaml
# Update PostgreSQL parameters in cluster.yaml
postgresql:
  parameters:
    max_connections: "200"
    shared_buffers: "256MB"
    effective_cache_size: "1GB"
```

#### MQTT Broker Configuration
```yaml
# Update Mosquitto configuration in configmap.yaml
mosquitto.conf: |
  persistence true
  persistence_location /mosquitto/data/
  log_dest stdout
  log_type all
  connection_messages true
  log_timestamp true
  allow_anonymous false
  password_file /mosquitto/config/passwd
```

#### Redis Configuration
```yaml
# Update Redis configuration for performance
redis.conf: |
  maxmemory 256mb
  maxmemory-policy allkeys-lru
  save 900 1
  save 300 10
  save 60 10000
```

### Scaling Considerations

#### Horizontal Scaling Limitations
- **Home Assistant**: Single replica only (stateful application)
- **PostgreSQL**: Single instance (can be scaled with CNPG)
- **Mosquitto**: Single replica (MQTT broker clustering complex)
- **Redis**: Single instance (clustering available but not configured)

#### Vertical Scaling
```yaml
# Increase Home Assistant resources
resources:
  requests:
    cpu: 1000m
    memory: 2Gi
  limits:
    cpu: 4000m
    memory: 8Gi
```

#### Storage Scaling
```bash
# Expand persistent volume
kubectl patch pvc home-assistant-config -n home-automation -p='
spec:
  resources:
    requests:
      storage: 20Gi
'
```

### Integration with Other Cluster Services

#### Monitoring Integration
```yaml
# ServiceMonitor for Prometheus scraping
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: home-assistant
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: home-assistant
  endpoints:
  - port: http
    path: /api/prometheus
```

#### Backup Integration
```yaml
# Longhorn recurring job for automated backups
apiVersion: longhorn.io/v1beta1
kind: RecurringJob
metadata:
  name: home-assistant-backup
spec:
  cron: "0 2 * * *"
  task: "backup"
  groups:
  - home-automation
  retain: 7
```

#### Service Mesh Integration
```yaml
# Cilium Network Policy for micro-segmentation
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: home-assistant-policy
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: home-assistant
  ingress:
  - fromEndpoints:
    - matchLabels:
        app.kubernetes.io/name: authentik-proxy
```

---

## Quick Reference

### Important URLs
- **Home Assistant**: https://homeassistant.k8s.home.geoffdavis.com
- **Internal Service**: http://home-assistant.home-automation.svc.cluster.local:8123

### Key Commands
```bash
# Check stack status
kubectl get pods -n home-automation

# View Home Assistant logs
kubectl logs -n home-automation -l app.kubernetes.io/name=home-assistant

# Access Home Assistant shell
kubectl exec -it -n home-automation deployment/home-assistant -- bash

# Restart Home Assistant
kubectl rollout restart deployment home-assistant -n home-automation

# Check database status
kubectl get cluster homeassistant-postgresql -n home-automation
```

### Configuration Files
- **Main Config**: [`home-assistant/configmap.yaml`](home-assistant/configmap.yaml)
- **Secrets**: [`home-assistant/external-secret.yaml`](home-assistant/external-secret.yaml)
- **Deployment**: [`home-assistant/deployment.yaml`](home-assistant/deployment.yaml)
- **Backup Strategy**: [`BACKUP_STRATEGY.md`](BACKUP_STRATEGY.md)

### Support Resources
- **Home Assistant Documentation**: https://www.home-assistant.io/docs/
- **CNPG Documentation**: https://cloudnative-pg.io/documentation/
- **Mosquitto Documentation**: https://mosquitto.org/documentation/
- **Cluster Documentation**: [`../../docs/`](../../docs/)

This documentation provides comprehensive coverage of the Home Assistant stack deployment, from architecture overview to detailed operational procedures. For additional information about cluster operations, backup procedures, or troubleshooting, refer to the linked documentation files and the broader cluster documentation in the `docs/` directory.