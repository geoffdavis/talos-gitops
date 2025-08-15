# Kubernetes Dashboard Comparison (2025)

## Overview Comparison

| Feature                | Kubernetes Dashboard | Headlamp                  | Octant                      |
| ---------------------- | -------------------- | ------------------------- | --------------------------- |
| **Type**               | Web-based            | Web-based                 | Desktop app (with web mode) |
| **Official Support**   | CNCF project         | CNCF Sandbox project      | VMware (archived)           |
| **Active Development** | Yes (v7.x in 2025)   | Yes (actively maintained) | No (archived Oct 2023)      |
| **Installation**       | Helm chart           | Helm chart                | Binary download             |
| **Resource Usage**     | Light (~200MB RAM)   | Light (~150MB RAM)        | Heavier (~500MB RAM)        |

## Authentication Comparison

### Kubernetes Dashboard

- **Token Authentication**: Required (by design)
- **OIDC Support**: Enterprise version only
- **Proxy Support**: Limited (still requires token)
- **Your Setup**: Using Kong proxy + manual token entry
- **Session Management**: Cookie-based after token login

### Headlamp

- **Token Authentication**: Optional
- **OIDC Support**: Native support (free)
- **Proxy Support**: Full support
- **Authentik Integration**: Works seamlessly
- **Session Management**: OIDC token refresh

### Octant (Deprecated)

- **Status**: Project archived October 2023
- **Not recommended for new deployments**

## Feature Comparison

### Kubernetes Dashboard

**Pros:**

- Official Kubernetes project
- Comprehensive resource coverage
- Real-time metrics integration
- Multi-language support
- Stable and battle-tested
- Good for read-only operations
- Built-in log viewer
- Terminal access to pods

**Cons:**

- Token authentication required
- No built-in OIDC in OSS version
- Limited customization
- No plugin system
- Basic YAML editor

### Headlamp

**Pros:**

- **Native OIDC authentication** (works with Authentik)
- Plugin architecture
- Modern React-based UI
- Extensible via plugins
- Multi-cluster support
- Dark mode
- Helm chart management
- CRD support
- Mobile-responsive design
- Active development

**Cons:**

- Smaller community
- Less mature than Dashboard
- Fewer built-in features
- Documentation still growing

## Integration with Your Setup

### Current Setup (Kubernetes Dashboard)

```yaml
# Current pain points:
- Manual token entry required
- Kong proxy doesn't bypass auth
- Helper scripts needed
- No Authentik SSO integration
```

### Headlamp Integration

```yaml
# Would work with your setup:
- Direct Authentik OIDC integration
- No token management needed
- Uses nginx-internal ingress
- Single sign-on with other services
```

## Headlamp Installation for Your Cluster

```yaml
# apps/headlamp/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: headlamp
  namespace: headlamp
spec:
  interval: 15m
  chart:
    spec:
      chart: headlamp
      version: "0.23.0" # Check for latest
      sourceRef:
        kind: HelmRepository
        name: headlamp
        namespace: flux-system
  values:
    config:
      oidc:
        clientId: "headlamp"
        clientSecret: "${HEADLAMP_OIDC_SECRET}"
        issuerURL: "https://authentik.k8s.home.geoffdavis.com/application/o/headlamp/"
        scopes: "openid profile email groups"

    ingress:
      enabled: true
      className: nginx-internal
      annotations:
        cert-manager.io/cluster-issuer: letsencrypt-prod
        external-dns.alpha.kubernetes.io/hostname: headlamp.k8s.home.geoffdavis.com
      hosts:
        - host: headlamp.k8s.home.geoffdavis.com
          paths:
            - path: /
              pathType: Prefix
      tls:
        - secretName: headlamp-tls
          hosts:
            - headlamp.k8s.home.geoffdavis.com
```

## Recommendation

**For your home lab setup, I recommend Headlamp because:**

1. **Native OIDC Support**: Works directly with Authentik without workarounds
2. **No Token Management**: Eliminates the current authentication hassle
3. **Active Development**: Regular updates and security patches
4. **Lightweight**: Similar resource usage to current Dashboard
5. **Modern UI**: Better user experience with dark mode
6. **Plugin System**: Can extend functionality as needed

### Migration Path

1. Deploy Headlamp alongside current Dashboard
2. Configure Authentik application for Headlamp
3. Test OIDC authentication
4. Once validated, make Headlamp primary
5. Keep Dashboard as backup/alternative

### Quick Headlamp Test

```bash
# Deploy locally to test (without auth)
docker run -p 4466:4466 ghcr.io/headlamp-k8s/headlamp:latest \
  -in-cluster=false \
  -kubeconfig=$HOME/.kube/config

# Access at http://localhost:4466
```

## Conclusion

While the Kubernetes Dashboard is the official solution, its token-only authentication in the OSS version makes it cumbersome for home lab use. Headlamp provides a modern alternative with native OIDC support that would integrate seamlessly with your Authentik setup, eliminating the need for token management while maintaining security through SSO.
