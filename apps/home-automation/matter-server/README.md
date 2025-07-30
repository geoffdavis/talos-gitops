# Home Assistant Matter Server

## Overview

The Home Assistant Matter Server provides Thread/Matter device support for the Home Assistant stack. It runs as a dedicated service that handles Matter device commissioning, communication, and management, connecting to Home Assistant via WebSocket API.

Matter is an industry-standard protocol for smart home devices that enables interoperability across different manufacturers and platforms. The Matter Server acts as a bridge between Matter/Thread devices and Home Assistant, providing secure and reliable device integration.

## Quick Access

- **Service**: `matter-server.home-automation.svc.cluster.local:5580`
- **WebSocket API**: `ws://localhost:5580/ws` (from Home Assistant)
- **Namespace**: `home-automation`
- **Chart**: `home-assistant-matter-server` v3.0.0

## Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│                    Matter Server Architecture                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐    WebSocket API    ┌─────────────────┐    │
│  │  Home Assistant │◄──────────────────►│  Matter Server  │    │
│  │   (Port: 8123)  │   ws://localhost:   │   (Port: 5580)  │    │
│  │                 │      5580/ws        │                 │    │
│  └─────────────────┘                     └─────────────────┘    │
│                                                   │              │
│                                          Host Network            │
│                                                   │              │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │              Matter/Thread Devices                          │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │ │
│  │  │   Lights    │  │   Sensors   │  │   Switches  │   ...  │ │
│  │  │             │  │             │  │             │        │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘        │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Key Components

- **Matter Server Container**: Python Matter Server (v8.0.0) handling Matter protocol communication
- **Host Networking**: Required for Matter/Thread device discovery and communication
- **Persistent Storage**: 5GB Longhorn volume for Matter certificates and device data
- **WebSocket API**: Communication interface with Home Assistant
- **Bluetooth Support**: Enabled for Matter device commissioning

## Configuration

### Key Configuration Values

```yaml
# Network interface for Matter/Thread device discovery
networkInterface: "enp3s0f0" # Mac mini primary interface

# Bluetooth commissioning support
bluetoothCommissioning:
  enabled: true

# Host networking for device discovery
hostNetwork: true
dnsPolicy: ClusterFirstWithHostNet

# Persistent storage for certificates and device data
persistence:
  storageClassName: "longhorn"
  size: 5Gi

# Security context for privileged operations
securityContext:
  privileged: true
  capabilities:
    add: ["NET_ADMIN", "NET_RAW", "SYS_ADMIN"]
```

### Home Assistant Integration for Configuration

The Matter Server integrates with Home Assistant through the following configuration in [`home-assistant/configmap.yaml`](../home-assistant/configmap.yaml):

```yaml
# Matter integration for Thread/Matter device support
matter:
  server: "ws://localhost:5580/ws"
  log_level: info
```

## Deployment

### Prerequisites

- Longhorn storage system operational
- Home Assistant stack deployed
- Host networking support on cluster nodes
- Network interface `enp3s0f0` available on nodes

### Deployment Process

1. **Deploy Matter Server**:

   ```bash
   kubectl apply -k apps/home-automation/matter-server/
   ```

2. **Verify Deployment**:

   ```bash
   # Check pod status
   kubectl get pods -n home-automation -l app.kubernetes.io/name=matter-server

   # Check service
   kubectl get svc -n home-automation matter-server

   # View logs
   kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server
   ```

3. **Validate Integration**:

   ```bash
   # Restart Home Assistant to pick up Matter integration
   kubectl rollout restart deployment home-assistant -n home-automation

   # Check Home Assistant logs for Matter integration
   kubectl logs -n home-automation -l app.kubernetes.io/name=home-assistant | grep -i matter
   ```

## Operations

### Matter Device Commissioning

#### Prerequisites for Device Commissioning

1. **Network Connectivity**: Ensure Matter devices are on the same network segment as cluster nodes
2. **Bluetooth Access**: Matter Server pod has Bluetooth access for commissioning
3. **Thread Network**: If using Thread devices, ensure Thread border router is configured

#### Commissioning Process

