# Operational Procedures Update - GitOps Lifecycle Management

## Overview

This document outlines the updated operational procedures following the successful migration to the GitOps lifecycle management system. These procedures replace the previous job-based workflows and provide standardized approaches for daily operations, maintenance, and troubleshooting.

## Daily Operations

### System Health Monitoring

#### Morning Health Check Routine

```bash
#!/bin/bash
# Daily morning health check - save as scripts/daily-health-check.sh

echo "=== GitOps Lifecycle Management Daily Health Check ==="
echo "Date: $(date)"
echo

# 1. Check overall system status
echo "1. Checking GitOps Lifecycle Management System Status..."
kubectl get helmrelease gitops-lifecycle-management -n flux-system
kubectl get pods -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management

# 2. Check service discovery controller
echo -e "\n2. Checking Service Discovery Controller..."
kubectl get deployment gitops-lifecycle-management-service-discovery -n flux-system
READY_REPLICAS=$(kubectl get deployment gitops-lifecycle-management-service-discovery -n flux-system -o jsonpath='{.status.readyReplicas}')
DESIRED_REPLICAS=$(kubectl get deployment gitops-lifecycle-management-service-discovery -n flux-system -o jsonpath='{.spec.replicas}')

if [ "$READY_REPLICAS" = "$DESIRED_REPLICAS" ]; then
    echo "✅ Service Discovery Controller: $READY_REPLICAS/$DESIRED_REPLICAS replicas ready"
else
    echo "❌ Service Discovery Controller: $READY_REPLICAS/$DESIRED_REPLICAS replicas ready"
fi

# 3. Check ProxyConfig resources
echo -e "\n3. Checking ProxyConfig Resources..."
kubectl get proxyconfigs --all-namespaces
PENDING_CONFIGS=$(kubectl get proxyconfigs --all-namespaces -o json | jq -r '.items[] | select(.status.phase == "Pending") | "\(.metadata.namespace)/\(.metadata.name)"')

if [ -z "$PENDING_CONFIGS" ]; then
    echo "✅ All ProxyConfig resources are in Ready state"
else
    echo "⚠️  Pending ProxyConfig resources:"
    echo "$PENDING_CONFIGS"
fi

# 4. Check recent errors
echo -e "\n4. Checking Recent Errors (last 2 hours)..."
ERROR_COUNT=$(kubectl logs -n flux-system -l app.kubernetes.io/component=service-discovery-controller --since=2h | grep -i error | wc -l)
if [ "$ERROR_COUNT" -eq 0 ]; then
    echo "✅ No errors in the last 2 hours"
else
    echo "⚠️  Found $ERROR_COUNT errors in the last 2 hours"
    kubectl logs -n flux-system -l app.kubernetes.io/component=service-discovery-controller --since=2h | grep -i error | tail -5
fi

# 5. Check Prometheus alerts
echo -e "\n5. Checking Active Alerts..."
if command -v curl >/dev/null 2>&1; then
    ACTIVE_ALERTS=$(curl -s http://prometheus.k8s.home.geoffdavis.com/api/v1/alerts 2>/dev/null | \
        jq -r '.data.alerts[] | select(.labels.component | contains("gitops")) | select(.state == "firing") | .labels.alertname' 2>/dev/null)

    if [ -z "$ACTIVE_ALERTS" ]; then
        echo "✅ No active GitOps-related alerts"
    else
        echo "🚨 Active alerts:"
        echo "$ACTIVE_ALERTS"
    fi
else
    echo "⚠️  curl not available, skipping alert check"
fi

echo -e "\n=== Health Check Complete ==="
```

#### Continuous Monitoring Tasks

**Service Discovery Controller Monitoring**:

```bash
# Check controller logs for issues
kubectl logs -n flux-system -l app.kubernetes.io/component=service-discovery-controller --tail=50

# Monitor ProxyConfig processing
watch kubectl get proxyconfigs --all-namespaces
```

**Cleanup Controller Monitoring**:

```bash
# Check cleanup metrics (if Prometheus is available)
curl -s http://prometheus.k8s.home.geoffdavis.com/api/v1/query?query=gitops_cleanup_cycle_duration_seconds

# Monitor cleanup activities
kubectl logs -n flux-system -l app.kubernetes.io/component=cleanup-controller --tail=20
```

