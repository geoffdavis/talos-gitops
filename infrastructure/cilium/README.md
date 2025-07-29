# Cilium CNI Documentation

Cilium is the Container Network Interface (CNI) used in the Talos GitOps Home-Ops Cluster, providing network connectivity, security, and observability for workloads. This document details its purpose, architecture, configuration, and operational aspects.

## Purpose

Cilium's primary functions include:

- **Network Connectivity**: Providing high-performance networking for pods.
- **Network Policy Enforcement**: Implementing Kubernetes Network Policies using eBPF.
- **Load Balancing**: Handling service load balancing for both internal and external traffic.
- **Observability**: Offering deep visibility into network traffic and security events via Hubble.

## Architecture and Integration

Cilium is deployed as a core component of the cluster's networking infrastructure. It leverages eBPF (extended Berkeley Packet Filter) to perform networking and security functions directly within the Linux kernel, offering high performance and flexibility.

Key aspects of its integration include:

- **GitOps Management**: Deployed and managed declaratively via HelmRelease in `infrastructure/cilium/helmrelease-bgp-only.yaml`.
- **Dual-Stack IPv4/IPv6**: Supports both IPv4 and IPv6 networking for pods and services.
- **BGP Integration**: Utilizes BGP for advertising LoadBalancer IPs to the external network, enabling robust external access to services.
- **Kube-proxy Replacement**: In this Talos-based cluster, Cilium effectively replaces `kube-proxy` for service load balancing.
- **XDP Disabled**: Configured with XDP (eXpress Data Path) disabled for compatibility with Mac mini hardware.

## Configuration

The primary configuration for Cilium is managed through its HelmRelease in `infrastructure/cilium/helmrelease-bgp-only.yaml`. Key configurable parameters include:

- **`enable-lb-ipam`**: Set to `true` to enable LoadBalancer IP Address Management.
- **`loadBalancer.l2.enabled`**: Set to `false` as BGP is used for LoadBalancer IP advertisement, not L2 announcements.
- **`loadBalancer.acceleration`**: Set to `disabled` for Mac mini compatibility.
- **`bgp.enabled`**: Set to `true` to enable Cilium's BGP control plane.
- **IPAM Mode**: Configured for `clusterPool` with specific CIDRs for pods and services.

## Operational Considerations

### Verifying Cilium Status

- Check overall Cilium health: `cilium status`
- Verify network connectivity: `cilium connectivity test`
- Monitor Cilium pods: `kubectl get pods -n kube-system -l k8s-app=cilium`

### BGP LoadBalancer Troubleshooting

If LoadBalancer services are not getting external IPs or are inaccessible:

- Verify BGP peering status: `cilium bgp peers`
- Check advertised routes: `cilium bgp routes`
- Ensure services have the correct `io.cilium/lb-ipam-pool` labels matching the defined IP pools.
- Review Cilium operator logs for IPAM issues.

## Related Files

- [`infrastructure/cilium/helmrelease-bgp-only.yaml`](../../infrastructure/cilium/helmrelease-bgp-only.yaml) - Cilium HelmRelease configuration.
- [`infrastructure/cilium-bgp/bgp-policy-legacy.yaml`](../../infrastructure/cilium-bgp/bgp-policy-legacy.yaml) - BGP peering policy configuration.
- [`infrastructure/cilium-pools/loadbalancer-pools.yaml`](../../infrastructure/cilium-pools/loadbalancer-pools.yaml) - LoadBalancer IP pool definitions.

Please ensure this file is created with the exact content provided. After creation, use the `attempt_completion` tool to report the successful creation of the file.
