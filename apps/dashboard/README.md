# Kubernetes Dashboard Documentation

The Kubernetes Dashboard provides a web-based user interface for managing and troubleshooting applications running in the cluster, as well as for managing the cluster itself. This document details its deployment, configuration, and integration within the Talos GitOps Home-Ops Cluster.

## Purpose

The Kubernetes Dashboard offers a user-friendly way to:

- Deploy containerized applications.
- Monitor the health and status of applications.
- Manage Kubernetes resources (Deployments, Pods, Services, etc.).
- View logs and troubleshoot issues.

## Architecture and Integration

In the Talos GitOps Home-Ops Cluster, the Kubernetes Dashboard is deployed via Flux CD and integrated with the external Authentik outpost system for seamless Single Sign-On (SSO). This eliminates the need for manual bearer token entry, providing a secure and streamlined access experience.

Key aspects of its integration include:

- **GitOps Management**: Deployed and managed declaratively via HelmRelease in `apps/dashboard/kubernetes-dashboard.yaml`.
- **Authentication**: Full SSO integration with Authentik via the external outpost, accessible at `https://dashboard.k8s.home.geoffdavis.com`.
- **RBAC**: Configured with appropriate ClusterRoleBinding to provide administrative access through the Authentik-authenticated user.
- **Kong Configuration**: Integrated with Kong (if enabled in the HelmRelease) to handle authentication headers and service discovery.

## Configuration

The primary configuration for the Kubernetes Dashboard is managed through its HelmRelease in `apps/dashboard/kubernetes-dashboard.yaml`. Key configurable parameters include:

- **Resource Limits**: CPU and memory allocations for the Dashboard pods.
- **Service Type**: Configured as a ClusterIP service, with external access managed by the Authentik proxy.
- **Authentication Settings**: While the Dashboard itself supports various authentication methods, access in this cluster is exclusively through Authentik SSO.

## Operational Considerations

### Accessing the Dashboard

Access the Kubernetes Dashboard via your web browser at `https://dashboard.k8s.home.geoffdavis.com`. You will be redirected to Authentik for authentication. Upon successful login, you will be granted access to the Dashboard.

### Troubleshooting

- **Authentication Issues**: If you encounter issues accessing the Dashboard, ensure your browser cache is cleared. Verify the Authentik external outpost is operational and that the proxy provider for the Dashboard is correctly configured in Authentik.
- **Permission Denied**: If you can access the Dashboard but see "Permission Denied" errors, verify the RBAC permissions for the Dashboard service account and your Authentik-authenticated user.
- **Deployment Failures**: Check Flux CD reconciliation status for the Dashboard HelmRelease and review pod logs in the `kubernetes-dashboard` namespace.

## Related Files

- [`apps/dashboard/kubernetes-dashboard.yaml`](../../apps/dashboard/kubernetes-dashboard.yaml) - HelmRelease for Kubernetes Dashboard.
- [`apps/dashboard/dashboard-service-account.yaml`](../../apps/dashboard/dashboard-service-account.yaml) - Service account and RBAC configurations.
- [`infrastructure/authentik-proxy/`](../../infrastructure/authentik-proxy/) - External Authentik proxy configuration.

Please ensure this file is created with the exact content provided. After creation, use the `attempt_completion` tool to report the successful creation of the file.
