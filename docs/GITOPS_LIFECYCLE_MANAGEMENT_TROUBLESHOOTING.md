# GitOps Lifecycle Management Troubleshooting Guide

## Overview

This guide provides comprehensive troubleshooting procedures for the GitOps lifecycle management system, covering common issues, diagnostic procedures, and resolution steps for all components.

## Quick Diagnostic Commands

### System Health Check

```bash
# Check overall system status
kubectl get helmrelease gitops-lifecycle-management -n flux-system
kubectl get pods -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management

# Check service discovery controller
kubectl get deployment gitops-lifecycle-management-service-discovery -n flux-system
kubectl logs -n flux-system -l app.kubernetes.io/component=service-discovery-controller

# Check ProxyConfig resources
kubectl get proxyconfigs --all-namespaces
kubectl get proxyconfigs --all-namespaces -o wide
```

### Monitoring and Alerts

```bash
# Check Prometheus alerts
kubectl get prometheusrule gitops-lifecycle-management-alerts -n flux-system

# View current alerts (if Prometheus is accessible)
curl -s http://prometheus.k8s.home.geoffdavis.com/api/v1/alerts | jq '.data.alerts[] | select(.labels.component | contains("gitops"))'

# Check ServiceMonitor
kubectl get servicemonitor -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management
```

## Component-Specific Troubleshooting

### 1. Service Discovery Controller Issues

#### Symptoms

- ProxyConfig resources stuck in "Pending" phase
- Services not getting Authentik proxy providers created
- Controller pod restarting frequently

#### Diagnostic Steps

```bash
# Check controller status
kubectl get deployment gitops-lifecycle-management-service-discovery -n flux-system
kubectl describe deployment gitops-lifecycle-management-service-discovery -n flux-system

# Check controller logs
kubectl logs -n flux-system -l app.kubernetes.io/component=service-discovery-controller --tail=100

# Check ProxyConfig status
kubectl get proxyconfigs --all-namespaces -o yaml | grep -A 10 -B 5 "phase\|conditions"

# Check Authentik connectivity
kubectl exec -n flux-system deployment/gitops-lifecycle-management-service-discovery -- \
  curl -s -H "Authorization: Bearer $AUTHENTIK_TOKEN" \
  http://authentik-server.authentik.svc.cluster.local:9000/api/v3/core/users/me/
```

#### Common Issues and Solutions

##### Issue: Controller Cannot Connect to Authentik

**Symptoms**: Logs show "connection refused" or "timeout" errors

**Diagnosis**:

```bash
# Check Authentik service status
kubectl get svc -n authentik authentik-server
kubectl get pods -n authentik -l app.kubernetes.io/component=server

# Test network connectivity
kubectl run debug-pod --rm -i --tty --image=curlimages/curl -- \
  curl -v http://authentik-server.authentik.svc.cluster.local:9000/api/v3/core/users/me/
```

**Solutions**:

1. **Authentik Service Down**: Restart Authentik deployment

   ```bash
   kubectl rollout restart deployment authentik-server -n authentik
   ```

2. **Network Policy Issues**: Check network policies

   ```bash
   kubectl get networkpolicies -n authentik
   kubectl get networkpolicies -n flux-system
   ```

3. **DNS Resolution Issues**: Check CoreDNS
   ```bash
   kubectl get pods -n kube-system -l k8s-app=kube-dns
   kubectl logs -n kube-system -l k8s-app=kube-dns
   ```

##### Issue: Authentication Token Invalid

**Symptoms**: Logs show "401 Unauthorized" or "403 Forbidden" errors

**Diagnosis**:

```bash
# Check token secret
kubectl get secret authentik-admin-token -n flux-system -o yaml

# Verify token in Authentik
kubectl exec -n authentik deployment/authentik-server -- \
  ak shell -c "from authentik.core.models import Token; print([t.key[:8] + '...' for t in Token.objects.filter(intent='api')])"
```

**Solutions**:

1. **Token Expired**: Regenerate token using enhanced token setup

   ```bash
   kubectl delete job authentik-enhanced-token-setup -n authentik
   flux reconcile kustomization infrastructure-authentik-outpost-config -n flux-system
   ```

2. **Token Not Synced**: Force external secret refresh
   ```bash
   kubectl annotate externalsecret authentik-admin-token -n flux-system \
     force-sync=$(date +%s) --overwrite
   ```

##### Issue: ProxyConfig Resources Stuck

**Symptoms**: ProxyConfig shows "Pending" phase for extended periods

**Diagnosis**:

