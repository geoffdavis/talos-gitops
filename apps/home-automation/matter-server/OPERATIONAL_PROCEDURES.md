# Matter Server Operational Procedures

This guide provides comprehensive operational procedures for managing the Matter Server integration in daily operations, including device management, monitoring, backup/recovery, and maintenance tasks.

## Overview

The Matter Server operational procedures ensure reliable Thread/Matter device support within the Home Assistant stack. This includes daily health monitoring, device lifecycle management, backup strategies, and troubleshooting procedures for production environments.

## Daily Operations

### Health Monitoring Tasks

#### 1. Daily Health Checks

**Morning Health Verification:**

```bash
# Check Matter Server pod status
kubectl get pods -n home-automation -l app.kubernetes.io/name=matter-server

# Expected output:
# NAME                            READY   STATUS    RESTARTS   AGE
# matter-server-xxxxxxxxx-xxxxx   1/1     Running   0          Xd

# Verify WebSocket connectivity
kubectl exec -n home-automation deployment/home-assistant -- \
  curl -I --http1.1 --upgrade WebSocket http://localhost:5580/ws

# Expected: HTTP/1.1 101 Switching Protocols

# Check recent logs for errors
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server --tail=50 | grep -i error

# Expected: No error messages in recent logs
```

**Resource Usage Monitoring:**

```bash
# Check CPU and memory usage
kubectl top pods -n home-automation -l app.kubernetes.io/name=matter-server

# Expected ranges:
# CPU: 50-200m under normal load
# Memory: 128-512Mi depending on device count

# Monitor storage usage
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  df -h /data

# Expected: Storage usage should be stable, not growing rapidly
```

**Device Connectivity Verification:**

```bash
# Test sample device connectivity (replace with actual device IP)
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ping -c 3 <matter-device-ip>

# Check Home Assistant device status via web interface
# Navigate to: Settings → Devices & Services → Matter
# Verify all devices show as "Available"
```

#### 2. Weekly Health Assessment

**Comprehensive System Check:**

```bash
# Generate weekly health report
cat > weekly-matter-health-$(date +%Y%m%d).md << EOF
# Matter Server Weekly Health Report - $(date)

## Pod Health
$(kubectl get pods -n home-automation -l app.kubernetes.io/name=matter-server -o wide)

## Resource Usage
$(kubectl top pods -n home-automation -l app.kubernetes.io/name=matter-server)

## Storage Usage
$(kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- df -h /data)

## Recent Errors
$(kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server --since=168h | grep -i error | tail -10)

## Device Count
Manual check required via Home Assistant interface

## Performance Notes
[Add any performance observations]

EOF
```

**Log Analysis:**

```bash
# Analyze logs for patterns or issues
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server --since=168h > matter-server-weekly.log

# Check for common issues
grep -i "connection\|timeout\|error\|fail" matter-server-weekly.log | sort | uniq -c | sort -nr

# Review high-frequency issues and plan remediation
```

### Performance Monitoring

#### 1. Response Time Monitoring

**Device Command Response Times:**

```bash
# Monitor command response times (manual testing required)
# Access Home Assistant web interface
# Test device commands and note response times
# Expected: Commands should execute within 1-2 seconds

# Log response time observations
echo "$(date): Device response time check - [NORMAL/SLOW/TIMEOUT]" >> matter-performance.log
```

**WebSocket Performance:**

```bash
# Monitor WebSocket connection stability
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server --since=24h | grep -i websocket

# Look for connection drops or reconnections
# Expected: Stable connections with minimal reconnection events
```

#### 2. Resource Trend Analysis

**CPU and Memory Trends:**

```bash
# Collect resource usage data
echo "$(date),$(kubectl top pods -n home-automation -l app.kubernetes.io/name=matter-server --no-headers | awk '{print $2","$3}')" >> matter-resources.csv

# Weekly trend analysis
tail -7 matter-resources.csv | awk -F, '{cpu+=$2; mem+=$3} END {print "Weekly avg CPU:", cpu/7, "Memory:", mem/7}'
```

