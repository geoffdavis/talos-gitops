# Matter Server Testing and Validation Guide

This guide provides comprehensive testing procedures for validating the Matter Server integration, including device discovery, commissioning, and integration with Home Assistant.

## Overview

The Matter Server testing process validates Thread/Matter device support, commissioning procedures, and integration with the Home Assistant stack. This includes network connectivity tests, device discovery validation, and end-to-end functionality verification.

## Testing Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Matter Testing Architecture                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐    WebSocket API    ┌─────────────────┐    │
│  │  Home Assistant │◄──────────────────►│  Matter Server  │    │
│  │   (Port: 8123)  │   ws://localhost:   │   (Port: 5580)  │    │
│  │                 │      5580/ws        │                 │    │
│  └─────────────────┘                     └─────────────────┘    │
│           │                                       │              │
│           │                              Host Network            │
│           │                                       │              │
│           │                              ┌─────────────────┐     │
│           │                              │   Test Device   │     │
│           │                              │  (Matter/Thread)│     │
│           │                              │                 │     │
│           │                              └─────────────────┘     │
│           │                                       │              │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                    Testing Scenarios                        │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │ │
│  │  │ Connectivity│  │ Commissioning│  │ Integration │        │ │
│  │  │   Tests     │  │    Tests     │  │   Tests     │        │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘        │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Pre-Testing Requirements

### Infrastructure Validation

Before beginning Matter device testing, ensure the following infrastructure is operational:

#### 1. Matter Server Health Check

```bash
# Verify Matter Server is running
kubectl get pods -n home-automation -l app.kubernetes.io/name=matter-server

# Expected output:
# NAME                            READY   STATUS    RESTARTS   AGE
# matter-server-xxxxxxxxx-xxxxx   1/1     Running   0          5m

# Check Matter Server logs for startup success
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server --tail=20

# Expected log entries:
# - "Matter server starting"
# - "WebSocket server started on port 5580"
# - "Matter server ready"
```

#### 2. Home Assistant Integration Status

```bash
# Verify Home Assistant is running and connected to Matter Server
kubectl logs -n home-automation -l app.kubernetes.io/name=home-assistant --tail=50 | grep -i matter

# Expected log entries:
# - "Setting up Matter integration"
# - "Matter WebSocket connected"
# - "Matter integration setup complete"
```

#### 3. Network Infrastructure

```bash
# Verify host networking is functional
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ip addr show enp3s0f0

# Expected: Network interface should have IP address assigned

# Test network connectivity to local subnet
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ping -c 3 172.29.51.1

# Expected: Successful ping responses
```

### Test Environment Setup

#### 1. Test Device Requirements

For comprehensive testing, you'll need:

- **Matter-compatible device** (light bulb, switch, sensor, etc.)
- **Thread Border Router** (optional, for Thread devices)
- **Mobile device** with Home Assistant app (for QR code scanning)
- **Network access** to the same subnet as cluster nodes

#### 2. Testing Tools

```bash
# Install testing utilities in Matter Server pod
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  apt-get update && apt-get install -y bluetooth bluez-tools

# Verify Bluetooth functionality (if using Bluetooth commissioning)
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  hciconfig -a

# Expected: Bluetooth adapter should be listed and UP
```

## Matter Device Discovery Testing

### Network Discovery Tests

#### 1. mDNS Discovery Validation

```bash
# Test mDNS service discovery
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  avahi-browse -at | grep -i matter

# Expected: Should show Matter services if devices are advertising

# Test DNS-SD discovery
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  dig @224.0.0.251 -p 5353 _matter._tcp.local

# Expected: Should return Matter service records
```

#### 2. Thread Network Discovery

```bash
# Check Thread network status (if Thread Border Router is available)
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  python3 -c "
import asyncio
from matter_server.client import MatterClient

async def check_thread():
    try:
        # This would require Matter Server API access
        print('Thread network discovery test')
        print('Manual verification required via Home Assistant interface')
    except Exception as e:
        print(f'Thread check failed: {e}')

asyncio.run(check_thread())
"
```