### Adding New Services

#### Standard Service Onboarding Process

**Step 1: Create ProxyConfig Resource**

```yaml
# Save as service-configs/<service-name>-proxy-config.yaml
apiVersion: gitops.io/v1
kind: ProxyConfig
metadata:
  name: <service-name>-proxy
  namespace: <service-namespace>
  labels:
    app.kubernetes.io/name: <service-name>
    app.kubernetes.io/component: authentication
spec:
  serviceName: <service-name>
  serviceNamespace: <service-namespace>
  externalHost: <service-name>.k8s.home.geoffdavis.com
  internalHost: http://<service-name>.<service-namespace>.svc.cluster.local:<port>
  port: <service-port>
  protocol: http
  authentikConfig:
    enabled: true
    providerName: <service-name>-proxy
    mode: forward_single
    skipPathRegex: "^/api/.*$"
    basicAuthEnabled: false
    internalHostSslValidation: false
  labels:
    environment: production
    team: <team-name>
  annotations:
    description: "Authentication proxy for <service-name>"
```

**Step 2: Deploy ProxyConfig**

```bash
# Apply the ProxyConfig resource
kubectl apply -f service-configs/<service-name>-proxy-config.yaml

# Monitor ProxyConfig status
kubectl get proxyconfig <service-name>-proxy -n <service-namespace> -w

# Check for successful provider creation
kubectl describe proxyconfig <service-name>-proxy -n <service-namespace>
```

**Step 3: Verify Service Integration**

```bash
# Check Authentik proxy provider creation
curl -s -H "Authorization: Bearer $AUTHENTIK_TOKEN" \
  http://authentik-server.authentik.svc.cluster.local:9000/api/v3/providers/proxy/ | \
  jq '.results[] | select(.name == "<service-name>-proxy")'

# Test service access
curl -I https://<service-name>.k8s.home.geoffdavis.com
```

**Step 4: Update Service Documentation**

```bash
# Add service to monitoring dashboard
# Update service inventory
# Document service-specific configuration
```

### Service Configuration Updates

#### Updating Existing ProxyConfig Resources

```bash
# Edit ProxyConfig resource
kubectl edit proxyconfig <service-name>-proxy -n <service-namespace>

# Monitor reconciliation
kubectl logs -n flux-system -l app.kubernetes.io/component=service-discovery-controller | \
  grep -A 5 -B 5 "<service-name>-proxy"

# Verify changes in Authentik
# Check provider configuration in Authentik admin interface
```

#### Bulk Configuration Updates

```bash
# Update multiple ProxyConfig resources
kubectl get proxyconfigs --all-namespaces -o yaml > proxyconfigs-backup.yaml

# Apply bulk changes using kubectl patch or yq
kubectl get proxyconfigs --all-namespaces -o name | \
  xargs -I {} kubectl patch {} --type='merge' -p='{"spec":{"authentikConfig":{"skipPathRegex":"^/(api|health)/.*$"}}}'
```

## Maintenance Procedures

### Weekly Maintenance Tasks

#### System Health Assessment

