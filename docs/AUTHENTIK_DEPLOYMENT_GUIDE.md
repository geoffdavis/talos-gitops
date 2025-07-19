# Authentik Deployment Guide

## Overview

This guide provides comprehensive instructions for deploying and managing Authentik with PostgreSQL in your Talos Kubernetes cluster. Authentik serves as the identity provider with RADIUS support for WiFi authentication and OIDC/SAML integration for applications.

## Architecture

### Components
- **Authentik Server**: Main identity provider application (2 replicas)
- **Authentik Worker**: Background task processor (1 replica)
- **Authentik RADIUS**: RADIUS server for WiFi authentication (2 replicas)
- **Redis**: Session and cache storage (built-in, 1 replica)
- **PostgreSQL Cluster**: Database backend (CNPG, 3 replicas)
- **Ingress**: HTTPS access via nginx-internal
- **External Secrets**: 1Password integration for credentials

### Network Architecture
```
Internet → Cloudflare Tunnel → Internal Ingress → Authentik Server
WiFi Clients → RADIUS LoadBalancer → Authentik RADIUS → Authentik Server
Applications → OIDC/SAML → Authentik Server → PostgreSQL Cluster
```

## Prerequisites

### Required Components
- ✅ Talos Kubernetes cluster (v1.28+)
- ✅ CNPG Operator deployed
- ✅ External Secrets Operator deployed
- ✅ 1Password Connect configured
- ✅ Ingress NGINX (internal) deployed
- ✅ Cert-manager deployed
- ✅ Longhorn storage deployed

### Required 1Password Secrets

#### 1. Authentik Configuration (`Authentik Configuration - home-ops`)
Create in **Automation** vault:
```
Title: Authentik Configuration - home-ops
Fields:
  secret_key: [Generate 50-character random string]
  smtp_host: smtp.gmail.com
  smtp_port: 587
  smtp_username: your-email@gmail.com
  smtp_password: [App-specific password]
  smtp_use_tls: true
  smtp_from: your-email@gmail.com
  radius_shared_secret: [Generate 32-character random string]
```

#### 2. PostgreSQL User (`PostgreSQL User - authentik - home-ops`)
Create in **Automation** vault:
```
Title: PostgreSQL User - authentik - home-ops
Fields:
  username: authentik
  password: [Generate 32-character random password]
```

#### 3. PostgreSQL Superuser (`PostgreSQL Superuser - home-ops`)
Create in **Automation** vault:
```
Title: PostgreSQL Superuser - home-ops
Fields:
  username: postgres
  password: [Generate 32-character random password]
```

#### 4. PostgreSQL S3 Backup (`PostgreSQL S3 Backup - home-ops`)
Create in **Automation** vault:
```
Title: PostgreSQL S3 Backup - home-ops
Fields:
  AWS_ACCESS_KEY_ID: [Longhorn S3 access key]
  AWS_SECRET_ACCESS_KEY: [Longhorn S3 secret key]
  AWS_DEFAULT_REGION: us-east-1
  AWS_ENDPOINT_URL: http://longhorn-s3-gateway.longhorn-system.svc.cluster.local
```

## Deployment Process

### Step 1: Verify Prerequisites

```bash
# Run the verification script
./scripts/verify-authentik-deployment.sh

# Check specific prerequisites
kubectl get namespace cnpg-system
kubectl get namespace external-secrets-system
kubectl get clustersecretstore onepassword-connect
```

### Step 2: Deploy PostgreSQL Cluster

```bash
# Deploy PostgreSQL cluster with CNPG
kubectl apply -k infrastructure/postgresql-cluster/

# Wait for cluster to be ready
kubectl wait --for=condition=Ready cluster/postgresql-cluster -n postgresql-system --timeout=600s

# Verify cluster status
kubectl get cluster -n postgresql-system postgresql-cluster
kubectl get pods -n postgresql-system -l postgresql=postgresql-cluster
```

### Step 3: Deploy Authentik

```bash
# Deploy Authentik components
kubectl apply -k infrastructure/authentik/

# Monitor deployment progress
kubectl get helmrelease -n authentik authentik -w

# Check pod status
kubectl get pods -n authentik
```

### Step 4: Verify Deployment

```bash
# Run comprehensive verification
./scripts/verify-authentik-deployment.sh

# Check specific components
kubectl get all -n authentik
kubectl get ingress -n authentik
kubectl get externalsecrets -n authentik
```