**Storage Growth Monitoring:**

```bash
# Track storage usage over time
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  du -sh /data >> matter-storage-usage.log

# Check for unusual growth patterns
tail -30 matter-storage-usage.log
```

## Device Management

### Adding New Matter Devices

#### 1. Pre-Addition Checklist

**Infrastructure Readiness:**

```bash
# Verify Matter Server health
kubectl get pods -n home-automation -l app.kubernetes.io/name=matter-server

# Check available resources
kubectl describe node | grep -A 5 "Allocated resources"

# Verify network connectivity to device subnet
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  nmap -sn 172.29.51.0/24
```

**Device Preparation:**

- Ensure device is Matter-certified
- Verify device is on same network segment as cluster
- Have device setup code or QR code ready
- Confirm device is in factory reset state

#### 2. Device Addition Process

**Commission New Device:**

1. **Access Home Assistant Interface:**
   - Navigate to <https://homeassistant.k8s.home.geoffdavis.com>
   - Go to Settings → Devices & Services
   - Click "Add Integration" → "Matter (BETA)"

2. **Follow Commissioning Process:**
   - Choose commissioning method (QR code, setup code, Bluetooth)
   - Complete device pairing following on-screen instructions
   - Assign device to appropriate room/area
   - Configure device name and settings

3. **Verify Device Addition:**

   ```bash
   # Monitor commissioning in logs
   kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server -f

   # Expected log entries:
   # - "Starting device commissioning"
   # - "Device discovery successful"
   # - "Commissioning completed"
   ```

4. **Test Device Functionality:**
   - Test basic device controls via Home Assistant interface
   - Verify device responds to commands within 2 seconds
   - Check device state synchronization

#### 3. Post-Addition Tasks

**Documentation Update:**

```bash
# Update device inventory
cat >> matter-device-inventory.md << EOF
## Device Added: $(date)
- **Device Type:** [Light/Switch/Sensor/etc.]
- **Manufacturer:** [Device Manufacturer]
- **Model:** [Device Model]
- **Location:** [Room/Area]
- **IP Address:** [Device IP if known]
- **Setup Method:** [QR Code/Setup Code/Bluetooth]
- **Notes:** [Any special configuration]

EOF
```

**Monitoring Setup:**

- Add device to monitoring dashboards if applicable
- Configure alerts for critical devices
- Update backup procedures if device stores important data

### Removing Matter Devices

#### 1. Device Removal Process

**Remove from Home Assistant:**

1. **Access Device Settings:**
   - Navigate to Settings → Devices & Services → Matter
   - Find device to remove
   - Click device name → Settings (gear icon)

2. **Remove Device:**
   - Click "Delete Device"
   - Confirm removal
   - Verify device no longer appears in device list

3. **Monitor Removal:**

   ```bash
   # Check logs for device removal
   kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server --tail=50 | grep -i remove

   # Verify device cleanup
   kubectl logs -n home-automation -l app.kubernetes.io/name=home-assistant --tail=50 | grep -i device
   ```

#### 2. Physical Device Reset

**Factory Reset Device:**

- Follow manufacturer instructions to factory reset device
- Verify device is no longer connected to Matter network
- Document removal in device inventory

**Network Cleanup:**

```bash
# Verify device no longer appears in network scans
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  nmap -sn 172.29.51.0/24 | grep <device-ip>

# Expected: Device IP should not respond or show different MAC address
```

### Device Troubleshooting

#### 1. Unresponsive Devices

**Diagnosis Steps:**

```bash
# Check device network connectivity
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ping -c 3 <device-ip>

# Monitor Matter Server logs for device communication
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server | grep <device-identifier>

# Check Home Assistant device status
# Manual: Navigate to Settings → Devices & Services → Matter
# Look for device status indicators
```

**Resolution Steps:**

1. **Network Troubleshooting:**
   - Verify device power and network connection
   - Check for network connectivity issues
   - Restart device if necessary

