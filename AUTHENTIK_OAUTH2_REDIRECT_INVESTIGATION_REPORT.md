# Authentik OAuth2 Redirect Investigation Report

## Executive Summary

The OAuth2 redirect fix job ran successfully but reported that 7 providers were detected but not recognized as "proxy providers" and expected applications were not found. After comprehensive investigation of the actual Authentik API structure, I discovered that:

1. **The OAuth2 redirect URLs are already correct** - they point to external domains, not internal cluster DNS
2. **The real issue is in the outpost configuration** - the external outpost has the wrong internal URL
3. **The OAuth2 redirect fix script had incorrect assumptions** about the Authentik API structure

## Investigation Methodology

### 1. Examined Current Configuration Files

- Reviewed [`infrastructure/authentik-proxy/fix-oauth2-redirect-urls-job.yaml`](infrastructure/authentik-proxy/fix-oauth2-redirect-urls-job.yaml)
- Analyzed the embedded Python script and its assumptions
- Reviewed test files to understand expected behavior

### 2. Created Diagnostic Script

- Deployed [`debug-authentik-api-structure-job.yaml`](debug-authentik-api-structure-job.yaml) to investigate actual API structure
- Comprehensive analysis of applications, providers, and outposts

## Key Findings

### Actual Authentik Configuration Structure

#### Applications (8 found)

```
- Name: 'Longhorn Storage', Slug: 'longhorn', Provider: 2, Launch URL: 'https://longhorn.k8s.home.geoffdavis.com'
- Name: 'Grafana', Slug: 'grafana', Provider: 5, Launch URL: 'https://grafana.k8s.home.geoffdavis.com'
- Name: 'Prometheus', Slug: 'prometheus', Provider: 6, Launch URL: 'https://prometheus.k8s.home.geoffdavis.com'
- Name: 'AlertManager', Slug: 'alertmanager', Provider: 7, Launch URL: 'https://alertmanager.k8s.home.geoffdavis.com'
- Name: 'Kubernetes Dashboard', Slug: 'dashboard', Provider: 3, Launch URL: 'https://dashboard.k8s.home.geoffdavis.com'
- Name: 'Hubble UI', Slug: 'hubble', Provider: 4, Launch URL: 'https://hubble.k8s.home.geoffdavis.com'
```

#### Proxy Providers (7 found)

```
- Name: 'longhorn-proxy', PK: 2, Mode: 'proxy', External Host: 'https://longhorn.k8s.home.geoffdavis.com'
- Name: 'grafana-proxy', PK: 5, Mode: 'proxy', External Host: 'https://grafana.k8s.home.geoffdavis.com'
- Name: 'prometheus-proxy', PK: 6, Mode: 'proxy', External Host: 'https://prometheus.k8s.home.geoffdavis.com'
- Name: 'alertmanager-proxy', PK: 7, Mode: 'proxy', External Host: 'https://alertmanager.k8s.home.geoffdavis.com'
- Name: 'dashboard-proxy', PK: 3, Mode: 'proxy', External Host: 'https://dashboard.k8s.home.geoffdavis.com'
- Name: 'hubble-proxy', PK: 4, Mode: 'proxy', External Host: 'https://hubble.k8s.home.geoffdavis.com'
```

#### OAuth2 Providers (7 found)

```
- Name: 'longhorn-proxy', PK: 2, Redirect URIs: 'https://longhorn.k8s.home.geoffdavis.com/outpost.goauthentik.io/callback?X-authentik-auth-callback=true'
- Name: 'grafana-proxy', PK: 5, Redirect URIs: 'https://grafana.k8s.home.geoffdavis.com/outpost.goauthentik.io/callback?X-authentik-auth-callback=true'
- [Similar pattern for all services]
```

#### Outposts (3 found)

```
- Name: 'authentik Embedded Outpost', PK: '26d1a2cc-cdc3-42b1-84a0-9f3dbc6b6083', Providers: [] (correctly empty)
- Name: 'k8s-external-proxy-outpost', PK: '3f0970c5-d6a3-43b2-9a36-d74665c6b24e', Providers: [2, 5, 6, 7, 3, 4]
- Name: 'radius-outpost', PK: '9d94c493-d7bb-47b4-aae9-d579c69b2ea5', Providers: [1]
```

### Critical Discovery: Dual Provider Architecture

The external authentik-proxy system uses a **dual provider architecture**:

- Each service has **both** a proxy provider AND an OAuth2 provider with the **same name**
- Both providers share the **same PK** (Primary Key)
- The OAuth2 providers handle redirect URLs
- The proxy providers handle forward authentication

### Root Cause Analysis

#### Why the OAuth2 Redirect Fix Failed

