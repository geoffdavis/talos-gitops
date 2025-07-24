# Authentik External Proxy Outpost

This directory contains the configuration for the external Authentik proxy outpost that replaces the problematic embedded outpost system. The external outpost provides a more robust and maintainable authentication architecture for all *.k8s.home.geoffdavis.com services.

## Architecture Overview

The external outpost consists of:

- **Dedicated Namespace**: `authentik-proxy` with proper security policies
- **External Proxy Deployment**: 2 replicas using `ghcr.io/goauthentik/proxy:2024.8.3`
- **Single Ingress**: Handles all *.k8s.home.geoffdavis.com domains
- **Service Routing**: ConfigMap-based backend service discovery
- **BGP Integration**: Uses nginx-internal ingress class with BGP load balancer

## Supported Services

The external outpost provides authentication for:

1. **Longhorn** (`longhorn.k8s.home.geoffdavis.com`) → `longhorn-frontend.longhorn-system:80`
2. **Grafana** (`grafana.k8s.home.geoffdavis.com`) → `kube-prometheus-stack-grafana.monitoring:80`
3. **Prometheus** (`prometheus.k8s.home.geoffdavis.com`) → `kube-prometheus-stack-prometheus.monitoring:9090`
4. **AlertManager** (`alertmanager.k8s.home.geoffdavis.com`) → `kube-prometheus-stack-alertmanager.monitoring:9093`
5. **Dashboard** (`dashboard.k8s.home.geoffdavis.com`) → `kubernetes-dashboard-kong-proxy.kubernetes-dashboard:443`
6. **Hubble** (`hubble.k8s.home.geoffdavis.com`) → `hubble-ui.kube-system:80`

## Configuration Files

- **`namespace.yaml`**: Dedicated namespace with security policies
- **`rbac.yaml`**: ServiceAccount and RBAC permissions
- **`configmap.yaml`**: Service routing and configuration data
- **`secret.yaml`**: ExternalSecret for Authentik API token
- **`deployment.yaml`**: External proxy deployment (2 replicas)
- **`service.yaml`**: ClusterIP service with metrics endpoint
- **`ingress.yaml`**: Single ingress handling all authenticated domains
- **`kustomization.yaml`**: Kustomize configuration

## Deployment Dependencies

The external outpost depends on:

1. **infrastructure-sources**: Flux source repositories
2. **infrastructure-external-secrets**: Secret management system
3. **infrastructure-cert-manager**: TLS certificate management
4. **infrastructure-ingress-nginx-internal**: BGP-enabled ingress controller
5. **infrastructure-authentik**: Main Authentik server

## Network Integration

- **Ingress Class**: `nginx-internal` (BGP load balancer integration)
- **Load Balancer IP**: `172.29.52.200` (BGP-advertised)
- **TLS Certificates**: Let's Encrypt via cert-manager
- **DNS Records**: Automatic via external-dns

## Validation Commands

### Check Deployment Status
```bash
# Check Flux Kustomization
flux get kustomizations infrastructure-authentik-proxy

# Check deployment health
kubectl get deployment -n authentik-proxy authentik-proxy
kubectl get pods -n authentik-proxy

# Check service and ingress
kubectl get svc -n authentik-proxy
kubectl get ingress -n authentik-proxy
```

### Verify Network Connectivity
```bash
# Test ingress IP assignment
kubectl get svc -n ingress-nginx-internal nginx-internal-ingress-nginx-controller

# Test DNS resolution
dig longhorn.k8s.home.geoffdavis.com
dig grafana.k8s.home.geoffdavis.com

# Test TLS certificates
kubectl get certificates -n authentik-proxy
```

### Test Authentication Flow
```bash
# Test service accessibility (should redirect to Authentik)
curl -I https://longhorn.k8s.home.geoffdavis.com
curl -I https://grafana.k8s.home.geoffdavis.com

# Check proxy health endpoint
kubectl port-forward -n authentik-proxy svc/authentik-proxy 9000:9000
curl http://localhost:9000/outpost.goauthentik.io/ping
```

### Monitor Logs
```bash
# Check proxy logs
kubectl logs -n authentik-proxy -l app.kubernetes.io/name=authentik-proxy

# Check ingress controller logs
kubectl logs -n ingress-nginx-internal -l app.kubernetes.io/name=ingress-nginx

# Check Authentik server logs
kubectl logs -n authentik -l app.kubernetes.io/name=authentik
```

## Troubleshooting

### Common Issues

1. **API Token Expired**: Check ExternalSecret and regenerate token in Authentik admin
2. **Service Discovery**: Verify backend service names and ports in ConfigMap
3. **Network Connectivity**: Ensure BGP advertisement and DNS records are correct
4. **TLS Issues**: Check cert-manager certificate issuance

### Recovery Procedures

1. **Restart Proxy**: `kubectl rollout restart deployment/authentik-proxy -n authentik-proxy`
2. **Force Secret Sync**: `kubectl annotate externalsecret authentik-proxy-token force-sync=$(date +%s) -n authentik-proxy`
3. **Recreate Ingress**: `kubectl delete ingress authentik-proxy -n authentik-proxy && kubectl apply -f ingress.yaml`

## Security Features

- **Pod Security Standards**: Restricted security context
- **RBAC**: Minimal required permissions
- **Network Policies**: Namespace isolation
- **TLS Everywhere**: End-to-end encryption
- **Security Headers**: Comprehensive HTTP security headers

## High Availability

- **2 Replicas**: Pod anti-affinity for node distribution
- **Health Checks**: Comprehensive liveness, readiness, and startup probes
- **Rolling Updates**: Zero-downtime deployments
- **Resource Limits**: Proper CPU and memory constraints

This external outpost configuration provides a robust, scalable, and maintainable authentication system that replaces the problematic embedded outpost approach.