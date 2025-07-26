# Flux GitHub Webhook Architecture Plan

## Executive Summary

This document outlines the comprehensive architectural plan for implementing a GitHub webhook integration with Flux using the existing Cloudflare tunnel infrastructure. This will be the first publicly exposed service through the Cloudflare tunnel, requiring careful security considerations and integration with existing monitoring systems.

## Current Infrastructure Analysis

### Existing Components

- **Flux System**: Deployed in `flux-system` namespace with notification controller ready
- **Cloudflare Tunnel**: Deployed with basic catch-all 404 rule, ready for ingress configuration
- **Domain Structure**:
  - External: `geoffdavis.com` (managed by external-dns)
  - Internal: `k8s.home.geoffdavis.com` (internal-only services)
- **Certificate Management**: cert-manager with Let's Encrypt (DNS01 and HTTP01 solvers)
- **Ingress Controllers**:
  - `nginx` (internal services)
  - `nginx-public` (ready for public services via tunnel)
- **Security**: 1Password Connect for secret management
- **Monitoring**: Prometheus with existing Flux monitoring rules

### Key Findings

- Webhook receiver service exists but is not configured for external access
- No current public ingress rules in Cloudflare tunnel
- All existing services use internal-only access patterns
- Strong security and monitoring foundation already in place

## Proposed Architecture

### Component Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                 Internet                                        │
└─────────────────────────┬───────────────────────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────────────────────────┐
│                    GitHub Webhook                                              │
│                flux-webhook.geoffdavis.com                                     │
└─────────────────────────┬───────────────────────────────────────────────────────┘
                          │ HTTPS (TLS 1.3)
                          │ Webhook Secret Validation
┌─────────────────────────▼───────────────────────────────────────────────────────┐
│                  Cloudflare Tunnel                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ Ingress Rules:                                                          │   │
│  │ - flux-webhook.geoffdavis.com → ingress-nginx-public:443               │   │
│  │ - Default: http_status:404                                              │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────────────────────────────────┘
                          │ HTTP/HTTPS
┌─────────────────────────▼───────────────────────────────────────────────────────┐
│                 Kubernetes Cluster                                             │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    ingress-nginx-public                                 │   │
│  │                  (nginx-public class)                                   │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐   │   │
│  │  │ Ingress Resource:                                               │   │   │
│  │  │ - Host: flux-webhook.geoffdavis.com                             │   │   │
│  │  │ - TLS: Let's Encrypt certificate                                │   │   │
│  │  │ - Path: /hook/flux-system → webhook-receiver:9292              │   │   │
│  │  │ - Security: Rate limiting, IP filtering                        │   │   │
│  │  └─────────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────┬───────────────────────────────────────────────┘   │
│                            │                                                     │
│  ┌─────────────────────────▼───────────────────────────────────────────────┐   │
│  │                    flux-system namespace                                │   │
│  │                                                                         │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐   │   │
│  │  │              webhook-receiver Service                           │   │   │
│  │  │                    Port: 9292                                   │   │   │
│  │  └─────────────────────────┬───────────────────────────────────────┘   │   │
│  │                            │                                             │   │
│  │  ┌─────────────────────────▼───────────────────────────────────────┐   │   │
│  │  │           notification-controller Pod                           │   │   │
│  │  │  - Webhook receiver endpoint: /hook/{receiver-name}             │   │   │
│  │  │  - Secret validation                                            │   │   │
│  │  │  - Event processing                                             │   │   │
│  │  └─────────────────────────┬───────────────────────────────────────┘   │   │
│  │                            │                                             │   │
│  │  ┌─────────────────────────▼───────────────────────────────────────┐   │   │
│  │  │                 Receiver Resource                               │   │   │
│  │  │  - GitHub webhook configuration                                 │   │   │
│  │  │  - Secret reference                                             │   │   │
│  │  │  - Event filtering                                              │   │   │
│  │  └─────────────────────────┬───────────────────────────────────────┘   │   │
│  └────────────────────────────┼─────────────────────────────────────────────┘   │
│                               │                                                 │
│  ┌────────────────────────────▼─────────────────────────────────────────────┐   │
│  │                     GitRepository Resources                              │   │
│  │  - Trigger reconciliation on webhook events                             │   │
│  │  - Validate webhook signatures                                           │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                      Monitoring Stack                                   │   │
│  │  - Prometheus metrics collection                                        │   │
│  │  - Webhook success/failure alerts                                       │   │
│  │  - Performance monitoring                                               │   │
│  │  - Security event logging                                               │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Detailed Component Specifications

