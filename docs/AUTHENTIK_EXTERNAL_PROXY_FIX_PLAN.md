# Authentik External Proxy Fix Plan

## Current Issues Analysis

Based on the configuration analysis and user feedback, the external authentik-proxy system has two main issues:

1. **Services redirecting to cluster internal addresses** - External URL caching issue
2. **Grafana returning 404** - Service name configuration issue

## Root Cause Analysis

### Issue 1: Internal DNS Redirects
- **Symptom**: Services like Longhorn and Dashboard redirect to internal cluster DNS instead of external URLs
- **Root Cause**: Authentik proxy providers are configured with internal cluster DNS for external_host instead of proper external URLs
- **Evidence**: External outpost is connected but proxy providers have cached internal configurations

### Issue 2: Grafana 404 Error
- **Symptom**: Grafana service returns 404 instead of authentication redirect
- **Root Cause**: Proxy provider configuration may have incorrect service name or URL
- **Evidence**: ConfigMap shows correct service name but proxy provider may be misconfigured

## Configuration Analysis

### Current Correct Configurations
- ✅ **ConfigMap Service Names**: [`infrastructure/authentik-proxy/configmap.yaml:20`](../infrastructure/authentik-proxy/configmap.yaml:20) shows correct `kube-prometheus-stack-grafana.monitoring.svc.cluster.local:80`
- ✅ **External Outpost ID**: [`infrastructure/authentik-proxy/outpost-id-configmap.yaml:13`](../infrastructure/authentik-proxy/outpost-id-configmap.yaml:13) shows `3f0970c5-d6a3-43b2-9a36-d74665c6b24e`
- ✅ **Deployment External URL**: [`infrastructure/authentik-proxy/deployment.yaml:76`](../infrastructure/authentik-proxy/deployment.yaml:76) shows `AUTHENTIK_HOST_BROWSER: "https://authentik.k8s.home.geoffdavis.com"`

### Service Configuration Matrix
| Service | External Host | Internal Host | Port | Status |
|---------|---------------|---------------|------|--------|
| longhorn | longhorn.k8s.home.geoffdavis.com | longhorn-frontend.longhorn-system | 80 | ❌ Redirecting to internal |
| grafana | grafana.k8s.home.geoffdavis.com | kube-prometheus-stack-grafana.monitoring | 80 | ❌ 404 Error |
| prometheus | prometheus.k8s.home.geoffdavis.com | kube-prometheus-stack-prometheus.monitoring | 9090 | ❌ Redirecting to internal |
| alertmanager | alertmanager.k8s.home.geoffdavis.com | kube-prometheus-stack-alertmanager.monitoring | 9093 | ❌ Redirecting to internal |
| dashboard | dashboard.k8s.home.geoffdavis.com | kubernetes-dashboard-kong-proxy.kubernetes-dashboard | 443 | ❌ Redirecting to internal |
| hubble | hubble.k8s.home.geoffdavis.com | hubble-ui.kube-system | 80 | ❌ Redirecting to internal |

## Fix Strategy

### Phase 1: Update Proxy Provider Configurations
**Objective**: Fix proxy providers in Authentik to use correct external URLs and service configurations

**Actions Required**:
1. Create Python script to update all 6 proxy providers with correct external_host URLs
2. Ensure all proxy providers use `https://SERVICE.k8s.home.geoffdavis.com` for external_host
3. Verify internal_host configurations match the ConfigMap service names
4. Update Grafana proxy provider specifically to ensure correct service name

### Phase 2: Clear External Outpost Cache
**Objective**: Update external outpost configuration to clear cached internal DNS configurations

**Actions Required**:
1. Update external outpost configuration with correct `authentik_host_browser` setting
2. Force outpost configuration refresh to clear cached internal URLs
3. Verify outpost connectivity after configuration update

### Phase 3: Validate Service Integration
**Objective**: Test all services work correctly with external authentication

**Actions Required**:
1. Test each service URL for proper authentication redirect
2. Verify authentication flow completes successfully
3. Confirm services are accessible after authentication
4. Validate DNS records are properly created

## Implementation Plan

### Step 1: Create Fix Script
Create `scripts/authentik-proxy-config/fix-external-urls.py` with the following functionality:

```python
# Key functions needed:
# 1. get_proxy_providers() - Get all current proxy providers
# 2. update_proxy_provider_external_urls() - Fix external_host for each provider
# 3. update_grafana_service_config() - Specifically fix Grafana service name
# 4. update_outpost_configuration() - Clear cached configurations
# 5. validate_service_connectivity() - Test each service
```

### Step 2: Create Kubernetes Job
Create `infrastructure/authentik-proxy/fix-external-urls-job.yaml` to run the fix script:

```yaml
# Job configuration to:
# 1. Wait for Authentik server availability
# 2. Run Python fix script with proper environment variables
# 3. Update ConfigMap with any necessary changes
# 4. Restart authentik-proxy deployment if needed
```

### Step 3: Update Service Configurations
Verify and update service configurations in ConfigMap if needed:

```yaml
# Ensure all service configurations are correct:
# - Grafana: kube-prometheus-stack-grafana.monitoring:80
# - Prometheus: kube-prometheus-stack-prometheus.monitoring:9090
# - AlertManager: kube-prometheus-stack-alertmanager.monitoring:9093
# - Dashboard: kubernetes-dashboard-kong-proxy.kubernetes-dashboard:443
# - Longhorn: longhorn-frontend.longhorn-system:80
# - Hubble: hubble-ui.kube-system:80
```

## Expected Outcomes

### After Fix Implementation
1. **✅ External URL Redirects**: All services redirect to `https://authentik.k8s.home.geoffdavis.com` for authentication
2. **✅ Grafana Accessibility**: Grafana service responds with authentication redirect instead of 404
3. **✅ Service Functionality**: All 6 services accessible after authentication
4. **✅ DNS Resolution**: All DNS records properly created and resolving
5. **✅ Authentication Flow**: Complete SSO flow working for all services

### Success Criteria
- [ ] `curl -I https://longhorn.k8s.home.geoffdavis.com` returns 302 redirect to Authentik
- [ ] `curl -I https://grafana.k8s.home.geoffdavis.com` returns 302 redirect to Authentik (not 404)
- [ ] `curl -I https://prometheus.k8s.home.geoffdavis.com` returns 302 redirect to Authentik
- [ ] `curl -I https://alertmanager.k8s.home.geoffdavis.com` returns 302 redirect to Authentik
- [ ] `curl -I https://dashboard.k8s.home.geoffdavis.com` returns 302 redirect to Authentik
- [ ] `curl -I https://hubble.k8s.home.geoffdavis.com` returns 302 redirect to Authentik
- [ ] All services accessible via browser after authentication
- [ ] External outpost shows connected status in Authentik admin interface

## Troubleshooting Guide

### If Services Still Redirect to Internal DNS
1. Check proxy provider `external_host` configuration in Authentik admin interface
2. Verify outpost configuration has correct `authentik_host_browser` setting
3. Restart authentik-proxy deployment to clear any cached configurations
4. Check ingress controller logs for routing issues

### If Grafana Still Returns 404
1. Verify Grafana service name in proxy provider configuration
2. Check if Grafana service is running: `kubectl get svc -n monitoring`
3. Test internal connectivity: `kubectl exec -n authentik-proxy <pod> -- curl http://kube-prometheus-stack-grafana.monitoring:80`
4. Verify proxy provider internal_host configuration

### If Authentication Flow Fails
1. Check Authentik server logs for authentication errors
2. Verify external outpost connectivity in Authentik admin interface
3. Test DNS resolution for authentik.k8s.home.geoffdavis.com
4. Check certificate validity for TLS connections

## Implementation Commands

### To Execute This Fix Plan
1. **Switch to Code Mode**: Use `switch_mode code` to implement the fix scripts
2. **Create Fix Script**: Implement `scripts/authentik-proxy-config/fix-external-urls.py`
3. **Create Kubernetes Job**: Implement `infrastructure/authentik-proxy/fix-external-urls-job.yaml`
4. **Deploy Fix**: Apply the job to execute the fixes
5. **Validate Results**: Test all services for proper authentication flow

### Monitoring Commands
```bash
# Check authentik-proxy pod status
kubectl get pods -n authentik-proxy

# Check authentik-proxy logs
kubectl logs -n authentik-proxy -l app.kubernetes.io/name=authentik-proxy --tail=50

# Test service responses
curl -I https://grafana.k8s.home.geoffdavis.com
curl -I https://longhorn.k8s.home.geoffdavis.com

# Check external outpost status in Authentik admin interface
# Navigate to: https://authentik.k8s.home.geoffdavis.com/if/admin/#/outpost/outposts
```

## Next Steps

1. **Immediate Action**: Switch to Code mode to implement the fix scripts
2. **Priority Focus**: Fix Grafana 404 error first as it's a clear service configuration issue
3. **Secondary Focus**: Update proxy provider external URLs to fix redirect issues
4. **Validation**: Test each service individually after fixes are applied
5. **Documentation**: Update operational procedures based on successful fixes

This comprehensive fix plan addresses both the Grafana service name issue and the external URL caching problem that are preventing the external authentik-proxy system from working correctly.