#### 3. Bluetooth Discovery

```bash
# Test Bluetooth device discovery
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  bluetoothctl scan on &

# Wait 10 seconds then check for discovered devices
sleep 10

kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  bluetoothctl devices

# Expected: Should list nearby Bluetooth devices
```

### Network Connectivity Tests

#### 1. Host Networking Validation

```bash
# Verify Matter Server can access host network interfaces
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ip route show

# Expected: Should show host routing table

# Test multicast connectivity (required for Matter discovery)
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ping -c 3 224.0.0.251

# Expected: Multicast ping should work (may show timeouts but should send packets)
```

#### 2. Port Accessibility

```bash
# Test that Matter Server port is accessible
kubectl exec -n home-automation deployment/home-assistant -- \
  nc -zv localhost 5580

# Expected: Connection should succeed

# Test WebSocket upgrade
kubectl exec -n home-automation deployment/home-assistant -- \
  curl -I --http1.1 --upgrade WebSocket http://localhost:5580/ws

# Expected: HTTP/1.1 101 Switching Protocols
```

## Matter Device Commissioning Procedures

### Pre-Commissioning Setup

#### 1. Device Preparation

**Physical Device Setup:**
1. Ensure Matter device is powered on and in factory reset state
2. Put device in commissioning/pairing mode (refer to device manual)
3. Note the device's setup code or QR code
4. Ensure device is on the same network segment as cluster nodes

**Network Preparation:**
```bash
# Verify network connectivity to device subnet
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  nmap -sn 172.29.51.0/24

# Expected: Should discover devices on the network
```

#### 2. Home Assistant Preparation

```bash
# Access Home Assistant web interface
curl -I https://homeassistant.k8s.home.geoffdavis.com

# Navigate to: Settings → Devices & Services → Add Integration
# Verify "Matter (BETA)" integration is available
```

### Commissioning Methods

#### Method 1: QR Code Commissioning

**Prerequisites:**
- Home Assistant mobile app installed
- Mobile device on same network as cluster
- Matter device with visible QR code

**Steps:**
1. **Access Home Assistant Mobile App**
   - Open Home Assistant app on mobile device
   - Navigate to Settings → Devices & Services
   - Tap "Add Integration" → "Matter (BETA)"

2. **Scan QR Code**
   - Select "Scan QR Code" option
   - Point camera at device QR code
   - Wait for code recognition

3. **Complete Commissioning**
   - Follow on-screen prompts
   - Assign device to room/area
   - Configure device name and settings

**Validation:**
```bash
# Check Matter Server logs for commissioning activity
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server -f

# Expected log entries during commissioning:
# - "Starting device commissioning"
# - "Device discovery successful"
# - "Commissioning completed"
```

#### Method 2: Manual Setup Code Entry

**Prerequisites:**
- Device setup code (11-digit numeric code)
- Access to Home Assistant web interface

**Steps:**
1. **Access Matter Integration**
   - Navigate to https://homeassistant.k8s.home.geoffdavis.com
   - Go to Settings → Devices & Services
   - Click "Add Integration" → "Matter (BETA)"

2. **Enter Setup Code**
   - Select "Enter setup code manually"
   - Input the 11-digit setup code
   - Click "Submit"

3. **Complete Device Setup**
   - Wait for device discovery
   - Configure device properties
   - Test device functionality

**Validation:**
```bash
# Monitor commissioning progress
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server --tail=50 | grep -i commission

# Check Home Assistant logs for device addition
kubectl logs -n home-automation -l app.kubernetes.io/name=home-assistant --tail=50 | grep -i matter
```

#### Method 3: Bluetooth Commissioning

**Prerequisites:**
- Bluetooth-enabled Matter device
- Bluetooth support in Matter Server pod

**Steps:**
1. **Verify Bluetooth Availability**
   ```bash
   kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
     bluetoothctl list
   
   # Expected: Should show available Bluetooth adapter
   ```