1. **Wrong Provider Type Detection**

   ```python
   # Script checked this (WRONG):
   if provider.get('provider_type') == 'proxy':

   # But API doesn't return 'provider_type' field
   # Should check 'component' field or endpoint used
   ```

2. **Wrong Application Lookup**

   ```python
   # Script looked for this (WRONG):
   if service.name in applications:  # e.g., "longhorn"

   # But applications use display names like "Longhorn Storage"
   # Should look by slug: applications[service.slug]
   ```

3. **Misunderstood Dual Provider Structure**
   - Script expected separate proxy and OAuth2 providers
   - Actual structure has both types with same names and PKs

4. **OAuth2 Redirect URLs Already Correct**
   - All redirect URLs already point to external domains
   - No internal cluster DNS URLs found in redirect configurations

### The Real Issue: Outpost Configuration

The investigation revealed the actual problem:

```yaml
# External Outpost Current Configuration (WRONG):
Internal URL: 'https://authentik.k8s.home.geoffdavis.com'  # Should be internal cluster DNS
Browser URL: 'https://authentik.k8s.home.geoffdavis.com'   # This is correct

# Should be:
Internal URL: 'http://authentik-server.authentik.svc.cluster.local:80'  # Internal cluster DNS
Browser URL: 'https://authentik.k8s.home.geoffdavis.com'                # External domain
```

## Correct API Endpoints for Current Configuration

Based on the investigation, the correct API endpoints are:

### 1. Applications API

```
GET /api/v3/core/applications/
- Returns applications with display names and slugs
- Use slug for service matching, not display name
```

### 2. Proxy Providers API

```
GET /api/v3/providers/proxy/
- Returns proxy providers with component: 'ak-provider-proxy-form'
- Each service has one proxy provider
```

### 3. OAuth2 Providers API

```
GET /api/v3/providers/oauth2/
- Returns OAuth2 providers with component: 'ak-provider-oauth2-form'
- Each service has one OAuth2 provider with same name as proxy provider
- Redirect URIs are already correctly configured
```

### 4. Outposts API

```
GET /api/v3/outposts/instances/
PATCH /api/v3/outposts/instances/{outpost_id}/
- External outpost ID: '3f0970c5-d6a3-43b2-9a36-d74665c6b24e'
- Configuration needs internal URL fix
```

## Corrected Fix Approach

### Issue: Outpost Internal URL Configuration

**Problem**: External outpost uses external domain for internal communication
**Solution**: Update outpost configuration to use internal cluster DNS

### Implementation: [`fix-outpost-internal-url-job.yaml`](fix-outpost-internal-url-job.yaml)

```yaml
# Fix the external outpost configuration:
config:
  authentik_host: "http://authentik-server.authentik.svc.cluster.local:80" # Internal cluster DNS
  authentik_host_browser: "https://authentik.k8s.home.geoffdavis.com" # External domain
```

### Why This Fixes the Authentication Flow

1. **Internal Communication**: Outpost connects to Authentik server via internal cluster DNS
2. **Browser Redirects**: Users are redirected to external domain for authentication
3. **OAuth2 Callbacks**: Already correctly configured to use external domains
4. **Service Access**: Forward auth works correctly with proper internal/external URL separation

## Validation Steps

### 1. Deploy the Correct Fix

```bash
kubectl apply -f fix-outpost-internal-url-job.yaml
```

### 2. Monitor Fix Execution

```bash
kubectl logs -n authentik-proxy -l job-name=fix-outpost-internal-url
```

### 3. Test Authentication Flow

```bash
# Test each service:
curl -I https://longhorn.k8s.home.geoffdavis.com
curl -I https://grafana.k8s.home.geoffdavis.com
# Should redirect to https://authentik.k8s.home.geoffdavis.com (not internal cluster DNS)
```

### 4. Verify Outpost Configuration

```bash
# Check outpost status in Authentik admin interface
# Verify internal URL is now: http://authentik-server.authentik.svc.cluster.local:80
# Verify browser URL is: https://authentik.k8s.home.geoffdavis.com
```

## Summary

- **OAuth2 redirect URLs are already correct** - no fix needed
- **Real issue is outpost internal URL configuration** - needs cluster DNS
- **Original OAuth2 redirect fix script had wrong assumptions** about API structure
- **Corrected fix targets the actual problem** - outpost configuration
- **Authentication should work after outpost internal URL fix**

## Recommendations

1. **Deploy the outpost internal URL fix** immediately
2. **Remove or update the OAuth2 redirect fix job** as it's not needed
3. **Update configuration scripts** to understand dual provider architecture
4. **Add monitoring** for outpost connectivity and authentication flow
5. **Document the dual provider architecture** for future reference

The external authentik-proxy system is well-configured except for this single outpost internal URL issue. Once fixed, all services should authenticate correctly through the external domain while maintaining proper internal cluster communication.