1. **Access Home Assistant**: Navigate to <https://homeassistant.k8s.home.geoffdavis.com>
2. **Add Integration**: Go to Settings → Devices & Services → Add Integration
3. **Select Matter**: Choose "Matter (BETA)" from the integration list
4. **Commission Device**: Follow the Matter commissioning flow:
   - Put device in pairing mode
   - Scan QR code or enter setup code
   - Complete device setup in Home Assistant

#### Commissioning Methods

- **QR Code**: Scan device QR code using Home Assistant mobile app
- **Setup Code**: Enter numeric setup code manually
- **Bluetooth**: Use Bluetooth for initial device discovery and commissioning

### Health Monitoring

#### Health Check Commands

```bash
# Check Matter Server pod health
kubectl get pods -n home-automation -l app.kubernetes.io/name=matter-server

# View Matter Server logs
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server --tail=100

# Check WebSocket connectivity from Home Assistant
kubectl exec -n home-automation deployment/home-assistant -- \
  curl -I --http1.1 --upgrade WebSocket http://localhost:5580/ws

# Verify persistent storage
kubectl get pvc -n home-automation | grep matter-server
```

#### Health Indicators

- **Pod Status**: Should be `Running` with `1/1` ready
- **WebSocket Endpoint**: Should respond to HTTP upgrade requests
- **Storage**: PVC should be `Bound` with sufficient space
- **Logs**: Should show successful Matter Server startup and device connections

### Performance Monitoring

#### Resource Usage

```bash
# Check resource usage
kubectl top pods -n home-automation -l app.kubernetes.io/name=matter-server

# View resource limits and requests
kubectl describe pod -n home-automation -l app.kubernetes.io/name=matter-server | grep -A 10 "Limits\|Requests"
```

#### Expected Resource Usage

- **CPU**: 50-200m under normal load
- **Memory**: 128-512Mi depending on device count
- **Storage**: Grows with device certificates and data

### Backup and Recovery

#### Data Backup

Matter Server data is automatically backed up as part of the Longhorn storage system:

```bash
# Check volume snapshots
kubectl get volumesnapshots -n home-automation | grep matter-server

# Manual snapshot creation
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: matter-server-manual-$(date +%Y%m%d-%H%M%S)
  namespace: home-automation
spec:
  source:
    persistentVolumeClaimName: matter-server-data
EOF
```

#### Recovery Procedures

1. **Pod Recovery**: Kubernetes automatically restarts failed pods
2. **Data Recovery**: Restore from Longhorn volume snapshots if needed
3. **Device Re-commissioning**: May be required after major data loss

## Integration

### Home Assistant Integration for Recovery

The Matter Server integrates with Home Assistant through:

1. **WebSocket API**: Real-time communication for device events and commands
2. **Matter Integration**: Home Assistant's built-in Matter integration component
3. **Device Discovery**: Automatic discovery of commissioned Matter devices
4. **State Synchronization**: Real-time device state updates

### Network Integration

- **Host Networking**: Required for Matter/Thread device discovery
- **Network Interface**: Uses `enp3s0f0` for device communication
- **Bluetooth**: Enabled for device commissioning
- **Thread Support**: Compatible with Thread border routers

### Security Integration

- **Privileged Mode**: Required for network and Bluetooth access
- **Certificate Management**: Automatic Matter certificate handling
- **Network Policies**: Integrated with cluster network security
- **Storage Encryption**: Longhorn provides encrypted storage

## Troubleshooting

### Common Issues

#### Matter Server Won't Start

**Symptoms**: Pod in `CrashLoopBackOff` or `Error` state

**Diagnosis**:

```bash
# Check pod events
kubectl describe pod -n home-automation -l app.kubernetes.io/name=matter-server

# View startup logs
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server --previous
```

**Common Causes**:

- Network interface `enp3s0f0` not available
- Insufficient privileges for network operations
- Storage volume mount issues

**Solutions**:

- Verify network interface exists on nodes
- Check security context and capabilities
- Validate Longhorn storage availability

#### Home Assistant Can't Connect to Matter Server

**Symptoms**: Matter integration shows connection errors in Home Assistant

**Diagnosis**:

```bash
# Test WebSocket connectivity
kubectl exec -n home-automation deployment/home-assistant -- \
  curl -v --http1.1 --upgrade WebSocket http://localhost:5580/ws

# Check Matter Server logs for connection attempts
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server | grep -i websocket
```

