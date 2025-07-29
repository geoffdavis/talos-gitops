# Monitoring Applications Documentation

The monitoring stack in the Talos GitOps Home-Ops Cluster provides comprehensive observability into the cluster's health, performance, and application metrics. This document details its components, architecture, configuration, and operational considerations, including the successful recovery from recent failures.

## Purpose

The monitoring applications enable:

- **Metrics Collection**: Gathering performance metrics from all cluster components and applications.
- **Alerting**: Notifying operators of critical issues and anomalies.
- **Visualization**: Providing dashboards for real-time insights into cluster status.
- **Troubleshooting**: Aiding in the diagnosis and resolution of operational problems.

## Architecture and Integration

The monitoring stack is deployed via the `kube-prometheus-stack` Helm chart and includes Prometheus, Grafana, and AlertManager. It is integrated with the cluster's BGP LoadBalancer for external access and managed through GitOps.

Key aspects of its integration include:

- **GitOps Management**: Deployed and managed declaratively via HelmRelease in `infrastructure/monitoring/helmrelease.yaml`.
- **Components**:
  - **Prometheus**: For time-series data collection.
  - **Grafana**: For data visualization and dashboarding.
  - **AlertManager**: For handling and routing alerts.
- **External Access**: All monitoring services are accessible via BGP-advertised LoadBalancer IPs (Grafana: `172.29.52.101`, Prometheus: `172.29.52.102`, AlertManager: `172.29.52.103`).
- **Single Source of Truth**: Configuration is maintained from `infrastructure/monitoring/` to prevent conflicts.

## Configuration

The primary configuration for the monitoring stack is managed through its HelmRelease in `infrastructure/monitoring/helmrelease.yaml`. Key configurable parameters include:

- **Resource Limits**: CPU and memory allocations for all monitoring components.
- **Service Monitors**: Defining targets for Prometheus to scrape metrics.
- **Alerting Rules**: Configuring conditions for AlertManager to trigger alerts.
- **Grafana Dashboards**: Pre-configured and custom dashboards for visualization.

## Operational Considerations

### Accessing Monitoring Tools

- **Grafana**: Access via `https://grafana.k8s.home.geoffdavis.com` (or directly via `172.29.52.101`).
- **Prometheus**: Access via `https://prometheus.k8s.home.geoffdavis.com` (or directly via `172.29.52.102`).
- **AlertManager**: Access via `https://alertmanager.k8s.home.geoffdavis.com` (or directly via `172.29.52.103`).

### Troubleshooting and Recovery

The monitoring stack recently underwent a significant recovery effort due to Renovate-induced failures, which caused duplicate HelmRelease conflicts and LoadBalancer IPAM dysfunction. The recovery involved:

- **Eliminating Duplicate HelmReleases**: Removing conflicting configurations from `apps/monitoring/` to establish `infrastructure/monitoring/` as the single source of truth.
- **Cleaning Corrupted Helm State**: Deleting failed Helm releases to allow clean redeployment.
- **Fixing LoadBalancer IPAM**: Restarting the Cilium operator and adding required `io.cilium/lb-ipam-pool: "bgp-default"` labels to services to ensure proper external IP assignment and BGP route advertisement.

If you encounter issues, check:

- Flux reconciliation status for `infrastructure-monitoring` kustomization.
- Pod status in the `monitoring` namespace.
- Cilium operator logs for IPAM issues.
- BGP routes to ensure external IPs are advertised.

## Related Files

- [`infrastructure/monitoring/helmrelease.yaml`](../../infrastructure/monitoring/helmrelease.yaml) - HelmRelease for the monitoring stack.
- [`infrastructure/cilium-pools/loadbalancer-pools.yaml`](../../infrastructure/cilium-pools/loadbalancer-pools.yaml) - LoadBalancer IP pool definitions.
- [`infrastructure/cilium-bgp/bgp-policy-legacy.yaml`](../../infrastructure/cilium-bgp/bgp-policy-legacy.yaml) - BGP peering policy.

Please ensure this file is created with the exact content provided. After creation, use the `attempt_completion` tool to report the successful creation of the file.