## Access Methods

### Web Interface

#### Method 1: Internal Network (Recommended)
```bash
# Access via internal domain
https://authentik.k8s.home.geoffdavis.com

# Requires DNS configuration:
# - Router DNS override: authentik.k8s.home.geoffdavis.com → 172.29.51.200
# - Or /etc/hosts: 172.29.51.200 authentik.k8s.home.geoffdavis.com
```

#### Method 2: Port Forward (Testing)
```bash
# Port forward to ingress controller
kubectl port-forward -n ingress-nginx-internal svc/ingress-nginx-internal-controller 8443:443

# Access via: https://localhost:8443
# Add Host header: authentik.k8s.home.geoffdavis.com
```

#### Method 3: NodePort (Fallback)
```bash
# Find NodePort
kubectl get svc -n ingress-nginx-internal ingress-nginx-internal-controller

# Access via: https://<node-ip>:<nodeport>
# Add Host header: authentik.k8s.home.geoffdavis.com
```

### Initial Login

**Default Credentials** (Bootstrap):
- **Username**: `admin@k8s.home.geoffdavis.com`
- **Password**: `changeme-bootstrap-password`

⚠️ **Important**: Change these credentials immediately after first login!

## RADIUS Configuration

### RADIUS Service Details
- **Service Type**: LoadBalancer (Cilium)
- **Authentication Port**: 1812/UDP
- **Accounting Port**: 1813/UDP
- **Shared Secret**: From 1Password (`radius_shared_secret`)

### WiFi Integration

#### UniFi Configuration
1. Navigate to **Settings** → **Profiles** → **RADIUS**
2. Create new RADIUS profile:
   ```
   Name: Authentik RADIUS
   Auth Server: <radius-loadbalancer-ip>
   Auth Port: 1812
   Auth Secret: <radius_shared_secret>
   Accounting Server: <radius-loadbalancer-ip>
   Accounting Port: 1813
   Accounting Secret: <radius_shared_secret>
   ```

#### WiFi Network Setup
1. Create new WiFi network
2. Security: WPA2/WPA3 Enterprise
3. RADIUS Profile: Authentik RADIUS
4. VLAN: Configure as needed

### RADIUS Client Configuration

```bash
# Get RADIUS service IP
kubectl get svc -n authentik authentik-radius

# Test RADIUS connectivity (requires radtest)
radtest username password <radius-ip> 1812 <shared-secret>
```

## OIDC/SAML Integration

### Creating OIDC Application

1. Login to Authentik web interface
2. Navigate to **Applications** → **Applications**
3. Click **Create**
4. Configure:
   ```
   Name: My Application
   Slug: my-application
   Provider: Create new OAuth2/OpenID Provider
   ```

5. Provider Configuration:
   ```
   Authorization flow: default-authorization-flow
   Client type: Confidential
   Client ID: <auto-generated>
   Client Secret: <auto-generated>
   Redirect URIs: https://myapp.example.com/auth/callback
   Signing Key: authentik Self-signed Certificate
   ```

### OIDC Integration Example

```yaml
# Example application configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-oidc-config
data:
  OIDC_ISSUER: "https://authentik.k8s.home.geoffdavis.com/application/o/my-application/"
  OIDC_CLIENT_ID: "your-client-id"
  OIDC_REDIRECT_URI: "https://myapp.example.com/auth/callback"
```

### SAML Integration

1. Create SAML Provider:
   ```
   ACS URL: https://myapp.example.com/saml/acs
   Issuer: https://authentik.k8s.home.geoffdavis.com
   Service Provider Binding: Post
   Audience: myapp
   ```

2. Download metadata:
   ```bash
   curl -o metadata.xml https://authentik.k8s.home.geoffdavis.com/application/saml/my-app/metadata/
   ```

## Backup and Recovery

### Automated Backups

#### PostgreSQL Backups
- **Schedule**: Daily at 3 AM
- **Retention**: 30 days
- **Method**: CNPG barman with S3 storage
- **Location**: Longhorn S3 gateway

#### Longhorn Volume Snapshots
- **Schedule**: Daily at 1 AM (before PostgreSQL backup)
- **Retention**: 7 daily snapshots
- **Weekly**: Sunday at 4 AM, 8 weeks retention

### Manual Backup

