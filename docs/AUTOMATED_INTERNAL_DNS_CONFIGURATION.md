# Automated Internal DNS Configuration with UniFi Webhook

## Overview

This document describes the automated DNS configuration solution that enables External-DNS to manage both external (Cloudflare) and internal (UniFi Dream Machine) domains automatically, eliminating the need for manual DNS record management.

## Architecture

### Dual External-DNS Setup

The solution uses two separate External-DNS instances:

1. **External-DNS (Cloudflare)**: Manages `geoffdavis.com` domains for public tunnel access
2. **External-DNS Internal (UniFi Webhook)**: Manages `k8s.home.geoffdavis.com` domains for internal network access

### Components

#### 1. UniFi Webhook (`external-dns-unifi-webhook`)

- **Location**: [`infrastructure/external-dns-unifi/`](../infrastructure/external-dns-unifi/)
- **Purpose**: Provides webhook interface for External-DNS to manage UniFi DNS records
- **Image**: `ghcr.io/kashalls/external-dns-unifi-webhook:v0.2.0`
- **Namespace**: `external-dns-unifi-system`

#### 2. Internal External-DNS (`external-dns-internal`)

- **Location**: [`infrastructure/external-dns-internal/`](../infrastructure/external-dns-internal/)
- **Purpose**: Manages internal domain DNS records via UniFi webhook
- **Provider**: `webhook`
- **Namespace**: `external-dns-internal-system`

#### 3. External External-DNS (`external-dns`)

- **Location**: [`infrastructure/external-dns/`](../infrastructure/external-dns/)
- **Purpose**: Manages external domain DNS records via Cloudflare
- **Provider**: `cloudflare`
- **Namespace**: `external-dns-system`

## Configuration Details

### Domain Separation

#### External Domains (Cloudflare)

```yaml
domainFilters:
  - geoffdavis.com # Only manage Cloudflare tunnel domains
```

#### Internal Domains (UniFi)

```yaml
domainFilters:
  - k8s.home.geoffdavis.com # Only manage internal domains
```

### Annotation Filters

#### External Services

Use standard external-dns annotations:

```yaml
annotations:
  external-dns.alpha.kubernetes.io/hostname: "service.geoffdavis.com"
```

#### Internal Services

Use internal-specific annotations:

```yaml
annotations:
  external-dns-internal.alpha.kubernetes.io/hostname: "service.k8s.home.geoffdavis.com"
  external-dns-internal.alpha.kubernetes.io/target: "172.29.51.200"
```

## Prerequisites

### 1. UniFi API Key in 1Password

The UniFi API key should already be available in 1Password:

- **Item Name**: `Home-ops Unifi API`
- **Field**: `password` (contains the API key)

### 2. UniFi Dream Machine Configuration

Ensure the UDM is accessible at the configured IP address (default: `https://192.168.1.1`).

## Deployment Components

### 1. UniFi Webhook Deployment

**File**: [`infrastructure/external-dns-unifi/deployment.yaml`](../infrastructure/external-dns-unifi/deployment.yaml)

Key configuration:

```yaml
env:
  - name: UNIFI_HOST
    value: "https://192.168.1.1" # Update with your UDM IP
  - name: UNIFI_API_KEY
    valueFrom:
      secretKeyRef:
        name: external-dns-unifi-secret
        key: api-key
  - name: UNIFI_VERSION
    value: "unifiOS"
```

### 2. External Secret for UniFi Credentials

**File**: [`infrastructure/external-dns-unifi/external-secret.yaml`](../infrastructure/external-dns-unifi/external-secret.yaml)

Retrieves UniFi API key from 1Password and creates Kubernetes secret `external-dns-unifi-secret`.

### 3. Internal External-DNS Configuration

**File**: [`infrastructure/external-dns-internal/helmrelease.yaml`](../infrastructure/external-dns-internal/helmrelease.yaml)

Configured to use webhook provider pointing to UniFi webhook service.

## Automated DNS Records

The following internal DNS records are now automatically managed:

| Service      | FQDN                                   | Target IP       | Management                  |
| ------------ | -------------------------------------- | --------------- | --------------------------- |
| Grafana      | `grafana.k8s.home.geoffdavis.com`      | `172.29.51.200` | Automated via UniFi webhook |
| Longhorn     | `longhorn.k8s.home.geoffdavis.com`     | `172.29.51.200` | Automated via UniFi webhook |
| Prometheus   | `prometheus.k8s.home.geoffdavis.com`   | `172.29.51.200` | Automated via UniFi webhook |
| Alertmanager | `alertmanager.k8s.home.geoffdavis.com` | `172.29.51.200` | Automated via UniFi webhook |

## Updated Ingress Configurations

### Internal Services

Updated to use internal external-dns annotations:

**Longhorn** ([`infrastructure/longhorn/ingress.yaml`](../infrastructure/longhorn/ingress.yaml)):

```yaml
annotations:
  external-dns-internal.alpha.kubernetes.io/hostname: "longhorn.k8s.home.geoffdavis.com"
  external-dns-internal.alpha.kubernetes.io/target: "172.29.51.200"
```

**Monitoring Services** ([`apps/monitoring/grafana.yaml`](../apps/monitoring/grafana.yaml)):

```yaml
annotations:
  external-dns-internal.alpha.kubernetes.io/hostname: "grafana.k8s.home.geoffdavis.com"
  external-dns-internal.alpha.kubernetes.io/target: "172.29.51.200"
```

## GitOps Integration

### Flux Kustomizations

Added to [`clusters/home-ops/infrastructure/networking.yaml`](../clusters/home-ops/infrastructure/networking.yaml):

1. **UniFi Webhook**: `infrastructure-external-dns-unifi`
2. **Internal External-DNS**: `infrastructure-external-dns-internal`

### Dependency Chain

```
infrastructure-onepassword
├── infrastructure-external-dns-unifi
│   └── infrastructure-external-dns-internal
└── infrastructure-external-dns (Cloudflare)
```

## Validation

### 1. Check Webhook Deployment

```bash
kubectl get pods -n external-dns-unifi-system
kubectl logs -n external-dns-unifi-system deployment/external-dns-unifi-webhook
```

### 2. Check Internal External-DNS

```bash
kubectl get pods -n external-dns-internal-system
kubectl logs -n external-dns-internal-system deployment/external-dns-internal
```

### 3. Verify DNS Records

```bash
# Check if DNS records are created in UniFi
nslookup grafana.k8s.home.geoffdavis.com
nslookup longhorn.k8s.home.geoffdavis.com
```

## Troubleshooting

### Common Issues

#### 1. UniFi Authentication Failures

- Verify credentials in 1Password
- Check UDM IP address configuration
- Ensure UDM is accessible from cluster

#### 2. Webhook Connection Issues

- Verify webhook service is running
- Check network connectivity to UniFi webhook
- Review webhook logs for errors

#### 3. DNS Record Creation Failures

- Check external-dns-internal logs
- Verify annotation filters match ingress annotations
- Ensure domain filters are correctly configured

### Log Analysis

#### UniFi Webhook Logs

```bash
kubectl logs -n external-dns-unifi-system deployment/external-dns-unifi-webhook -f
```

#### Internal External-DNS Logs

```bash
kubectl logs -n external-dns-internal-system deployment/external-dns-internal -f
```

## Benefits

### 1. Full Automation

- No manual DNS record management required
- Automatic creation/deletion of DNS records
- Consistent DNS management across environments

### 2. Clear Separation

- External domains managed by Cloudflare
- Internal domains managed by UniFi
- No configuration conflicts

### 3. GitOps Integration

- All configuration managed via Git
- Automated deployment via Flux
- Version controlled DNS management

## Security Considerations

### 1. Credential Management

- UniFi credentials stored securely in 1Password
- Automatic credential rotation supported
- Kubernetes secrets managed by External Secrets

### 2. Network Security

- Webhook communication within cluster
- UniFi access limited to necessary permissions
- TLS encryption for all communications

## Maintenance

### 1. Credential Rotation

Update credentials in 1Password - External Secrets will automatically sync.

### 2. UniFi Webhook Updates

Monitor for new releases of `external-dns-unifi-webhook` and update image tags.

### 3. Configuration Changes

All configuration changes should be made via Git and deployed through GitOps.

## References

- [External-DNS UniFi Webhook](https://github.com/kashalls/external-dns-unifi-webhook)
- [External-DNS Documentation](https://kubernetes-sigs.github.io/external-dns/)
- [UniFi API Documentation](https://ubntwiki.com/products/software/unifi-controller/api)
