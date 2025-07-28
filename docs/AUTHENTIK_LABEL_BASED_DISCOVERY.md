# Authentik Label-Based Service Discovery

## Overview

Instead of manually configuring each service in Helm values, we can use Kubernetes labels and annotations to automatically discover and configure services for Authentik proxy authentication.

## Label-Based Approach

### Service Labels and Annotations

Services that need Authentik proxy authentication would be labeled like this:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: home-assistant
  namespace: home-automation
  labels:
    app.kubernetes.io/name: home-assistant
    # Enable Authentik proxy discovery
    authentik.io/proxy: "enabled"
  annotations:
    # Authentik proxy configuration
    authentik.io/external-host: "homeassistant.k8s.home.geoffdavis.com"
    authentik.io/service-name: "Home Assistant"
    authentik.io/description: "Home Assistant home automation platform"
    authentik.io/publisher: "Home Assistant"
    authentik.io/slug: "homeassistant"
    # Optional: custom internal port if different from service port
    authentik.io/internal-port: "8123"
spec:
  selector:
    app.kubernetes.io/name: home-assistant
  ports:
    - name: http
      port: 8123
      targetPort: 8123
```

### Automatic Discovery Script

A controller or job could discover services with these labels:

```bash
#!/bin/bash
# Discover all services with authentik proxy labels
kubectl get services --all-namespaces \
  -l "authentik.io/proxy=enabled" \
  -o json | jq -r '.items[] | {
    namespace: .metadata.namespace,
    name: .metadata.name,
    externalHost: .metadata.annotations."authentik.io/external-host",
    serviceName: .metadata.annotations."authentik.io/service-name",
    description: .metadata.annotations."authentik.io/description",
    publisher: .metadata.annotations."authentik.io/publisher",
    slug: .metadata.annotations."authentik.io/slug",
    port: (.spec.ports[0].port // .metadata.annotations."authentik.io/internal-port")
  }'
```

## Implementation Options

### Option 1: Custom Resource Definitions (CRDs)

Create a custom resource for Authentik proxy services:

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: authentikproxies.authentik.io
spec:
  group: authentik.io
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              serviceName:
                type: string
              serviceNamespace:
                type: string
              externalHost:
                type: string
              displayName:
                type: string
              description:
                type: string
              publisher:
                type: string
              enabled:
                type: boolean
                default: true
  scope: Namespaced
  names:
    plural: authentikproxies
    singular: authentikproxy
    kind: AuthentikProxy
```

Then services would be configured like:

```yaml
apiVersion: authentik.io/v1
kind: AuthentikProxy
metadata:
  name: home-assistant
  namespace: home-automation
spec:
  serviceName: home-assistant
  serviceNamespace: home-automation
  externalHost: homeassistant.k8s.home.geoffdavis.com
  displayName: "Home Assistant"
  description: "Home Assistant home automation platform"
  publisher: "Home Assistant"
  enabled: true
```

### Option 2: Ingress-Based Discovery

Use ingress annotations to automatically configure Authentik:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: home-assistant
  namespace: home-automation
  annotations:
    # Standard ingress annotations
    kubernetes.io/ingress.class: nginx-internal
    cert-manager.io/cluster-issuer: letsencrypt-prod
    
    # Authentik proxy annotations
    authentik.io/proxy: "enabled"
    authentik.io/service-name: "Home Assistant"
    authentik.io/description: "Home Assistant home automation platform"
    authentik.io/publisher: "Home Assistant"
spec:
  tls:
    - hosts:
        - homeassistant.k8s.home.geoffdavis.com
      secretName: home-assistant-tls
  rules:
    - host: homeassistant.k8s.home.geoffdavis.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: home-assistant
                port:
                  number: 8123
```

### Option 3: Operator Pattern

Create a Kubernetes operator that:

1. Watches for services/ingresses with Authentik labels
2. Automatically creates proxy providers in Authentik
3. Updates the external outpost configuration
4. Handles cleanup when services are removed

## Benefits of Label-Based Approach

### Advantages

- **Declarative**: Service configuration lives with the service
- **Automatic**: No manual configuration files to maintain
- **Consistent**: Same pattern for all services
- **GitOps Friendly**: Everything in version control
- **Self-Documenting**: Configuration is visible in service manifests

### Example: Home Assistant Service

```yaml
# apps/home-automation/home-assistant/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: home-assistant
  namespace: home-automation
  labels:
    app.kubernetes.io/name: home-assistant
    authentik.io/proxy: "enabled"
  annotations:
    authentik.io/external-host: "homeassistant.k8s.home.geoffdavis.com"
    authentik.io/service-name: "Home Assistant"
    authentik.io/description: "Home Assistant home automation platform"
    authentik.io/publisher: "Home Assistant"
    authentik.io/slug: "homeassistant"
spec:
  selector:
    app.kubernetes.io/name: home-assistant
  ports:
    - name: http
      port: 8123
      targetPort: 8123
  type: ClusterIP
```

## Implementation Strategy

### Phase 1: Label-Based Discovery Job

1. Create a job that discovers services with `authentik.io/proxy=enabled`
2. Generate proxy provider configurations automatically
3. Update Authentik via API

### Phase 2: Controller/Operator

1. Implement a controller that watches for labeled services
2. Automatically create/update/delete proxy providers
3. Handle service lifecycle events

### Phase 3: Integration with External Outpost

1. Automatically assign new providers to external outpost
2. Handle outpost updates without manual intervention
3. Provide status feedback via service annotations

## Comparison with Current Approaches

| Approach | Pros | Cons |
|----------|------|------|
| **Manual Config** | Simple, explicit | Error-prone, maintenance overhead |
| **Helm Values** | Templated, validated | Still manual, centralized config |
| **Label-Based** | Automatic, declarative | Requires controller/operator |
| **CRD-Based** | Type-safe, Kubernetes-native | More complex setup |
| **Ingress-Based** | Leverages existing resources | Limited to ingress-exposed services |

## Recommended Implementation

For your use case, I'd recommend starting with **Option 2 (Ingress-Based Discovery)** because:

1. **Minimal Changes**: You already have ingresses for these services
2. **Natural Fit**: Authentik proxy is about external access, which ingresses handle
3. **Simple Implementation**: Can be done with a discovery job
4. **Easy Migration**: Existing services just need annotation updates

Would you like me to implement the ingress-based discovery approach?
