# Daily Operations Guide

This guide covers the essential daily, weekly, and monthly operational tasks for maintaining the Talos GitOps home-ops cluster in production.

## Daily Health Checks (5 minutes)

### 1. Cluster Status Overview

```bash
# Quick cluster health check
task cluster:status

# Check all nodes are Ready
kubectl get nodes

# Verify no failed pods
kubectl get pods -A | grep -v Running | grep -v Completed

# Check resource utilization
kubectl top nodes
kubectl top pods -A --sort-by=memory | head -10
```

**Expected Results:**

- All 3 nodes in `Ready` state
- No pods in `Error`, `CrashLoopBackOff`, or `Pending` states
- Node CPU < 80%, Memory < 85%

### 2. GitOps Health Check

```bash
# Verify Flux reconciliation status
flux get kustomizations

# Check for any stuck reconciliations
flux get all --status-selector ready=false

# Monitor recent deployments
flux logs --since=24h | grep -E "(error|failed)" || echo "No errors in last 24h"
```

**Expected Results:**

- All kustomizations showing `Ready` status
- No resources stuck in `Not Ready` state
- No recent reconciliation errors

### 3. Service Accessibility Check

```bash
# Test key service endpoints
curl -I -k https://longhorn.k8s.home.geoffdavis.com
curl -I -k https://grafana.k8s.home.geoffdavis.com
curl -I -k https://dashboard.k8s.home.geoffdavis.com

# Check LoadBalancer services have external IPs
kubectl get svc -A --field-selector spec.type=LoadBalancer
```

**Expected Results:**

- All services return HTTP 200 or proper redirect (302/301)
- All LoadBalancer services have external IPs assigned
- Authentication redirects working (302 to Authentik)

### 4. Storage Health Check

```bash
# Check Longhorn system health
kubectl get pods -n longhorn-system | grep -v Running || echo "All Longhorn pods running"

# Verify storage volumes
kubectl get pv | grep -E "(Failed|Pending)" || echo "All volumes healthy"

# Check storage capacity
kubectl exec -n longhorn-system $(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}') -- \
  curl -s http://longhorn-backend:9500/v1/volumes | jq '.data[] | {name: .name, size: .size, state: .state}'
```

**Expected Results:**

- All Longhorn pods in `Running` state
- No volumes in `Failed` or `Pending` state
- Total storage utilization < 80%

## Weekly Operations (15 minutes)

### 1. System Updates Review

```bash
# Check for pending Renovate updates
gh pr list --label "dependencies" --state open

# Review cluster component versions
kubectl version --short
talosctl version --short
flux version --short
```

### 2. Security Validation

```bash
# Verify certificate expiration status
kubectl get certificates -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[0].status,EXPIRY:.status.notAfter"

# Check for security policy violations
kubectl get events -A --field-selector type=Warning | grep -i "security\|policy" | tail -10

# Validate external outpost authentication
curl -s https://authentik.k8s.home.geoffdavis.com/outpost.goauthentik.io/ping
```

### 3. Performance Monitoring

```bash
# Check resource trends in Grafana
echo "Review Grafana dashboards:"
echo "- Node resources: https://grafana.k8s.home.geoffdavis.com/d/node-overview"
echo "- Cluster overview: https://grafana.k8s.home.geoffdavis.com/d/cluster-overview"
echo "- Storage performance: https://grafana.k8s.home.geoffdavis.com/d/longhorn-overview"

# Generate resource utilization report
kubectl top nodes
kubectl get pods -A --sort-by=.status.containerStatuses[0].restartCount | tail -10
```

### 4. Backup Validation

```bash
# Check Longhorn backup status
kubectl get volumesnapshots -A

# Verify 1Password secret synchronization
kubectl get externalsecrets -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.conditions[0].type,LAST-SYNC:.status.refreshTime"

# Review recent configuration changes
git log --oneline --since="1 week ago" | head -10
```

## Monthly Operations (30 minutes)