```bash
# Check specific ProxyConfig
kubectl describe proxyconfig <name> -n <namespace>

# Check controller processing
kubectl logs -n flux-system -l app.kubernetes.io/component=service-discovery-controller | \
  grep -A 5 -B 5 "<proxyconfig-name>"
```

**Solutions**:

1. **Invalid Configuration**: Fix ProxyConfig spec

   ```bash
   kubectl edit proxyconfig <name> -n <namespace>
   ```

2. **Controller Stuck**: Restart controller

   ```bash
   kubectl rollout restart deployment gitops-lifecycle-management-service-discovery -n flux-system
   ```

3. **Manual Provider Creation**: Create provider manually in Authentik UI as fallback

### 2. Helm Hook Issues

#### Symptoms

- Helm deployment stuck in pending state
- Hook jobs failing repeatedly
- Post-install validation failures

#### Diagnostic Steps

```bash
# Check Helm release status
helm status gitops-lifecycle-management -n flux-system

# Check hook jobs
kubectl get jobs -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management

# Check hook job logs
kubectl logs -n flux-system job/gitops-lifecycle-management-auth-setup
kubectl logs -n flux-system job/gitops-lifecycle-management-db-init
kubectl logs -n flux-system job/gitops-lifecycle-management-validation
```

#### Common Issues and Solutions

##### Issue: Pre-Install Authentication Setup Fails

**Symptoms**: `gitops-lifecycle-management-auth-setup` job fails

**Diagnosis**:

```bash
kubectl logs -n flux-system job/gitops-lifecycle-management-auth-setup
kubectl describe job gitops-lifecycle-management-auth-setup -n flux-system
```

**Solutions**:

1. **Authentik Not Ready**: Wait for Authentik to be fully operational

   ```bash
   kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=server -n authentik --timeout=300s
   ```

2. **Token Issues**: Check token configuration (see authentication token troubleshooting above)

3. **Manual Cleanup**: Delete failed job and retry
   ```bash
   kubectl delete job gitops-lifecycle-management-auth-setup -n flux-system
   helm upgrade gitops-lifecycle-management ./charts/gitops-lifecycle-management -n flux-system
   ```

##### Issue: Database Initialization Hook Fails

**Symptoms**: `gitops-lifecycle-management-db-init` job fails

**Diagnosis**:

```bash
kubectl logs -n flux-system job/gitops-lifecycle-management-db-init
kubectl get secret postgresql-admin-credentials -n flux-system -o yaml
```

**Solutions**:

1. **Database Not Ready**: Check PostgreSQL cluster status

   ```bash
   kubectl get cluster -A
   kubectl describe cluster homeassistant-postgresql -n home-automation
   ```

2. **Credentials Issues**: Verify database credentials

   ```bash
   kubectl get externalsecret postgresql-admin-credentials -n flux-system
   ```

3. **Network Connectivity**: Test database connectivity
   ```bash
   kubectl run pg-test --rm -i --tty --image=postgres:16-alpine -- \
     psql -h homeassistant-postgresql-rw.home-automation.svc.cluster.local -U postgres
   ```

##### Issue: Post-Install Validation Fails

**Symptoms**: `gitops-lifecycle-management-validation` job fails

**Diagnosis**:

```bash
kubectl logs -n flux-system job/gitops-lifecycle-management-validation
```

**Solutions**:

1. **Component Not Ready**: Check individual component status

   ```bash
   kubectl get deployment gitops-lifecycle-management-service-discovery -n flux-system
   kubectl get crd proxyconfigs.gitops.io
   ```

2. **Validation Timeout**: Increase validation timeout in Helm values
   ```yaml
   validation:
     hooks:
       activeDeadlineSeconds: 300 # Increase from 180
   ```

### 3. ProxyConfig CRD Issues

#### Symptoms

- ProxyConfig resources not being created
- CRD validation errors
- Status not updating properly

#### Diagnostic Steps

```bash
# Check CRD installation
kubectl get crd proxyconfigs.gitops.io
kubectl describe crd proxyconfigs.gitops.io

# Check ProxyConfig resources
kubectl get proxyconfigs --all-namespaces
kubectl describe proxyconfig <name> -n <namespace>

# Validate ProxyConfig spec
kubectl apply --dry-run=client -f <proxyconfig-file>
```

#### Common Issues and Solutions

##### Issue: CRD Not Installed

**Symptoms**: "no matches for kind ProxyConfig" errors

**Solutions**:

