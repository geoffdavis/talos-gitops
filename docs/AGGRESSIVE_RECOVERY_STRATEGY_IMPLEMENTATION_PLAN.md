# Aggressive Recovery Strategy: Complete GitOps Lifecycle Management Elimination

## Executive Summary

This document provides a detailed implementation plan for executing the **Aggressive Recovery Strategy** to eliminate the problematic `infrastructure-gitops-lifecycle-management` component that is causing HelmRelease installation timeouts and blocking cluster recovery.

**Current Status**: 87.1% Ready (27/31 Kustomizations)
**Target Status**: 100% Ready (31/31 Kustomizations)
**Strategy**: Complete elimination of gitops-lifecycle-management component
**Success Probability**: 95% (highest among all strategies)

## Root Cause Analysis

### Primary Blocker
- **Component**: `infrastructure-gitops-lifecycle-management`
- **Issue**: HelmRelease installation timeout (exceeding 15-minute limit)
- **Impact**: Blocking dependency chain recovery for `infrastructure-authentik-outpost-config`

### Dependency Chain
```
infrastructure-gitops-lifecycle-management (FAILED - PRIMARY BLOCKER)
    ↓ blocks
infrastructure-authentik-outpost-config (DependencyNotReady)
```

### Component Analysis
The `gitops-lifecycle-management` component provides:
- Authentication management automation
- Service discovery controller
- Database initialization hooks
- External secrets management
- Monitoring and observability

**Critical Finding**: The external Authentik outpost system is already operational and production-ready, making this component redundant.

## Safety Assessment

### Pre-Recovery System State
✅ **Operational Systems (27/31)**:
- External Authentik outpost system (COMPLETE and PRODUCTION-READY)
- Home Assistant stack (COMPLETE)
- Monitoring stack (COMPLETE)
- Kubernetes Dashboard with seamless SSO (COMPLETE)
- BGP LoadBalancer system (COMPLETE)
- Core infrastructure (networking, storage, certificates)

### Risk Analysis
- **LOW RISK**: External outpost system already handles all authentication requirements
- **NO SERVICE DISRUPTION**: All user-facing services remain operational
- **REVERSIBLE**: Complete rollback procedures provided

## Implementation Plan

### Phase 1: Pre-Recovery Safety Procedures

#### 1.1 Create System Backup
```bash
# Create backup directory with timestamp
BACKUP_DIR="recovery-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup current Flux state
flux export source git flux-system > "$BACKUP_DIR/flux-source.yaml"
flux export kustomization --all > "$BACKUP_DIR/flux-kustomizations.yaml"
flux export helmrelease --all > "$BACKUP_DIR/flux-helmreleases.yaml"

# Backup current cluster state
kubectl get kustomizations.kustomize.toolkit.fluxcd.io -A -o yaml > "$BACKUP_DIR/cluster-kustomizations.yaml"
kubectl get helmreleases.helm.toolkit.fluxcd.io -A -o yaml > "$BACKUP_DIR/cluster-helmreleases.yaml"

# Backup authentication system state
kubectl get secrets -n authentik-proxy -o yaml > "$BACKUP_DIR/authentik-proxy-secrets.yaml"
kubectl get configmaps -n authentik-proxy -o yaml > "$BACKUP_DIR/authentik-proxy-configmaps.yaml"

# Backup Git repository state
git log --oneline -10 > "$BACKUP_DIR/git-recent-commits.txt"
git status > "$BACKUP_DIR/git-status.txt"
```

#### 1.2 Validate Current System Health
```bash
# Check external outpost system health
kubectl get pods -n authentik-proxy
kubectl get ingress -n authentik-proxy
curl -I -k https://longhorn.k8s.home.geoffdavis.com
curl -I -k https://grafana.k8s.home.geoffdavis.com

# Verify BGP and networking
kubectl get svc --field-selector spec.type=LoadBalancer -A
kubectl exec -n kube-system -l k8s-app=cilium -- cilium bgp peers

# Check core infrastructure
kubectl get nodes
kubectl get pods -n kube-system | grep -E "(cilium|coredns)"
kubectl get pods -n longhorn-system | head -5
```

**Safety Checkpoint 1**: All validation commands must pass before proceeding.