### 1. Domain and DNS Configuration

**Proposed Domain**: `flux-webhook.geoffdavis.com`

**DNS Configuration**:

- External DNS will automatically create CNAME record pointing to Cloudflare tunnel
- Let's Encrypt certificate via DNS01 challenge using existing Cloudflare API token
- No internal DNS required (public-only endpoint)

### 2. Cloudflare Tunnel Configuration

**Updated ConfigMap** (`infrastructure/cloudflare-tunnel/configmap.yaml`):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cloudflare-tunnel-config
  namespace: cloudflare-tunnel
data:
  config.yaml: |
    tunnel: home-ops-tunnel
    credentials-file: /etc/cloudflared/creds/credentials.json
    metrics: 0.0.0.0:2000
    no-autoupdate: true

    ingress:
      # Flux webhook endpoint
      - hostname: flux-webhook.geoffdavis.com
        service: https://ingress-nginx-public.ingress-nginx-public.svc.cluster.local:443
        originRequest:
          noTLSVerify: false
          connectTimeout: 30s
          tlsTimeout: 10s
          keepAliveTimeout: 90s
          httpHostHeader: flux-webhook.geoffdavis.com
      
      # Default rule - catch all
      - service: http_status:404
```

**Security Features**:

- TLS verification enabled
- Custom HTTP host header preservation
- Connection timeouts configured
- Metrics endpoint for monitoring

### 3. Ingress Configuration

**Public Ingress Resource** (`infrastructure/flux-webhook/ingress.yaml`):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: flux-webhook
  namespace: flux-system
  annotations:
    # Use public ingress class for tunnel access
    kubernetes.io/ingress.class: nginx-public

    # Certificate management
    cert-manager.io/cluster-issuer: "letsencrypt-prod"

    # External DNS configuration
    external-dns.alpha.kubernetes.io/hostname: "flux-webhook.geoffdavis.com"

    # Security configurations
    nginx.ingress.kubernetes.io/rate-limit: "10"
    nginx.ingress.kubernetes.io/rate-limit-window: "1m"
    nginx.ingress.kubernetes.io/limit-connections: "5"

    # SSL and security headers
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/ssl-protocols: "TLSv1.2 TLSv1.3"

    # Webhook-specific configurations
    nginx.ingress.kubernetes.io/proxy-body-size: "1m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "30"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "10"

    # Security headers
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "X-Content-Type-Options: nosniff";
      more_set_headers "X-Frame-Options: DENY";
      more_set_headers "X-XSS-Protection: 1; mode=block";
      more_set_headers "Referrer-Policy: strict-origin-when-cross-origin";
spec:
  ingressClassName: nginx-public
  tls:
    - hosts:
        - flux-webhook.geoffdavis.com
      secretName: flux-webhook-tls
  rules:
    - host: flux-webhook.geoffdavis.com
      http:
        paths:
          - path: /hook
            pathType: Prefix
            backend:
              service:
                name: webhook-receiver
                port:
                  number: 9292
```

### 4. Flux Receiver Configuration

**Receiver Resource** (`infrastructure/flux-webhook/receiver.yaml`):

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1
kind: Receiver
metadata:
  name: github-webhook
  namespace: flux-system
spec:
  type: github
  events:
    - "ping"
    - "push"
    - "pull_request"
  resources:
    - apiVersion: source.toolkit.fluxcd.io/v1
      kind: GitRepository
      name: flux-system
      namespace: flux-system
    - apiVersion: source.toolkit.fluxcd.io/v1
      kind: GitRepository
      name: homelab-config
      namespace: flux-system
  secretRef:
    name: github-webhook-secret
  suspend: false
