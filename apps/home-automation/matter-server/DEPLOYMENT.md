# Matter Server Deployment Guide

This guide provides comprehensive procedures for deploying the Matter Server integration within the Home Assistant stack on the Talos GitOps cluster.

## Overview

The Matter Server provides Thread/Matter device support for Home Assistant, enabling commissioning and control of Matter-compatible IoT devices. This deployment integrates with the existing Home Assistant stack using host networking for optimal device discovery and communication.

## Architecture

- **Container**: `ghcr.io/home-assistant-libs/python-matter-server:8.0.0`
- **Networking**: Host networking for Thread/Matter device discovery
- **Storage**: Persistent volume for certificates and device data (5GB Longhorn)
- **Integration**: WebSocket connection to Home Assistant (`ws://localhost:5580/ws`)
- **Security**: Privileged mode with NET_ADMIN, NET_RAW, SYS_ADMIN capabilities
- **Interface**: Uses `enp3s0f0` network interface on Mac mini nodes

## Pre-deployment Checklist

### Infrastructure Prerequisites

Before deploying the Matter Server, verify the following infrastructure components are operational:

#### 1. Home Assistant Stack Health

```bash
# Verify Home Assistant stack is running
kubectl get pods -n home-automation

# Expected output: All pods should be Running (1/1 Ready)
# - home-assistant-xxx
# - homeassistant-postgresql-xxx
# - mosquitto-xxx  
# - redis-xxx

# Check Home Assistant web interface accessibility
curl -I https://homeassistant.k8s.home.geoffdavis.com
# Expected: HTTP/2 200 or redirect to authentication
```

#### 2. Storage System Validation

```bash
# Verify Longhorn storage system is operational
kubectl get pods -n longhorn-system | grep -E "(longhorn-manager|longhorn-driver)"

# Check available storage capacity
kubectl get nodes -o custom-columns="NAME:.metadata.name,STORAGE:.status.allocatable.storage"

# Verify storage class exists
kubectl get storageclass longhorn
# Expected: longhorn storage class should exist and be available
```

#### 3. Network Infrastructure

```bash
# Verify network interface exists on nodes
kubectl get nodes -o wide

# Check network interface on each node (replace NODE_NAME)
kubectl debug node/NODE_NAME -it --image=busybox -- ip addr show enp3s0f0
# Expected: Interface should exist and have IP address assigned

# Verify host networking support
kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'
```

#### 4. Authentication System

```bash
# Verify external Authentik outpost is operational
kubectl get pods -n authentik-proxy
kubectl get ingress -n authentik-proxy

# Test Home Assistant authentication flow
curl -I https://homeassistant.k8s.home.geoffdavis.com
# Expected: Proper redirect to Authentik authentication
```

### Configuration Validation

#### 1. Helm Repository Access

```bash
# Verify Helm repository is available
kubectl get helmrepository -n flux-system charts-derwitt-dev

# Check repository sync status
flux get sources helm -n flux-system
# Expected: charts-derwitt-dev should show "stored artifact for revision"
```

#### 2. Namespace and RBAC

```bash
# Verify home-automation namespace exists
kubectl get namespace home-automation

# Check namespace security policies
kubectl get namespace home-automation -o yaml | grep -A 5 labels
# Expected: Should have privileged PodSecurity policy for s6-overlay compatibility
```

#### 3. Home Assistant Configuration

```bash
# Verify Home Assistant configuration includes Matter integration
kubectl get configmap -n home-automation home-assistant-configuration -o yaml | grep -A 5 matter
# Expected: Should show Matter server WebSocket configuration
```

## Step-by-Step Deployment

### Phase 1: Pre-deployment Validation

#### 1. Verify Prerequisites

Run the complete pre-deployment checklist above. All checks must pass before proceeding.

#### 2. Review Configuration

```bash
# Review Matter Server Helm configuration
cat apps/home-automation/matter-server/helmrelease.yaml

# Verify network interface configuration matches cluster nodes
grep -A 2 "networkInterface" apps/home-automation/matter-server/helmrelease.yaml
# Expected: Should show "enp3s0f0" for Mac mini nodes
```

#### 3. Check Resource Availability

```bash
# Verify sufficient resources available on nodes
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check for existing Matter Server deployment (should not exist)
kubectl get pods -n home-automation -l app.kubernetes.io/name=matter-server
# Expected: No resources found (clean deployment)
```

### Phase 2: Matter Server Deployment

#### 1. Deploy Matter Server

```bash
# Deploy the complete home-automation stack (includes Matter Server)
kubectl apply -k apps/home-automation/

# Alternative: Deploy only Matter Server component
kubectl apply -k apps/home-automation/matter-server/
```

#### 2. Monitor Deployment Progress