2. **Start Bluetooth Discovery**
   ```bash
   kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
     bluetoothctl scan on
   ```

3. **Commission via Home Assistant**
   - Access Home Assistant web interface
   - Add Matter integration
   - Select Bluetooth commissioning option
   - Follow commissioning workflow

**Validation:**
```bash
# Check Bluetooth pairing logs
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server | grep -i bluetooth

# Verify device appears in Home Assistant
# Manual: Check Devices & Services for new Matter device
```

### Commissioning Troubleshooting

#### Issue: Device Not Discovered

**Diagnosis:**
```bash
# Check network connectivity to device
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ping -c 3 <device-ip>

# Verify mDNS is working
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  avahi-browse -at | grep -i matter

# Check Matter Server logs for discovery attempts
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server | grep -i discover
```

**Solutions:**
- Ensure device is in commissioning mode
- Verify network connectivity between cluster and device
- Check firewall rules for mDNS traffic (port 5353)
- Restart Matter Server if needed

#### Issue: Commissioning Fails

**Diagnosis:**
```bash
# Check commissioning logs
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server | grep -i commission

# Verify WebSocket connection
kubectl exec -n home-automation deployment/home-assistant -- \
  curl -v --http1.1 --upgrade WebSocket http://localhost:5580/ws
```

**Solutions:**
- Verify setup code is correct
- Ensure device is not already commissioned to another controller
- Check network stability during commissioning
- Reset device and retry commissioning

## Integration Validation Testing

### Home Assistant Integration Tests

#### 1. Device Control Testing

**Basic Device Control:**
```bash
# Access Home Assistant web interface
# Navigate to: Overview → [Device Name]
# Test basic controls (on/off, brightness, etc.)

# Monitor Matter Server logs during control commands
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server -f

# Expected: Should show command transmission and response logs
```

**Automation Testing:**
```bash
# Create test automation in Home Assistant:
# 1. Go to Settings → Automations & Scenes
# 2. Create automation with Matter device trigger/action
# 3. Test automation execution

# Monitor logs for automation activity
kubectl logs -n home-automation -l app.kubernetes.io/name=home-assistant | grep -i automation
```

#### 2. State Synchronization Testing

**Real-time State Updates:**
```bash
# Monitor state changes in real-time
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server -f &

# Manually change device state (physical button, etc.)
# Verify state change appears in Home Assistant interface
# Check logs for state update messages
```

**State Persistence Testing:**
```bash
# Change device state via Home Assistant
# Restart Matter Server pod
kubectl delete pod -n home-automation -l app.kubernetes.io/name=matter-server

# Wait for pod restart
kubectl wait --for=condition=Ready pod -n home-automation -l app.kubernetes.io/name=matter-server --timeout=300s

# Verify device state is maintained after restart
```

#### 3. WebSocket Communication Testing

**Connection Stability:**
```bash
# Monitor WebSocket connections
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server | grep -i websocket

# Test connection recovery after network interruption
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  iptables -A OUTPUT -p tcp --dport 8123 -j DROP

# Wait 30 seconds, then restore connectivity
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  iptables -D OUTPUT -p tcp --dport 8123 -j DROP

# Verify WebSocket reconnection in logs
```

### Performance Testing

#### 1. Response Time Testing

**Command Response Time:**
```bash
# Test device response times
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  python3 -c "
import time
import asyncio
from datetime import datetime

async def test_response_time():
    print('Testing Matter device response times')
    print('Manual testing required via Home Assistant interface')
    print('Expected: Device commands should execute within 1-2 seconds')

asyncio.run(test_response_time())
"
```

**Load Testing:**
```bash
# Test multiple simultaneous commands
# This requires manual testing via Home Assistant interface
# Send multiple device commands rapidly and monitor response times
```

#### 2. Resource Usage Monitoring