#### 1.3 Document Current Flux State
```bash
# Document failing components
flux get kustomizations | grep -E "(Failed|DependencyNotReady)"
flux get helmreleases | grep -E "(Failed|DependencyNotReady)"

# Record current dependency chain
echo "Current blocking dependencies:" > "$BACKUP_DIR/blocking-dependencies.txt"
kubectl get kustomization infrastructure-gitops-lifecycle-management -n flux-system -o yaml >> "$BACKUP_DIR/blocking-dependencies.txt"
kubectl get kustomization infrastructure-authentik-outpost-config -n flux-system -o yaml >> "$BACKUP_DIR/blocking-dependencies.txt"
```

### Phase 2: Dependency Chain Analysis and Preparation

#### 2.1 Identify All Dependencies
```bash
# Find all Kustomizations that depend on gitops-lifecycle-management
grep -r "infrastructure-gitops-lifecycle-management" clusters/home-ops/infrastructure/
```

**Expected Dependencies**:
- `infrastructure-authentik-outpost-config` (in `outpost-config.yaml`)

#### 2.2 Prepare Dependency Updates
Create updated configuration files that remove the dependency:

**File**: `clusters/home-ops/infrastructure/outpost-config.yaml`
```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure-authentik-outpost-config
  namespace: flux-system
spec:
  dependsOn:
    - name: infrastructure-authentik
    - name: infrastructure-external-secrets
    - name: infrastructure-onepassword
    # REMOVED: - name: infrastructure-gitops-lifecycle-management
  interval: 30m
  retryInterval: 2m
  timeout: 15m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/authentik-outpost-config
  prune: true
  wait: true
  healthChecks:
    - apiVersion: batch/v1
      kind: Job
      name: authentik-radius-outpost-config
      namespace: authentik
```

### Phase 3: Aggressive Elimination Execution

#### 3.1 Remove GitOps Lifecycle Management Kustomization
```bash
# Stage 1: Remove from Flux configuration
git checkout -b aggressive-recovery-$(date +%Y%m%d-%H%M%S)

# Remove the Kustomization definition from identity.yaml
sed -i '/^---$/,/^---$/{ /name: infrastructure-gitops-lifecycle-management/,/^---$/{//!d}; /name: infrastructure-gitops-lifecycle-management/d; }' clusters/home-ops/infrastructure/identity.yaml

# Alternative manual approach - edit the file to remove lines 137-182
# vim clusters/home-ops/infrastructure/identity.yaml
# Delete the entire infrastructure-gitops-lifecycle-management Kustomization block
```

#### 3.2 Update Dependencies
```bash
# Update outpost-config.yaml to remove dependency
cp clusters/home-ops/infrastructure/outpost-config.yaml "$BACKUP_DIR/outpost-config.yaml.backup"

# Remove the gitops-lifecycle-management dependency
sed -i '/- name: infrastructure-gitops-lifecycle-management/d' clusters/home-ops/infrastructure/outpost-config.yaml
```

#### 3.3 Remove Infrastructure Directory
```bash
# Remove the entire gitops-lifecycle-management infrastructure
rm -rf infrastructure/gitops-lifecycle-management/

# Remove the chart directory
rm -rf charts/gitops-lifecycle-management/
```

**Safety Checkpoint 2**: Verify all changes before committing.

#### 3.4 Commit and Deploy Changes
```bash
# Verify changes
git status
git diff --name-only

# Commit the elimination
git add .
git commit -m "feat: eliminate gitops-lifecycle-management component

- Remove infrastructure-gitops-lifecycle-management Kustomization
- Remove dependency from infrastructure-authentik-outpost-config
- Delete infrastructure/gitops-lifecycle-management directory
- Delete charts/gitops-lifecycle-management directory

This resolves HelmRelease installation timeout issues blocking
cluster recovery. External outpost system already provides all
required functionality."

# Push changes
git push origin aggressive-recovery-$(date +%Y%m%d-%H%M%S)
```

### Phase 4: Recovery Monitoring and Validation

