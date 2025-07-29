# Longhorn Dashboard Access Guide

## Current Status ✅

The Longhorn dashboard is **fully functional** and accessible through multiple methods now that Cilium CNI is properly deployed.

## Verification Results

### ✅ Ingress Controller Status

- nginx-ingress controller: **Running** (2/2 pods ready)
- Service type: LoadBalancer (pending external IP, as expected without BGP)
- NodePort access: HTTP:30334, HTTPS:31752

### ✅ Longhorn Components Status

- Longhorn UI: **Running** (2/2 pods ready)
- Longhorn Manager: **Running** (2/3 pods ready, sufficient for operation)
- Longhorn Frontend Service: **Available**
- Authentication: **Configured** (basic auth with 1Password integration)

### ✅ Ingress Configuration

- Ingress resource: **Applied** and **functional**
- Hostname: `longhorn.k8s.home.geoffdavis.com`
- TLS: **Configured** with cert-manager
- Authentication: **Required** (HTTP 401 response confirms auth is working)
- HTTP to HTTPS redirect: **Working** (HTTP 308 redirect)

## Access Methods

### Method 1: Port-Forward (Recommended for Testing)

```bash
# Start port-forward for ingress controller
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8443:443 --address=0.0.0.0

# Access via browser with hostname header
# Add to /etc/hosts: 127.0.0.1 longhorn.k8s.home.geoffdavis.com
# Then visit: https://longhorn.k8s.home.geoffdavis.com:8443
```

### Method 2: NodePort Access (For Home Network)

```bash
# Access via any cluster node IP + NodePort
# HTTPS: https://<node-ip>:31752
# HTTP: http://<node-ip>:30334 (redirects to HTTPS)

# Example with current node IPs:
# https://10.0.0.18:31752 (with Host header: longhorn.k8s.home.geoffdavis.com)
# https://10.0.1.157:31752 (with Host header: longhorn.k8s.home.geoffdavis.com)
```

### Method 3: Direct Service Access (Bypass Ingress)

```bash
# Port-forward directly to Longhorn service (no auth required)
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8081:80 --address=0.0.0.0

# Access: http://localhost:8081
# Note: This bypasses authentication and TLS
```

## DNS Configuration for Home Network

To access via the intended hostname `longhorn.k8s.home.geoffdavis.com`:

1. **Option A: Router DNS Override**
   - Configure router to resolve `longhorn.k8s.home.geoffdavis.com` to `172.29.51.200`
   - Access via: `https://longhorn.k8s.home.geoffdavis.com:31752`

2. **Option B: Local /etc/hosts**

   ```bash
   # Add to /etc/hosts on client machine:
   172.29.51.200 longhorn.k8s.home.geoffdavis.com

   # Then access via: https://longhorn.k8s.home.geoffdavis.com:31752
   ```

3. **Option C: External-DNS (Future)**
   - Deploy external-dns to automatically manage DNS records
   - Would enable access via standard HTTPS port (443)

## Authentication

- **Username**: `admin`
- **Password**: Stored in 1Password vault "Longhorn UI Credentials - home-ops"
- **Method**: HTTP Basic Authentication
- **Secret**: `longhorn-auth` in `longhorn-system` namespace

## Troubleshooting

### If Dashboard Shows 502 Errors

```bash
# Check Longhorn manager pods
kubectl get pods -n longhorn-system -l app=longhorn-manager

# Restart failing manager pods
kubectl delete pods -n longhorn-system -l app=longhorn-manager

# Wait for pods to restart and stabilize
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s
```

### If Ingress Not Working

```bash
# Check ingress controller
kubectl get pods -n ingress-nginx

# Check ingress resource
kubectl get ingress -n longhorn-system

# Test ingress connectivity
curl -k -I -H "Host: longhorn.k8s.home.geoffdavis.com" https://<node-ip>:31752
```

## Network Requirements

- **Cluster Networking**: ✅ Cilium CNI (43/46 pods managed)
- **BGP**: ❌ Disabled (LoadBalancer services remain pending)
- **NodePort Access**: ✅ Available on all ready nodes
- **Internal DNS**: ✅ Functional for service discovery
- **External DNS**: ❌ Not deployed (manual DNS configuration required)

## Next Steps

1. **For Production Use**: Deploy external-dns for automatic DNS management
2. **For BGP**: Re-enable BGP configuration if LoadBalancer external IPs are needed
3. **For Security**: Consider network policies to restrict dashboard access
4. **For Monitoring**: Set up alerts for Longhorn component health

## Verification Commands

```bash
# Quick status check
./test-longhorn-access.sh

# Detailed component check
kubectl get all -n longhorn-system
kubectl get all -n ingress-nginx

# Test ingress functionality
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8443:443 &
curl -k -I -H "Host: longhorn.k8s.home.geoffdavis.com" https://localhost:8443
```