```bash
# Watch Matter Server pod creation
kubectl get pods -n home-automation -l app.kubernetes.io/name=matter-server -w

# Monitor Helm release status
kubectl get helmrelease -n home-automation matter-server -w

# Check Flux reconciliation
flux get helmreleases -n home-automation
```

#### 3. Verify Initial Deployment

```bash
# Check pod status (should reach Running state)
kubectl get pods -n home-automation -l app.kubernetes.io/name=matter-server

# Expected output:
# NAME                            READY   STATUS    RESTARTS   AGE
# matter-server-xxxxxxxxx-xxxxx   1/1     Running   0          2m

# Verify service creation
kubectl get svc -n home-automation matter-server
# Expected: ClusterIP service on port 5580
```

### Phase 3: Integration Validation

#### 1. Verify Matter Server Health

```bash
# Check Matter Server logs for successful startup
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server --tail=50

# Expected log entries:
# - "Matter server starting"
# - "WebSocket server started on port 5580"
# - "Matter server ready"
# - No error messages about network interface or permissions
```

#### 2. Test WebSocket Endpoint

```bash
# Test WebSocket endpoint accessibility
kubectl exec -n home-automation deployment/home-assistant -- \
  curl -I --http1.1 --upgrade WebSocket http://localhost:5580/ws

# Expected: HTTP/1.1 101 Switching Protocols (WebSocket upgrade successful)
```

#### 3. Verify Host Networking

```bash
# Check that Matter Server pod has host networking
kubectl get pod -n home-automation -l app.kubernetes.io/name=matter-server -o yaml | grep hostNetwork
# Expected: hostNetwork: true

# Verify network interface access
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ip addr show enp3s0f0
# Expected: Should show network interface with IP address
```

#### 4. Validate Storage

```bash
# Check persistent volume claim
kubectl get pvc -n home-automation | grep matter-server
# Expected: matter-server-data should be Bound

# Verify storage mount
kubectl describe pod -n home-automation -l app.kubernetes.io/name=matter-server | grep -A 5 Mounts
# Expected: Should show /data mount point
```

### Phase 4: Home Assistant Integration

#### 1. Restart Home Assistant

```bash
# Restart Home Assistant to pick up Matter integration
kubectl rollout restart deployment home-assistant -n home-automation

# Monitor restart progress
kubectl rollout status deployment home-assistant -n home-automation
```

#### 2. Verify Matter Integration

```bash
# Check Home Assistant logs for Matter integration
kubectl logs -n home-automation -l app.kubernetes.io/name=home-assistant --tail=100 | grep -i matter

# Expected log entries:
# - "Setting up Matter integration"
# - "Matter WebSocket connected"
# - "Matter integration setup complete"
```

#### 3. Test Web Interface Access

```bash
# Test Home Assistant web interface
curl -I https://homeassistant.k8s.home.geoffdavis.com

# Access via browser and verify Matter integration appears in:
# Settings → Devices & Services → Integrations
# Should show "Matter (BETA)" integration as configured
```

## Verification Procedures

### Deployment Health Checks

#### 1. Pod Health Verification

```bash
# Comprehensive pod status check
kubectl get pods -n home-automation -l app.kubernetes.io/name=matter-server -o wide

# Check pod events for any issues
kubectl describe pod -n home-automation -l app.kubernetes.io/name=matter-server

# Verify resource usage
kubectl top pods -n home-automation -l app.kubernetes.io/name=matter-server
```

#### 2. Service Connectivity Tests

```bash
# Test service endpoint from within cluster
kubectl run test-matter-connectivity --rm -i --tty --image=busybox --restart=Never -- \
  wget -qO- http://matter-server.home-automation.svc.cluster.local:5580/

# Test WebSocket connectivity from Home Assistant pod
kubectl exec -n home-automation deployment/home-assistant -- \
  python3 -c "
import websocket
try:
    ws = websocket.create_connection('ws://localhost:5580/ws', timeout=5)
    print('WebSocket connection successful')
    ws.close()
except Exception as e:
    print(f'WebSocket connection failed: {e}')
"
```

#### 3. Network Interface Validation

```bash
# Verify network interface configuration
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ip route show

# Check Bluetooth availability (if enabled)
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  hciconfig -a 2>/dev/null || echo "Bluetooth not available"

# Test network connectivity to local subnet
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ping -c 3 172.29.51.1
```

### Integration Testing

#### 1. Home Assistant Matter Integration

```bash
# Check Matter integration status in Home Assistant
kubectl exec -n home-automation deployment/home-assistant -- \
  python3 -c "
import requests
import json
try:
    # This would require HA API token - manual verification recommended
    print('Manual verification required via web interface')
    print('Navigate to Settings → Devices & Services → Integrations')
    print('Verify Matter (BETA) integration is present and configured')
except Exception as e:
    print(f'API check failed: {e}')
"
```