### 1. Comprehensive Health Assessment

```bash
# Generate comprehensive cluster report
task cluster:health-report  # If this task exists, otherwise manual checks

# Review all namespace resource quotas and limits
kubectl describe resourcequotas -A

# Check for deprecated API versions
kubectl api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get --show-kind --ignore-not-found -A | grep -i deprecated
```

### 2. Security Hardening Review

```bash
# Review RBAC permissions
kubectl get clusterroles,roles -A -o wide

# Check Pod Security Standards compliance
kubectl get namespaces -o custom-columns="NAME:.metadata.name,PSS-ENFORCE:.metadata.labels.pod-security\.kubernetes\.io/enforce"

# Validate network policies
kubectl get networkpolicies -A
```

### 3. Capacity Planning

```bash
# Storage capacity analysis
kubectl exec -n longhorn-system $(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}') -- \
  curl -s http://longhorn-backend:9500/v1/nodes | jq '.data[] | {name: .name, storageAvailable: .storageAvailable, storageScheduled: .storageScheduled}'

# Review node resource allocation
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check for resource contention
kubectl top pods -A --containers --sort-by=cpu | head -20
```

## Application Management

### Deploying New Applications

```bash
# Create new application directory
mkdir -p apps/my-new-app

# Follow the standard application pattern
cat > apps/my-new-app/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: my-new-app
resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
EOF

# Add to Flux management
# Edit clusters/home-ops/infrastructure/apps.yaml to include new app

# Deploy via GitOps
git add apps/my-new-app/
git commit -m "Deploy my-new-app"
git push

# Monitor deployment
flux get kustomizations apps-my-new-app --watch
kubectl rollout status deployment/my-new-app -n my-new-app
```

### Updating Applications

```bash
# Update application configuration
# Edit relevant files in apps/my-app/

# Deploy changes
git add apps/my-app/
git commit -m "Update my-app configuration"
git push

# Monitor rollout
kubectl rollout status deployment/my-app -n my-app
kubectl get pods -n my-app -w
```

### Rolling Back Applications

```bash
# Quick rollback via kubectl
kubectl rollout undo deployment/my-app -n my-app

# Proper GitOps rollback (preferred)
git revert <commit-hash>
git push

# Monitor rollback
kubectl rollout status deployment/my-app -n my-app
```

## Infrastructure Maintenance

### Updating Infrastructure Services

```bash
# Update Helm chart versions in infrastructure/
# Example: infrastructure/monitoring/helmrelease.yaml

# Commit and deploy
git add infrastructure/
git commit -m "Update monitoring stack to v2.x.x"
git push

# Monitor deployment
flux get helmreleases -n monitoring --watch
```

### Managing Secrets

```bash
# Add new secret to 1Password and sync
kubectl get externalsecrets -A

# Force external secret refresh
kubectl annotate externalsecret my-secret force-sync="$(date +%s)" -n my-namespace

# Validate secret creation
kubectl get secrets -n my-namespace
```

### Network Operations

```bash
# Verify BGP peering status
task bgp:verify-peering

# Check LoadBalancer IP allocation
kubectl get ciliumloadbalancerippools -o yaml

# Test DNS resolution
dig @172.29.51.1 new-service.k8s.home.geoffdavis.com

# Update DNS records (handled automatically by external-dns)
kubectl get ingress -A
```

## Troubleshooting Procedures

### Common Issues

#### Pods Stuck in Pending State

```bash
# Check node resources and constraints
kubectl describe pod <pod-name> -n <namespace>

# Check for storage issues
kubectl get pv,pvc -A | grep -E "(Pending|Failed)"

# Verify node affinity and tolerations
kubectl get nodes --show-labels
```

#### GitOps Reconciliation Failures

```bash
# Check Flux controller logs
flux logs --all-namespaces --follow

# Force reconciliation
flux reconcile source git flux-system
flux reconcile kustomization <stuck-kustomization>

# Check for resource conflicts
kubectl get events -A --sort-by=.metadata.creationTimestamp | tail -20
```