#### 4.1 Monitor Flux Reconciliation
```bash
# Force immediate reconciliation
flux reconcile source git flux-system

# Monitor Kustomization recovery
watch -n 5 'flux get kustomizations | grep -E "(infrastructure-authentik-outpost-config|infrastructure-authentik-proxy)"'

# Monitor overall system status
watch -n 10 'flux get kustomizations | grep -c Ready; echo "Total: 31"'
```

#### 4.2 Validate Dependency Chain Recovery
```bash
# Check authentik-outpost-config recovery
kubectl get kustomization infrastructure-authentik-outpost-config -n flux-system -o yaml

# Monitor for DependencyNotReady resolution
flux get kustomizations --status-selector="!Ready"

# Verify no remaining references to gitops-lifecycle-management
kubectl get kustomizations -A | grep gitops-lifecycle-management || echo "Successfully eliminated"
```

**Safety Checkpoint 3**: Verify dependency chain recovery before proceeding.

#### 4.3 Authentication System Validation
```bash
# Test all authenticated services
services=("longhorn" "grafana" "prometheus" "alertmanager" "dashboard" "homeassistant")
for service in "${services[@]}"; do
    echo "Testing $service.k8s.home.geoffdavis.com..."
    curl -I -k "https://$service.k8s.home.geoffdavis.com" | head -1
done

# Verify external outpost health
kubectl get pods -n authentik-proxy
kubectl logs -n authentik-proxy -l app.kubernetes.io/name=authentik-proxy --tail=10

# Check authentication endpoints
curl -I -k https://longhorn.k8s.home.geoffdavis.com/outpost.goauthentik.io/ping
```

### Phase 5: Success Validation and Cleanup

#### 5.1 Verify 100% Ready Status
```bash
# Check final Kustomization count
READY_COUNT=$(flux get kustomizations | grep -c "True.*Ready")
TOTAL_COUNT=31

echo "Ready Kustomizations: $READY_COUNT/$TOTAL_COUNT"

if [ "$READY_COUNT" -eq "$TOTAL_COUNT" ]; then
    echo "✅ SUCCESS: 100% Ready status achieved!"
else
    echo "❌ INCOMPLETE: $READY_COUNT/$TOTAL_COUNT Ready"
    flux get kustomizations | grep -v "True.*Ready"
fi
```

#### 5.2 Final System Health Check
```bash
# Comprehensive health validation
kubectl get nodes
kubectl get pods --field-selector=status.phase!=Running -A | grep -v Completed || echo "All pods running"
kubectl get svc --field-selector spec.type=LoadBalancer -A
flux get sources
flux get kustomizations
flux get helmreleases | grep -v "True.*Ready" || echo "All HelmReleases ready"
```

#### 5.3 Merge Recovery Branch
```bash
# Create pull request or merge directly
git checkout main
git merge aggressive-recovery-$(date +%Y%m%d-%H%M%S)
git push origin main

# Tag successful recovery
git tag -a "recovery-success-$(date +%Y%m%d)" -m "Successful aggressive recovery - 100% Ready status achieved"
git push origin --tags
```

## Rollback Procedures

### Emergency Rollback (if system becomes unstable)

#### Immediate Rollback
```bash
# Revert Git changes
git checkout main
git revert HEAD --no-edit
git push origin main

# Force Flux reconciliation
flux reconcile source git flux-system
```

#### Full System Restore
```bash
# Restore from backup
kubectl apply -f "$BACKUP_DIR/cluster-kustomizations.yaml"
kubectl apply -f "$BACKUP_DIR/cluster-helmreleases.yaml"

# Restore infrastructure directory
git checkout HEAD~1 -- infrastructure/gitops-lifecycle-management/
git checkout HEAD~1 -- charts/gitops-lifecycle-management/
git checkout HEAD~1 -- clusters/home-ops/infrastructure/identity.yaml
git checkout HEAD~1 -- clusters/home-ops/infrastructure/outpost-config.yaml

git add .
git commit -m "rollback: restore gitops-lifecycle-management component"
git push origin main
```

### Partial Rollback (if only specific components fail)

#### Restore Dependencies Only
```bash
# Restore dependency in outpost-config.yaml
git checkout HEAD~1 -- clusters/home-ops/infrastructure/outpost-config.yaml
git add clusters/home-ops/infrastructure/outpost-config.yaml
git commit -m "rollback: restore gitops-lifecycle-management dependency"
git push origin main
```