#### 2. WebSocket Communication Test

```bash
# Monitor WebSocket traffic (run in separate terminal)
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server -f &

# Restart Home Assistant to trigger WebSocket reconnection
kubectl rollout restart deployment home-assistant -n home-automation

# Look for WebSocket connection logs in Matter Server
# Expected: "WebSocket client connected" messages
```

#### 3. Storage Persistence Test

```bash
# Create test file in Matter Server storage
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  touch /data/deployment-test-$(date +%s)

# Restart Matter Server pod
kubectl delete pod -n home-automation -l app.kubernetes.io/name=matter-server

# Wait for pod to restart and verify file persistence
kubectl wait --for=condition=Ready pod -n home-automation -l app.kubernetes.io/name=matter-server --timeout=300s

kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ls -la /data/deployment-test-*
# Expected: Test file should still exist
```

## Rollback Procedures

### Emergency Rollback

If the Matter Server deployment fails or causes issues with the Home Assistant stack:

#### 1. Immediate Rollback

```bash
# Remove Matter Server deployment
kubectl delete -k apps/home-automation/matter-server/

# Verify removal
kubectl get pods -n home-automation -l app.kubernetes.io/name=matter-server
# Expected: No resources found

# Restart Home Assistant to remove Matter integration
kubectl rollout restart deployment home-assistant -n home-automation
```

#### 2. Clean Up Resources

```bash
# Remove persistent volume claim (WARNING: This deletes Matter certificates and device data)
kubectl delete pvc -n home-automation matter-server-data

# Remove any remaining resources
kubectl delete all -n home-automation -l app.kubernetes.io/name=matter-server

# Verify cleanup
kubectl get all -n home-automation -l app.kubernetes.io/name=matter-server
# Expected: No resources found
```

#### 3. Restore Home Assistant Configuration

```bash
# If Home Assistant configuration was modified, restore from backup
# This step depends on your backup strategy

# Verify Home Assistant functionality without Matter
curl -I https://homeassistant.k8s.home.geoffdavis.com
# Expected: Home Assistant should be accessible and functional
```

### Partial Rollback (Configuration Only)

If only configuration changes need to be reverted:

#### 1. Revert Helm Configuration

```bash
# Edit Helm release to previous working configuration
kubectl edit helmrelease -n home-automation matter-server

# Or revert to previous Git commit
git revert <commit-hash>
git push

# Monitor Flux reconciliation
flux get helmreleases -n home-automation matter-server
```

#### 2. Restart Services

```bash
# Restart Matter Server with new configuration
kubectl rollout restart deployment matter-server -n home-automation

# Restart Home Assistant if needed
kubectl rollout restart deployment home-assistant -n home-automation
```

## Post-deployment Tasks

### Configuration Validation

#### 1. Verify Complete Stack Health

```bash
# Check all home-automation pods
kubectl get pods -n home-automation

# Expected: All pods Running (1/1 Ready)
# - home-assistant-xxx
# - homeassistant-postgresql-xxx  
# - mosquitto-xxx
# - redis-xxx
# - matter-server-xxx

# Check services
kubectl get svc -n home-automation
# Expected: All services should have endpoints
```

#### 2. Test End-to-End Functionality

```bash
# Test Home Assistant web interface
curl -I https://homeassistant.k8s.home.geoffdavis.com

# Verify authentication flow works
# Manual: Navigate to https://homeassistant.k8s.home.geoffdavis.com
# Expected: Redirect to Authentik, successful login, access to Home Assistant
```

#### 3. Validate Matter Integration

```bash
# Check Home Assistant logs for Matter integration
kubectl logs -n home-automation -l app.kubernetes.io/name=home-assistant | grep -i matter | tail -10

# Expected log entries:
# - Matter integration loaded successfully
# - WebSocket connection to Matter server established
# - No error messages related to Matter
```

### Health Monitoring Setup

#### 1. Configure Monitoring Alerts

```bash
# Verify Matter Server is included in monitoring
kubectl get servicemonitor -n home-automation | grep matter-server

# Check Prometheus targets (if monitoring is configured)
# Manual: Access Grafana and verify Matter Server metrics are collected
```

#### 2. Set Up Log Monitoring

```bash
# Configure log aggregation for Matter Server
# This depends on your logging infrastructure

# Verify logs are being collected
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server --tail=1
```

### Documentation Updates

#### 1. Update Operational Documentation

- Update [`OPERATIONAL_PROCEDURES.md`](OPERATIONAL_PROCEDURES.md) with deployment date and configuration
- Document any custom configuration changes made during deployment
- Update backup procedures to include Matter Server data

