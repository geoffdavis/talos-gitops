# Flux Timeout Configuration Guide

This document provides the rationale and procedures for timeout configurations implemented across the GitOps infrastructure to prevent reconciliation hangs and ensure robust operations.

## Configuration Philosophy

### Design Principles

1. **Fail Fast, Recover Gracefully**: Timeouts should be long enough to allow normal operations but short enough to detect problems quickly
2. **Component Complexity Scaling**: More complex components get longer timeouts
3. **Dependency Awareness**: Timeouts consider dependency chains and startup ordering
4. **Resource Constraints**: Timeouts account for cluster resource limitations
5. **Operational Visibility**: All timeout events should be monitored and alertable

### Timeout Hierarchy

```text
GitRepository (60s) → HelmRepository (5m) → HelmRelease (5-20m) → Kustomization (5-20m)
```

## HelmRelease Timeout Configuration

### Timeout Categories

#### Critical Infrastructure (20 minutes)

**Components**: Longhorn, Cilium
**Rationale**:

- Complex initialization sequences
- Storage provisioning dependencies
- Network configuration complexity
- High impact of failure

**Configuration**:

```yaml
spec:
  timeout: 20m
  install:
    timeout: 20m
    remediation:
      retries: 3
  upgrade:
    timeout: 20m
    remediation:
      retries: 3
      remediateLastFailure: true
    cleanupOnFail: true
  rollback:
    timeout: 10-15m
    cleanupOnFail: true
```

#### Standard Infrastructure (15 minutes)

**Components**: cert-manager, ingress-nginx
**Rationale**:

- Moderate complexity
- CRD installation requirements
- Service dependencies
- Standard recovery expectations

**Configuration**:

```yaml
spec:
  timeout: 15m
  install:
    timeout: 15m
    remediation:
      retries: 3
  upgrade:
    timeout: 15m
    remediation:
      retries: 3
      remediateLastFailure: true
    cleanupOnFail: true
  rollback:
    timeout: 10m
    cleanupOnFail: true
```

#### Simple Applications (10 minutes)

**Components**: external-dns, monitoring tools
**Rationale**:

- Simple deployment patterns
- Minimal dependencies
- Quick startup expectations
- Fast failure detection preferred

**Configuration**:

```yaml
spec:
  timeout: 10m
  install:
    timeout: 10m
    remediation:
      retries: 3
  upgrade:
    timeout: 10m
    remediation:
      retries: 3
      remediateLastFailure: true
    cleanupOnFail: true
  rollback:
    timeout: 5m
    cleanupOnFail: true
```

### Remediation Strategy

- **Retries**: 3 attempts for all components
- **Cleanup on Fail**: Enabled to prevent resource leaks
- **Remediate Last Failure**: Enabled for upgrades to handle partial failures
- **Rollback Timeout**: Shorter than install/upgrade for faster recovery

## Kustomization Timeout Configuration

### Layer-Based Timeouts

#### Sources Layer (5 minutes)

**Components**: Helm repositories, basic configurations
**Rationale**: Simple resource definitions with minimal complexity

```yaml
spec:
  timeout: 5m0s
  retryInterval: 2m0s
  wait: true
```

#### Core Infrastructure (10 minutes)

**Components**: External secrets, 1Password, cert-manager
**Rationale**: Foundation services with moderate complexity

```yaml
spec:
  timeout: 10m0s
  retryInterval: 2m0s
  wait: true
```

#### Storage Infrastructure (20 minutes)

**Components**: Longhorn storage system
**Rationale**: Complex storage initialization and USB SSD configuration

```yaml
spec:
  timeout: 20m0s
  retryInterval: 3m0s
  wait: true
```

#### Networking Infrastructure (15 minutes)

**Components**: Ingress, DNS, tunnels, BGP
**Rationale**: Network service dependencies and configuration complexity

```yaml
spec:
  timeout: 15m0s
  retryInterval: 2m0s
  wait: true
```

#### Applications (5-10 minutes)

**Components**: Dashboard, monitoring applications
**Rationale**: Simple applications with minimal dependencies

```yaml
spec:
  timeout: 5-10m0s
  retryInterval: 1-2m0s
  wait: true
```

### Retry Configuration

- **Retry Interval**: Balanced between quick recovery and avoiding resource thrashing
- **Wait**: Enabled to ensure proper dependency ordering
- **Health Checks**: Configured for critical components to verify readiness

## Source Timeout Configuration

### GitRepository (60 seconds)

**Rationale**: Git operations should be fast; longer timeouts indicate network issues

```yaml
spec:
  timeout: 60s
  interval: 1m0s
```

### HelmRepository (5 minutes)

**Rationale**: Helm index downloads can be large; allows for network variability

```yaml
spec:
  timeout: 5m
  interval: 12h
```

## Implementation Procedures

### 1. Initial Configuration

When adding new components:

1. **Assess Complexity**: Determine component category (critical/standard/simple)
2. **Set Base Timeout**: Use category defaults as starting point
3. **Configure Remediation**: Enable retries and cleanup
4. **Add Health Checks**: For critical components
5. **Monitor Performance**: Adjust based on actual behavior

### 2. Timeout Adjustment Process