2. **Matter Server Refresh:**

   ```bash
   # Restart Matter Server to refresh device connections
   kubectl rollout restart deployment matter-server -n home-automation

   # Monitor restart and device reconnection
   kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server -f
   ```

3. **Device Re-commissioning:**
   - If device remains unresponsive, remove and re-commission
   - Follow device removal and addition procedures

#### 2. Slow Device Response

**Performance Analysis:**

```bash
# Check network latency to device
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ping -c 10 <device-ip>

# Monitor Matter Server resource usage
kubectl top pods -n home-automation -l app.kubernetes.io/name=matter-server

# Check for network congestion
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  iftop -i enp3s0f0 -t -s 10
```

**Optimization Steps:**

- Verify adequate resources for Matter Server
- Check network configuration for optimal performance
- Consider Thread network optimization for Thread devices
- Review device placement and signal strength

## Backup and Recovery

### Data Backup Procedures

#### 1. Matter Server Data Backup

**Automated Backup (via Longhorn):**

```bash
# Verify automatic snapshots are working
kubectl get volumesnapshots -n home-automation | grep matter-server

# Check snapshot schedule
kubectl get volumesnapshotclass -o yaml | grep -A 10 matter

# Expected: Regular snapshots should be created automatically
```

**Manual Backup Creation:**

```bash
# Create manual snapshot for maintenance or upgrades
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: matter-server-manual-$(date +%Y%m%d-%H%M%S)
  namespace: home-automation
spec:
  source:
    persistentVolumeClaimName: matter-server-data
  volumeSnapshotClassName: longhorn-snapshot-vsc
EOF

# Verify snapshot creation
kubectl get volumesnapshots -n home-automation | grep matter-server-manual
```

**Data Export for External Backup:**

```bash
# Export Matter Server data for external backup
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  tar -czf /tmp/matter-backup-$(date +%Y%m%d).tar.gz /data

# Copy backup to external location
kubectl cp home-automation/$(kubectl get pod -n home-automation -l app.kubernetes.io/name=matter-server -o jsonpath='{.items[0].metadata.name}'):/tmp/matter-backup-$(date +%Y%m%d).tar.gz ./matter-backup-$(date +%Y%m%d).tar.gz
```

#### 2. Configuration Backup

**Helm Configuration Backup:**

```bash
# Backup Helm release configuration
kubectl get helmrelease -n home-automation matter-server -o yaml > matter-server-helmrelease-backup-$(date +%Y%m%d).yaml

# Backup complete home-automation configuration
kubectl get all,pvc,secrets,configmaps -n home-automation -o yaml > home-automation-backup-$(date +%Y%m%d).yaml
```

**Device Configuration Export:**

```bash
# Export Home Assistant configuration (includes Matter device config)
kubectl exec -n home-automation deployment/home-assistant -- \
  tar -czf /tmp/ha-config-backup-$(date +%Y%m%d).tar.gz /config

# Copy Home Assistant config backup
kubectl cp home-automation/$(kubectl get pod -n home-automation -l app.kubernetes.io/name=home-assistant -o jsonpath='{.items[0].metadata.name}'):/tmp/ha-config-backup-$(date +%Y%m%d).tar.gz ./ha-config-backup-$(date +%Y%m%d).tar.gz
```

### Recovery Procedures

#### 1. Matter Server Data Recovery

**Recovery from Volume Snapshot:**

```bash
# List available snapshots
kubectl get volumesnapshots -n home-automation | grep matter-server

# Create new PVC from snapshot (replace SNAPSHOT_NAME)
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: matter-server-data-restored
  namespace: home-automation
spec:
  storageClassName: longhorn
  dataSource:
    name: SNAPSHOT_NAME
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF

# Update Matter Server deployment to use restored PVC
kubectl patch helmrelease matter-server -n home-automation --type='merge' -p='
spec:
  values:
    persistence:
      existingClaim: matter-server-data-restored
'
```

**Recovery from External Backup:**

