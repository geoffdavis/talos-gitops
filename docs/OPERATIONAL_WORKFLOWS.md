# Operational Workflows: Bootstrap vs GitOps

## Overview

This guide provides practical, step-by-step workflows for common operational tasks, clearly indicating when to use Bootstrap vs GitOps approaches. Each workflow includes the rationale for the chosen approach and potential pitfalls to avoid.

## Table of Contents

1. [Quick Decision Reference](#quick-decision-reference)
2. [Application Management](#application-management)
3. [Infrastructure Changes](#infrastructure-changes)
4. [Network Configuration](#network-configuration)
5. [Security and Secrets](#security-and-secrets)
6. [Storage Management](#storage-management)
7. [Monitoring and Observability](#monitoring-and-observability)
8. [Disaster Recovery](#disaster-recovery)
9. [Troubleshooting Workflows](#troubleshooting-workflows)

## Quick Decision Reference

### When to Use Bootstrap (Taskfile Commands)

- ✅ Node-level configuration changes
- ✅ Cluster networking modifications
- ✅ Talos OS updates
- ✅ Core CNI changes
- ✅ Initial secret bootstrapping
- ✅ System-level troubleshooting

### When to Use GitOps (Git Commits)

- ✅ Application deployments
- ✅ Infrastructure service updates
- ✅ Configuration changes
- ✅ Scaling operations
- ✅ Certificate management
- ✅ Monitoring configuration

## Application Management

### Adding a New Application

**Approach**: GitOps Phase
**Rationale**: Applications are operational workloads that benefit from version control and collaborative development

**Workflow**:

```bash
# 1. Create application directory structure
mkdir -p apps/my-new-app

# 2. Create namespace
cat > apps/my-new-app/namespace.yaml << EOF
apiVersion: v1
kind: Namespace
metadata:
  name: my-new-app
  labels:
    name: my-new-app
EOF

# 3. Create deployment
cat > apps/my-new-app/deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-new-app
  namespace: my-new-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-new-app
  template:
    metadata:
      labels:
        app: my-new-app
    spec:
      containers:
      - name: my-new-app
        image: nginx:1.21
        ports:
        - containerPort: 80
EOF

# 4. Create service
cat > apps/my-new-app/service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: my-new-app
  namespace: my-new-app
spec:
  selector:
    app: my-new-app
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF

# 5. Create kustomization
cat > apps/my-new-app/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
EOF

# 6. Add to GitOps management
# Edit clusters/home-ops/infrastructure/apps.yaml to include:
cat >> clusters/home-ops/infrastructure/apps.yaml << EOF
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps-my-new-app
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./apps/my-new-app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    - name: infrastructure-ingress-nginx
EOF

# 7. Commit and deploy
git add apps/my-new-app/ clusters/home-ops/infrastructure/apps.yaml
git commit -m "Add my-new-app application"
git push

# 8. Monitor deployment
flux get kustomizations --watch
kubectl get pods -n my-new-app
```

### Updating an Existing Application

**Approach**: GitOps Phase
**Workflow**:

```bash
# 1. Update the application manifest
vim apps/my-app/deployment.yaml
# Change image version, resource limits, etc.

# 2. Commit changes
git add apps/my-app/
git commit -m "Update my-app to version 2.0"
git push

# 3. Monitor rollout
kubectl rollout status deployment/my-app -n my-app
```

### Removing an Application

**Approach**: GitOps Phase
**Workflow**:

```bash
# 1. Remove from GitOps management
# Edit clusters/home-ops/infrastructure/apps.yaml
# Remove the Kustomization for the app

# 2. Commit removal
git add clusters/home-ops/infrastructure/apps.yaml
git commit -m "Remove my-old-app application"
git push

# 3. Verify cleanup (Flux will prune resources)
kubectl get all -n my-old-app
```

## Infrastructure Changes

### Adding a New Infrastructure Service

**Approach**: GitOps Phase
**Example**: Adding Redis for application caching

**Workflow**:

```bash
# 1. Create infrastructure directory
mkdir -p infrastructure/redis

# 2. Create namespace
cat > infrastructure/redis/namespace.yaml << EOF
apiVersion: v1
kind: Namespace
metadata:
  name: redis-system
EOF

# 3. Create HelmRelease
cat > infrastructure/redis/helmrelease.yaml << EOF
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: redis
  namespace: redis-system
spec:
  interval: 30m
  chart:
    spec:
      chart: redis
      version: "17.3.7"
      sourceRef:
        kind: HelmRepository
        name: bitnami
        namespace: flux-system
  values:
    auth:
      enabled: false
    replica:
      replicaCount: 1
EOF

# 4. Create kustomization
cat > infrastructure/redis/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - helmrelease.yaml
EOF

# 5. Add to infrastructure management
# Edit clusters/home-ops/infrastructure/storage.yaml or create new file

# 6. Commit and deploy
git add infrastructure/redis/
git commit -m "Add Redis infrastructure service"
git push
```

### Updating Infrastructure Service Configuration

**Approach**: GitOps Phase
**Example**: Scaling Longhorn replicas

**Workflow**:

```bash
# 1. Update HelmRelease values
vim infrastructure/longhorn/helmrelease.yaml
# Modify replica counts, resource limits, etc.

# 2. Commit changes
git add infrastructure/longhorn/
git commit -m "Scale Longhorn for increased capacity"
git push

# 3. Monitor update
flux get helmreleases -n longhorn-system
kubectl get pods -n longhorn-system
```

## Network Configuration

### Changing Cluster Network Settings

**Approach**: Bootstrap Phase
**Rationale**: Network configuration affects the fundamental cluster operation

**Example**: Changing pod CIDR ranges

**Workflow**:

```bash
# 1. Update cluster configuration
vim talconfig.yaml
# Modify clusterPodNets and clusterSvcNets

# 2. Update Talos patches if needed
vim talos/patches/cluster.yaml

# 3. Regenerate Talos configuration
task talos:generate-config

# 4. Apply to nodes (may require restart)
task talos:apply-config

# 5. Verify cluster networking
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

### Adding BGP Peering Configuration

**Approach**: GitOps Phase
**Rationale**: BGP configuration is operational and benefits from change tracking

**Workflow**:

```bash
# 1. Update BGP policy
vim infrastructure/cilium-bgp/bgp-policy.yaml
# Add new peer configurations

# 2. Update load balancer pools if needed
vim infrastructure/cilium/loadbalancer-pool.yaml

# 3. Commit changes
git add infrastructure/cilium-bgp/ infrastructure/cilium/
git commit -m "Add new BGP peer for additional network"
git push

# 4. Verify BGP peering
kubectl get ciliumbgpclusterconfig
cilium bgp peers
```

### Updating DNS Configuration

**Approach**: Depends on scope

**For External DNS (GitOps)**:

```bash
# Update external-dns configuration
vim infrastructure/external-dns/helmrelease.yaml
git add infrastructure/external-dns/
git commit -m "Update DNS provider configuration"
git push
```

**For Cluster DNS (Bootstrap)**:

```bash
# Update cluster DNS domain
vim talconfig.yaml
task talos:generate-config
task talos:apply-config
```

## Security and Secrets

### Adding New Secrets

**Approach**: Hybrid (Bootstrap for initial setup, GitOps for ongoing management)

**For 1Password-managed secrets (GitOps)**:

```bash
# 1. Add secret to 1Password vault
op item create --category="Secure Note" \
  --title="My App Database Password" \
  --vault="Services" \
  "password[password]=supersecret123"

# 2. Create ExternalSecret
cat > apps/my-app/external-secret.yaml << EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-app-db-secret
  namespace: my-app
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: onepassword-connect-secret-store
    kind: SecretStore
  target:
    name: my-app-db-secret
    creationPolicy: Owner
  data:
  - secretKey: password
    remoteRef:
      key: "My App Database Password"
      property: password
EOF

# 3. Update kustomization
echo "  - external-secret.yaml" >> apps/my-app/kustomization.yaml

# 4. Commit and deploy
git add apps/my-app/
git commit -m "Add database secret for my-app"
git push
```

### Rotating Cluster Certificates

**Approach**: Bootstrap Phase
**Rationale**: Cluster certificates are fundamental to cluster security

**Workflow**:

```bash
# 1. Generate new certificates (if needed)
task talos:generate-config

# 2. Apply new configuration
task talos:apply-config

# 3. Restart cluster components if required
kubectl rollout restart deployment -n kube-system
```

### Updating TLS Certificates

**Approach**: GitOps Phase
**Rationale**: Application certificates are managed by cert-manager

**Workflow**:

```bash
# 1. Update certificate configuration
vim infrastructure/cert-manager-issuers/cluster-issuer.yaml

# 2. Commit changes
git add infrastructure/cert-manager-issuers/
git commit -m "Update certificate issuer configuration"
git push

# 3. Monitor certificate renewal
kubectl get certificates -A
kubectl describe certificate my-cert -n my-namespace
```

## Storage Management

### Adding New Storage Classes

**Approach**: GitOps Phase
**Workflow**:

```bash
# 1. Create storage class manifest
cat > infrastructure/longhorn/storage-class-fast.yaml << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-fast
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "2"
  staleReplicaTimeout: "2880"
  fromBackup: ""
  diskSelector: "ssd"
  nodeSelector: "storage-node"
EOF

# 2. Update kustomization
echo "  - storage-class-fast.yaml" >> infrastructure/longhorn/kustomization.yaml

# 3. Commit and deploy
git add infrastructure/longhorn/
git commit -m "Add fast storage class for SSD nodes"
git push
```

### Configuring Storage Node Labels

**Approach**: Bootstrap Phase
**Rationale**: Node labels are system-level configuration

**Workflow**:

```bash
# 1. Update node configuration
vim talconfig.yaml
# Add nodeLabels section

# 2. Regenerate and apply
task talos:generate-config
task talos:apply-config

# 3. Verify labels
kubectl get nodes --show-labels
```

## Monitoring and Observability

### Adding New Monitoring Dashboards

**Approach**: GitOps Phase
**Workflow**:

```bash
# 1. Create ConfigMap with dashboard JSON
cat > infrastructure/monitoring/dashboard-my-app.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-app-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  my-app.json: |
    {
      "dashboard": {
        "title": "My App Metrics",
        // ... dashboard JSON
      }
    }
EOF

# 2. Update kustomization
echo "  - dashboard-my-app.yaml" >> infrastructure/monitoring/kustomization.yaml

# 3. Commit and deploy
git add infrastructure/monitoring/
git commit -m "Add monitoring dashboard for my-app"
git push
```

### Updating Prometheus Configuration

**Approach**: GitOps Phase
**Workflow**:

```bash
# 1. Update Prometheus HelmRelease
vim infrastructure/monitoring/prometheus.yaml
# Modify scrape configs, retention, etc.

# 2. Commit changes
git add infrastructure/monitoring/
git commit -m "Update Prometheus scrape configuration"
git push

# 3. Monitor rollout
kubectl rollout status statefulset/prometheus-server -n monitoring
```

## Disaster Recovery

### Cluster Recovery After Power Outage

**Approach**: Bootstrap Phase
**Rationale**: Fundamental cluster recovery requires bootstrap procedures

**Workflow**:

```bash
# 1. Verify node accessibility
task cluster:status

# 2. Recover kubeconfig if needed
task talos:recover-kubeconfig

# 3. Check cluster state
kubectl get nodes
kubectl get pods -A

# 4. If cluster is broken, perform recovery
task cluster:recover

# 5. Verify GitOps is working
flux get kustomizations
```

### Restoring from Backup

**Approach**: Hybrid

**For Longhorn volumes (GitOps)**:

```bash
# Restore via Longhorn UI or kubectl
kubectl apply -f backup-restore-manifest.yaml
```

**For etcd backup (Bootstrap)**:

```bash
# Use Talos etcd recovery procedures
talosctl etcd snapshot /path/to/backup.db
```

## Troubleshooting Workflows

### Application Not Starting

**Diagnostic Approach**:

```bash
# 1. Check GitOps status
flux get kustomizations
flux logs --follow

# 2. Check application resources
kubectl get all -n my-app
kubectl describe pod <pod-name> -n my-app

# 3. Check dependencies
kubectl get secrets -n my-app
kubectl get configmaps -n my-app

# 4. Check events
kubectl get events -n my-app --sort-by='.lastTimestamp'
```

### Network Connectivity Issues

**Diagnostic Approach**:

```bash
# 1. Check Cilium status (Bootstrap component)
kubectl get pods -n kube-system -l k8s-app=cilium
cilium status

# 2. Check BGP peering (GitOps component)
kubectl get ciliumbgpclusterconfig
cilium bgp peers

# 3. Check load balancer pools
kubectl get ippools
kubectl get svc --all-namespaces | grep LoadBalancer

# 4. Test connectivity
kubectl run test-pod --image=busybox --rm -it -- /bin/sh
```

### Storage Issues

**Diagnostic Approach**:

```bash
# 1. Check Longhorn status
kubectl get pods -n longhorn-system
kubectl get volumes -n longhorn-system

# 2. Check storage classes
kubectl get storageclass

# 3. Check PVC status
kubectl get pvc -A

# 4. Check node storage
kubectl describe nodes | grep -A 5 "Allocated resources"
```

## Best Practices Summary

### Bootstrap Phase Operations

1. **Test in Development**: Always test bootstrap changes in a dev environment
2. **Backup First**: Ensure you have backups before making system-level changes
3. **Document Changes**: Keep clear records of what was changed and why
4. **Verify Dependencies**: Understand what depends on the component you're changing

### GitOps Phase Operations

1. **Use Feature Branches**: Make changes in branches and use pull requests
2. **Small Changes**: Make incremental changes that are easy to review and rollback
3. **Monitor Deployments**: Watch Flux logs during deployments
4. **Test Rollbacks**: Ensure you can rollback changes if needed

### General Guidelines

1. **Understand the Boundary**: Know why a component is in Bootstrap vs GitOps
2. **Follow Dependencies**: Respect the dependency chain
3. **Monitor Health**: Use health checks and monitoring to verify changes
4. **Document Decisions**: Record why you chose a particular approach

## Emergency Procedures

### When GitOps is Broken

```bash
# 1. Check Flux system
kubectl get pods -n flux-system
kubectl logs -n flux-system -l app=source-controller

# 2. Manually apply critical fixes
kubectl apply -f critical-fix.yaml

# 3. Fix GitOps and re-sync
flux reconcile source git flux-system
flux reconcile kustomization flux-system
```

### When Bootstrap Components Fail

```bash
# 1. Use emergency recovery
task cluster:emergency-recovery

# 2. Check node status
talosctl health --nodes <ip>

# 3. Apply safe recovery procedures
task cluster:safe-reset  # Only if necessary
```

This operational guide provides the practical knowledge needed to maintain and operate the cluster effectively while respecting the Bootstrap vs GitOps architectural boundaries.