```bash
# 1. Analyze current performance
kubectl get helmrelease -A -o wide
kubectl describe helmrelease <name> -n <namespace>

# 2. Check reconciliation metrics
kubectl logs -n flux-system deployment/helm-controller | grep timeout

# 3. Adjust configuration
# Edit appropriate helmrelease.yaml or kustomization.yaml

# 4. Apply changes
flux reconcile source git flux-system

# 5. Monitor results
watch kubectl get helmrelease <name> -n <namespace>
```

### 3. Validation Procedures

After timeout changes:

1. **Force Reconciliation**: Test new timeout values
2. **Monitor Metrics**: Check reconciliation duration
3. **Verify Alerts**: Ensure monitoring captures timeout events
4. **Document Changes**: Update this guide with lessons learned

## Monitoring Integration

### Key Metrics

- `gotk_reconcile_duration_seconds`: Reconciliation duration by resource
- `gotk_reconcile_condition`: Success/failure status
- `gotk_suspend_status`: Suspended resource tracking

### Alert Thresholds

- **Warning**: Reconciliation > 5 minutes (75% of minimum timeout)
- **Critical**: Reconciliation failure after retries
- **Info**: Resource suspension events

### Dashboard Queries

```promql
# Average reconciliation time by component
avg(gotk_reconcile_duration_seconds) by (kind, name)

# Timeout events
increase(gotk_reconcile_condition{type="Ready",status="False"}[1h])

# Success rate
rate(gotk_reconcile_condition{type="Ready",status="True"}[5m])
```

## Troubleshooting Decision Tree

### Timeout Exceeded

1. **Check Resource Availability**
   - CPU/Memory constraints
   - Storage availability
   - Network connectivity

2. **Analyze Component Logs**
   - Application startup issues
   - Dependency failures
   - Configuration errors

3. **Evaluate Timeout Appropriateness**
   - Compare with similar components
   - Consider environment factors
   - Review historical performance

4. **Adjust Configuration**
   - Increase timeout if justified
   - Fix underlying issues
   - Improve resource allocation

### Frequent Timeouts

1. **Resource Optimization**
   - Increase cluster resources
   - Optimize application configuration
   - Improve storage performance

2. **Dependency Analysis**
   - Review startup ordering
   - Check health check configuration
   - Validate network policies

3. **Configuration Tuning**
   - Adjust retry intervals
   - Modify health check timeouts
   - Optimize resource requests/limits

## Best Practices

### Configuration Management

1. **Version Control**: All timeout changes tracked in Git
2. **Documentation**: Update rationale for significant changes
3. **Testing**: Validate changes in development environment
4. **Monitoring**: Track impact of timeout adjustments

### Operational Procedures

1. **Regular Review**: Monthly timeout performance analysis
2. **Proactive Adjustment**: Adjust before problems occur
3. **Incident Response**: Document timeout-related incidents
4. **Knowledge Sharing**: Share lessons learned with team

### Environment Considerations

#### Development

- Shorter timeouts for faster feedback
- More aggressive retry policies
- Detailed logging enabled

#### Staging

- Production-like timeouts
- Comprehensive testing scenarios
- Performance validation

#### Production

- Conservative timeout values
- Robust retry mechanisms
- Comprehensive monitoring

## Configuration Templates

### New HelmRelease Template

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <component-name>
  namespace: <namespace>
spec:
  interval: 30m
  timeout: <15m|10m|5m> # Based on complexity
  install:
    timeout: <15m|10m|5m>
    remediation:
      retries: 3
  upgrade:
    timeout: <15m|10m|5m>
    remediation:
      retries: 3
      remediateLastFailure: true
    cleanupOnFail: true
  rollback:
    timeout: <10m|5m|3m>
    cleanupOnFail: true
  chart:
    spec:
      chart: <chart-name>
      version: "<version>"
      sourceRef:
        kind: HelmRepository
        name: <repository-name>
        namespace: flux-system
      interval: 12h
```

### New Kustomization Template

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: <component-name>
  namespace: flux-system
spec:
  interval: 10m0s
  timeout: <20m|15m|10m|5m>0s # Based on complexity
  path: <path>
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  retryInterval: <3m|2m|1m>0s
  wait: true
  dependsOn:
    - name: <dependency>
  healthChecks: # For critical components
    - apiVersion: apps/v1
      kind: Deployment
      name: <deployment-name>
      namespace: <namespace>
```

## Change Log

| Date       | Component          | Change                              | Rationale                    |
| ---------- | ------------------ | ----------------------------------- | ---------------------------- |
| 2025-01-17 | All HelmReleases   | Added comprehensive timeout configs | Prevent reconciliation hangs |
| 2025-01-17 | All Kustomizations | Added retry and wait policies       | Improve reliability          |
| 2025-01-17 | All Sources        | Added timeout configurations        | Handle network issues        |

## Related Documentation

- [Flux Timeout Troubleshooting](FLUX_TIMEOUT_TROUBLESHOOTING.md)
- [Operational Workflows](OPERATIONAL_WORKFLOWS.md)
- [Component Migration Guide](COMPONENT_MIGRATION_GUIDE.md)
- [Bootstrap vs GitOps Architecture](BOOTSTRAP_VS_GITOPS_ARCHITECTURE.md)
