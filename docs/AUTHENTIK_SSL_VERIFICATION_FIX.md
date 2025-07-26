# Authentik SSL Verification Fix Guide

## Problem Description

The authentik "Local Kubernetes Cluster" integration is unhealthy due to SSL certificate verification failures when communicating with the Kubernetes API server. This prevents the outpost from receiving provider configuration via websocket, resulting in 404 errors on all protected services.

## Root Cause

Authentik uses its own self-signed CA and cannot verify the Kubernetes API server's SSL certificates, causing the outpost controller to fail when trying to sync configuration.

## Manual Fix via Web Interface

### Step 1: Access Authentik Admin Interface

1. Navigate to: `https://authentik.k8s.home.geoffdavis.com/if/admin/`
2. Login with admin credentials

### Step 2: Navigate to Outpost Integrations

1. Go to: **System** → **Outposts** → **Integrations**
2. Or directly: `https://authentik.k8s.home.geoffdavis.com/if/admin/#/outpost/integrations`

### Step 3: Edit Kubernetes Service Connection

1. Find the "Local Kubernetes Cluster" integration
2. Click the **Edit** button (pencil icon)
3. **Uncheck** the "Verify Kubernetes API SSL Certificate" option
4. Click **Update** to save changes

### Step 4: Verify Fix

1. The integration status should change from "Unhealthy" to "Healthy"
2. Wait 30-60 seconds for the outpost to receive new configuration
3. Test authentication by accessing: `https://dashboard.k8s.home.geoffdavis.com/`

## Automated Fix via Job

Alternatively, deploy the automated fix job:

```bash
kubectl apply -f infrastructure/authentik-outpost-config/fix-kubernetes-ssl-verification.yaml
```

**Note**: This job may fail if the service connections API endpoint returns HTML instead of JSON. In that case, use the manual fix above.

## Expected Results After Fix

1. **Outpost Logs**: Should show provider configuration being received
2. **Authentication Flow**: Accessing protected services should redirect to authentik login
3. **Service Access**: After authentication, services should be accessible
4. **Integration Status**: "Local Kubernetes Cluster" should show as "Healthy"

## Troubleshooting

If the fix doesn't work immediately:

1. **Restart Outpost Pod**:

   ```bash
   kubectl delete pod -n authentik -l goauthentik.io/outpost-name=proxy-outpost
   ```

2. **Check Outpost Logs**:

   ```bash
   kubectl logs -n authentik -l goauthentik.io/outpost-name=proxy-outpost --tail=20
   ```

3. **Verify Provider Configuration**:
   ```bash
   TOKEN=$(kubectl get secret -n authentik authentik-admin-token -o jsonpath='{.data.token}' | base64 -d)
   curl -k -H "Authorization: Bearer $TOKEN" https://authentik.k8s.home.geoffdavis.com/api/v3/outposts/instances/
   ```

## Current System Status

- ✅ Authentik Server: Running and accessible
- ✅ Outpost Pod: Running with websocket connection
- ✅ Provider Configuration: All providers configured in authentik
- ✅ SSL Certificates: Generated and properly configured
- ✅ Ingress Routing: All protected services routed to outpost
- ❌ SSL Verification: Needs manual fix via web interface

## Protected Services

Once fixed, these services will be protected by authentik authentication:

- Kubernetes Dashboard: `https://dashboard.k8s.home.geoffdavis.com/`
- Hubble UI: `https://hubble.k8s.home.geoffdavis.com/`
- Grafana: `https://grafana.k8s.home.geoffdavis.com/`
- Prometheus: `https://prometheus.k8s.home.geoffdavis.com/`
- Alertmanager: `https://alertmanager.k8s.home.geoffdavis.com/`
- Longhorn: `https://longhorn.k8s.home.geoffdavis.com/`