```bash
#!/bin/bash
# Weekly maintenance script - save as scripts/weekly-maintenance.sh

echo "=== Weekly GitOps Lifecycle Management Maintenance ==="
echo "Date: $(date)"

# 1. Check resource usage trends
echo "1. Checking Resource Usage..."
kubectl top pods -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management

# 2. Review error patterns
echo -e "\n2. Reviewing Error Patterns (last 7 days)..."
kubectl logs -n flux-system -l app.kubernetes.io/component=service-discovery-controller --since=168h | \
  grep -i error | sort | uniq -c | sort -nr | head -10

# 3. Check ProxyConfig resource health
echo -e "\n3. Checking ProxyConfig Resource Health..."
kubectl get proxyconfigs --all-namespaces -o json | \
  jq -r '.items[] | select(.status.phase != "Ready") | "\(.metadata.namespace)/\(.metadata.name): \(.status.phase)"'

# 4. Validate Authentik provider consistency
echo -e "\n4. Validating Authentik Provider Consistency..."
PROXYCONFIG_COUNT=$(kubectl get proxyconfigs --all-namespaces --no-headers | wc -l)
echo "ProxyConfig resources: $PROXYCONFIG_COUNT"

# 5. Check cleanup controller effectiveness
echo -e "\n5. Checking Cleanup Controller Effectiveness..."
COMPLETED_JOBS=$(kubectl get jobs --all-namespaces --field-selector=status.successful=1 | wc -l)
FAILED_JOBS=$(kubectl get jobs --all-namespaces --field-selector=status.failed=1 | wc -l)
echo "Completed jobs: $COMPLETED_JOBS"
echo "Failed jobs: $FAILED_JOBS"

# 6. Performance metrics review
echo -e "\n6. Performance Metrics Review..."
if command -v curl >/dev/null 2>&1; then
    AVG_RECONCILE_TIME=$(curl -s http://prometheus.k8s.home.geoffdavis.com/api/v1/query?query=avg\(gitops_proxyconfig_reconcile_duration_seconds\) 2>/dev/null | \
        jq -r '.data.result[0].value[1]' 2>/dev/null)
    if [ "$AVG_RECONCILE_TIME" != "null" ] && [ -n "$AVG_RECONCILE_TIME" ]; then
        echo "Average reconcile time: ${AVG_RECONCILE_TIME}s"
    fi
fi

echo -e "\n=== Weekly Maintenance Complete ==="
```

#### Configuration Backup

```bash
#!/bin/bash
# Configuration backup script

BACKUP_DIR="backups/gitops-lifecycle-$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# Backup Helm values
helm get values gitops-lifecycle-management -n flux-system > "$BACKUP_DIR/helm-values.yaml"

# Backup ProxyConfig resources
kubectl get proxyconfigs --all-namespaces -o yaml > "$BACKUP_DIR/proxyconfigs.yaml"

# Backup CRD
kubectl get crd proxyconfigs.gitops.io -o yaml > "$BACKUP_DIR/proxyconfig-crd.yaml"

# Backup monitoring configuration
kubectl get prometheusrule gitops-lifecycle-management-alerts -n flux-system -o yaml > "$BACKUP_DIR/prometheus-rules.yaml"

echo "Backup completed in $BACKUP_DIR"
```

### Monthly Maintenance Tasks

#### Performance Optimization Review

```bash
# 1. Analyze resource usage patterns
kubectl top pods -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management --containers

# 2. Review reconciliation performance
# Check Prometheus metrics for trends
curl -s http://prometheus.k8s.home.geoffdavis.com/api/v1/query_range?query=gitops_proxyconfig_reconcile_duration_seconds&start=$(date -d '30 days ago' +%s)&end=$(date +%s)&step=3600

# 3. Optimize resource limits if needed
kubectl patch deployment gitops-lifecycle-management-service-discovery -n flux-system -p '{"spec":{"template":{"spec":{"containers":[{"name":"controller","resources":{"limits":{"cpu":"200m","memory":"256Mi"}}}]}}}}'
```

#### Security Review

```bash
# 1. Review RBAC permissions
kubectl describe clusterrole gitops-lifecycle-management
kubectl describe clusterrolebinding gitops-lifecycle-management

# 2. Check security contexts
kubectl get deployment gitops-lifecycle-management-service-discovery -n flux-system -o yaml | grep -A 10 securityContext

# 3. Validate secret management
kubectl get externalsecrets -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management
```

### Upgrade Procedures

#### Helm Chart Upgrades

```bash
# 1. Backup current configuration
helm get values gitops-lifecycle-management -n flux-system > pre-upgrade-values.yaml

# 2. Review upgrade changes
helm diff upgrade gitops-lifecycle-management ./charts/gitops-lifecycle-management -n flux-system

# 3. Perform upgrade
helm upgrade gitops-lifecycle-management ./charts/gitops-lifecycle-management -n flux-system

# 4. Verify upgrade success
kubectl rollout status deployment gitops-lifecycle-management-service-discovery -n flux-system
kubectl get proxyconfigs --all-namespaces | grep -v Ready
```

#### CRD Upgrades

