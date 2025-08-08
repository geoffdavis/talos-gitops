# GitOps Lifecycle Management Quick Reference

## Overview

This quick reference guide provides essential commands and procedures for daily operations with the GitOps lifecycle management system. Use this as a cheat sheet for common tasks and troubleshooting.

## Quick Status Checks

### System Health

```bash
# Overall system status
kubectl get helmrelease gitops-lifecycle-management -n flux-system
kubectl get pods -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management

# Service discovery controller
kubectl get deployment gitops-lifecycle-management-service-discovery -n flux-system

# ProxyConfig resources
kubectl get proxyconfigs --all-namespaces
```

### Component Status

```bash
# Check all components at once
kubectl get pods,svc,deployments -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management

# Check CRD installation
kubectl get crd proxyconfigs.gitops.io

# Check monitoring
kubectl get servicemonitor,prometheusrule -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management
```

## Common Operations

### Adding a New Service

#### 1. Create ProxyConfig Resource

```yaml
apiVersion: gitops.io/v1
kind: ProxyConfig
metadata:
  name: my-service-proxy
  namespace: my-namespace
spec:
  serviceName: my-service
  serviceNamespace: my-namespace
  externalHost: my-service.k8s.home.geoffdavis.com
  internalHost: http://my-service.my-namespace.svc.cluster.local:80
  authentikConfig:
    providerName: my-service-proxy
    mode: forward_single
```

#### 2. Apply and Monitor

```bash
# Apply the configuration
kubectl apply -f my-service-proxy-config.yaml

# Monitor status
kubectl get proxyconfig my-service-proxy -n my-namespace -w

# Check detailed status
kubectl describe proxyconfig my-service-proxy -n my-namespace
```

### Updating Service Configuration

```bash
# Edit ProxyConfig
kubectl edit proxyconfig my-service-proxy -n my-namespace

# Patch specific fields
kubectl patch proxyconfig my-service-proxy -n my-namespace --type='merge' -p='{"spec":{"authentikConfig":{"skipPathRegex":"^/(api|health)/.*$"}}}'

# Monitor reconciliation
kubectl logs -n flux-system -l app.kubernetes.io/component=service-discovery-controller | grep my-service-proxy
```

### Removing a Service

```bash
# Delete ProxyConfig (this will also clean up Authentik provider)
kubectl delete proxyconfig my-service-proxy -n my-namespace

# Verify cleanup
kubectl get proxyconfig my-service-proxy -n my-namespace
```

## Troubleshooting Commands

### Controller Issues

```bash
# Check controller logs
kubectl logs -n flux-system -l app.kubernetes.io/component=service-discovery-controller --tail=50

# Restart controller
kubectl rollout restart deployment gitops-lifecycle-management-service-discovery -n flux-system

# Check controller status
kubectl rollout status deployment gitops-lifecycle-management-service-discovery -n flux-system
```

### ProxyConfig Issues

```bash
# List all ProxyConfig resources with status
kubectl get proxyconfigs --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase,PROVIDER-ID:.status.authentikProviderId"

# Check stuck resources
kubectl get proxyconfigs --all-namespaces -o json | jq -r '.items[] | select(.status.phase == "Pending") | "\(.metadata.namespace)/\(.metadata.name)"'

# Get detailed status
kubectl describe proxyconfig <name> -n <namespace>
```

### Authentication Issues

```bash
# Test Authentik connectivity
kubectl exec -n flux-system deployment/gitops-lifecycle-management-service-discovery -- \
  curl -s -H "Authorization: Bearer $AUTHENTIK_TOKEN" \
  http://authentik-server.authentik.svc.cluster.local:9000/api/v3/core/users/me/

# Check token secret
kubectl get secret authentik-admin-token -n flux-system -o yaml

# Force token refresh
kubectl annotate externalsecret authentik-admin-token -n flux-system force-sync=$(date +%s) --overwrite
```

### Helm Issues

```bash
# Check Helm release status
helm status gitops-lifecycle-management -n flux-system

# Check Helm hooks
kubectl get jobs -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management

# View hook logs
kubectl logs -n flux-system job/gitops-lifecycle-management-auth-setup
kubectl logs -n flux-system job/gitops-lifecycle-management-db-init
kubectl logs -n flux-system job/gitops-lifecycle-management-validation
```

## Emergency Procedures

### Quick Recovery

```bash
# Restart all components
kubectl rollout restart deployment gitops-lifecycle-management-service-discovery -n flux-system

# Rollback Helm release
helm rollback gitops-lifecycle-management -n flux-system

# Emergency disable
kubectl scale deployment gitops-lifecycle-management-service-discovery --replicas=0 -n flux-system
```