```

**Alert Configuration** (`infrastructure/flux-webhook/alert.yaml`):

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Alert
metadata:
  name: github-webhook-alerts
  namespace: flux-system
spec:
  providerRef:
    name: webhook-logger
  eventSeverity: info
  eventSources:
    - kind: Receiver
      name: github-webhook
  summary: "GitHub webhook event received"
  suspend: false
```

### 5. Security Implementation

#### Webhook Secret Management

**External Secret** (`infrastructure/flux-webhook/external-secret.yaml`):

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: github-webhook-secret
  namespace: flux-system
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: onepassword-connect
    kind: ClusterSecretStore
  target:
    name: github-webhook-secret
    creationPolicy: Owner
  data:
    - secretKey: token
      remoteRef:
        key: "GitHub Flux Webhook Secret"
        property: "token"
```

#### Security Measures

1. **Webhook Secret Validation**: GitHub webhook secret stored in 1Password
2. **TLS Encryption**: End-to-end TLS with Let's Encrypt certificates
3. **Rate Limiting**: 10 requests per minute per IP
4. **Connection Limiting**: Maximum 5 concurrent connections
5. **Request Size Limiting**: 1MB maximum payload
6. **Security Headers**: Comprehensive security headers via ingress annotations
7. **IP Filtering**: Can be implemented via Cloudflare if needed
8. **Path Restriction**: Only `/hook` path exposed publicly

#### Network Security

- **Ingress Class Isolation**: Uses dedicated `nginx-public` ingress class
- **Namespace Isolation**: Webhook receiver runs in `flux-system` namespace
- **Service Account**: Dedicated service account with minimal permissions
- **Network Policies**: Can be implemented for additional isolation

### 6. Monitoring and Observability

#### Metrics Collection

**ServiceMonitor Extension** (`infrastructure/monitoring/flux-webhook-monitoring.yaml`):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: flux-webhook-receiver
  namespace: monitoring
  labels:
    app.kubernetes.io/name: flux-system
    app.kubernetes.io/component: webhook-receiver
spec:
  namespaceSelector:
    matchNames:
      - flux-system
  selector:
    matchLabels:
      app: notification-controller
  endpoints:
    - port: http-prom
      interval: 30s
      path: /metrics
      scrapeTimeout: 10s
```

#### Alert Rules

**PrometheusRule Extension** (`infrastructure/monitoring/flux-webhook-alerts.yaml`):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: flux-webhook-alerts
  namespace: monitoring
  labels:
    app.kubernetes.io/name: flux-system
    prometheus: kube-prometheus
    role: alert-rules
spec:
  groups:
    - name: flux-webhook.rules
      interval: 30s
      rules:
        # Webhook receiver availability
        - alert: FluxWebhookReceiverDown
          expr: up{job="flux-system-notification-controller"} == 0
          for: 2m
          labels:
            severity: critical
            component: flux-webhook
          annotations:
            summary: "Flux webhook receiver is down"
            description: "Flux webhook receiver has been down for more than 2 minutes."

        # Webhook authentication failures
        - alert: FluxWebhookAuthFailures
          expr: increase(gotk_webhook_receiver_requests_total{status_code!~"2.."}[5m]) > 5
          for: 1m
          labels:
            severity: warning
            component: flux-webhook
          annotations:
            summary: "High webhook authentication failures"
            description: "More than 5 webhook authentication failures in the last 5 minutes."

        # Webhook processing errors
        - alert: FluxWebhookProcessingErrors
          expr: increase(gotk_webhook_receiver_errors_total[5m]) > 3
          for: 1m
          labels:
            severity: warning
            component: flux-webhook
          annotations:
            summary: "Webhook processing errors detected"
            description: "More than 3 webhook processing errors in the last 5 minutes."

        # High webhook latency
        - alert: FluxWebhookHighLatency
          expr: histogram_quantile(0.95, rate(gotk_webhook_receiver_duration_seconds_bucket[5m])) > 5
          for: 2m
          labels:
            severity: warning
            component: flux-webhook
          annotations:
            summary: "High webhook processing latency"
            description: "95th percentile webhook processing latency is above 5 seconds."

        # Ingress availability
        - alert: FluxWebhookIngressDown
          expr: nginx_ingress_controller_requests{ingress="flux-webhook"} == 0
          for: 5m
          labels:
            severity: critical
            component: flux-webhook
          annotations:
            summary: "Flux webhook ingress not receiving traffic"
            description: "Flux webhook ingress has not received traffic for 5 minutes."