**Solutions**:

- Verify both pods are running on the same node (host networking)
- Check Matter Server WebSocket endpoint is responding
- Restart Home Assistant to retry connection

#### Device Commissioning Fails

**Symptoms**: Unable to commission Matter devices through Home Assistant

**Diagnosis**:

```bash
# Check Bluetooth availability
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  hciconfig -a

# Verify network connectivity to devices
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ping <device-ip>
```

**Solutions**:

- Ensure device is in pairing mode
- Verify network connectivity between cluster and devices
- Check Bluetooth functionality if using Bluetooth commissioning
- Validate Thread network configuration for Thread devices

#### Storage Issues

**Symptoms**: Matter Server loses device data or certificates

**Diagnosis**:

```bash
# Check PVC status
kubectl get pvc -n home-automation | grep matter-server

# Verify volume mount
kubectl describe pod -n home-automation -l app.kubernetes.io/name=matter-server | grep -A 5 Mounts
```

**Solutions**:

- Verify Longhorn storage system health
- Check volume mount permissions
- Restore from backup if data corruption occurred

### Debug Commands

```bash
# Enable debug logging
kubectl patch configmap home-assistant-configuration -n home-automation --patch '
data:
  configuration.yaml: |
    matter:
      server: "ws://localhost:5580/ws"
      log_level: debug
'

# View detailed Matter Server logs
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server -f

# Check network interface status
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ip addr show enp3s0f0

# Test Bluetooth functionality
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  bluetoothctl list
```

### Performance Troubleshooting

#### High Resource Usage

**Symptoms**: Matter Server consuming excessive CPU or memory

**Diagnosis**:

```bash
# Monitor resource usage
kubectl top pods -n home-automation -l app.kubernetes.io/name=matter-server --containers

# Check for memory leaks
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ps aux | head -20
```

**Solutions**:

- Review device count and activity levels
- Consider increasing resource limits
- Check for problematic devices causing excessive traffic

#### Slow Device Response

**Symptoms**: Matter devices respond slowly to commands

**Diagnosis**:

- Check network latency to devices
- Monitor Matter Server processing logs
- Verify Thread network performance

**Solutions**:

- Optimize network configuration
- Reduce device polling frequency
- Check Thread border router performance

## Security Considerations

### Network Security

- **Host Networking**: Required but increases attack surface
- **Network Policies**: Implement appropriate network policies
- **Device Isolation**: Consider VLAN isolation for IoT devices

### Access Control

- **RBAC**: Matter Server runs with minimal required permissions
- **Service Account**: Dedicated service account with limited scope
- **Pod Security**: Privileged mode required for network operations

### Data Protection

- **Certificate Security**: Matter certificates stored securely
- **Storage Encryption**: Longhorn provides encryption at rest
- **Network Encryption**: Matter protocol provides end-to-end encryption

## Maintenance

### Regular Maintenance Tasks

1. **Monitor Resource Usage**: Check CPU, memory, and storage usage weekly
2. **Review Logs**: Check for errors or warnings in Matter Server logs
3. **Update Devices**: Keep Matter devices firmware updated
4. **Backup Validation**: Verify backup integrity monthly

### Upgrade Procedures

1. **Chart Updates**: Update Helm chart version in `helmrelease.yaml`
2. **Image Updates**: Update container image tag for security patches
3. **Testing**: Validate device functionality after upgrades
4. **Rollback Plan**: Maintain rollback capability for failed upgrades

### Capacity Planning

- **Device Limits**: Monitor number of commissioned devices
- **Storage Growth**: Plan for certificate and device data growth
- **Network Bandwidth**: Consider impact of device communication

---

## Support Resources

- **Matter Specification**: <https://csa-iot.org/all-solutions/matter/>
- **Home Assistant Matter**: <https://www.home-assistant.io/integrations/matter/>
- **Python Matter Server**: <https://github.com/home-assistant-libs/python-matter-server>
- **Thread Group**: <https://www.threadgroup.org/>
- **Cluster Documentation**: [../../docs/](../../docs/)

---

_This documentation provides comprehensive guidance for deploying, operating, and troubleshooting the Home Assistant Matter Server in the Talos GitOps cluster environment._
