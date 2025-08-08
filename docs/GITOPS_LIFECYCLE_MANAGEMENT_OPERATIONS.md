# GitOps Lifecycle Management Operations Guide

This document provides comprehensive operational procedures for the GitOps Lifecycle Management system, including cleanup controllers, retry mechanisms, and monitoring.

## Overview

The GitOps Lifecycle Management system provides robust cleanup and retry mechanisms to ensure reliable GitOps operations. It consists of:

- **Cleanup Controller**: Automated cleanup of jobs, stuck resources, and orphaned providers
- **Enhanced Retry Logic**: Exponential backoff retry mechanisms for init containers and hooks
- **Service Discovery Controller**: Automated Authentik proxy provider management
- **Monitoring & Alerting**: Comprehensive metrics and Prometheus alerts

## Architecture Components

### Cleanup Controller

The cleanup controller runs as a deployment and performs the following operations:

- **Job Cleanup**: Removes completed and failed jobs based on configurable TTL
- **Stuck Resource Cleanup**: Handles pods stuck in terminating state and jobs without TTL
- **Orphaned Provider Cleanup**: Removes Authentik proxy providers no longer referenced
- **Event Cleanup**: Removes old Kubernetes events
- **ReplicaSet Cleanup**: Removes old replica sets while maintaining minimum count

### Retry Mechanisms

Enhanced retry logic with exponential backoff is implemented for:

- **Database Connectivity**: PostgreSQL connection with proper SSL and timeout handling
- **Service Connectivity**: TCP port checks for Redis, MQTT, and other services
- **HTTP Endpoints**: Health checks with expected status codes
- **Kubernetes Resources**: Resource readiness and condition checks
- **Secret Availability**: ExternalSecret synchronization validation

### Monitoring System

Comprehensive monitoring includes:

- **Prometheus Metrics**: Cleanup operations, retry attempts, success/failure rates
- **ServiceMonitors**: Automatic metric collection from all controllers
- **PrometheusRules**: 15+ alert rules covering all operational aspects
- **Grafana Integration**: Ready for dashboard creation

## Deployment

### Prerequisites

- Kubernetes cluster with GitOps (Flux) installed
- Prometheus Operator for monitoring
- 1Password Connect for secret management
- Authentik for identity management

### Installation

1. **Deploy via Helm**:
   ```bash
   helm install gitops-lifecycle-management ./charts/gitops-lifecycle-management \
     --namespace gitops-system \
     --create-namespace \
     --values values-production.yaml
   ```

2. **Deploy via GitOps**:
   ```yaml
   apiVersion: helm.toolkit.fluxcd.io/v2
   kind: HelmRelease
   metadata:
     name: gitops-lifecycle-management
     namespace: gitops-system
   spec:
     interval: 30m
     chart:
       spec:
         chart: ./charts/gitops-lifecycle-management
         sourceRef:
           kind: GitRepository
           name: talos-gitops
     values:
       cleanup:
         enabled: true
       monitoring:
         enabled: true
         prometheusRules:
           enabled: true
   ```

### Configuration

Key configuration options in `values.yaml`:

```yaml
# Cleanup configuration
cleanup:
  enabled: true
  controller:
    interval: "1h"
    policies:
      completedJobs:
        enabled: true
        ttl: "1h"
      failedJobs:
        enabled: true
        ttl: "24h"
      orphanedProviders:
        enabled: true
        maxAge: "7d"

# Retry configuration
retry:
  enabled: true
  defaults:
    maxAttempts: 10
    baseDelay: 2
    maxDelay: 60
    backoffMultiplier: 2
    jitter: true

# Monitoring configuration
monitoring:
  enabled: true
  prometheusRules:
    enabled: true
    thresholds:
      cleanupFailureRate: 0.1
      maxCleanupDuration: 300
```

## Operations

### Daily Operations

#### Health Checks

1. **Check Controller Status**:
   ```bash
   kubectl get pods -n gitops-system -l app.kubernetes.io/name=gitops-lifecycle-management
   ```

2. **Monitor Cleanup Operations**:
   ```bash
   kubectl logs -n gitops-system -l app.kubernetes.io/component=cleanup-controller --tail=100
   ```

3. **Check Metrics**:
   ```bash
   kubectl port-forward -n gitops-system svc/gitops-lifecycle-management-cleanup-metrics 8080:8080
   curl http://localhost:8080/metrics | grep gitops_cleanup
   ```

#### Monitoring Alerts

Monitor these key alerts in Prometheus/AlertManager:

- `GitOpsCleanupControllerDown`: Controller is not running
- `GitOpsCleanupHighFailureRate`: High cleanup failure rate
- `GitOpsRetryHighFailureRate`: High retry failure rate
- `GitOpsExcessiveJobCleanup`: Too many jobs being cleaned up

### Troubleshooting

#### Cleanup Controller Issues

1. **Controller Not Starting**:
   ```bash
   # Check pod status
   kubectl describe pod -n gitops-system -l app.kubernetes.io/component=cleanup-controller
   
   # Check RBAC permissions
   kubectl auth can-i delete jobs --as=system:serviceaccount:gitops-system:gitops-lifecycle-management
   ```

2. **High Cleanup Failure Rate**:
   ```bash
   # Check cleanup logs
   kubectl logs -n gitops-system -l app.kubernetes.io/component=cleanup-controller | grep ERROR
   
   # Check Authentik connectivity
   kubectl exec -n gitops-system deployment/gitops-lifecycle-management-cleanup -- \
     curl -s http://authentik-server.authentik.svc.cluster.local:80/api/v3/core/users/me/
   ```

3. **Stuck Resources Not Being Cleaned**:
   ```bash
   # Check for stuck pods manually
   kubectl get pods --all-namespaces --field-selector=status.phase=Terminating
   
   # Check cleanup policy configuration
   kubectl get configmap -n gitops-system gitops-lifecycle-management-cleanup-scripts -o yaml
   ```

#### Retry Mechanism Issues

1. **Init Containers Failing**:
   ```bash
   # Check init container logs
   kubectl logs <pod-name> -c <init-container-name>
   
   # Check retry function availability
   kubectl exec <pod-name> -c <init-container-name> -- ls -la /scripts/
   ```

2. **Excessive Retry Attempts**:
   ```bash
   # Check retry metrics
   kubectl port-forward svc/gitops-lifecycle-management-retry-metrics 8082:8082
   curl http://localhost:8082/retry-metrics | grep gitops_retry_attempts_total
   
   # Check service availability
   kubectl get endpoints -A | grep -E "(postgres|redis|mosquitto)"
   ```

#### Service Discovery Issues

1. **ProxyConfig Resources Stuck**:
   ```bash
   # Check ProxyConfig status
   kubectl get proxyconfigs --all-namespaces
   
   # Check service discovery controller logs
   kubectl logs -n gitops-system -l app.kubernetes.io/component=service-discovery-controller
   ```

2. **Authentik Provider Creation Failing**:
   ```bash
   # Test Authentik API connectivity
   kubectl exec -n gitops-system deployment/gitops-lifecycle-management-service-discovery -- \
     curl -s -H "Authorization: Bearer $AUTHENTIK_TOKEN" \
     http://authentik-server.authentik.svc.cluster.local:80/api/v3/providers/proxy/
   ```

### Maintenance

#### Updating Configuration

1. **Update Cleanup Policies**:
   ```bash
   # Edit values and upgrade
   helm upgrade gitops-lifecycle-management ./charts/gitops-lifecycle-management \
     --namespace gitops-system \
     --values values-production.yaml
   ```

2. **Update Retry Settings**:
   ```yaml
   # In values.yaml
   retry:
     services:
       database:
         maxAttempts: 50  # Increase for problematic services
         timeout: 900
   ```

#### Scaling Operations

1. **Scale Cleanup Controller**:
   ```yaml
   cleanup:
     controller:
       replicas: 2  # For high-load environments
   ```

2. **Adjust Cleanup Intervals**:
   ```yaml
   cleanup:
     controller:
       interval: "30m"  # More frequent cleanup
   ```

### Metrics and Monitoring

#### Key Metrics

Monitor these metrics in Prometheus:

```promql
# Cleanup operations
gitops_cleanup_jobs_cleaned_total
gitops_cleanup_cycle_duration_seconds
gitops_cleanup_errors_total

# Retry operations
gitops_retry_attempts_total
gitops_retry_success_total
gitops_retry_failure_total
gitops_retry_duration_seconds

# Controller health
up{job="gitops-lifecycle-management-cleanup-metrics"}
up{job="gitops-lifecycle-management-service-discovery-metrics"}
```

#### Grafana Dashboards

Create dashboards with these panels:

1. **Cleanup Operations**:
   - Cleanup cycle duration (histogram)
   - Jobs cleaned per hour (rate)
   - Cleanup error rate (percentage)

2. **Retry Operations**:
   - Retry attempts by operation (rate)
   - Retry success rate (percentage)
   - Retry duration by operation (histogram)