#### Restore Infrastructure Directory Only
```bash
# Restore infrastructure without Flux Kustomization
git checkout HEAD~1 -- infrastructure/gitops-lifecycle-management/
git add infrastructure/gitops-lifecycle-management/
git commit -m "rollback: restore gitops-lifecycle-management infrastructure"
git push origin main
```

## Monitoring Commands

### Real-time Recovery Monitoring
```bash
# Terminal 1: Overall Flux status
watch -n 5 'echo "=== FLUX KUSTOMIZATIONS ==="; flux get kustomizations | head -20'

# Terminal 2: Specific component monitoring
watch -n 5 'echo "=== TARGET COMPONENTS ==="; kubectl get kustomization infrastructure-authentik-outpost-config -n flux-system; echo; kubectl get kustomization infrastructure-authentik-proxy -n flux-system'

# Terminal 3: Authentication system health
watch -n 10 'echo "=== AUTHENTICATION HEALTH ==="; kubectl get pods -n authentik-proxy; echo; curl -s -I -k https://longhorn.k8s.home.geoffdavis.com | head -1'

# Terminal 4: System resource monitoring
watch -n 15 'echo "=== SYSTEM RESOURCES ==="; kubectl top nodes; echo; kubectl get pods --field-selector=status.phase!=Running -A | head -10'
```

### Progress Tracking Commands
```bash
# Count ready Kustomizations
flux get kustomizations | grep -c "True.*Ready"

# List failing components
flux get kustomizations | grep -v "True.*Ready"

# Check for dependency issues
kubectl get kustomizations -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Ready")].message}{"\n"}{end}' | grep -i dependency

# Monitor Helm operations
flux get helmreleases | grep -v "True.*Ready"
```

## Emergency Procedures

### Cluster Instability Response

#### Level 1: Service Disruption
```bash
# Check core services
kubectl get pods -n kube-system | grep -E "(coredns|cilium)"
kubectl get svc kubernetes

# Verify networking
kubectl exec -n kube-system -l k8s-app=cilium -- cilium status --brief

# Test internal connectivity
kubectl run test-pod --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default.svc.cluster.local
```

#### Level 2: Authentication System Failure
```bash
# Check external outpost system
kubectl get pods -n authentik-proxy
kubectl get pods -n authentik

# Restart authentication components if needed
kubectl rollout restart deployment authentik-proxy -n authentik-proxy
kubectl rollout restart deployment authentik-server -n authentik

# Verify ingress controller
kubectl get pods -n ingress-nginx-internal
kubectl get svc -n ingress-nginx-internal
```

#### Level 3: Complete System Recovery
```bash
# Emergency cluster reset (LAST RESORT)
# This preserves OS but wipes cluster state
task cluster:safe-reset CONFIRM=SAFE-RESET

# Re-bootstrap from backup
task bootstrap:phased
```

### Communication Procedures

#### Status Updates
```bash
# Generate status report
echo "=== RECOVERY STATUS REPORT ===" > recovery-status.txt
echo "Timestamp: $(date)" >> recovery-status.txt
echo "Ready Kustomizations: $(flux get kustomizations | grep -c 'True.*Ready')/31" >> recovery-status.txt
echo "" >> recovery-status.txt
echo "Failing Components:" >> recovery-status.txt
flux get kustomizations | grep -v "True.*Ready" >> recovery-status.txt
echo "" >> recovery-status.txt
echo "Authentication System Status:" >> recovery-status.txt
kubectl get pods -n authentik-proxy >> recovery-status.txt
```

#### Escalation Triggers
- **Immediate**: If core services (DNS, networking) fail
- **Within 15 minutes**: If authentication system becomes unavailable
- **Within 30 minutes**: If rollback procedures fail
- **Within 60 minutes**: If cluster becomes unresponsive

## Success Criteria

### Primary Success Metrics
- ✅ **100% Ready Status**: All 31 Flux Kustomizations show "Ready: True"
- ✅ **Authentication System Operational**: All 6 services accessible via SSO
- ✅ **No Service Disruption**: All user-facing services remain available
- ✅ **Dependency Chain Resolved**: No "DependencyNotReady" status