```

#### Logging Configuration

- **Structured Logging**: JSON format for webhook events
- **Log Aggregation**: Integration with existing logging infrastructure
- **Audit Trail**: All webhook events logged with timestamps and source IPs
- **Error Tracking**: Detailed error logging for troubleshooting

### 7. Implementation Sequence

#### Phase 1: Foundation Setup (Low Risk)

1. **Create webhook namespace resources**

   - Namespace (if needed)
   - ServiceAccount
   - RBAC permissions

2. **Configure secret management**

   - Create 1Password entry for webhook secret
   - Deploy ExternalSecret resource
   - Verify secret creation

3. **Update certificate issuer**
   - Add `geoffdavis.com` to DNS01 solver zones
   - Test certificate generation

#### Phase 2: Ingress Configuration (Medium Risk)

1. **Deploy public ingress resource**

   - Create ingress with security annotations
   - Verify certificate provisioning
   - Test internal connectivity

2. **Update external DNS**
   - Verify DNS record creation
   - Test domain resolution

#### Phase 3: Tunnel Configuration (Medium Risk)

1. **Update Cloudflare tunnel config**

   - Add ingress rule for webhook domain
   - Deploy updated ConfigMap
   - Restart tunnel pods

2. **Verify tunnel connectivity**
   - Test external access to webhook endpoint
   - Verify TLS certificate chain
   - Test rate limiting

#### Phase 4: Flux Integration (High Risk)

1. **Deploy Receiver resource**

   - Create GitHub webhook receiver
   - Configure event filtering
   - Test webhook endpoint

2. **Configure GitHub webhook**
   - Add webhook URL to GitHub repository
   - Configure webhook secret
   - Test webhook delivery

#### Phase 5: Monitoring and Validation (Low Risk)

1. **Deploy monitoring resources**

   - ServiceMonitor for metrics collection
   - PrometheusRule for alerting
   - Verify metrics collection

2. **End-to-end testing**
   - Test complete webhook flow
   - Verify Flux reconciliation triggers
   - Validate monitoring and alerting

### 8. Security Considerations

#### Threat Model

**External Threats**:

- **DDoS Attacks**: Mitigated by Cloudflare protection and rate limiting
- **Webhook Spoofing**: Mitigated by GitHub webhook secret validation
- **Certificate Attacks**: Mitigated by Let's Encrypt certificate pinning
- **Data Exfiltration**: Mitigated by minimal exposed surface area

**Internal Threats**:

- **Privilege Escalation**: Mitigated by RBAC and service account isolation
- **Lateral Movement**: Mitigated by network policies and namespace isolation
- **Secret Exposure**: Mitigated by 1Password integration and secret rotation

#### Security Controls

1. **Authentication**: GitHub webhook secret validation
2. **Authorization**: RBAC-based access control
3. **Encryption**: TLS 1.2/1.3 end-to-end encryption
4. **Monitoring**: Comprehensive logging and alerting
5. **Rate Limiting**: Request and connection rate limiting
6. **Input Validation**: Webhook payload validation
7. **Secret Management**: Automated secret rotation via 1Password

### 9. Rollback and Troubleshooting

#### Rollback Procedures

**Emergency Rollback** (< 5 minutes):

1. **Disable webhook in GitHub**: Remove webhook URL from repository settings
2. **Suspend Receiver**: Set `suspend: true` in Receiver resource
3. **Remove tunnel rule**: Comment out webhook rule in tunnel ConfigMap

**Partial Rollback** (< 15 minutes):

1. **Revert tunnel configuration**: Restore previous ConfigMap version
2. **Remove ingress resource**: Delete public ingress for webhook
3. **Suspend Flux receiver**: Prevent webhook processing

**Full Rollback** (< 30 minutes):

1. **Remove all webhook resources**: Delete all webhook-related resources
2. **Revert DNS changes**: Remove external DNS annotations
3. **Clean up certificates**: Remove webhook TLS certificates

#### Troubleshooting Guide

**Common Issues**:

1. **Webhook not reachable**:

   - Check Cloudflare tunnel logs
   - Verify ingress controller status
   - Test internal service connectivity
   - Validate DNS resolution

2. **Certificate issues**:

   - Check cert-manager logs
   - Verify Let's Encrypt rate limits
   - Test DNS01 challenge resolution
   - Validate Cloudflare API token

3. **Authentication failures**:

   - Verify webhook secret in 1Password
   - Check ExternalSecret status
   - Validate GitHub webhook configuration
   - Review webhook payload logs

4. **Performance issues**:
   - Monitor webhook processing latency
   - Check ingress controller resources
   - Verify tunnel connection health
   - Review rate limiting configuration

**Diagnostic Commands**:

```bash
# Check webhook receiver status
kubectl get receiver -n flux-system