**CPU and Memory Usage:**
```bash
# Monitor Matter Server resource usage
kubectl top pods -n home-automation -l app.kubernetes.io/name=matter-server --containers

# Expected resource usage:
# CPU: 50-200m under normal load
# Memory: 128-512Mi depending on device count

# Monitor resource usage over time
watch -n 5 'kubectl top pods -n home-automation -l app.kubernetes.io/name=matter-server'
```

**Storage Usage:**
```bash
# Check persistent storage usage
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  df -h /data

# Monitor storage growth with device additions
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  du -sh /data/*
```

## Network Connectivity Tests

### Host Networking Validation

#### 1. Network Interface Testing

```bash
# Verify network interface configuration
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ip addr show enp3s0f0

# Expected: Interface should have IP address and be UP

# Test interface connectivity
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ping -c 3 -I enp3s0f0 172.29.51.1

# Expected: Successful ping via specified interface
```

#### 2. Multicast Connectivity

```bash
# Test multicast group membership (required for Matter discovery)
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ip maddr show enp3s0f0

# Expected: Should show multicast group memberships

# Test multicast packet transmission
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ping -c 3 224.0.0.251

# Expected: Packets should be transmitted (responses may timeout)
```

#### 3. Port Accessibility Testing

```bash
# Test Matter Server port from different network locations
kubectl run network-test --rm -i --tty --image=busybox --restart=Never -- \
  nc -zv matter-server.home-automation.svc.cluster.local 5580

# Test from Home Assistant pod
kubectl exec -n home-automation deployment/home-assistant -- \
  nc -zv localhost 5580

# Expected: Both tests should show successful connections
```

### Thread Network Testing

#### 1. Thread Border Router Detection

```bash
# Check for Thread Border Router on network
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  avahi-browse -at | grep -i thread

# Expected: Should show Thread services if border router is present
```

#### 2. Thread Network Connectivity

```bash
# Test Thread network connectivity (requires Thread devices)
# This is primarily validated through successful Thread device commissioning
# Manual verification required via Home Assistant interface
```

## Troubleshooting Common Issues

### Device Discovery Problems

#### Issue: Matter Devices Not Discovered

**Diagnosis Steps:**
```bash
# Check network connectivity
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  nmap -sn 172.29.51.0/24

# Verify mDNS functionality
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  avahi-browse -at

# Check Matter Server logs
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server | grep -i discover
```

**Common Solutions:**
- Ensure devices are in commissioning mode
- Verify network connectivity between cluster and devices
- Check firewall rules for mDNS (port 5353)
- Restart Matter Server pod if needed

#### Issue: Bluetooth Commissioning Fails

**Diagnosis Steps:**
```bash
# Check Bluetooth adapter status
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  hciconfig -a

# Verify Bluetooth service
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  systemctl status bluetooth
```

**Common Solutions:**
- Verify Bluetooth adapter is available and enabled
- Check device Bluetooth compatibility
- Ensure device is in Bluetooth pairing mode
- Restart Bluetooth service if needed

### Integration Issues

#### Issue: Home Assistant Can't Control Devices

**Diagnosis Steps:**
```bash
# Check WebSocket connection
kubectl exec -n home-automation deployment/home-assistant -- \
  curl -v --http1.1 --upgrade WebSocket http://localhost:5580/ws

# Monitor command transmission
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server -f

# Check Home Assistant logs
kubectl logs -n home-automation -l app.kubernetes.io/name=home-assistant | grep -i matter
```

**Common Solutions:**
- Verify WebSocket connection is stable
- Check device network connectivity
- Restart Home Assistant to refresh device connections
- Re-commission problematic devices

#### Issue: Slow Device Response

**Diagnosis Steps:**
```bash
# Monitor network latency
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ping -c 10 <device-ip>

# Check Matter Server resource usage
kubectl top pods -n home-automation -l app.kubernetes.io/name=matter-server
```

**Common Solutions:**
- Optimize network configuration
- Check for network congestion
- Verify adequate resources for Matter Server
- Consider Thread network optimization

### Performance Issues