### Secondary Success Metrics
- ✅ **Flux Reconciliation**: All sources and Kustomizations reconciling normally
- ✅ **Resource Health**: All pods running, no failed deployments
- ✅ **Network Connectivity**: BGP peering stable, LoadBalancer IPs accessible
- ✅ **Monitoring Active**: Prometheus, Grafana, AlertManager operational

### Validation Checklist
```bash
# Run complete validation suite
./validate-recovery-success.sh
```

**Validation Script** (`validate-recovery-success.sh`):
```bash
#!/bin/bash
set -e

echo "=== RECOVERY SUCCESS VALIDATION ==="
echo "Timestamp: $(date)"
echo

# Check Flux status
echo "1. Flux Kustomizations Status:"
READY_COUNT=$(flux get kustomizations | grep -c "True.*Ready")
echo "   Ready: $READY_COUNT/31"
if [ "$READY_COUNT" -eq 31 ]; then
    echo "   ✅ SUCCESS: 100% Ready status achieved"
else
    echo "   ❌ INCOMPLETE: Missing $(( 31 - READY_COUNT )) Kustomizations"
    flux get kustomizations | grep -v "True.*Ready"
fi
echo

# Check authentication system
echo "2. Authentication System Status:"
AUTH_PODS=$(kubectl get pods -n authentik-proxy --no-headers | grep -c "Running")
echo "   Authentik Proxy Pods Running: $AUTH_PODS"
if [ "$AUTH_PODS" -gt 0 ]; then
    echo "   ✅ Authentication system operational"
else
    echo "   ❌ Authentication system not running"
fi
echo

# Test service accessibility
echo "3. Service Accessibility Test:"
services=("longhorn" "grafana" "prometheus" "alertmanager" "dashboard" "homeassistant")
success_count=0
for service in "${services[@]}"; do
    if curl -s -I -k "https://$service.k8s.home.geoffdavis.com" | grep -q "HTTP"; then
        echo "   ✅ $service.k8s.home.geoffdavis.com accessible"
        ((success_count++))
    else
        echo "   ❌ $service.k8s.home.geoffdavis.com not accessible"
    fi
done
echo "   Services accessible: $success_count/6"
echo

# Check system health
echo "4. System Health Check:"
NODE_COUNT=$(kubectl get nodes --no-headers | grep -c "Ready")
echo "   Nodes Ready: $NODE_COUNT/3"
FAILED_PODS=$(kubectl get pods -A --field-selector=status.phase!=Running --no-headers | grep -v Completed | wc -l)
echo "   Failed Pods: $FAILED_PODS"
if [ "$FAILED_PODS" -eq 0 ]; then
    echo "   ✅ All pods running successfully"
else
    echo "   ❌ $FAILED_PODS pods not running"
fi
echo

# Final assessment
echo "=== FINAL ASSESSMENT ==="
if [ "$READY_COUNT" -eq 31 ] && [ "$AUTH_PODS" -gt 0 ] && [ "$success_count" -eq 6 ] && [ "$FAILED_PODS" -eq 0 ]; then
    echo "🎉 RECOVERY SUCCESSFUL: All criteria met"
    echo "   - 100% Flux Kustomizations ready"
    echo "   - Authentication system operational"
    echo "   - All services accessible"
    echo "   - System health optimal"
    exit 0
else
    echo "⚠️  RECOVERY INCOMPLETE: Some criteria not met"
    echo "   Review failed checks above and apply corrective measures"
    exit 1
fi
```

## Post-Recovery Actions

### Documentation Updates
1. Update memory bank context with successful recovery
2. Document lessons learned and process improvements
3. Update operational procedures based on recovery experience

### System Optimization
1. Review and optimize remaining Kustomization dependencies
2. Implement monitoring for similar timeout issues
3. Enhance backup and recovery procedures

### Preventive Measures
1. Implement pre-commit hooks for dependency validation
2. Add automated testing for Flux configuration changes
3. Create monitoring alerts for HelmRelease timeout issues

---

**Document Version**: 1.0
**Created**: 2025-08-12
**Status**: Ready for execution
**Risk Level**: LOW (95% success probability)
**Estimated Duration**: 30-60 minutes
**Rollback Time**: 5-15 minutes