```bash
# Reinstall CRD
kubectl apply -f charts/gitops-lifecycle-management/templates/crds/proxyconfig-crd.yaml

# Or reinstall entire chart
helm upgrade gitops-lifecycle-management ./charts/gitops-lifecycle-management -n flux-system
```

##### Issue: ProxyConfig Validation Errors

**Symptoms**: "validation failed" errors when creating ProxyConfig

**Solutions**:

1. **Check Required Fields**: Ensure all required fields are present

   ```yaml
   spec:
     serviceName: "required"
     serviceNamespace: "required"
     externalHost: "required"
     internalHost: "required"
     authentikConfig:
       providerName: "required"
   ```

2. **Validate Field Types**: Ensure correct data types
   ```yaml
   spec:
     port: 80 # integer, not string
     protocol: "http" # must be "http" or "https"
   ```

### 4. Monitoring and Alerting Issues

#### Symptoms

- Prometheus alerts not firing
- Metrics not being collected
- ServiceMonitor not working

#### Diagnostic Steps

```bash
# Check ServiceMonitor
kubectl get servicemonitor -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management
kubectl describe servicemonitor gitops-lifecycle-management -n flux-system

# Check Prometheus targets
curl -s http://prometheus.k8s.home.geoffdavis.com/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.job | contains("gitops"))'

# Check metrics endpoint
kubectl port-forward -n flux-system deployment/gitops-lifecycle-management-service-discovery 8080:8080
curl http://localhost:8080/metrics
```

#### Common Issues and Solutions

##### Issue: Metrics Not Being Scraped

**Symptoms**: No metrics visible in Prometheus

**Solutions**:

1. **ServiceMonitor Labels**: Check ServiceMonitor selector labels

   ```bash
   kubectl get servicemonitor gitops-lifecycle-management -n flux-system -o yaml
   ```

2. **Service Labels**: Ensure service has correct labels

   ```bash
   kubectl get svc gitops-lifecycle-management-service-discovery -n flux-system -o yaml
   ```

3. **Prometheus Configuration**: Check Prometheus ServiceMonitor selector
   ```bash
   kubectl get prometheus -o yaml | grep -A 10 serviceMonitorSelector
   ```

##### Issue: Alerts Not Firing

**Symptoms**: Expected alerts not appearing in AlertManager

**Solutions**:

1. **PrometheusRule Installation**: Check PrometheusRule resource

   ```bash
   kubectl get prometheusrule gitops-lifecycle-management-alerts -n flux-system
   kubectl describe prometheusrule gitops-lifecycle-management-alerts -n flux-system
   ```

2. **Alert Rule Syntax**: Validate alert rule syntax

   ```bash
   # Check Prometheus rules page for syntax errors
   curl -s http://prometheus.k8s.home.geoffdavis.com/api/v1/rules
   ```

3. **Metric Availability**: Ensure required metrics are available
   ```bash
   curl -s http://prometheus.k8s.home.geoffdavis.com/api/v1/query?query=up{job="gitops-lifecycle-management-service-discovery-metrics"}
   ```

## Emergency Procedures

### Complete System Recovery

If the entire GitOps lifecycle management system is non-functional:

#### 1. Emergency Rollback

```bash
# Rollback to previous Helm release
helm rollback gitops-lifecycle-management -n flux-system

# Or disable the system temporarily
kubectl scale deployment gitops-lifecycle-management-service-discovery --replicas=0 -n flux-system
```

#### 2. Manual Service Configuration

If automatic service discovery is broken, configure services manually:

```bash
# Access Authentik admin interface
kubectl port-forward -n authentik svc/authentik-server 9000:9000

# Navigate to https://localhost:9000/if/admin/
# Manually create proxy providers and applications
```

#### 3. Bypass GitOps Lifecycle Management

For critical services, temporarily bypass the system:

```bash
# Create service-specific configuration jobs
kubectl apply -f infrastructure/authentik-outpost-config/longhorn-proxy-config-job.yaml
kubectl apply -f infrastructure/authentik-outpost-config/monitoring-proxy-config-job.yaml
```

### Data Recovery

#### ProxyConfig Resource Recovery

```bash
# Backup existing ProxyConfig resources
kubectl get proxyconfigs --all-namespaces -o yaml > proxyconfigs-backup.yaml

# Restore from backup
kubectl apply -f proxyconfigs-backup.yaml
```

#### Authentik Configuration Recovery

```bash
# Export Authentik configuration
kubectl exec -n authentik deployment/authentik-server -- \
  ak export --output /tmp/authentik-backup.json

kubectl cp authentik/authentik-server-pod:/tmp/authentik-backup.json ./authentik-backup.json
```