```bash
# Create immediate PostgreSQL backup
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: authentik-manual-backup-$(date +%Y%m%d-%H%M%S)
  namespace: postgresql-system
spec:
  cluster:
    name: postgresql-cluster
  method: barmanObjectStore
EOF

# Create Longhorn volume snapshot
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: authentik-redis-snapshot-$(date +%Y%m%d-%H%M%S)
  namespace: authentik
spec:
  source:
    persistentVolumeClaimName: redis-data-authentik-redis-master-0
  volumeSnapshotClassName: longhorn-snapshot-vsc
EOF
```

### Recovery Procedures

#### PostgreSQL Point-in-Time Recovery
```bash
# Create new cluster from backup
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgresql-cluster-recovery
  namespace: postgresql-system
spec:
  instances: 3
  bootstrap:
    recovery:
      source: postgresql-cluster
      recoveryTarget:
        targetTime: "2024-01-15 10:00:00"
  externalClusters:
    - name: postgresql-cluster
      barmanObjectStore:
        destinationPath: "s3://longhorn-backup/postgresql-cluster"
        s3Credentials:
          accessKeyId:
            name: postgresql-s3-backup-credentials
            key: AWS_ACCESS_KEY_ID
          secretAccessKey:
            name: postgresql-s3-backup-credentials
            key: AWS_SECRET_ACCESS_KEY
EOF
```

#### Volume Restore from Snapshot
```bash
# Restore PVC from snapshot
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: redis-data-restored
  namespace: authentik
spec:
  storageClassName: longhorn-ssd
  dataSource:
    name: authentik-redis-snapshot-20240115-100000
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
```

## Monitoring and Observability

### Metrics Collection
- **Prometheus**: ServiceMonitor configured for Authentik server
- **Grafana**: Dashboard available (see monitoring-dashboard.yaml)
- **Alerts**: PrometheusRule for critical conditions

### Key Metrics
- `authentik_admin_workers_total`: Worker process count
- `authentik_events_total`: Authentication events
- `authentik_outpost_last_update`: RADIUS outpost health
- `postgresql_up`: Database availability

### Health Checks

```bash
# Authentik server health
kubectl exec -n authentik deployment/authentik-server -- curl -f http://localhost:9000/-/health/live/

# RADIUS health
kubectl exec -n authentik deployment/authentik-radius -- curl -f http://localhost:9300/outpost.goauthentik.io/ping

# PostgreSQL health
kubectl exec -n postgresql-system postgresql-cluster-1 -- pg_isready
```

### Log Analysis

```bash
# Authentik server logs
kubectl logs -n authentik -l app.kubernetes.io/name=authentik,app.kubernetes.io/component=server

# RADIUS logs
kubectl logs -n authentik -l app.kubernetes.io/name=authentik-radius

# PostgreSQL logs
kubectl logs -n postgresql-system -l postgresql=postgresql-cluster

# External secrets logs
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets
```

## Troubleshooting

### Common Issues

#### 1. External Secrets Not Syncing
**Symptoms**: ExternalSecret shows `SecretSyncError`

**Diagnosis**:
```bash
kubectl describe externalsecret -n authentik authentik-config
kubectl logs -n onepassword-connect deployment/onepassword-connect
```

**Solutions**:
- Verify 1Password item names match exactly
- Check 1Password Connect token validity
- Ensure vault permissions are correct

#### 2. Database Connection Failures
**Symptoms**: Authentik pods crash with database errors

**Diagnosis**:
```bash
kubectl logs -n authentik deployment/authentik-server
kubectl get cluster -n postgresql-system postgresql-cluster
```

**Solutions**:
- Verify PostgreSQL cluster is healthy
- Check database credentials in external secrets
- Ensure database initialization job completed

#### 3. RADIUS Authentication Failures
**Symptoms**: WiFi clients cannot authenticate

**Diagnosis**:
```bash
kubectl logs -n authentik deployment/authentik-radius
kubectl get svc -n authentik authentik-radius
```

**Solutions**:
- Verify RADIUS shared secret matches
- Check LoadBalancer IP assignment
- Ensure RADIUS outpost is connected to Authentik

#### 4. Ingress Access Issues
**Symptoms**: Cannot access Authentik web interface

**Diagnosis**:
```bash
kubectl get ingress -n authentik
kubectl get pods -n ingress-nginx-internal
kubectl describe certificate -n authentik authentik-tls-certificate
```

**Solutions**:
- Verify DNS resolution
- Check TLS certificate status
- Ensure ingress controller is running

### Emergency Procedures

