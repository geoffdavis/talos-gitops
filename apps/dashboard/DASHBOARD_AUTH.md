# Kubernetes Dashboard Authentication

## Current Status

The Kubernetes Dashboard (v7.x) requires explicit token authentication by design. This is a security feature built into the Dashboard application itself and cannot be bypassed at the ingress or proxy level.

### Why Kong Header Injection Doesn't Work

Even though we've configured Kong to inject the Authorization header with a valid service account token, the Dashboard still prompts for authentication because:

1. **Client-Side Validation**: The Dashboard web UI checks for authentication state in the browser
2. **Session Management**: The Dashboard expects tokens to be submitted through its `/api/v1/login` endpoint to establish a session
3. **Security by Design**: The Dashboard intentionally requires explicit user authentication to prevent unauthorized access

## Available Solutions

### 1. Quick Access Script (Recommended)

Use the provided helper script that retrieves and displays the token:

```bash
./scripts/dashboard-login.sh
```

This script:

- Retrieves the kubernetes-dashboard-viewer token
- Copies it to your clipboard (on macOS)
- Displays it for manual copy if needed
- Optionally opens the Dashboard in your browser

### 2. Bookmarklet for Auto-Fill

Open `/apps/dashboard/dashboard-auto-login-bookmarklet.html` in your browser to set up a bookmarklet that automatically fills the token field.

### 3. Browser Extension

Install a userscript manager (like Tampermonkey) and use the provided script to automatically fill and submit the token.

### 4. Direct Token Retrieval

Manually get the token when needed:

```bash
kubectl get secret -n kubernetes-dashboard kubernetes-dashboard-viewer-token \
  -o jsonpath='{.data.token}' | base64 -d
```

## Why Not OAuth2 Proxy?

While OAuth2 Proxy can handle authentication with Authentik, it doesn't solve the Dashboard's token requirement because:

- The Dashboard still requires a Kubernetes API token for authorization
- OAuth2 Proxy can authenticate users but can't generate valid Kubernetes tokens
- The Dashboard doesn't support OIDC authentication directly in the open-source version

## Security Considerations

The current setup uses a long-lived service account token (1 year validity) with cluster-wide read/write permissions. This is acceptable for a home lab but consider:

1. **Token Rotation**: Periodically rotate the service account token
2. **RBAC Restrictions**: Consider using more restrictive RBAC rules if needed
3. **Network Security**: Dashboard is only accessible on the internal network

## Alternative Dashboards

If the token requirement is too cumbersome, consider these alternatives that support OIDC/proxy authentication:

1. **Headlamp**: Modern Kubernetes dashboard with OIDC support
2. **Lens**: Desktop application with built-in authentication
3. **K9s**: Terminal-based UI (no web interface needed)
4. **Octant**: VMware's developer-centric dashboard

## Technical Details

### Current Architecture

```text
User -> nginx-internal -> Kong Proxy -> Dashboard Services
                           |
                           +-> Injects Authorization header (doesn't work for UI)
```

### Dashboard Components

- **kubernetes-dashboard-web**: Frontend UI (requires token input)
- **kubernetes-dashboard-api**: Backend API (validates tokens)
- **kubernetes-dashboard-auth**: Authentication service (manages sessions)
- **kubernetes-dashboard-kong**: Proxy layer (handles routing and headers)

### Service Account

- Name: `kubernetes-dashboard-viewer`
- Permissions: Cluster-wide read/write access
- Token Validity: 1 year from creation