## Performance Troubleshooting

### High Resource Usage

#### CPU Usage Issues

```bash
# Check CPU usage
kubectl top pods -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management

# Check resource limits
kubectl describe deployment gitops-lifecycle-management-service-discovery -n flux-system | grep -A 10 Limits
```

**Solutions**:

1. **Increase Resource Limits**:

   ```yaml
   serviceDiscovery:
     controller:
       resources:
         limits:
           cpu: 200m # Increase from 100m
           memory: 256Mi # Increase from 128Mi
   ```

2. **Optimize Reconcile Interval**:
   ```yaml
   serviceDiscovery:
     discovery:
       reconcileInterval: "10m" # Increase from 5m
   ```

#### Memory Usage Issues

```bash
# Check memory usage
kubectl top pods -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management

# Check for memory leaks
kubectl logs -n flux-system -l app.kubernetes.io/component=service-discovery-controller | grep -i "memory\|oom"
```

**Solutions**:

1. **Increase Memory Limits**: See CPU usage solutions above
2. **Restart Controller**: `kubectl rollout restart deployment gitops-lifecycle-management-service-discovery -n flux-system`

### Slow Performance

#### Long Reconciliation Times

```bash
# Check reconciliation metrics
curl -s http://prometheus.k8s.home.geoffdavis.com/api/v1/query?query=gitops_proxyconfig_reconcile_duration_seconds
```

**Solutions**:

1. **Reduce API Call Frequency**: Optimize controller logic
2. **Increase Timeout Values**: Adjust timeout configurations
3. **Parallel Processing**: Enable parallel processing if available

## Preventive Measures

### Regular Health Checks

```bash
#!/bin/bash
# Daily health check script

echo "=== GitOps Lifecycle Management Health Check ==="

# Check controller status
kubectl get deployment gitops-lifecycle-management-service-discovery -n flux-system

# Check ProxyConfig resources
kubectl get proxyconfigs --all-namespaces | grep -v "Ready"

# Check recent errors
kubectl logs -n flux-system -l app.kubernetes.io/component=service-discovery-controller --since=24h | grep -i error

# Check Prometheus alerts
curl -s http://prometheus.k8s.home.geoffdavis.com/api/v1/alerts | \
  jq '.data.alerts[] | select(.labels.component | contains("gitops")) | select(.state == "firing")'
```

### Monitoring Setup

1. **Set up Grafana Dashboard**: Create dashboard for GitOps lifecycle management metrics
2. **Configure AlertManager**: Ensure alerts are routed to appropriate channels
3. **Log Aggregation**: Set up centralized logging for all components

### Backup Procedures

```bash
#!/bin/bash
# Weekly backup script

# Backup ProxyConfig resources
kubectl get proxyconfigs --all-namespaces -o yaml > "proxyconfigs-$(date +%Y%m%d).yaml"

# Backup Helm values
helm get values gitops-lifecycle-management -n flux-system > "helm-values-$(date +%Y%m%d).yaml"

# Backup Authentik configuration
kubectl exec -n authentik deployment/authentik-server -- \
  ak export --output "/tmp/authentik-backup-$(date +%Y%m%d).json"
```

## Getting Help

### Log Collection

When reporting issues, collect the following logs:

```bash
#!/bin/bash
# Log collection script

mkdir -p gitops-logs
cd gitops-logs

# Controller logs
kubectl logs -n flux-system -l app.kubernetes.io/component=service-discovery-controller > controller.log

# Helm release status
helm status gitops-lifecycle-management -n flux-system > helm-status.log

# ProxyConfig resources
kubectl get proxyconfigs --all-namespaces -o yaml > proxyconfigs.yaml

# Recent events
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -50 > events.log

# System status
kubectl get pods,svc,deployments -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management > system-status.log

echo "Logs collected in gitops-logs/ directory"
```

### Support Channels

1. **Internal Documentation**: Check project documentation and runbooks
2. **Monitoring Dashboards**: Review Grafana dashboards for system health
3. **Team Communication**: Use established team communication channels
4. **Issue Tracking**: Create detailed issue reports with collected logs

## Conclusion

This troubleshooting guide covers the most common issues and their solutions for the GitOps lifecycle management system. Regular monitoring, preventive maintenance, and following the diagnostic procedures outlined here will help maintain system reliability and quickly resolve any issues that arise.

For issues not covered in this guide, collect the diagnostic information as outlined and escalate through appropriate channels with detailed problem descriptions and collected logs.
