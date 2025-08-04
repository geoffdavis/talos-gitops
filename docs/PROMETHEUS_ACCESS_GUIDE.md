# Prometheus Access Guide

This guide documents how to access Prometheus after removing it from external authentication to reduce the attack surface.

## Overview

**Security Change**: Prometheus has been removed from external authentication and is now only accessible via kubectl port-forward for security reasons.

**Rationale**:

- Reduces attack surface by removing external access
- Prometheus contains sensitive cluster metrics and configuration
- Administrative access should be restricted to cluster operators
- Grafana provides user-friendly dashboards for general monitoring needs

## Access Methods

### Method 1: kubectl port-forward (Recommended)

```bash
# Forward Prometheus to local port 9090
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Access Prometheus in browser
open http://localhost:9090
```

### Method 2: kubectl port-forward with custom port

```bash
# Forward to a different local port if 9090 is in use
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 8090:9090

# Access Prometheus in browser
open http://localhost:8090
```

### Method 3: Background port-forward

```bash
# Run port-forward in background
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &

# Access Prometheus
open http://localhost:9090

# Stop background port-forward when done
kill %1  # or find the process ID and kill it
```

## Service Information

- **Service Name**: `kube-prometheus-stack-prometheus`
- **Namespace**: `monitoring`
- **Internal Port**: `9090`
- **Service Type**: `ClusterIP` (internal only)

## Common Use Cases

### 1. Query Metrics Directly

Access the Prometheus query interface to:

- Write and test PromQL queries
- Explore available metrics
- Debug monitoring issues
- Validate metric collection

### 2. Configuration Management

Access Prometheus configuration:

- View active configuration
- Check service discovery
- Validate scrape targets
- Review alerting rules

### 3. Troubleshooting

Use Prometheus for troubleshooting:

- Check target health
- Validate metric ingestion
- Debug query performance
- Analyze time series data

## Security Considerations

### Why External Access Was Removed

1. **Sensitive Data**: Prometheus contains detailed cluster metrics including resource usage, pod information, and system performance data
2. **Configuration Exposure**: Prometheus configuration reveals internal cluster architecture and service discovery
3. **Attack Surface**: External access increases potential attack vectors
4. **Administrative Tool**: Prometheus is primarily an administrative tool, not end-user facing

### Access Control

- **Cluster Admin Required**: kubectl access requires cluster admin permissions
- **Network Isolation**: No external network exposure
- **Audit Trail**: kubectl commands are logged for security auditing
- **Session Control**: Port-forward sessions are temporary and user-controlled

## Alternative Access for Users

### Grafana Dashboards (Recommended for Users)

For general monitoring needs, users should use Grafana:

- **URL**: `https://grafana.k8s.home.geoffdavis.com`
- **Authentication**: Native OIDC with Authentik
- **User-Friendly**: Pre-built dashboards and visualizations
- **Role-Based**: Proper user role management

### AlertManager (Still Externally Accessible)

For alert management:

- **URL**: `https://alertmanager.k8s.home.geoffdavis.com`
- **Authentication**: Via Authentik proxy
- **Purpose**: Alert configuration and silencing

## Troubleshooting

### Port-forward Issues

1. **Port Already in Use**:

   ```bash
   # Check what's using the port
   lsof -i :9090

   # Use a different local port
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 8090:9090
   ```

2. **Connection Refused**:

   ```bash
   # Check if Prometheus service is running
   kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus

   # Check service endpoints
   kubectl get endpoints -n monitoring kube-prometheus-stack-prometheus
   ```

3. **Permission Denied**:

   ```bash
   # Verify kubectl access
   kubectl auth can-i get pods -n monitoring

   # Check cluster connection
   kubectl cluster-info
   ```

### Service Discovery

```bash
# Check Prometheus service
kubectl get svc -n monitoring kube-prometheus-stack-prometheus

# Verify service type is ClusterIP
kubectl describe svc -n monitoring kube-prometheus-stack-prometheus
```

## Automation Scripts

### Quick Access Script

Create a script for easy access:

```bash
#!/bin/bash
# prometheus-access.sh

echo "Starting Prometheus port-forward..."
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
PF_PID=$!

echo "Prometheus accessible at http://localhost:9090"
echo "Press Ctrl+C to stop port-forward"

# Wait for interrupt
trap "kill $PF_PID; exit" INT
wait $PF_PID
```

### Task Integration

Add to Taskfile.yml:

```yaml
prometheus:access:
  desc: Access Prometheus via port-forward
  cmd: kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

## Rollback Procedures

If external access needs to be restored:

### Option 1: Restore LoadBalancer Service

```bash
# Edit the HelmRelease to restore LoadBalancer
kubectl patch helmrelease -n monitoring kube-prometheus-stack --type='merge' -p='{"spec":{"values":{"prometheus":{"service":{"type":"LoadBalancer","annotations":{"io.cilium/lb-ipam-pool":"bgp-default"},"labels":{"io.cilium/lb-ipam-pool":"bgp-default"}}}}}}'
```

### Option 2: Add Back to Proxy Configuration

1. Add Prometheus back to `infrastructure/authentik-proxy/configmap.yaml`
2. Add Prometheus back to `infrastructure/authentik-proxy/service-discovery-job.yaml`
3. Apply changes: `kubectl apply -k infrastructure/authentik-proxy/`

## Best Practices

1. **Use Grafana for General Access**: Direct users to Grafana dashboards instead of raw Prometheus
2. **Temporary Sessions**: Only use port-forward when needed, don't leave running permanently
3. **Secure Workstation**: Ensure your local machine is secure when port-forwarding
4. **Document Usage**: Log when and why you access Prometheus directly for audit purposes
5. **Regular Review**: Periodically review if external access is truly needed

This approach significantly reduces the attack surface while maintaining necessary administrative access to Prometheus for cluster operators.
