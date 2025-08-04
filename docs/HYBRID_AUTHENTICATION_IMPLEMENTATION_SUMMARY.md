# Hybrid Authentication Strategy Implementation Summary

This document summarizes the implementation of the hybrid authentication strategy for the Talos GitOps home-ops cluster, providing validation procedures and rollback instructions.

## Implementation Overview

**Strategy**: Hybrid authentication approach that reduces complexity and operational overhead while maintaining security.

**Phases Completed**:

1. ✅ **Grafana Native OIDC Migration** (Highest Impact)
2. ✅ **Dashboard Kong Configuration Fix** (Resolves immediate problem)
3. ✅ **Prometheus Authentication Removal** (Reduces attack surface)
4. ✅ **Proxy Configuration Simplification** (Reduces operational overhead)

## Current Authentication Architecture

### Services by Authentication Method

#### Native OIDC Authentication

- **Grafana**: `https://grafana.k8s.home.geoffdavis.com`
  - Method: Native Grafana OIDC integration with Authentik
  - Client ID: `grafana`
  - Benefits: Direct authentication, better performance, native user experience

#### Ingress-Based Authentication

- **Dashboard**: `https://dashboard.k8s.home.geoffdavis.com`
  - Method: nginx-ingress with Authentik auth annotations
  - Benefits: Eliminates Kong complexity, removes token prompting

#### Proxy-Based Authentication (Simplified)

- **Longhorn**: `https://longhorn.k8s.home.geoffdavis.com`
- **AlertManager**: `https://alertmanager.k8s.home.geoffdavis.com`
- **Hubble**: `https://hubble.k8s.home.geoffdavis.com`
- **Home Assistant**: `https://homeassistant.k8s.home.geoffdavis.com`
- Method: External Authentik outpost proxy (simplified configuration)

#### No External Authentication (Security)

- **Prometheus**: Internal access only via `kubectl port-forward`
  - Rationale: Reduces attack surface, contains sensitive metrics
  - Access: `kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090`

## Validation Procedures

### Phase 1.1: Grafana OIDC Validation

```bash
# 1. Deploy OIDC setup
kubectl apply -f infrastructure/authentik-outpost-config/grafana-oidc-setup-job.yaml

# 2. Monitor job execution
kubectl logs -n authentik job/grafana-oidc-setup -f

# 3. 1Password entry automatically created by setup job
# Title: "home-ops-grafana-oidc-client-secret"
# Field: "credential" = <client-secret>
# Tags: "kubernetes,home-ops,grafana,oidc"

# 4. Deploy updated configuration
kubectl apply -k infrastructure/monitoring/

# 5. Test authentication flow
# Navigate to: https://grafana.k8s.home.geoffdavis.com
# Expected: Redirect to Authentik → Login → Redirect back to Grafana
```

**Success Criteria**:

- ✅ Grafana accessible without proxy
- ✅ OIDC login redirects to Authentik
- ✅ Successful authentication returns to Grafana
- ✅ User permissions based on Authentik groups

### Phase 1.2: Dashboard Authentication Validation

```bash
# 1. Deploy updated Dashboard configuration
kubectl apply -k apps/dashboard/

# 2. Verify Kong is disabled
kubectl get pods -n kubernetes-dashboard | grep -v kong

# 3. Check ingress configuration
kubectl get ingress -n kubernetes-dashboard

# 4. Test authentication flow
# Navigate to: https://dashboard.k8s.home.geoffdavis.com
# Expected: Redirect to Authentik → Login → Redirect back to Dashboard
```

**Success Criteria**:

- ✅ No Kong pods running
- ✅ Direct ingress access working
- ✅ No bearer token prompting
- ✅ Seamless SSO authentication

### Phase 1.3: Prometheus Access Validation

```bash
# 1. Verify service is ClusterIP
kubectl get svc -n monitoring kube-prometheus-stack-prometheus

# 2. Test port-forward access
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# 3. Access Prometheus
open http://localhost:9090

# 4. Verify no external access
curl -I https://prometheus.k8s.home.geoffdavis.com  # Should fail
```

**Success Criteria**:

- ✅ Service type is ClusterIP
- ✅ Port-forward access works
- ✅ No external network access
- ✅ Prometheus UI accessible locally

### Phase 1.4: Simplified Proxy Validation

```bash
# 1. Deploy simplified configuration
kubectl apply -k infrastructure/authentik-proxy/

# 2. Run static configuration job
kubectl apply -f infrastructure/authentik-proxy/static-proxy-config.yaml

# 3. Monitor job execution
kubectl logs -n authentik-proxy job/static-proxy-config -f

# 4. Test remaining proxy services
curl -I https://longhorn.k8s.home.geoffdavis.com
curl -I https://alertmanager.k8s.home.geoffdavis.com
curl -I https://hubble.k8s.home.geoffdavis.com
curl -I https://homeassistant.k8s.home.geoffdavis.com
```

**Success Criteria**:

- ✅ Static configuration replaces CronJob
- ✅ Only 4 services in proxy configuration
- ✅ All proxy services redirect to Authentik
- ✅ Successful authentication for all services

## Complete Authentication Flow Testing

### Test Script

```bash
#!/bin/bash
# test-authentication-flows.sh

echo "=== Testing Hybrid Authentication Implementation ==="

# Test Grafana OIDC
echo "Testing Grafana OIDC..."
curl -I https://grafana.k8s.home.geoffdavis.com 2>/dev/null | head -1

# Test Dashboard Ingress Auth
echo "Testing Dashboard ingress auth..."
curl -I https://dashboard.k8s.home.geoffdavis.com 2>/dev/null | head -1

# Test Prometheus (should fail externally)
echo "Testing Prometheus external access (should fail)..."
curl -I https://prometheus.k8s.home.geoffdavis.com 2>/dev/null || echo "✅ External access properly blocked"

# Test Proxy Services
echo "Testing proxy services..."
for service in longhorn alertmanager hubble homeassistant; do
  echo "  Testing $service..."
  curl -I https://$service.k8s.home.geoffdavis.com 2>/dev/null | head -1
done

echo "=== Authentication Flow Testing Complete ==="
```

