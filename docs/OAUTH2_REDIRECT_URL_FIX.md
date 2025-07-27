# OAuth2 Redirect URL Fix for External Authentik-Proxy

## Overview

This document describes the OAuth2 redirect URL fix implemented to resolve authentication issues in the external authentik-proxy system where redirect URLs were pointing to internal cluster hostnames instead of external URLs.

## Problem Description

### Root Cause

The debug task revealed that while the authentication flow was working (proper 302 redirects), the redirect URLs were still pointing to the internal cluster hostname `authentik-server.authentik.svc.cluster.local` instead of the external URL `https://authentik.k8s.home.geoffdavis.com`.

### Impact

- Users would be redirected to internal cluster DNS names during OAuth2 authentication
- Authentication flow would fail because browsers cannot resolve internal cluster DNS
- Services at `*.k8s.home.geoffdavis.com` would be inaccessible due to broken authentication redirects

## Solution Architecture

### Components Created

1. **OAuth2 Redirect Fix Job** (`infrastructure/authentik-proxy/fix-oauth2-redirect-urls-job.yaml`)

   - Kubernetes Job that runs after the main proxy configuration
   - Uses ArgoCD PostSync hook with weight 25 (runs after main config job)
   - Fixes OAuth2 application configurations and provider settings

2. **Python Fix Script** (embedded in the Job YAML)

   - Comprehensive OAuth2RedirectFixer class
   - Handles proxy providers, OAuth2 providers, and applications
   - Updates redirect URIs to use external hostnames

3. **Test Suite** (`tests/authentik-proxy-config/test_oauth2_redirect_fix.py`)

   - Comprehensive pytest-based test coverage
   - Validates YAML structure, Python syntax, and functionality
   - Integration tests for the complete fix process

4. **Test Runner** (`scripts/test-oauth2-redirect-fix.sh`)
   - Standalone test script for validation
   - YAML syntax checking, Python script validation, pytest execution

## Technical Implementation

### OAuth2RedirectFixer Class

The main fix logic is implemented in the `OAuth2RedirectFixer` class with the following key methods:

#### Core Methods

- `fix_proxy_provider_external_host()`: Updates proxy provider external host URLs
- `fix_oauth2_provider_redirect_uris()`: Updates OAuth2 provider redirect URIs
- `fix_application_launch_url()`: Updates application launch URLs
- `fix_all_oauth2_redirects()`: Orchestrates the complete fix process

#### Service Configuration

The script handles 6 services:

- **longhorn**: `longhorn.k8s.home.geoffdavis.com`
- **grafana**: `grafana.k8s.home.geoffdavis.com`
- **prometheus**: `prometheus.k8s.home.geoffdavis.com`
- **alertmanager**: `alertmanager.k8s.home.geoffdavis.com`
- **dashboard**: `dashboard.k8s.home.geoffdavis.com`
- **hubble**: `hubble.k8s.home.geoffdavis.com`

#### OAuth2 Redirect URIs

For each service, the following redirect URIs are configured:

```
https://<service>.k8s.home.geoffdavis.com/akprox/callback
https://<service>.k8s.home.geoffdavis.com/outpost.goauthentik.io/callback
https://<service>.k8s.home.geoffdavis.com/auth/callback
https://<service>.k8s.home.geoffdavis.com/oauth/callback
```

### Fix Process Flow

1. **Authentication Test**: Verify API connectivity to Authentik
2. **Data Collection**: Fetch existing applications and providers
3. **Proxy Provider Fix**: Update external host URLs for proxy providers
4. **OAuth2 Provider Fix**: Update redirect URIs for OAuth2 providers
5. **Application Fix**: Update launch URLs for applications
6. **Validation**: Verify all changes were applied successfully

## Deployment

### Prerequisites

- External authentik-proxy system must be deployed and operational
- Authentik server must be accessible at `http://authentik-server.authentik.svc.cluster.local:80`
- Valid API token must be available in the `authentik-proxy-token` secret

### Deployment Process

The fix is deployed automatically via GitOps:

1. **Kustomization**: Job is included in `infrastructure/authentik-proxy/kustomization.yaml`
2. **ArgoCD Hook**: Runs automatically after main proxy configuration (PostSync, weight 25)
3. **Execution**: Job runs once and fixes all OAuth2 redirect URLs
4. **Cleanup**: Job completes and can be cleaned up by ArgoCD

### Manual Deployment

If manual deployment is needed:

```bash
kubectl apply -f infrastructure/authentik-proxy/fix-oauth2-redirect-urls-job.yaml
```

## Testing