```bash
# 1. Backup existing CRD and resources
kubectl get crd proxyconfigs.gitops.io -o yaml > proxyconfig-crd-backup.yaml
kubectl get proxyconfigs --all-namespaces -o yaml > proxyconfigs-backup.yaml

# 2. Apply new CRD version
kubectl apply -f charts/gitops-lifecycle-management/templates/crds/proxyconfig-crd.yaml

# 3. Validate existing resources
kubectl get proxyconfigs --all-namespaces
```

## Incident Response Procedures

### Severity Levels

#### Severity 1: Critical System Failure

**Definition**: Complete GitOps lifecycle management system failure affecting multiple services

**Response Procedure**:

1. **Immediate Assessment** (0-5 minutes):

   ```bash
   # Check system status
   kubectl get pods -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management
   kubectl get helmrelease gitops-lifecycle-management -n flux-system
   ```

2. **Emergency Mitigation** (5-15 minutes):

   ```bash
   # Attempt quick restart
   kubectl rollout restart deployment gitops-lifecycle-management-service-discovery -n flux-system

   # If restart fails, rollback
   helm rollback gitops-lifecycle-management -n flux-system
   ```

3. **Service Restoration** (15-30 minutes):
   ```bash
   # Manual service configuration if needed
   kubectl apply -f infrastructure/authentik-outpost-config/longhorn-proxy-config-job.yaml
   kubectl apply -f infrastructure/authentik-outpost-config/monitoring-proxy-config-job.yaml
   ```

#### Severity 2: Partial System Degradation

**Definition**: Some ProxyConfig resources failing, but system partially functional

**Response Procedure**:

1. **Identify Affected Services** (0-10 minutes):

   ```bash
   kubectl get proxyconfigs --all-namespaces | grep -v Ready
   kubectl logs -n flux-system -l app.kubernetes.io/component=service-discovery-controller --tail=100
   ```

2. **Targeted Resolution** (10-30 minutes):

   ```bash
   # Restart controller if needed
   kubectl rollout restart deployment gitops-lifecycle-management-service-discovery -n flux-system

   # Fix specific ProxyConfig issues
   kubectl describe proxyconfig <failing-config> -n <namespace>
   ```

#### Severity 3: Performance Degradation

**Definition**: System functional but performing poorly

**Response Procedure**:

1. **Performance Analysis** (0-15 minutes):

   ```bash
   kubectl top pods -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management
   kubectl logs -n flux-system -l app.kubernetes.io/component=service-discovery-controller | grep -i "slow\|timeout"
   ```

2. **Optimization** (15-45 minutes):

   ```bash
   # Increase resource limits
   kubectl patch deployment gitops-lifecycle-management-service-discovery -n flux-system -p '{"spec":{"template":{"spec":{"containers":[{"name":"controller","resources":{"limits":{"cpu":"200m","memory":"256Mi"}}}]}}}}'

   # Adjust reconciliation interval
   # Update Helm values and redeploy
   ```

### Communication Procedures

#### Incident Communication Template

```
Subject: [INCIDENT] GitOps Lifecycle Management - <Severity Level>

Incident Summary:
- Start Time: <timestamp>
- Severity: <1/2/3>
- Impact: <description of affected services>
- Status: <investigating/mitigating/resolved>

Current Actions:
- <list of actions being taken>

Next Update: <timestamp>

Contact: <incident commander>
```

#### Status Page Updates

```bash
# Update status page (if available)
curl -X POST https://status.example.com/api/incidents \
  -H "Authorization: Bearer $STATUS_TOKEN" \
  -d '{
    "name": "GitOps Lifecycle Management Issue",
    "status": "investigating",
    "message": "Investigating issues with service authentication"
  }'
```

## Change Management

### Change Categories

#### Standard Changes

**Definition**: Low-risk changes following established procedures

**Examples**:

- Adding new ProxyConfig resources
- Updating service configurations
- Routine maintenance tasks

**Approval**: Team lead approval required

#### Normal Changes

**Definition**: Medium-risk changes requiring testing

**Examples**:

- Helm chart upgrades
- CRD updates
- Resource limit adjustments

**Approval**: Change advisory board approval required

#### Emergency Changes

**Definition**: High-risk changes required for incident resolution

**Examples**:

- Emergency rollbacks
- Critical security patches
- System recovery procedures

**Approval**: Incident commander approval

### Change Implementation Process

#### Pre-Change Checklist

```bash
# 1. Backup current configuration
helm get values gitops-lifecycle-management -n flux-system > pre-change-backup.yaml
kubectl get proxyconfigs --all-namespaces -o yaml > proxyconfigs-pre-change.yaml

# 2. Test in development environment
# Apply changes to dev cluster first

# 3. Prepare rollback plan
# Document rollback procedures

# 4. Schedule maintenance window
# Notify stakeholders
```

#### Post-Change Validation

```bash
# 1. Verify system health
kubectl get pods -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management
kubectl get proxyconfigs --all-namespaces | grep -v Ready

# 2. Test service functionality
curl -I https://longhorn.k8s.home.geoffdavis.com
curl -I https://grafana.k8s.home.geoffdavis.com

# 3. Monitor for issues
kubectl logs -n flux-system -l app.kubernetes.io/component=service-discovery-controller --tail=50

# 4. Update documentation
# Document any configuration changes
```

## Monitoring and Alerting

### Key Metrics to Monitor

#### System Health Metrics

- Controller pod status and restart count
- ProxyConfig resource status distribution
- Helm release status
- Resource usage (CPU, memory)

#### Performance Metrics

- ProxyConfig reconciliation duration
- API call success rates
- Cleanup operation effectiveness
- Error rates and patterns

#### Business Metrics

- Number of services under management
- Authentication success rates
- Service availability
- Mean time to recovery

### Alert Response Procedures

#### Controller Down Alert

```bash
# 1. Check pod status
kubectl get pods -n flux-system -l app.kubernetes.io/component=service-discovery-controller

# 2. Check recent events
kubectl get events -n flux-system --sort-by='.lastTimestamp' | tail -10

# 3. Restart if needed
kubectl rollout restart deployment gitops-lifecycle-management-service-discovery -n flux-system
```

#### High Error Rate Alert

```bash
# 1. Analyze error patterns
kubectl logs -n flux-system -l app.kubernetes.io/component=service-discovery-controller --since=1h | grep -i error | sort | uniq -c

# 2. Check Authentik connectivity
kubectl exec -n flux-system deployment/gitops-lifecycle-management-service-discovery -- \
  curl -s http://authentik-server.authentik.svc.cluster.local:9000/api/v3/core/users/me/

# 3. Investigate specific failures
kubectl get proxyconfigs --all-namespaces | grep -v Ready
```

## Documentation Maintenance

### Documentation Update Schedule

- **Daily**: Update operational logs and incident reports
- **Weekly**: Review and update troubleshooting procedures
- **Monthly**: Update architectural documentation and runbooks
- **Quarterly**: Comprehensive documentation review and reorganization

### Documentation Standards

- All procedures must include example commands
- Error scenarios must include diagnostic steps
- Changes must be version controlled
- Documentation must be tested regularly

## Training and Knowledge Transfer

### Operator Training Requirements

1. **Basic Operations**: Daily health checks, service onboarding
2. **Troubleshooting**: Common issues and resolution procedures
3. **Incident Response**: Emergency procedures and communication
4. **Change Management**: Safe change implementation practices

### Knowledge Transfer Procedures

1. **Documentation Review**: New operators must review all operational procedures
2. **Shadowing**: New operators shadow experienced team members
3. **Hands-on Practice**: Practice procedures in development environment
4. **Certification**: Complete operational competency assessment

## Conclusion

These updated operational procedures provide a comprehensive framework for managing the GitOps lifecycle management system. Regular adherence to these procedures will ensure system reliability, quick incident resolution, and smooth day-to-day operations.

Key operational improvements achieved:

- ✅ **Standardized Procedures**: Consistent approaches across all operations
- ✅ **Automated Health Checks**: Proactive monitoring and issue detection
- ✅ **Structured Incident Response**: Clear escalation and resolution procedures
- ✅ **Comprehensive Change Management**: Safe and controlled change implementation
- ✅ **Continuous Improvement**: Regular review and optimization processes

Teams should customize these procedures based on their specific operational requirements and integrate them with existing operational frameworks and tools.
