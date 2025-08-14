# Cluster Stabilization Plan

## Current State Assessment
**Date**: 2025-08-14  
**Critical Issues**: 1 failing HelmRelease blocking GitOps chain  
**Impact**: Cannot deploy new workloads, trust in cluster stability compromised  

### Failing Components
1. **authentik-proxy-config HelmRelease**
   - Status: Stalled/Failed
   - Root Cause: Post-upgrade hooks failing repeatedly
   - Impact: Blocking infrastructure-authentik-proxy Kustomization
   - Cascading: Preventing dependent workloads from deploying

### Root Causes of Instability
1. **Overly Complex Helm Hooks**
   - Pre-install/post-install/post-upgrade hooks with fragile curl scripts
   - Hardcoded ports and endpoints prone to configuration drift
   - No idempotency - hooks fail on re-runs

2. **Tight Coupling**
   - Authentication proxy configuration tightly coupled to Authentik availability
   - Hooks depend on exact API responses and timing
   - No graceful degradation or retry mechanisms

3. **Configuration Management Anti-Patterns**
   - Inline Job definitions in HelmRelease values
   - Mixing infrastructure provisioning with application deployment
   - No separation of concerns between setup and runtime

## Stabilization Strategy

### Phase 1: Immediate Stabilization (15 minutes)
**Goal**: Get cluster to green state, all reconciliations passing

1. **Disable All Helm Hooks in authentik-proxy-config**
   ```yaml
   # charts/authentik-proxy-config/values.yaml
   hooks:
     enabled: false  # Disable ALL hooks
   ```

2. **Remove Inline Jobs from HelmRelease**
   - Remove the `resources:` section with inline Job definitions
   - Keep only essential configuration values

3. **Bump Chart Version and Deploy**
   ```bash
   # Bump to 0.2.0 to force clean deployment
   # Commit and push
   # Force reconciliation
   ```

### Phase 2: Simplify Architecture (30 minutes)
**Goal**: Remove unnecessary complexity

1. **Convert Dynamic Configuration to Static**
   - Move proxy provider configuration to ConfigMaps
   - Use Kustomize patches for environment-specific values
   - Remove runtime API calls

2. **Separate Concerns**
   - Infrastructure setup: One-time manual or separate automation
   - Application deployment: Pure declarative GitOps
   - Configuration updates: Through Git commits only

3. **Remove Service Discovery Automation**
   - Explicitly define services that need proxy authentication
   - Use static configuration instead of label-based discovery

### Phase 3: Implement Proper Patterns (1 hour)
**Goal**: Establish reliable, maintainable patterns

1. **Use Init Containers Instead of Hooks**
   - Readiness checks in init containers
   - No complex scripting in hooks
   - Clear success/failure conditions

2. **Implement Proper Health Checks**
   ```yaml
   healthChecks:
     - type: http
       url: http://service/health
       interval: 30s
       timeout: 10s
   ```

3. **Use External Secrets for All Sensitive Data**
   - No inline secrets
   - Proper secret rotation
   - Clear secret dependencies

### Phase 4: Validation and Documentation (30 minutes)
**Goal**: Ensure stability and maintainability

1. **Validation Checklist**
   - [ ] All Kustomizations showing Ready=True
   - [ ] All HelmReleases showing Ready=True
   - [ ] No pending or failing Jobs
   - [ ] Can deploy new test workload successfully
   - [ ] Can modify and redeploy existing workload

2. **Documentation Updates**
   - Update CLAUDE.md with new patterns
   - Document what NOT to do (anti-patterns)
   - Create runbook for common issues

## Implementation Steps

### Step 1: Disable Problematic Components
```bash
# 1. Edit chart to disable all hooks
cd charts/authentik-proxy-config
```

```yaml
# values.yaml
hooks:
  enabled: false
  preInstallTokenSetup:
    enabled: false
  postInstall:
    enabled: false
  postUpgrade:
    enabled: false
```