### Automated Testing

Run the comprehensive test suite:

```bash
# Run all tests
cd tests/authentik-proxy-config
./run_tests.sh

# Run OAuth2 redirect fix tests specifically
python3 -m pytest test_oauth2_redirect_fix.py -v

# Run standalone test script
cd scripts
./test-oauth2-redirect-fix.sh
```

### Test Coverage

- **Syntax Validation**: YAML and Python script syntax checking
- **Unit Tests**: Individual method testing with mocked API calls
- **Integration Tests**: Complete fix process simulation
- **Security Tests**: Kubernetes Job security context validation
- **Configuration Tests**: Environment variable and resource limit validation

### Manual Verification

After deployment, verify the fix:

1. **Check Job Status**:

   ```bash
   kubectl get jobs -n authentik-proxy -l app.kubernetes.io/component=oauth2-redirect-fix
   ```

2. **Check Job Logs**:

   ```bash
   kubectl logs -n authentik-proxy -l app.kubernetes.io/component=oauth2-redirect-fix
   ```

3. **Test Authentication Flow**:
   - Navigate to any service: `https://longhorn.k8s.home.geoffdavis.com`
   - Verify redirect goes to `https://authentik.k8s.home.geoffdavis.com` (not internal cluster DNS)
   - Complete authentication and verify successful service access

## Configuration

### Environment Variables

The fix job uses the following environment variables:

- `AUTHENTIK_HOST`: Authentik server URL (from secret)
- `AUTHENTIK_TOKEN`: API token (from secret)
- `EXTERNAL_DOMAIN`: External domain (`k8s.home.geoffdavis.com`)
- `AUTHENTIK_EXTERNAL_URL`: External Authentik URL (`https://authentik.k8s.home.geoffdavis.com`)

### Security Context

The job runs with strict security settings:

- Non-root user (UID 65534)
- No privilege escalation
- All capabilities dropped
- Runtime default seccomp profile

## Troubleshooting

### Common Issues

1. **Job Fails with Authentication Error**:

   - Verify `authentik-proxy-token` secret exists and contains valid token
   - Check Authentik server accessibility from cluster

2. **Job Fails with API Errors**:

   - Check Authentik server logs for API request issues
   - Verify token has sufficient permissions for provider/application management

3. **Redirect URLs Not Updated**:

   - Check job logs for specific service failures
   - Verify service names match between script and Authentik configuration

4. **Authentication Still Redirects to Internal URLs**:
   - Verify job completed successfully
   - Check if there are cached redirect URLs in browser
   - Verify outpost configuration is using external URLs

### Debug Commands

```bash
# Check job status
kubectl describe job -n authentik-proxy fix-oauth2-redirect-urls

# View job logs
kubectl logs -n authentik-proxy -l job-name=fix-oauth2-redirect-urls

# Check secret availability
kubectl get secret -n authentik-proxy authentik-proxy-token

# Test API connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -H "Authorization: Bearer <token>" \
  http://authentik-server.authentik.svc.cluster.local:80/api/v3/core/users/me/
```

## Monitoring

### Success Indicators

- Job completes with exit code 0
- All 6 services show "Successfully processed" in logs
- Authentication redirects use external URLs
- All services accessible via browser with proper SSO flow

### Failure Indicators

- Job fails or times out
- API authentication failures in logs
- Services still redirect to internal cluster DNS
- Authentication loops or 500 errors

## Integration with External Authentik-Proxy System

This fix is part of the comprehensive external authentik-proxy system and works in conjunction with:

- **Main Proxy Configuration Job**: Creates providers and applications
- **External Outpost Configuration**: Sets up external outpost with correct URLs
- **Ingress Configuration**: Routes traffic to external outpost
- **BGP Load Balancer**: Provides external IP for ingress

The OAuth2 redirect fix ensures the final piece of the authentication flow works correctly by updating all redirect URLs to use external hostnames instead of internal cluster DNS.

## Future Enhancements

1. **Automatic Detection**: Detect and fix redirect URL issues automatically
2. **Validation**: Add post-fix validation to ensure redirects work correctly
3. **Monitoring**: Add metrics and alerts for redirect URL health
4. **Configuration**: Make external domain configurable via ConfigMap
5. **Rollback**: Add ability to rollback redirect URL changes if needed

## Conclusion

The OAuth2 redirect URL fix resolves the final authentication issue in the external authentik-proxy system by ensuring all OAuth2 applications and providers use external hostnames for redirect URLs. This enables users to successfully authenticate and access services at `*.k8s.home.geoffdavis.com` with proper SSO functionality.