# View webhook logs
kubectl logs -n flux-system -l app=notification-controller

# Check ingress status
kubectl get ingress -n flux-system flux-webhook

# Verify certificate
kubectl get certificate -n flux-system flux-webhook-tls

# Test webhook endpoint
curl -I https://flux-webhook.geoffdavis.com/hook/github-webhook
```

### 10. Performance and Scalability

#### Performance Characteristics

**Expected Load**:

- **Webhook Frequency**: 10-50 webhooks per day (typical development activity)
- **Peak Load**: 5-10 webhooks per hour during active development
- **Payload Size**: 1-10KB typical GitHub webhook payload
- **Processing Time**: < 100ms per webhook (excluding reconciliation)

**Resource Requirements**:

- **CPU**: Minimal additional load on notification-controller
- **Memory**: < 10MB additional memory for webhook processing
- **Network**: < 1MB/day additional bandwidth
- **Storage**: Minimal log storage requirements

#### Scalability Considerations

**Horizontal Scaling**:

- Notification controller supports multiple replicas
- Ingress controller already configured for high availability
- Cloudflare tunnel provides automatic load balancing

**Vertical Scaling**:

- Current resource limits sufficient for expected load
- Can increase notification-controller resources if needed
- Ingress controller resources already optimized

### 11. Compliance and Governance

#### Security Compliance

**Data Protection**:

- No sensitive data stored in webhook payloads
- All secrets managed via 1Password integration
- Audit trail maintained for all webhook events
- TLS encryption for data in transit

**Access Control**:

- RBAC-based permissions for all components
- Service account isolation
- Network policy enforcement (optional)
- Regular access review procedures

#### Operational Governance

**Change Management**:

- All changes tracked via GitOps workflow
- Staged deployment process with rollback procedures
- Monitoring and alerting for all changes
- Documentation updates for all modifications

**Incident Response**:

- Defined escalation procedures
- Automated alerting for critical issues
- Runbook procedures for common problems
- Post-incident review process

## Conclusion

This architectural plan provides a comprehensive, secure, and well-integrated approach to implementing GitHub webhook functionality for Flux. The design leverages existing infrastructure components while maintaining security best practices and operational excellence.

The phased implementation approach minimizes risk while ensuring proper testing and validation at each stage. The comprehensive monitoring and alerting ensure operational visibility, while the detailed rollback procedures provide confidence in the deployment process.

The solution is designed to scale with the organization's needs while maintaining the high security and reliability standards established in the existing infrastructure.