### Manual Service Configuration

```bash
# If automatic configuration fails, use legacy jobs
kubectl apply -f infrastructure/authentik-outpost-config/longhorn-proxy-config-job.yaml
kubectl apply -f infrastructure/authentik-outpost-config/monitoring-proxy-config-job.yaml

# Monitor job completion
kubectl get jobs -n authentik
kubectl logs -n authentik job/authentik-longhorn-proxy-config
```

### System Reset

```bash
# Delete all ProxyConfig resources
kubectl delete proxyconfigs --all --all-namespaces

# Reinstall system
helm uninstall gitops-lifecycle-management -n flux-system
helm install gitops-lifecycle-management ./charts/gitops-lifecycle-management -n flux-system
```

## Monitoring and Metrics

### Prometheus Queries

```bash
# Controller health
up{job="gitops-lifecycle-management-service-discovery-metrics"}

# ProxyConfig processing time
gitops_proxyconfig_reconcile_duration_seconds

# Error rates
rate(gitops_cleanup_errors_total[5m])

# Cleanup effectiveness
gitops_cleanup_jobs_cleaned_total
```

### Alert Status

```bash
# Check active alerts
curl -s http://prometheus.k8s.home.geoffdavis.com/api/v1/alerts | \
  jq '.data.alerts[] | select(.labels.component | contains("gitops")) | select(.state == "firing")'

# Check alert rules
kubectl get prometheusrule gitops-lifecycle-management-alerts -n flux-system -o yaml
```

## Configuration Management

### Helm Values

```bash
# Get current values
helm get values gitops-lifecycle-management -n flux-system

# Update values
helm upgrade gitops-lifecycle-management ./charts/gitops-lifecycle-management -n flux-system \
  --set serviceDiscovery.discovery.reconcileInterval=10m

# Dry run upgrade
helm upgrade gitops-lifecycle-management ./charts/gitops-lifecycle-management -n flux-system --dry-run
```

### Environment Variables

```bash
# Check controller environment
kubectl get deployment gitops-lifecycle-management-service-discovery -n flux-system -o yaml | grep -A 20 env:

# Update environment variable
kubectl patch deployment gitops-lifecycle-management-service-discovery -n flux-system -p '{"spec":{"template":{"spec":{"containers":[{"name":"controller","env":[{"name":"LOG_LEVEL","value":"debug"}]}]}}}}'
```

## Backup and Recovery

### Backup Commands

```bash
# Backup ProxyConfig resources
kubectl get proxyconfigs --all-namespaces -o yaml > proxyconfigs-backup-$(date +%Y%m%d).yaml

# Backup Helm values
helm get values gitops-lifecycle-management -n flux-system > helm-values-backup-$(date +%Y%m%d).yaml

# Backup CRD
kubectl get crd proxyconfigs.gitops.io -o yaml > proxyconfig-crd-backup-$(date +%Y%m%d).yaml
```

### Recovery Commands

```bash
# Restore ProxyConfig resources
kubectl apply -f proxyconfigs-backup-<date>.yaml

# Restore Helm configuration
helm upgrade gitops-lifecycle-management ./charts/gitops-lifecycle-management -n flux-system \
  -f helm-values-backup-<date>.yaml

# Restore CRD
kubectl apply -f proxyconfig-crd-backup-<date>.yaml
```

## Performance Tuning

### Resource Optimization

```bash
# Check resource usage
kubectl top pods -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management

# Update resource limits
kubectl patch deployment gitops-lifecycle-management-service-discovery -n flux-system -p '{"spec":{"template":{"spec":{"containers":[{"name":"controller","resources":{"limits":{"cpu":"200m","memory":"256Mi"}}}]}}}}'

# Adjust reconciliation interval
# Update in Helm values and redeploy
```

### Scaling

```bash
# Scale controller replicas
kubectl scale deployment gitops-lifecycle-management-service-discovery --replicas=2 -n flux-system

# Check scaling status
kubectl get deployment gitops-lifecycle-management-service-discovery -n flux-system
```

## Useful Aliases

Add these to your shell profile for faster operations:

```bash
# GitOps lifecycle management aliases
alias glm-status='kubectl get pods,svc,deployments -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management'
alias glm-logs='kubectl logs -n flux-system -l app.kubernetes.io/component=service-discovery-controller --tail=50'
alias glm-restart='kubectl rollout restart deployment gitops-lifecycle-management-service-discovery -n flux-system'
alias pc-list='kubectl get proxyconfigs --all-namespaces'
alias pc-pending='kubectl get proxyconfigs --all-namespaces -o json | jq -r ".items[] | select(.status.phase == \"Pending\") | \"\(.metadata.namespace)/\(.metadata.name)\""'
alias glm-health='kubectl get helmrelease gitops-lifecycle-management -n flux-system && kubectl get proxyconfigs --all-namespaces | grep -v Ready'
```