#### 2. Update Monitoring Dashboards

- Add Matter Server metrics to Grafana dashboards
- Configure alerts for Matter Server health
- Document Matter Server monitoring procedures

### Security Validation

#### 1. Verify Security Context

```bash
# Check security context is properly applied
kubectl get pod -n home-automation -l app.kubernetes.io/name=matter-server -o yaml | grep -A 10 securityContext

# Expected: privileged: true, capabilities: NET_ADMIN, NET_RAW, SYS_ADMIN
```

#### 2. Network Security

```bash
# Verify network policies (if configured)
kubectl get networkpolicies -n home-automation

# Test that Matter Server can only access required services
# This depends on your network policy configuration
```

## Troubleshooting Common Deployment Issues

### Pod Startup Failures

#### Issue: Pod in CrashLoopBackOff

**Diagnosis:**
```bash
kubectl describe pod -n home-automation -l app.kubernetes.io/name=matter-server
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server --previous
```

**Common Causes:**
- Network interface `enp3s0f0` not available on node
- Insufficient privileges for network operations
- Storage volume mount failures
- Helm chart configuration errors

**Solutions:**
- Verify network interface exists: `kubectl debug node/NODE_NAME -it --image=busybox -- ip addr show`
- Check security context and capabilities in Helm configuration
- Verify Longhorn storage system health
- Review Helm release configuration for errors

#### Issue: Pod Pending State

**Diagnosis:**
```bash
kubectl describe pod -n home-automation -l app.kubernetes.io/name=matter-server
kubectl get events -n home-automation --sort-by='.lastTimestamp'
```

**Common Causes:**
- Insufficient resources on nodes
- Storage provisioning failures
- Node selector constraints not met
- Pod security policy violations

**Solutions:**
- Check node resource availability
- Verify Longhorn storage class and provisioner
- Review node selector and tolerations
- Check namespace security policies

### Helm Release Failures

#### Issue: Helm Release Failed

**Diagnosis:**
```bash
kubectl get helmrelease -n home-automation matter-server -o yaml
kubectl describe helmrelease -n home-automation matter-server
flux logs --level=error
```

**Common Causes:**
- Helm repository not accessible
- Chart version not found
- Invalid configuration values
- Flux reconciliation errors

**Solutions:**
- Verify Helm repository sync status
- Check chart version availability
- Validate Helm values configuration
- Review Flux system logs

### Integration Issues

#### Issue: Home Assistant Can't Connect to Matter Server

**Diagnosis:**
```bash
kubectl exec -n home-automation deployment/home-assistant -- \
  curl -v http://localhost:5580/ws
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server | grep -i websocket
```

**Solutions:**
- Verify both pods are on same node (host networking requirement)
- Check Matter Server WebSocket endpoint is responding
- Restart Home Assistant deployment
- Verify network connectivity between pods

## Success Criteria

The Matter Server deployment is considered successful when:

### Technical Criteria

- ✅ Matter Server pod is Running (1/1 Ready)
- ✅ WebSocket endpoint responds on port 5580
- ✅ Host networking is properly configured
- ✅ Persistent storage is mounted and accessible
- ✅ Network interface `enp3s0f0` is accessible from pod
- ✅ Security context allows required network operations

### Integration Criteria

- ✅ Home Assistant connects to Matter Server via WebSocket
- ✅ Matter integration appears in Home Assistant web interface
- ✅ No error messages in Home Assistant or Matter Server logs
- ✅ Home Assistant web interface remains accessible and functional

### Operational Criteria

- ✅ All home-automation stack pods are healthy
- ✅ Authentication flow works correctly
- ✅ Monitoring and logging are functional
- ✅ Backup procedures include Matter Server data

## Next Steps

After successful deployment:

1. **Device Commissioning**: Follow [`TESTING.md`](TESTING.md) for Matter device commissioning procedures
2. **Operational Procedures**: Review [`OPERATIONAL_PROCEDURES.md`](OPERATIONAL_PROCEDURES.md) for daily operations
3. **Monitoring Setup**: Configure monitoring and alerting for Matter Server
4. **Documentation**: Update cluster documentation with Matter Server information

---

## Support Resources

- **Matter Server Documentation**: https://github.com/home-assistant-libs/python-matter-server
- **Home Assistant Matter Integration**: https://www.home-assistant.io/integrations/matter/
- **Helm Chart Documentation**: https://github.com/derwitt-dev/helm-charts/tree/main/charts/home-assistant-matter-server
- **Cluster Documentation**: [../../../docs/](../../../docs/)

---

_This deployment guide provides comprehensive procedures for deploying the Matter Server integration in the Talos GitOps cluster environment. Follow all steps carefully and verify each phase before proceeding._