```bash
# Create temporary pod for data restoration
kubectl run matter-restore --image=busybox --rm -i --tty --restart=Never \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "matter-restore",
      "image": "busybox",
      "command": ["sleep", "3600"],
      "volumeMounts": [{
        "name": "matter-data",
        "mountPath": "/data"
      }]
    }],
    "volumes": [{
      "name": "matter-data",
      "persistentVolumeClaim": {
        "claimName": "matter-server-data"
      }
    }]
  }
}' -- sh

# Inside the pod, restore data
kubectl cp ./matter-backup-YYYYMMDD.tar.gz home-automation/matter-restore:/tmp/
kubectl exec -n home-automation matter-restore -- \
  tar -xzf /tmp/matter-backup-YYYYMMDD.tar.gz -C /

# Restart Matter Server to pick up restored data
kubectl rollout restart deployment matter-server -n home-automation
```

#### 2. Complete System Recovery

**Full Stack Recovery:**

```bash
# Restore complete home-automation namespace
kubectl delete namespace home-automation
kubectl create namespace home-automation

# Apply backed up configuration
kubectl apply -f home-automation-backup-YYYYMMDD.yaml

# Verify all components are restored
kubectl get pods -n home-automation

# Test Matter Server functionality
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server
```

**Device Re-commissioning After Recovery:**

- Some devices may need to be re-commissioned after major recovery
- Follow device addition procedures for affected devices
- Update device inventory with any changes

### Disaster Recovery Planning

#### 1. Recovery Time Objectives (RTO)

**Target Recovery Times:**

- **Matter Server Pod Recovery:** 5 minutes (automatic restart)
- **Data Recovery from Snapshot:** 15 minutes
- **Complete System Recovery:** 30 minutes
- **Device Re-commissioning:** 5-10 minutes per device

#### 2. Recovery Point Objectives (RPO)

**Data Loss Tolerance:**

- **Matter Certificates:** Maximum 24 hours (daily snapshots)
- **Device Configuration:** Maximum 1 hour (frequent snapshots)
- **Operational Data:** Maximum 15 minutes (continuous replication)

#### 3. Disaster Recovery Testing

**Monthly DR Test:**

```bash
# Test snapshot restoration (non-production)
# 1. Create test namespace
kubectl create namespace matter-test

# 2. Restore from snapshot to test namespace
# 3. Verify data integrity
# 4. Clean up test environment
kubectl delete namespace matter-test
```

## Security Management

### Certificate Management

#### 1. Matter Certificate Monitoring

**Certificate Health Check:**

```bash
# Check Matter certificate storage
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ls -la /data/certificates/

# Monitor certificate expiration (if applicable)
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  find /data -name "*.pem" -o -name "*.crt" | xargs ls -la

# Check for certificate-related errors in logs
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server | grep -i certificate
```

#### 2. Certificate Rotation

**Automatic Certificate Management:**

- Matter Server handles certificate lifecycle automatically
- Monitor logs for certificate renewal activities
- Backup certificates as part of regular data backup

**Manual Certificate Intervention (if needed):**

```bash
# Only perform if directed by Matter Server documentation
# Backup existing certificates before any manual intervention
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  cp -r /data/certificates /data/certificates-backup-$(date +%Y%m%d)
```

### Access Control

#### 1. RBAC Monitoring

**Service Account Permissions:**

```bash
# Verify Matter Server service account permissions
kubectl describe serviceaccount matter-server -n home-automation

# Check for any permission escalation
kubectl auth can-i --list --as=system:serviceaccount:home-automation:matter-server
```

#### 2. Network Security

**Network Policy Validation:**

```bash
# Check network policies affecting Matter Server
kubectl get networkpolicies -n home-automation

# Verify required network access
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  nc -zv matter-server.home-automation.svc.cluster.local 5580
```

**Host Network Security:**

```bash
# Monitor host network access (required for Matter Server)
kubectl get pod -n home-automation -l app.kubernetes.io/name=matter-server -o yaml | grep hostNetwork

# Expected: hostNetwork: true (required for Matter device discovery)
```

### Security Incident Response

#### 1. Security Alert Procedures

**Suspicious Activity Detection:**