#### Reset Authentik Admin Password
```bash
# Access Authentik server pod
kubectl exec -it -n authentik deployment/authentik-server -- /bin/bash

# Reset admin password
python manage.py shell -c "
from authentik.core.models import User
user = User.objects.get(username='akadmin')
user.set_password('new-secure-password')
user.save()
"
```

#### Force PostgreSQL Failover
```bash
# Promote replica to primary (if primary fails)
kubectl patch cluster -n postgresql-system postgresql-cluster --type='merge' -p='{"spec":{"switchoverTo":"postgresql-cluster-2"}}'
```

#### Restart All Components
```bash
# Restart Authentik components
kubectl rollout restart deployment -n authentik authentik-server
kubectl rollout restart deployment -n authentik authentik-worker
kubectl rollout restart deployment -n authentik authentik-radius

# Restart PostgreSQL (rolling restart)
kubectl delete pod -n postgresql-system -l postgresql=postgresql-cluster
```

## Security Considerations

### Network Security
- Authentik web interface accessible only via internal ingress
- RADIUS service exposed via LoadBalancer (required for WiFi)
- PostgreSQL accessible only within cluster
- TLS encryption for all web traffic

### Authentication Security
- Strong password policies enforced
- MFA support available
- Session management with Redis
- RADIUS shared secret rotation

### Data Protection
- Database encryption at rest (Longhorn)
- Backup encryption (S3)
- Secret management via 1Password
- Network policies (recommended)

## Operational Procedures

### Regular Maintenance

#### Weekly Tasks
```bash
# Check backup status
kubectl get backup -n postgresql-system
kubectl get recurringjob -n longhorn-system

# Verify external secrets sync
kubectl get externalsecrets -A

# Review security logs
kubectl logs -n authentik -l app.kubernetes.io/name=authentik --since=168h | grep -i "failed\|error\|unauthorized"
```

#### Monthly Tasks
```bash
# Update Authentik version (if needed)
# Edit infrastructure/authentik/kustomization.yaml
# Update image tags and commit changes

# Rotate RADIUS shared secret
# Update in 1Password and restart RADIUS deployment

# Review user access and permissions
# Access Authentik admin interface and audit users
```

### Scaling Operations

#### Scale Authentik Components
```bash
# Scale server replicas
kubectl scale deployment -n authentik authentik-server --replicas=3

# Scale RADIUS replicas
kubectl scale deployment -n authentik authentik-radius --replicas=3
```

#### Scale PostgreSQL Cluster
```bash
# Edit cluster specification
kubectl patch cluster -n postgresql-system postgresql-cluster --type='merge' -p='{"spec":{"instances":5}}'
```

## Integration Examples

### Grafana OIDC Integration
```yaml
# Grafana values.yaml excerpt
grafana:
  grafana.ini:
    auth.generic_oauth:
      enabled: true
      name: Authentik
      client_id: grafana-client-id
      client_secret: grafana-client-secret
      scopes: openid profile email
      auth_url: https://authentik.k8s.home.geoffdavis.com/application/o/authorize/
      token_url: https://authentik.k8s.home.geoffdavis.com/application/o/token/
      api_url: https://authentik.k8s.home.geoffdavis.com/application/o/userinfo/
      allow_sign_up: true
      role_attribute_path: contains(groups[*], 'Grafana Admins') && 'Admin' || 'Viewer'
```

### Longhorn OIDC Integration
```yaml
# Longhorn settings
auth:
  type: oidc
  oidc:
    issuer: https://authentik.k8s.home.geoffdavis.com/application/o/longhorn/
    clientId: longhorn-client-id
    clientSecret: longhorn-client-secret
    scopes: openid profile email groups
```

## Verification Commands

```bash
# Complete deployment verification
./scripts/verify-authentik-deployment.sh

# Quick health check
kubectl get pods -n authentik
kubectl get pods -n postgresql-system
kubectl get externalsecrets -A

# Test backup functionality
./scripts/authentik-backup-test.sh

# Network connectivity test
kubectl run test-pod --image=busybox --rm -it -- /bin/sh
# From inside pod: nslookup authentik-server.authentik.svc.cluster.local
```

---

**Cluster**: home-ops  
**Identity Provider**: Authentik v2024.8.3  
**Database**: PostgreSQL 16.4 (CNPG)  
**Storage**: Longhorn SSD  
**Backup**: S3 + Longhorn Snapshots