3. **Controller Health**:
   - Controller uptime
   - Memory and CPU usage
   - Pod restart rate

### Security Considerations

#### RBAC Permissions

The system requires these permissions:

```yaml
rules:
  - apiGroups: [""]
    resources: ["services", "endpoints", "configmaps", "secrets", "pods", "events"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch", "delete"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

#### Secret Management

- All sensitive data stored in 1Password
- ExternalSecrets used for Kubernetes secret synchronization
- Authentik API tokens rotated regularly
- Database credentials managed via CloudNativePG

### Backup and Recovery

#### Configuration Backup

1. **Backup Helm Values**:
   ```bash
   helm get values gitops-lifecycle-management -n gitops-system > backup-values.yaml
   ```

2. **Backup Custom Resources**:
   ```bash
   kubectl get proxyconfigs --all-namespaces -o yaml > proxyconfigs-backup.yaml
   ```

#### Recovery Procedures

1. **Controller Recovery**:
   ```bash
   # Restart controllers
   kubectl rollout restart deployment -n gitops-system -l app.kubernetes.io/name=gitops-lifecycle-management
   
   # Check recovery
   kubectl get pods -n gitops-system -l app.kubernetes.io/name=gitops-lifecycle-management
   ```

2. **Metrics Recovery**:
   ```bash
   # Restart ServiceMonitors
   kubectl delete servicemonitor -n gitops-system -l app.kubernetes.io/name=gitops-lifecycle-management
   kubectl apply -f charts/gitops-lifecycle-management/templates/monitoring/
   ```

### Performance Tuning

#### Cleanup Controller Optimization

1. **Adjust Cleanup Intervals**:
   ```yaml
   cleanup:
     controller:
       interval: "30m"  # More frequent for busy clusters
   ```

2. **Optimize Resource Limits**:
   ```yaml
   cleanup:
     controller:
       resources:
         limits:
           cpu: 200m      # Increase for large clusters
           memory: 256Mi
   ```

#### Retry Mechanism Optimization

1. **Service-Specific Tuning**:
   ```yaml
   retry:
     services:
       database:
         maxAttempts: 50
         baseDelay: 1
         maxDelay: 20
   ```

2. **Circuit Breaker Tuning**:
   ```yaml
   retry:
     circuitBreaker:
       failureThreshold: 3  # Lower for faster failure detection
       recoveryTimeout: 30
   ```

## Best Practices

### Deployment Best Practices

1. **Use GitOps**: Deploy via HelmRelease for version control
2. **Environment Separation**: Different values for dev/staging/prod
3. **Resource Limits**: Always set appropriate resource limits
4. **Health Checks**: Configure proper liveness and readiness probes
5. **Monitoring**: Enable all monitoring components

### Operational Best Practices

1. **Regular Monitoring**: Check alerts and metrics daily
2. **Log Analysis**: Review controller logs for patterns
3. **Capacity Planning**: Monitor resource usage trends
4. **Documentation**: Keep runbooks updated
5. **Testing**: Test recovery procedures regularly

### Security Best Practices

1. **Least Privilege**: Use minimal required RBAC permissions
2. **Secret Rotation**: Rotate API tokens regularly
3. **Network Policies**: Implement proper network segmentation
4. **Audit Logging**: Enable Kubernetes audit logging
5. **Vulnerability Scanning**: Scan container images regularly

## Troubleshooting Reference

### Common Issues

| Issue | Symptoms | Solution |
|-------|----------|----------|
| Controller not starting | Pod in CrashLoopBackOff | Check RBAC permissions and secrets |
| High cleanup failure rate | Alert firing | Check Authentik connectivity and API tokens |
| Stuck resources accumulating | Resources not being cleaned | Verify cleanup policies and permissions |
| Retry failures | Init containers failing | Check service availability and network connectivity |
| Missing metrics | No data in Prometheus | Verify ServiceMonitor configuration |

### Emergency Procedures

1. **Disable Cleanup Controller**:
   ```bash
   kubectl scale deployment gitops-lifecycle-management-cleanup --replicas=0 -n gitops-system
   ```

2. **Manual Cleanup**:
   ```bash
   # Clean up stuck jobs manually
   kubectl delete jobs --all-namespaces --field-selector=status.conditions[0].type=Failed
   ```

3. **Reset Metrics**:
   ```bash
   # Restart metrics collection
   kubectl delete pod -n gitops-system -l app.kubernetes.io/component=cleanup-controller
   ```

This operations guide provides comprehensive procedures for managing the GitOps Lifecycle Management system. Regular review and updates of these procedures ensure reliable cluster operations.