#### Issue: High Resource Usage

**Diagnosis Steps:**
```bash
# Monitor detailed resource usage
kubectl top pods -n home-automation -l app.kubernetes.io/name=matter-server --containers

# Check for memory leaks
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ps aux | head -20

# Monitor storage usage
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  df -h /data
```

**Common Solutions:**
- Review device count and activity levels
- Increase resource limits if needed
- Check for problematic devices causing excessive traffic
- Monitor and clean up storage usage

## Test Validation Criteria

### Successful Testing Criteria

The Matter Server testing is considered successful when:

#### Infrastructure Tests
- ✅ Matter Server pod is healthy and responsive
- ✅ WebSocket endpoint accessible from Home Assistant
- ✅ Host networking properly configured
- ✅ Network interface accessible and functional
- ✅ Persistent storage mounted and writable

#### Device Discovery Tests
- ✅ mDNS discovery functional for Matter devices
- ✅ Bluetooth discovery working (if enabled)
- ✅ Thread network discovery operational (if applicable)
- ✅ Network connectivity to device subnet confirmed

#### Commissioning Tests
- ✅ At least one Matter device successfully commissioned
- ✅ Device appears in Home Assistant interface
- ✅ Device responds to basic control commands
- ✅ Device state synchronization working

#### Integration Tests
- ✅ Home Assistant can control commissioned devices
- ✅ Device state changes reflected in real-time
- ✅ Automations work with Matter devices
- ✅ WebSocket communication stable

#### Performance Tests
- ✅ Device commands execute within 2 seconds
- ✅ Resource usage within expected limits
- ✅ No memory leaks or excessive storage growth
- ✅ System remains stable under normal load

### Test Documentation

#### Test Results Recording

Create a test results log:
```bash
# Create test results file
cat > matter-server-test-results.md << EOF
# Matter Server Test Results

**Test Date:** $(date)
**Tester:** [Your Name]
**Environment:** Talos GitOps Cluster

## Infrastructure Tests
- [ ] Matter Server Health: PASS/FAIL
- [ ] WebSocket Connectivity: PASS/FAIL
- [ ] Host Networking: PASS/FAIL
- [ ] Storage Access: PASS/FAIL

## Device Tests
- [ ] Device Discovery: PASS/FAIL
- [ ] Device Commissioning: PASS/FAIL
- [ ] Device Control: PASS/FAIL
- [ ] State Synchronization: PASS/FAIL

## Performance Tests
- [ ] Response Times: PASS/FAIL
- [ ] Resource Usage: PASS/FAIL
- [ ] Stability: PASS/FAIL

## Notes
[Add any additional observations or issues]

EOF
```

## Next Steps After Testing

### Successful Testing

If all tests pass:
1. **Document Configuration**: Record successful device types and configurations
2. **Update Monitoring**: Add Matter Server metrics to monitoring dashboards
3. **Create Backups**: Ensure Matter certificates and device data are backed up
4. **Operational Procedures**: Follow [`OPERATIONAL_PROCEDURES.md`](OPERATIONAL_PROCEDURES.md) for daily operations

### Failed Testing

If tests fail:
1. **Review Logs**: Analyze Matter Server and Home Assistant logs for errors
2. **Check Configuration**: Verify Helm configuration and network settings
3. **Consult Troubleshooting**: Follow troubleshooting procedures in this guide
4. **Escalate Issues**: Document issues and consult support resources

## Support Resources

- **Matter Specification**: https://csa-iot.org/all-solutions/matter/
- **Home Assistant Matter Integration**: https://www.home-assistant.io/integrations/matter/
- **Python Matter Server**: https://github.com/home-assistant-libs/python-matter-server
- **Thread Group Documentation**: https://www.threadgroup.org/
- **Cluster Documentation**: [../../../docs/](../../../docs/)

---

_This testing guide provides comprehensive validation procedures for the Matter Server integration. Follow all test procedures to ensure reliable Matter device support in your Home Assistant deployment._