```bash
# Monitor for unusual network activity
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server | grep -E "unauthorized|failed|denied"

# Check for unexpected device connections
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server | grep -i "new device\|commission"
```

**Incident Response Steps:**

1. **Isolate Affected Components:**

   ```bash
   # If security incident detected, isolate Matter Server
   kubectl scale deployment matter-server -n home-automation --replicas=0
   ```

2. **Collect Evidence:**

   ```bash
   # Collect logs for analysis
   kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server --since=24h > matter-incident-logs.txt

   # Export configuration for analysis
   kubectl get pod -n home-automation -l app.kubernetes.io/name=matter-server -o yaml > matter-incident-config.yaml
   ```

3. **Recovery Actions:**
   - Restore from known good backup
   - Re-commission devices if necessary
   - Update security configurations

## Monitoring and Alerting

### Metrics Collection

#### 1. Matter Server Metrics

**Resource Metrics:**

```bash
# Collect CPU and memory metrics
kubectl top pods -n home-automation -l app.kubernetes.io/name=matter-server --containers

# Storage metrics
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  df -h /data | tail -1 | awk '{print "Storage Usage: " $5 " of " $2}'
```

**Application Metrics:**

```bash
# WebSocket connection count (if exposed by Matter Server)
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server --tail=100 | grep -c "WebSocket.*connected"

# Device count (manual verification via Home Assistant interface required)
# Navigate to Settings → Devices & Services → Matter
```

#### 2. Integration with Cluster Monitoring

**Prometheus Integration:**

```bash
# Verify Matter Server is included in monitoring
kubectl get servicemonitor -n home-automation | grep matter-server

# Check if metrics endpoint is available
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  curl -s http://localhost:5580/metrics || echo "Metrics endpoint not available"
```

**Grafana Dashboard:**

- Create Matter Server dashboard in Grafana
- Include pod health, resource usage, and device count metrics
- Set up alerts for critical thresholds

### Alert Configuration

#### 1. Critical Alerts

**Pod Health Alerts:**

```yaml
# Example Prometheus alert rule
groups:
  - name: matter-server
    rules:
      - alert: MatterServerDown
        expr: up{job="matter-server"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Matter Server is down"
          description: "Matter Server pod has been down for more than 5 minutes"
```

**Resource Usage Alerts:**

```yaml
- alert: MatterServerHighMemory
  expr: container_memory_usage_bytes{pod=~"matter-server.*"} / container_spec_memory_limit_bytes > 0.8
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Matter Server high memory usage"
    description: "Matter Server memory usage is above 80%"
```

#### 2. Warning Alerts

**Performance Alerts:**

```yaml
- alert: MatterServerHighCPU
  expr: rate(container_cpu_usage_seconds_total{pod=~"matter-server.*"}[5m]) > 0.5
  for: 15m
  labels:
    severity: warning
  annotations:
    summary: "Matter Server high CPU usage"
    description: "Matter Server CPU usage is above 50%"
```

**Storage Alerts:**

```yaml
- alert: MatterServerStorageFull
  expr: kubelet_volume_stats_used_bytes{persistentvolumeclaim="matter-server-data"} / kubelet_volume_stats_capacity_bytes{persistentvolumeclaim="matter-server-data"} > 0.85
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Matter Server storage usage high"
    description: "Matter Server storage usage is above 85%"
```

### Log Management

#### 1. Log Aggregation

**Centralized Logging:**

```bash
# Configure log forwarding to centralized logging system
# This depends on your logging infrastructure (ELK, Loki, etc.)

# Verify logs are being collected
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server --tail=1
```

**Log Retention:**

```bash
# Configure log retention policies
# Retain Matter Server logs for at least 30 days for troubleshooting
# Archive older logs for compliance if required
```

#### 2. Log Analysis

**Automated Log Analysis:**

