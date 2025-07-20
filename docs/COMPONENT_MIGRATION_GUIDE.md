# Component Migration Guide: Bootstrap ↔ GitOps

## Overview

This guide provides procedures for safely migrating components between Bootstrap and GitOps phases. While the current architecture is well-designed, there may be cases where components need to be moved between phases due to changing requirements or architectural improvements.

## Table of Contents

1. [Migration Principles](#migration-principles)
2. [Pre-Migration Assessment](#pre-migration-assessment)
3. [Bootstrap to GitOps Migration](#bootstrap-to-gitops-migration)
4. [GitOps to Bootstrap Migration](#gitops-to-bootstrap-migration)
5. [Cilium Case Study](#cilium-case-study)
6. [Idempotency Verification](#idempotency-verification)
7. [Rollback Procedures](#rollback-procedures)
8. [Testing Framework](#testing-framework)

## Migration Principles

### When to Consider Migration

**Bootstrap → GitOps**:
- Component no longer required for cluster bootstrap
- Benefits from version control and collaborative management
- Has stable APIs and doesn't require system-level access
- Can be deployed after cluster is operational

**GitOps → Bootstrap**:
- Component becomes foundational to cluster operation
- Required for GitOps system itself to function
- Needs system-level access or configuration
- Must exist before other components can start

### Safety Guidelines

1. **Never migrate critical path components** without thorough testing
2. **Always have a rollback plan** before starting migration
3. **Test in development environment** first
4. **Verify dependencies** won't be broken
5. **Ensure idempotency** of deployment methods
6. **Document the migration** for future reference

## Pre-Migration Assessment

### Dependency Analysis Checklist

Before migrating any component, complete this assessment:

```bash
# 1. Identify what depends on this component
grep -r "component-name" infrastructure/ apps/ clusters/
kubectl get all -A | grep component-name

# 2. Identify what this component depends on
# Check manifests for dependencies, secrets, configmaps, etc.

# 3. Check if component is in critical path
# Can the cluster start without this component?

# 4. Verify deployment method compatibility
# Can this be deployed via both methods?
```

### Risk Assessment Matrix

| Risk Level | Criteria | Migration Approach |
|------------|----------|-------------------|
| **Low** | Non-critical, no dependencies, well-tested | Standard migration |
| **Medium** | Some dependencies, operational impact | Staged migration with testing |
| **High** | Critical path, many dependencies | Extensive testing, gradual rollout |
| **Critical** | Core cluster functionality | Avoid migration or expert review |

## Bootstrap to GitOps Migration

### Standard Migration Procedure

**Example**: Migrating a monitoring component from bootstrap to GitOps

#### Phase 1: Preparation

```bash
# 1. Create GitOps manifests
mkdir -p infrastructure/my-component

# 2. Extract current configuration
kubectl get deployment my-component -n my-namespace -o yaml > infrastructure/my-component/deployment.yaml

# 3. Clean up the exported manifest
# Remove status, resourceVersion, uid, etc.
vim infrastructure/my-component/deployment.yaml

# 4. Create supporting manifests
cat > infrastructure/my-component/namespace.yaml << EOF
apiVersion: v1
kind: Namespace
metadata:
  name: my-namespace
EOF

# 5. Create kustomization
cat > infrastructure/my-component/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - deployment.yaml
EOF

# 6. Create Flux Kustomization
cat > clusters/home-ops/infrastructure/my-component.yaml << EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure-my-component
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./infrastructure/my-component
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    - name: infrastructure-sources
EOF
```

#### Phase 2: Testing

```bash
# 1. Test GitOps deployment in parallel
kubectl apply --dry-run=client -k infrastructure/my-component/

# 2. Deploy to test namespace
kubectl create namespace my-component-test
kubectl apply -k infrastructure/my-component/ -n my-component-test

# 3. Verify functionality
kubectl get pods -n my-component-test
kubectl logs -n my-component-test -l app=my-component

# 4. Clean up test
kubectl delete namespace my-component-test
```

#### Phase 3: Migration

```bash
# 1. Commit GitOps manifests (but don't include in main kustomization yet)
git add infrastructure/my-component/
git commit -m "Add GitOps manifests for my-component (not active)"
git push

# 2. Remove from bootstrap task
# Edit Taskfile.yml to remove deployment commands
vim Taskfile.yml

# 3. Test bootstrap without component
# In development environment:
task apps:deploy-core  # Should not deploy my-component

# 4. Activate GitOps management
git add clusters/home-ops/infrastructure/my-component.yaml
git commit -m "Migrate my-component to GitOps management"
git push

# 5. Verify GitOps deployment
flux get kustomizations
kubectl get pods -n my-namespace
```

#### Phase 4: Cleanup

```bash
# 1. Remove any bootstrap-specific configurations
# Clean up scripts, remove from task dependencies

# 2. Update documentation
# Update component lists in docs/

# 3. Verify idempotency
task apps:deploy-core  # Should be idempotent now
```

### Complex Migration Example: External Secrets Operator

This component is currently in bootstrap but could potentially be moved to GitOps:

#### Assessment
- **Dependencies**: Required by 1Password Connect and other secret management
- **Risk**: High - critical for secret management
- **Recommendation**: Keep in bootstrap (foundational component)

#### If Migration Were Necessary

```bash
# 1. Create HelmRelease for External Secrets
cat > infrastructure/external-secrets/helmrelease.yaml << EOF
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: external-secrets
  namespace: external-secrets-system
spec:
  interval: 30m
  chart:
    spec:
      chart: external-secrets
      version: "0.9.11"
      sourceRef:
        kind: HelmRepository
        name: external-secrets
        namespace: flux-system
  install:
    createNamespace: true
  values:
    installCRDs: true
EOF

# 2. Update bootstrap to only create initial secrets
# Modify bootstrap-1password-secrets.sh to not install operator

# 3. Ensure proper dependency ordering in GitOps
# External Secrets must come before components that use it
```

## GitOps to Bootstrap Migration

### When This Might Be Necessary

- Component becomes required for cluster bootstrap
- GitOps system depends on the component
- Component needs system-level access

### Migration Procedure

**Example**: Moving a component that became foundational

#### Phase 1: Create Bootstrap Implementation

```bash
# 1. Add to Taskfile.yml
vim Taskfile.yml
# Add new task for component deployment

# 2. Create bootstrap scripts if needed
cat > scripts/deploy-my-component.sh << EOF
#!/bin/bash
# Deploy my-component via direct kubectl/helm
helm upgrade --install my-component chart/my-component \
  --namespace my-namespace \
  --create-namespace \
  --wait
EOF

# 3. Add to bootstrap sequence
# Update bootstrap:cluster task to include new component
```

#### Phase 2: Test Bootstrap Deployment

```bash
# 1. Test in development environment
task my-component:deploy

# 2. Verify functionality
kubectl get pods -n my-namespace

# 3. Test full bootstrap sequence
task bootstrap:cluster
```

#### Phase 3: Remove from GitOps

```bash
# 1. Remove Flux Kustomization
git rm clusters/home-ops/infrastructure/my-component.yaml

# 2. Keep manifests for reference but mark as inactive
# Add comment to infrastructure/my-component/kustomization.yaml
echo "# This component is now managed by bootstrap phase" >> infrastructure/my-component/kustomization.yaml

# 3. Commit changes
git add .
git commit -m "Migrate my-component to bootstrap phase"
git push

# 4. Verify Flux removes the component
flux get kustomizations
# Component should be removed by Flux pruning
```

## Cilium Case Study

Cilium demonstrates a successful hybrid approach that could serve as a model for other complex components.

### Current Architecture

**Bootstrap Phase**:
- Core CNI installation via Helm
- Basic networking functionality
- Required for pod networking

**GitOps Phase**:
- BGP configuration
- Load balancer pools
- Advanced networking features

### Why This Works

1. **Clear Separation**: Core vs operational features
2. **Dependency Respect**: CNI before BGP
3. **Operational Benefits**: BGP config benefits from Git tracking
4. **Maintainability**: Each phase handles appropriate concerns

### Potential Consolidation

If CRD ordering issues were resolved, Cilium could potentially be fully moved to GitOps:

```bash
# 1. Create comprehensive HelmRelease
cat > infrastructure/cilium/helmrelease-complete.yaml << EOF
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: cilium
  namespace: kube-system
spec:
  interval: 30m
  chart:
    spec:
      chart: cilium
      version: "1.16.1"
      sourceRef:
        kind: HelmRepository
        name: cilium
        namespace: flux-system
  values:
    # All CNI and BGP configuration combined
    cni:
      install: true
    bgp:
      enabled: true
      announce:
        loadbalancerIP: true
EOF

# 2. Update infrastructure/cilium/kustomization.yaml
resources:
  - namespace.yaml
  - helmrelease-complete.yaml
  - loadbalancer-pool.yaml
  - loadbalancer-pool-ipv6.yaml

# 3. Remove from bootstrap tasks
# Remove apps:deploy-cilium from Taskfile.yml

# 4. Test thoroughly
# Ensure CRDs are installed in correct order
# Verify networking works during bootstrap
```

## Idempotency Verification

### Testing Framework

Create a comprehensive test to verify idempotency:

```bash
#!/bin/bash
# test-idempotency.sh

set -e

echo "Testing bootstrap idempotency..."

# Run bootstrap tasks multiple times
for i in {1..3}; do
    echo "Bootstrap run $i..."
    task apps:deploy-core
    
    # Check for errors
    if kubectl get events --all-namespaces | grep -i error | grep -v "Normal"; then
        echo "ERROR: Found errors in run $i"
        exit 1
    fi
    
    # Wait between runs
    sleep 30
done

echo "Testing GitOps idempotency..."

# Force reconciliation multiple times
for i in {1..3}; do
    echo "GitOps reconciliation $i..."
    flux reconcile kustomization flux-system
    flux reconcile kustomization infrastructure-sources
    
    # Check Flux status
    if ! flux get kustomizations | grep -q "True.*True"; then
        echo "ERROR: GitOps not healthy in run $i"
        exit 1
    fi
    
    sleep 30
done

echo "Idempotency tests passed!"
```

### Verification Checklist

- [ ] Bootstrap tasks can be run multiple times without errors
- [ ] GitOps reconciliation doesn't cause resource conflicts
- [ ] No duplicate resources are created
- [ ] Health checks pass after each run
- [ ] No unnecessary restarts or updates occur

## Rollback Procedures

### Bootstrap Migration Rollback

```bash
# 1. Re-add to bootstrap tasks
vim Taskfile.yml
# Restore component deployment

# 2. Remove from GitOps
git rm clusters/home-ops/infrastructure/my-component.yaml
git commit -m "Rollback: Move my-component back to bootstrap"
git push

# 3. Deploy via bootstrap
task my-component:deploy

# 4. Verify functionality
kubectl get pods -n my-namespace
```

### GitOps Migration Rollback

```bash
# 1. Remove GitOps management
git rm clusters/home-ops/infrastructure/my-component.yaml
git commit -m "Rollback: Remove my-component from GitOps"
git push

# 2. Re-add to bootstrap
vim Taskfile.yml
# Add component back to bootstrap tasks

# 3. Deploy via bootstrap
task apps:deploy-core

# 4. Clean up GitOps manifests
# Move infrastructure/my-component/ to archive/
```

## Testing Framework

### Pre-Migration Tests

```bash
# 1. Component functionality test
kubectl get pods -n component-namespace
kubectl logs -n component-namespace -l app=component

# 2. Dependency test
# Verify dependent components still work

# 3. Performance baseline
# Capture metrics before migration
```

### Post-Migration Tests

```bash
# 1. Deployment method test
# Verify component deploys via new method

# 2. Functionality test
# Same tests as pre-migration

# 3. Integration test
# Verify dependent components still work

# 4. Performance comparison
# Compare with baseline metrics
```

### Automated Testing

```bash
#!/bin/bash
# migration-test-suite.sh

# Pre-migration tests
echo "Running pre-migration tests..."
./test-component-functionality.sh
./test-dependencies.sh

# Perform migration
echo "Performing migration..."
./migrate-component.sh

# Post-migration tests
echo "Running post-migration tests..."
./test-component-functionality.sh
./test-dependencies.sh
./test-idempotency.sh

# Rollback test
echo "Testing rollback..."
./rollback-component.sh
./test-component-functionality.sh

echo "Migration test suite completed!"
```

## Best Practices

### Planning
1. **Document the rationale** for migration
2. **Assess all dependencies** thoroughly
3. **Plan rollback procedures** before starting
4. **Test in development** environment first

### Execution
1. **Make incremental changes** when possible
2. **Verify each step** before proceeding
3. **Monitor cluster health** throughout process
4. **Keep detailed logs** of changes made

### Validation
1. **Test idempotency** of new deployment method
2. **Verify all functionality** works as expected
3. **Check performance impact** of migration
4. **Update documentation** to reflect changes

### Maintenance
1. **Monitor for issues** after migration
2. **Update runbooks** and procedures
3. **Train team members** on new processes
4. **Review migration** for lessons learned

## Conclusion

Component migration between Bootstrap and GitOps phases should be approached carefully with thorough testing and clear rollback procedures. The current architecture is well-designed, and migrations should only be undertaken when there are clear operational benefits or changing requirements.

The hybrid approach demonstrated by Cilium shows that complex components can span both phases when there are clear architectural reasons for the separation.