#### Service Connectivity Issues

```bash
# Check service endpoints
kubectl get endpoints -n <namespace>

# Verify ingress configuration
kubectl get ingress -A -o wide

# Test internal connectivity
kubectl run debug --image=busybox -it --rm --restart=Never -- /bin/sh
# Inside container: wget -O- http://service.namespace:port
```

#### Authentication Problems

```bash
# Check Authentik external outpost status
kubectl get pods -n authentik-proxy
kubectl logs -n authentik-proxy -l app.kubernetes.io/name=authentik-proxy

# Verify external outpost connectivity in Authentik admin
echo "Check outpost status at: https://authentik.k8s.home.geoffdavis.com/if/admin/"

# Test authentication endpoints
curl -I https://longhorn.k8s.home.geoffdavis.com/outpost.goauthentik.io/ping
```

## Emergency Procedures

### Cluster Recovery

```bash
# If cluster is unresponsive, check node status
talosctl version --nodes 172.29.51.11,172.29.51.12,172.29.51.13

# Safe cluster reset (preserves OS)
task cluster:safe-reset CONFIRM=SAFE-RESET

# Emergency cluster rebuild
task cluster:emergency-recovery
```

### Service Restoration

```bash
# Restart critical services
kubectl rollout restart deployment/authentik-proxy -n authentik-proxy
kubectl rollout restart daemonset/cilium -n kube-system

# Force Flux reconciliation of all components
flux reconcile source git flux-system --with-source
```

### Data Recovery

```bash
# Longhorn volume recovery
kubectl get volumesnapshots -A
# Use Longhorn UI for detailed recovery procedures

# Configuration backup
git log --oneline -n 20  # Recent changes
git checkout <known-good-commit>  # Rollback if needed
```

## Monitoring and Alerting

### Key Metrics to Monitor

- **Node Resources**: CPU, Memory, Disk utilization < 80%
- **Pod Health**: No pods in error states for > 5 minutes
- **Storage**: Longhorn volume health, capacity utilization
- **Network**: BGP peering status, service connectivity
- **GitOps**: Flux reconciliation success rate > 95%

### Alert Thresholds

- **Critical**: Node down, service outage, storage full
- **Warning**: High resource utilization, reconciliation delays
- **Info**: Successful deployments, routine maintenance

### Grafana Dashboards

Access these dashboards daily:

- **Node Overview**: <https://grafana.k8s.home.geoffdavis.com/d/node-overview>
- **Cluster Resources**: <https://grafana.k8s.home.geoffdavis.com/d/cluster-overview>
- **Storage Performance**: <https://grafana.k8s.home.geoffdavis.com/d/longhorn-overview>
- **Network Traffic**: <https://grafana.k8s.home.geoffdavis.com/d/cilium-overview>

## Best Practices

### Configuration Management

- **Always use GitOps**: Never apply configurations directly with kubectl
- **Test changes**: Use staging environment or careful rollout strategies
- **Document changes**: Clear commit messages and PR descriptions
- **Version control**: Tag releases and maintain changelog

### Security Operations

- **Regular updates**: Monitor Renovate PRs and apply security updates promptly
- **Access review**: Regularly audit RBAC permissions and service accounts
- **Certificate management**: Monitor certificate expiration and renewal
- **Secret rotation**: Rotate sensitive credentials quarterly

### Performance Optimization

- **Resource requests/limits**: Set appropriate values for all applications
- **Storage optimization**: Regular cleanup of unused volumes and snapshots
- **Network efficiency**: Monitor and optimize service mesh traffic
- **Scaling strategy**: Implement HPA for variable workloads

---

**Remember**: This cluster uses a two-phase architecture - Bootstrap changes require direct intervention, while GitOps changes should always go through version control. When in doubt, prefer GitOps approaches for all operational changes.
