# Authentik Proxy Configuration Helm Chart

A Helm chart for automatically configuring Authentik proxy providers and applications using GitOps-compatible hooks. This chart replaces manual Kubernetes Jobs with proper Helm lifecycle management.

## Overview

This chart configures Authentik proxy providers and applications for the following services:
- Kubernetes Dashboard
- Hubble UI (Cilium)
- Grafana
- Prometheus
- AlertManager
- Longhorn UI

## Features

- **GitOps Compatible**: Uses Helm hooks for proper lifecycle management
- **Atomic Configuration**: All services are configured atomically with rollback on failure
- **Idempotent**: Safe to run multiple times, handles existing configurations gracefully
- **Comprehensive Error Handling**: Retry logic with exponential backoff
- **Security Focused**: Minimal RBAC permissions, non-root containers, read-only filesystems
- **Token Management**: Integrates with External Secrets for secure token handling

## Prerequisites

1. **Authentik Deployment**: Authentik must be deployed and running
2. **External Secrets**: External Secrets Operator must be configured with 1Password
3. **Admin Token**: Valid Authentik admin API token stored in 1Password
4. **Authorization Flow**: Existing authorization flow UUID (default: `be0ee023-11fe-4a43-b453-bc67957cafbf`)

## Installation

### 1. Add the Chart Repository

```bash
# If using a local chart
helm install authentik-proxy-config ./charts/authentik-proxy-config -n authentik
```

### 2. Configure Values

Create a `values.yaml` file with your specific configuration:

```yaml
authentik:
  host: "http://authentik-server.authentik.svc.cluster.local"
  authFlowUuid: "be0ee023-11fe-4a43-b453-bc67957cafbf"

services:
  dashboard:
    enabled: true
    externalHost: "https://dashboard.k8s.home.geoffdavis.com"
  grafana:
    enabled: true
    externalHost: "https://grafana.k8s.home.geoffdavis.com"
  # ... configure other services as needed

hooks:
  timeout: 300
  retries: 3
  backoff: 15
```

### 3. Install the Chart

```bash
helm install authentik-proxy-config ./charts/authentik-proxy-config \
  -n authentik \
  -f values.yaml
```

## Configuration

### Service Configuration

Each service can be individually enabled/disabled and configured:

```yaml
services:
  dashboard:
    name: "Kubernetes Dashboard"
    slug: "dashboard"
    externalHost: "https://dashboard.k8s.home.geoffdavis.com"
    internalHost: "http://kubernetes-dashboard-web.kubernetes-dashboard.svc.cluster.local:8000"
    description: "Kubernetes cluster management dashboard"
    publisher: "Kubernetes"
    enabled: true
```

### Hook Configuration

Configure hook behavior:

```yaml
hooks:
  timeout: 300          # Maximum execution time in seconds
  retries: 3           # Number of retry attempts
  backoff: 15          # Backoff time between retries in seconds
  image: "curlimages/curl:8.5.0"  # Container image for hooks
```

### Proxy Provider Settings

Configure proxy provider behavior:

```yaml
proxyProvider:
  mode: "forward_single"
  cookieDomain: "k8s.home.geoffdavis.com"
  skipPathRegex: "^/api/.*$"
  basicAuthEnabled: false
  internalHostSslValidation: false
```

### RBAC Configuration

```yaml
rbac:
  create: true
  serviceAccountName: "authentik-proxy-config"
```

## Hook Lifecycle

### Pre-Install Hook (Weight: -5)
- Validates Authentik server readiness
- Checks admin token validity
- Verifies required secrets exist
- Tests API connectivity

### Post-Install Hook (Weight: 1)
- Creates proxy providers for all enabled services
- Creates applications for each service
- Updates proxy outpost with all providers atomically
- Implements rollback on any failure

### Post-Upgrade Hook (Weight: 1)
- Updates existing configurations
- Handles service additions/removals
- Maintains configuration consistency

## Security

### Container Security
- Runs as non-root user (UID 65534)
- Read-only root filesystem
- Drops all capabilities
- Uses seccomp runtime default profile

### RBAC Permissions
Minimal required permissions:
- `secrets`: get, list (for token access)
- `configmaps`: get, list (for configuration)
- `pods`: get, list (for readiness checks)
- `services`: get, list (for service discovery)

## Troubleshooting

### Hook Failures

Check hook logs:
```bash
kubectl logs -n authentik job/authentik-proxy-config-post-install-config
```

### Authentication Issues

Verify token secret:
```bash
kubectl get secret authentik-radius-token -n authentik -o yaml
```

### Service Configuration Issues

Check ConfigMap:
```bash
kubectl get configmap authentik-proxy-config-service-config -n authentik -o yaml
```

### Manual Cleanup

If hooks fail and need cleanup:
```bash
# Delete failed jobs
kubectl delete job -n authentik -l app.kubernetes.io/name=authentik-proxy-config

# Force Helm reconciliation
helm upgrade authentik-proxy-config ./charts/authentik-proxy-config -n authentik -f values.yaml
```

## Integration with Flux

This chart is designed to work seamlessly with Flux GitOps:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: authentik-proxy-config
  namespace: authentik
spec:
  interval: 30m
  chart:
    spec:
      chart: ./charts/authentik-proxy-config
      sourceRef:
        kind: GitRepository
        name: infrastructure
        namespace: flux-system
  dependsOn:
    - name: authentik
      namespace: authentik
  values:
    authentik:
      host: "http://authentik-server.authentik.svc.cluster.local"
    services:
      dashboard:
        enabled: true
      grafana:
        enabled: true
      # ... other services
```

## Migration from Jobs

To migrate from the existing Kubernetes Jobs:

1. **Backup Current Configuration**: Export existing providers and applications from Authentik
2. **Deploy Chart**: Install this Helm chart
3. **Verify Configuration**: Check that all services are properly configured
4. **Remove Old Jobs**: Delete the old Job-based configuration
5. **Update GitOps**: Update your GitOps configuration to use the new chart

## Values Reference

| Parameter | Description | Default |
|-----------|-------------|---------|
| `authentik.host` | Authentik server URL | `http://authentik-server.authentik.svc.cluster.local` |
| `authentik.authFlowUuid` | Authorization flow UUID | `be0ee023-11fe-4a43-b453-bc67957cafbf` |
| `services.*.enabled` | Enable/disable service configuration | `true` |
| `services.*.externalHost` | External URL for the service | Required |
| `services.*.internalHost` | Internal service URL | Required |
| `hooks.timeout` | Hook execution timeout | `300` |
| `hooks.retries` | Number of retry attempts | `3` |
| `hooks.backoff` | Backoff time between retries | `15` |
| `rbac.create` | Create RBAC resources | `true` |
| `rbac.serviceAccountName` | Service account name | `authentik-proxy-config` |

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This chart is licensed under the MIT License.