## Rollback Procedures

### Rollback Phase 1.1: Revert Grafana to Proxy

```bash
# 1. Remove OIDC configuration from Grafana
kubectl patch helmrelease -n monitoring kube-prometheus-stack --type='json' -p='[
  {"op": "remove", "path": "/spec/values/grafana/env"},
  {"op": "remove", "path": "/spec/values/grafana/envFromSecrets"},
  {"op": "remove", "path": "/spec/values/grafana/ingress"}
]'

# 2. Add Grafana back to proxy configuration
# Edit infrastructure/authentik-proxy/configmap.yaml
# Add: grafana section back to services.yaml

# 3. Add Grafana back to static configuration
# Edit infrastructure/authentik-proxy/static-proxy-config.yaml
# Add: configure_proxy_provider call for Grafana

# 4. Apply changes
kubectl apply -k infrastructure/authentik-proxy/
kubectl apply -k infrastructure/monitoring/
```

### Rollback Phase 1.2: Revert Dashboard to Kong

```bash
# 1. Re-enable Kong in Dashboard HelmRelease
kubectl patch helmrelease -n kubernetes-dashboard kubernetes-dashboard --type='json' -p='[
  {"op": "replace", "path": "/spec/values/kong/enabled", "value": true},
  {"op": "remove", "path": "/spec/values/app/ingress"}
]'

# 2. Restore Kong configuration files
# Restore: apps/dashboard/kong-config-static.yaml
# Restore: apps/dashboard/kong-config-service-account.yaml

# 3. Update kustomization
# Add Kong resources back to apps/dashboard/kustomization.yaml

# 4. Apply changes
kubectl apply -k apps/dashboard/
```

### Rollback Phase 1.3: Restore Prometheus External Access

```bash
# 1. Restore LoadBalancer service
kubectl patch helmrelease -n monitoring kube-prometheus-stack --type='json' -p='[
  {"op": "replace", "path": "/spec/values/prometheus/service/type", "value": "LoadBalancer"},
  {"op": "add", "path": "/spec/values/prometheus/service/annotations", "value": {"io.cilium/lb-ipam-pool": "bgp-default"}},
  {"op": "add", "path": "/spec/values/prometheus/service/labels", "value": {"io.cilium/lb-ipam-pool": "bgp-default"}}
]'

# 2. Add Prometheus back to proxy configuration
# Edit infrastructure/authentik-proxy/configmap.yaml and static-proxy-config.yaml

# 3. Apply changes
kubectl apply -k infrastructure/monitoring/
kubectl apply -k infrastructure/authentik-proxy/
```

### Rollback Phase 1.4: Restore Complex Service Discovery

```bash
# 1. Replace static configuration with CronJob
# Edit infrastructure/authentik-proxy/kustomization.yaml
# Replace: static-proxy-config.yaml with service-discovery-job.yaml

# 2. Apply changes
kubectl apply -k infrastructure/authentik-proxy/

# 3. Verify CronJob is running
kubectl get cronjob -n authentik-proxy authentik-service-discovery
```

## Benefits Achieved

### Operational Benefits

- **Reduced Complexity**: Eliminated Kong proxy complexity for Dashboard
- **Better Performance**: Native OIDC for Grafana removes proxy overhead
- **Simplified Maintenance**: Static configuration replaces complex CronJob
- **Reduced Attack Surface**: Prometheus no longer externally accessible

### Security Benefits

- **Defense in Depth**: Multiple authentication methods reduce single points of failure
- **Principle of Least Privilege**: Prometheus restricted to administrative access only
- **Improved Auditability**: Clear authentication paths for each service
- **Reduced Credential Exposure**: Fewer services requiring external authentication

### User Experience Benefits

- **Seamless SSO**: Consistent authentication experience across services
- **No Manual Tokens**: Eliminated bearer token prompting for Dashboard
- **Native Integration**: Grafana OIDC provides better user experience
- **Clear Access Patterns**: Users understand how to access each service

## Monitoring and Maintenance

### Regular Health Checks

```bash
# Weekly authentication health check
./test-authentication-flows.sh

# Monthly certificate validation
kubectl get certificates -A

# Quarterly access review
# Review Authentik user groups and permissions
# Validate service access patterns
# Update documentation as needed
```

### Troubleshooting Common Issues

1. **Grafana OIDC Login Loop**:
   - Check client secret in 1Password
   - Verify redirect URI configuration
   - Check Authentik application settings

2. **Dashboard Authentication Failures**:
   - Verify ingress annotations
   - Check nginx-ingress controller logs
   - Validate Authentik outpost connectivity

3. **Proxy Service Issues**:
   - Check external outpost status in Authentik
   - Verify proxy provider configurations
   - Monitor authentik-proxy pod logs

## Conclusion

The hybrid authentication strategy implementation successfully:

- ✅ **Reduced operational complexity** by eliminating Kong proxy issues
- ✅ **Improved security posture** by removing Prometheus external access
- ✅ **Enhanced user experience** with native OIDC and seamless SSO
- ✅ **Simplified maintenance** with static configuration management
- ✅ **Maintained backward compatibility** with clear rollback procedures

The cluster now operates with a more maintainable, secure, and user-friendly authentication architecture while preserving the ability to rollback if needed.