```bash
# Create log analysis script
cat > analyze-matter-logs.sh << 'EOF'
#!/bin/bash
# Analyze Matter Server logs for common issues

echo "=== Matter Server Log Analysis - $(date) ==="

# Get recent logs
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server --tail=1000 > /tmp/matter-logs.txt

# Count error types
echo "Error Summary:"
grep -i error /tmp/matter-logs.txt | sort | uniq -c | sort -nr | head -10

# Check for connection issues
echo -e "\nConnection Issues:"
grep -i "connection\|timeout\|disconnect" /tmp/matter-logs.txt | wc -l

# Device commissioning activity
echo -e "\nCommissioning Activity:"
grep -i "commission" /tmp/matter-logs.txt | wc -l

# WebSocket activity
echo -e "\nWebSocket Connections:"
grep -i websocket /tmp/matter-logs.txt | tail -5

rm /tmp/matter-logs.txt
EOF

chmod +x analyze-matter-logs.sh
```

## Maintenance Tasks

### Regular Maintenance Schedule

#### 1. Daily Tasks

- [ ] Check pod health and status
- [ ] Verify WebSocket connectivity
- [ ] Monitor resource usage
- [ ] Review error logs
- [ ] Test sample device connectivity

#### 2. Weekly Tasks

- [ ] Generate health report
- [ ] Analyze log patterns
- [ ] Review device inventory
- [ ] Check backup integrity
- [ ] Update documentation

#### 3. Monthly Tasks

- [ ] Review and update monitoring dashboards
- [ ] Test disaster recovery procedures
- [ ] Analyze performance trends
- [ ] Update security configurations
- [ ] Plan capacity upgrades if needed

### Upgrade Procedures

#### 1. Matter Server Upgrades

**Pre-Upgrade Checklist:**

```bash
# Create backup before upgrade
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: matter-server-pre-upgrade-$(date +%Y%m%d)
  namespace: home-automation
spec:
  source:
    persistentVolumeClaimName: matter-server-data
EOF

# Verify backup creation
kubectl get volumesnapshots -n home-automation | grep pre-upgrade
```

**Upgrade Process:**

```bash
# Update Helm chart version in helmrelease.yaml
# Commit changes to Git repository
# Monitor Flux reconciliation

# Verify upgrade success
kubectl get pods -n home-automation -l app.kubernetes.io/name=matter-server
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server --tail=50
```

**Post-Upgrade Validation:**

```bash
# Test WebSocket connectivity
kubectl exec -n home-automation deployment/home-assistant -- \
  curl -I --http1.1 --upgrade WebSocket http://localhost:5580/ws

# Test device functionality via Home Assistant interface
# Verify all devices are responsive and functional
```

#### 2. Rollback Procedures

**Automatic Rollback:**

```bash
# If upgrade fails, Flux will automatically rollback
# Monitor rollback process
flux get helmreleases -n home-automation matter-server

# Verify rollback success
kubectl get pods -n home-automation -l app.kubernetes.io/name=matter-server
```

**Manual Rollback:**

```bash
# If manual rollback needed, revert Git changes
git revert <upgrade-commit-hash>
git push

# Or restore from pre-upgrade snapshot
# Follow data recovery procedures using pre-upgrade snapshot
```

### Capacity Planning

#### 1. Resource Planning

**Growth Projections:**

```bash
# Monitor resource usage trends
# Plan for device growth (estimate 10-20MB per device)
# Consider CPU scaling for large device counts (>50 devices)

# Calculate storage requirements
echo "Current device count: [Manual count from Home Assistant]"
echo "Projected growth: [Estimate new devices per month]"
echo "Storage planning: [Current usage + growth projection]"
```

**Scaling Recommendations:**

- **CPU**: Increase limits if consistently above 300m
- **Memory**: Increase if consistently above 400Mi
- **Storage**: Plan for 100MB per 10 devices plus certificates
- **Network**: Consider dedicated VLAN for large IoT deployments

#### 2. Performance Optimization

**Network Optimization:**

```bash
# Monitor network latency to devices
kubectl exec -n home-automation -l app.kubernetes.io/name=matter-server -- \
  ping -c 10 <device-subnet-gateway>

# Consider Thread network optimization for Thread devices
# Plan for Thread Border Router deployment if needed
```