## Common Error Messages and Solutions

### "ProxyConfig stuck in Pending phase"

```bash
# Check controller logs
kubectl logs -n flux-system -l app.kubernetes.io/component=service-discovery-controller | grep <proxyconfig-name>

# Check Authentik connectivity
kubectl exec -n flux-system deployment/gitops-lifecycle-management-service-discovery -- curl -s http://authentik-server.authentik.svc.cluster.local:9000/api/v3/core/users/me/

# Restart controller if needed
kubectl rollout restart deployment gitops-lifecycle-management-service-discovery -n flux-system
```

### "Authentication failed with status: 401"

```bash
# Check token secret
kubectl get secret authentik-admin-token -n flux-system -o jsonpath='{.data.token}' | base64 -d

# Force token refresh
kubectl annotate externalsecret authentik-admin-token -n flux-system force-sync=$(date +%s) --overwrite

# Regenerate token if needed
kubectl delete job authentik-enhanced-token-setup -n authentik
```

### "Helm hook job failed"

```bash
# Check hook job status
kubectl get jobs -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management

# View hook logs
kubectl logs -n flux-system job/<hook-job-name>

# Delete failed job and retry
kubectl delete job <hook-job-name> -n flux-system
helm upgrade gitops-lifecycle-management ./charts/gitops-lifecycle-management -n flux-system
```

### "Controller pod restarting"

```bash
# Check pod events
kubectl describe pod -n flux-system -l app.kubernetes.io/component=service-discovery-controller

# Check resource limits
kubectl top pod -n flux-system -l app.kubernetes.io/component=service-discovery-controller

# Increase resources if needed
kubectl patch deployment gitops-lifecycle-management-service-discovery -n flux-system -p '{"spec":{"template":{"spec":{"containers":[{"name":"controller","resources":{"limits":{"memory":"256Mi"}}}]}}}}'
```

## Integration Points

### Flux GitOps

```bash
# Force Flux reconciliation
flux reconcile kustomization infrastructure-gitops-lifecycle-management -n flux-system

# Check Flux status
flux get kustomizations -n flux-system | grep gitops-lifecycle-management
```

### Authentik Integration

```bash
# Check Authentik providers
curl -s -H "Authorization: Bearer $AUTHENTIK_TOKEN" \
  http://authentik-server.authentik.svc.cluster.local:9000/api/v3/providers/proxy/ | \
  jq '.results[] | {name: .name, external_host: .external_host}'

# Access Authentik admin interface
kubectl port-forward -n authentik svc/authentik-server 9000:9000
# Navigate to http://localhost:9000/if/admin/
```

### 1Password Integration

```bash
# Check 1Password Connect
kubectl get pods -n onepassword-connect

# Check external secrets
kubectl get externalsecrets -n flux-system -l app.kubernetes.io/name=gitops-lifecycle-management
```

## Best Practices

### Service Configuration

- Always use descriptive names for ProxyConfig resources
- Include proper labels and annotations for organization
- Test configuration in development environment first
- Document service-specific requirements

### Monitoring

- Set up alerts for critical components
- Monitor ProxyConfig resource status regularly
- Review controller logs for patterns
- Track performance metrics over time

### Maintenance

- Perform regular backups of configuration
- Keep Helm chart and dependencies updated
- Review and optimize resource usage
- Document any customizations or workarounds

### Security

- Rotate authentication tokens regularly
- Review RBAC permissions periodically
- Keep security contexts properly configured
- Monitor for security-related alerts

## Support Resources

### Documentation

- [Migration Summary](./GITOPS_LIFECYCLE_MANAGEMENT_MIGRATION_SUMMARY.md)
- [Troubleshooting Guide](./GITOPS_LIFECYCLE_MANAGEMENT_TROUBLESHOOTING.md)
- [Operational Procedures](./OPERATIONAL_PROCEDURES_UPDATE.md)

### Monitoring Dashboards

- Grafana: http://grafana.k8s.home.geoffdavis.com
- Prometheus: http://prometheus.k8s.home.geoffdavis.com
- AlertManager: http://alertmanager.k8s.home.geoffdavis.com

### Key Contacts

- Platform Team: For system-level issues
- Security Team: For authentication and security issues
- Development Teams: For service-specific configuration

This quick reference should cover 90% of daily operations. For complex scenarios, refer to the comprehensive troubleshooting guide and operational procedures documentation.
