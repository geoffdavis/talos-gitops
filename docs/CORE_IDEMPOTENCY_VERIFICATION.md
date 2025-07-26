# Core Deployment Idempotency Verification

This document explains how to verify that the [`apps:deploy-core`](../Taskfile.yml:402) task is idempotent and can be run multiple times safely.

## Overview

The [`apps:deploy-core`](../Taskfile.yml:402) task deploys foundational components during the Bootstrap phase:

- [Cilium CNI](../infrastructure/cilium/helmrelease.yaml:1)
- [External Secrets Operator](../infrastructure/external-secrets/external-secrets-operator.yaml:1)
- [1Password Connect](../infrastructure/onepassword-connect/deployment.yaml:1)
- [Longhorn Storage](../infrastructure/longhorn/kustomization.yaml:1)

For operational safety and ease of updates, this task must be idempotent - meaning it can be run multiple times without causing conflicts or degrading cluster health.

## Verification Script

The [`scripts/verify-core-idempotency.sh`](../scripts/verify-core-idempotency.sh:1) script automatically tests idempotency by:

1. **Capturing initial cluster state** - Resource counts, pod status, events
2. **Running [`apps:deploy-core`](../Taskfile.yml:402) multiple times** - Default 3 iterations
3. **Checking for conflicts** - Resource conflicts, failed pods, error events
4. **Verifying component health** - All core components remain healthy
5. **Comparing states** - Cluster state should be identical between runs

## Running the Verification

### Using Task (Recommended)

```bash
task apps:verify-core-idempotency
```

### Direct Script Execution

```bash
./scripts/verify-core-idempotency.sh
```

## Prerequisites

- Kubernetes cluster must be accessible via [`kubectl`](../Taskfile.yml:35)
- [`task`](../Taskfile.yml:22) command must be available
- Core components should already be deployed (for meaningful testing)

## Test Results

### Success Indicators

- ✅ All [`apps:deploy-core`](../Taskfile.yml:402) runs complete without errors
- ✅ No resource conflicts or "already exists" errors
- ✅ All component pods remain healthy across runs
- ✅ Cluster resource state identical between runs

### Warning Indicators

- ⚠️ Component health issues (pods not ready)
- ⚠️ Resource state differences between runs
- ⚠️ Warning events in cluster logs

### Failure Indicators

- ❌ [`apps:deploy-core`](../Taskfile.yml:402) task fails on subsequent runs
- ❌ Resource conflicts or duplicate resource errors
- ❌ Component pods fail or become unhealthy

## Test Artifacts

The script saves detailed logs in `/tmp/idempotency-test/`:

- `run-*-output.txt` - Task execution output
- `run-*-errors.txt` - Error logs from each run
- `run-*-resources.txt` - Cluster resource state snapshots
- `initial-*.txt` - Initial component states

## Troubleshooting

### Common Issues

**Helm Release Conflicts**

- Symptom: "release already exists" errors
- Solution: Ensure Helm charts use `--upgrade --install` pattern

**CRD Timing Issues**

- Symptom: "no matches for kind" errors
- Solution: Add proper wait conditions for CRD establishment

**Resource Ownership Conflicts**

- Symptom: "field is immutable" errors
- Solution: Use strategic merge patches or recreate resources

### Component-Specific Issues

**Cilium CNI**

- Check for DaemonSet rollout conflicts
- Verify node-specific tolerations

**External Secrets**

- Ensure webhook validation is working
- Check CRD establishment timing

**1Password Connect**

- Verify secret store configurations
- Check credential synchronization

**Longhorn Storage**

- Monitor storage class conflicts
- Check node storage preparation

## Integration with Bootstrap Process

This verification ensures that:

1. **Component updates are safe** - [`apps:deploy-core`](../Taskfile.yml:402) can be re-run for updates
2. **Recovery procedures work** - Failed deployments can be retried
3. **Operational workflows are reliable** - No manual intervention needed

## Best Practices

1. **Run verification after changes** - Test idempotency when modifying core components
2. **Include in CI/CD** - Automate verification in deployment pipelines
3. **Monitor for regressions** - Regular testing catches idempotency issues early
4. **Document exceptions** - Note any components that require special handling

## Related Documentation

- [Bootstrap vs GitOps Architecture](./BOOTSTRAP_VS_GITOPS_ARCHITECTURE.md) - Overall architectural context
- [Operational Workflows](./OPERATIONAL_WORKFLOWS.md) - How idempotency fits into operations
- [Component Migration Guide](./COMPONENT_MIGRATION_GUIDE.md) - Moving components between phases

## Future Improvements

Potential enhancements to the verification process:

1. **Parallel execution testing** - Verify concurrent [`apps:deploy-core`](../Taskfile.yml:402) runs
2. **Resource drift detection** - Monitor for configuration drift over time
3. **Performance impact analysis** - Measure deployment time consistency
4. **Integration with monitoring** - Alert on idempotency failures