**Resource Optimization:**

```bash
# Optimize resource requests and limits based on actual usage
# Monitor and adjust based on device count and activity
# Consider node affinity for optimal placement
```

## Support and Escalation

### Internal Support Procedures

#### 1. First-Level Support

**Common Issue Resolution:**

- Pod restart issues → Check resource availability and logs
- Device connectivity → Verify network and device status
- Performance issues → Check resource usage and network latency
- WebSocket issues → Restart Home Assistant and Matter Server

#### 2. Escalation Criteria

**Escalate to Second-Level Support:**

- Persistent pod crashes after restart
- Data corruption or loss
- Security incidents
- Performance degradation affecting multiple devices

### External Support Resources

#### 1. Documentation Resources

- **Matter Specification**: <https://csa-iot.org/all-solutions/matter/>
- **Home Assistant Matter Integration**: <https://www.home-assistant.io/integrations/matter/>
- **Python Matter Server**: <https://github.com/home-assistant-libs/python-matter-server>
- **Helm Chart Documentation**: <https://github.com/derwitt-dev/helm-charts>

#### 2. Community Support

- **Home Assistant Community**: <https://community.home-assistant.io/>
- **Matter Developer Community**: <https://github.com/project-chip/connectedhomeip>
- **Kubernetes Community**: <https://kubernetes.io/community/>

### Incident Management

#### 1. Incident Classification

**Severity Levels:**

- **Critical**: Complete service outage, security breach
- **High**: Significant functionality loss, multiple device failures
- **Medium**: Single device issues, performance degradation
- **Low**: Minor issues, cosmetic problems

#### 2. Response Procedures

**Critical Incident Response:**

1. **Immediate Actions:**
   - Assess impact and scope
   - Implement temporary workarounds
   - Notify stakeholders

2. **Investigation:**
   - Collect logs and configuration
   - Identify root cause
   - Document findings

3. **Resolution:**
   - Implement permanent fix
   - Verify resolution
   - Update documentation

4. **Post-Incident:**
   - Conduct post-mortem review
   - Update procedures
   - Implement preventive measures

---

## Operational Checklist Templates

### Daily Operations Checklist

```markdown
# Matter Server Daily Operations - [DATE]

## Health Checks

- [ ] Pod status: Running (1/1 Ready)
- [ ] WebSocket connectivity: Functional
- [ ] Resource usage: Within normal limits
- [ ] Error logs: No critical errors
- [ ] Device connectivity: Sample devices responsive

## Performance Monitoring

- [ ] CPU usage: \_\_\_m (target: <200m)
- [ ] Memory usage: \_\_\_Mi (target: <400Mi)
- [ ] Storage usage: \_\_% (target: <80%)
- [ ] Response times: Normal (<2s)

## Issues Identified

- [ ] None
- [ ] [Describe any issues and actions taken]

## Notes

[Add any operational notes or observations]

Completed by: [Name]
Time: [Time]
```

### Weekly Maintenance Checklist

```markdown
# Matter Server Weekly Maintenance - [DATE]

## System Health Review

- [ ] Generated weekly health report
- [ ] Analyzed log patterns
- [ ] Reviewed device inventory
- [ ] Checked backup integrity
- [ ] Updated documentation

## Performance Analysis

- [ ] Resource usage trends reviewed
- [ ] Device response time analysis
- [ ] Network connectivity assessment
- [ ] Storage growth evaluation

## Maintenance Actions

- [ ] Log cleanup performed
- [ ] Configuration updates applied
- [ ] Security patches reviewed
- [ ] Monitoring dashboards updated

## Planning

- [ ] Capacity planning reviewed
- [ ] Upgrade schedule confirmed
- [ ] Training needs identified
- [ ] Process improvements noted

Completed by: [Name]
Date: [Date]
```

---

_This operational procedures guide provides comprehensive guidance for managing the Matter Server integration in production environments. Follow these procedures to ensure reliable and secure Matter device support in your Home Assistant deployment._
