# External DNS Documentation

External DNS automates the management of DNS records for services exposed in the Talos GitOps Home-Ops Cluster. This document details its purpose, architecture, configuration, and operational aspects, including its integration with various DNS providers.

## Purpose

External DNS enables:

- **Automated DNS Record Management**: Automatically creates and updates DNS records in external DNS providers based on Kubernetes Ingresses and Services.
- **Service Discovery**: Facilitates easy discovery of services by external clients.
- **Reduced Manual Effort**: Eliminates the need for manual DNS record creation and updates, reducing human error and improving efficiency.

## Architecture and Integration

External DNS operates by watching Kubernetes resources (Ingresses and Services) and synchronizing their hostnames with configured DNS providers. In this cluster, it integrates with multiple providers to manage both internal and external DNS records.

Key aspects of its integration include:

- **GitOps Management**: Deployed and managed declaratively via HelmRelease in `infrastructure/external-dns-internal/helmrelease.yaml` and `infrastructure/external-dns-unifi/deployment.yaml`.
- **Multiple Providers**:
  - **Cloudflare**: For external DNS records (e.g., `geoffdavis.com`).
  - **Unifi**: For internal DNS records within the Unifi network.
  - **Internal DNS**: For `k8s.home.geoffdavis.com` domain.
- **Ingress and Service Monitoring**: Watches for `Ingress` resources with specific annotations (e.g., `external-dns.alpha.kubernetes.io/hostname`) and `Service` resources of type `LoadBalancer`.

## Configuration

The primary configuration for External DNS is managed through its HelmReleases and deployments in `infrastructure/external-dns-internal/` and `infrastructure/external-dns-unifi/`.

### Common Parameters

- **`provider`**: Specifies the DNS provider (e.g., `cloudflare`, `unifi`).
- **`domainFilters`**: Restricts External DNS to manage records for specific domains.
- **`source`**: Defines the Kubernetes resource types to watch (e.g., `ingress`, `service`).
- **`policy`**: Determines how DNS records are managed (e.g., `sync`, `upsert-only`).

### Provider-Specific Configuration

- **Cloudflare**: Requires API tokens or credentials configured as Kubernetes secrets, often sourced from 1Password via External Secrets.
- **Unifi**: Requires Unifi controller URL and credentials.

## Operational Considerations

### Verifying External DNS Status

- Check External DNS pod status: `kubectl get pods -n external-dns-internal` (or `external-dns-unifi`)
- Review External DNS logs for synchronization events and errors: `kubectl logs -n external-dns-internal -l app.kubernetes.io/name=external-dns`

### Troubleshooting

- **Missing DNS Records**:
  - Verify the Ingress or Service has the correct `external-dns.alpha.kubernetes.io/hostname` annotation.
  - Check External DNS logs for errors related to the specific record.
  - Ensure the DNS provider credentials are valid and accessible.
- **Incorrect IP Addresses**:
  - Verify the LoadBalancer Service has obtained an external IP.
  - Check if the External DNS pod is correctly resolving the service IP.
- **Provider Connectivity Issues**:
  - Ensure network connectivity from the External DNS pod to the DNS provider's API endpoint.

## Related Files

- [`infrastructure/external-dns-internal/helmrelease.yaml`](../../infrastructure/external-dns-internal/helmrelease.yaml) - HelmRelease for internal External DNS.
- [`infrastructure/external-dns-unifi/deployment.yaml`](../../infrastructure/external-dns-unifi/deployment.yaml) - Deployment for Unifi External DNS.
- [`infrastructure/external-dns-internal/external-secret.yaml`](../../infrastructure/external-dns-internal/external-secret.yaml) - External Secret for Cloudflare credentials.