### Step 2: Clean HelmRelease
```yaml
# infrastructure/authentik-proxy/helmrelease-config.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: authentik-proxy-config
  namespace: authentik-proxy
spec:
  interval: 30m  # Increase interval
  timeout: 5m    # Reasonable timeout
  chart:
    spec:
      chart: ./charts/authentik-proxy-config
      sourceRef:
        kind: GitRepository
        name: flux-system
        namespace: flux-system
  values:
    # Only essential runtime configuration
    externalSecrets:
      tokenSecretName: "authentik-admin-token-enhanced"
      tokenSecretKey: "token"
    # Remove ALL resources: sections
    # Remove ALL inline Jobs
```

### Step 3: Static Configuration
```yaml
# infrastructure/authentik-proxy/proxy-providers-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: proxy-providers-static
  namespace: authentik-proxy
data:
  providers.yaml: |
    providers:
      - name: longhorn
        externalHost: https://longhorn.k8s.home.geoffdavis.com
        internalHost: http://longhorn-frontend.longhorn-system:80
      - name: hubble
        externalHost: https://hubble.k8s.home.geoffdavis.com
        internalHost: http://hubble-ui.kube-system:80
      # Add other services as needed
```

### Step 4: Version Bump and Deploy
```bash
# 1. Bump chart version
sed -i '' 's/version: 0.1.10/version: 0.2.0/' charts/authentik-proxy-config/Chart.yaml

# 2. Commit changes
git add -A
git commit -m "fix: simplify authentik-proxy-config, remove failing hooks"

# 3. Push to trigger Flux
git push origin main

# 4. Force reconciliation
flux reconcile source git flux-system
flux reconcile kustomization infrastructure-authentik-proxy
```

## Success Criteria

1. **All Green Dashboard**
   ```bash
   flux get all -A | grep -v "True.*True"
   # Should return nothing
   ```

2. **Successful Test Deployment**
   ```yaml
   # test-deployment.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: test-nginx
     namespace: default
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: test-nginx
     template:
       metadata:
         labels:
           app: test-nginx
       spec:
         containers:
         - name: nginx
           image: nginx:alpine
   ```

3. **Clean Logs**
   ```bash
   flux logs --all-namespaces --since=5m | grep -i error
   # Should show no recurring errors
   ```

## Maintenance Going Forward

### DO:
- Use static configuration wherever possible
- Keep Helm charts simple - just templates and values
- Test changes in staging before production
- Use proper GitOps patterns - everything through Git

### DON'T:
- Use complex Helm hooks for configuration
- Make runtime API calls in deployment scripts
- Mix infrastructure setup with application deployment
- Use inline Job definitions in HelmRelease values

## Recovery Procedures

If stabilization fails:

1. **Complete Hook Removal**
   ```bash
   # Delete all hook templates
   rm -rf charts/authentik-proxy-config/templates/hooks/
   ```

2. **Minimal Chart**
   Create minimal chart with just:
   - ConfigMap for static config
   - ServiceAccount if needed
   - RBAC if needed

3. **Manual Uninstall/Reinstall**
   ```bash
   # Suspend Flux management
   flux suspend helmrelease authentik-proxy-config -n authentik-proxy
   
   # Manual cleanup
   helm uninstall authentik-proxy-config -n authentik-proxy
   
   # Resume Flux
   flux resume helmrelease authentik-proxy-config -n authentik-proxy
   ```

## Timeline

- **T+0**: Start stabilization
- **T+15min**: All hooks disabled, cluster reconciling
- **T+45min**: Simplified architecture deployed
- **T+90min**: Full validation complete
- **T+120min**: Documentation updated, cluster stable

## Notes

The root issue is trying to do too much automation in Helm hooks. Authentik provider/application configuration should either be:
1. Done once manually through the UI
2. Managed by a proper operator/controller
3. Configured through static files in Git

The current approach of runtime API calls in hooks is fragile and anti-GitOps.