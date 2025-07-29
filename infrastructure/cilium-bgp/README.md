# BGP LoadBalancer Documentation

The BGP (Border Gateway Protocol) LoadBalancer in the Talos GitOps Home-Ops Cluster provides robust external access to services by advertising LoadBalancer IPs to the network. This document details its purpose, architecture, configuration, and operational aspects, including the use of multiple virtual routers and IP pools.

## Purpose

The BGP LoadBalancer enables:

- **External Service Access**: Making Kubernetes services accessible from outside the cluster via dedicated IP addresses.
- **High Availability**: Distributing traffic across multiple service endpoints.
- **Network Integration**: Seamless integration with the existing network infrastructure (e.g., UDM Pro) through BGP peering.
- **Scalability**: Allowing for flexible assignment of IP addresses from defined pools.

## Architecture and Integration

The BGP LoadBalancer is implemented using Cilium's BGP control plane. It operates by establishing BGP peering sessions with external routers (e.g., UDM Pro) and advertising service LoadBalancer IPs. This architecture replaces traditional L2 announcements for improved reliability and control.

Key aspects of its integration include:

- **GitOps Management**: Configured declaratively via `CiliumBGPPeeringPolicy` in `infrastructure/cilium-bgp/bgp-policy-legacy.yaml`.
- **Multiple Virtual Routers**: Utilizes dedicated virtual routers for different IP pools (e.g., `bgp-default`, `bgp-ingress`) with explicit service selectors. This ensures proper advertisement of IPs from all pools.
- **IP Pools**: IP addresses are allocated from predefined pools (e.g., `172.29.52.100-199` for `bgp-default`, `172.29.52.200-220` for `bgp-ingress`).
- **Network Separation**: LoadBalancer IPs are advertised on a dedicated VLAN (VLAN 52) separate from management traffic (VLAN 51).
- **Graceful Restart**: Enabled for BGP peering to ensure minimal disruption during router restarts.

## Configuration

The primary configuration for the BGP LoadBalancer is managed through `infrastructure/cilium-bgp/bgp-policy-legacy.yaml` and `infrastructure/cilium-pools/loadbalancer-pools.yaml`.

### `bgp-policy-legacy.yaml`

This file defines the `CiliumBGPPeeringPolicy` which includes:

- **`localASN`**: The cluster's ASN (e.g., `64512`).
- **`neighbors`**: Configuration for BGP peers (e.g., UDM Pro's IP and ASN `64513`).
- **`virtualRouters`**: Multiple entries, each defining:
  - `serviceSelector`: Labels to match services for this virtual router (e.g., `io.cilium/lb-ipam-pool: "bgp-default"`).
  - `serviceAdvertisements`: Specifies `LoadBalancerIP` to advertise service IPs.
  - `exportPodCIDR`: Set to `true` only on one virtual router to avoid duplicate advertisements.

### `loadbalancer-pools.yaml`

This file defines the `CiliumLoadBalancerIPPool` resources, specifying the IP ranges for each pool:

- `bgp-default`: For general services.
- `bgp-ingress`: For ingress controllers.
- `bgp-reserved`: For future use.

## Operational Considerations

### Verifying BGP Status

- Check BGP peering status: `cilium bgp peers`
- View advertised routes: `cilium bgp routes`
- Verify LoadBalancer service IPs: `kubectl get svc -A --field-selector spec.type=LoadBalancer -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,EXTERNAL-IP:.status.loadBalancer.ingress[0].ip,POOL:.metadata.annotations.io\.cilium/lb-ipam-pool"`

### Troubleshooting

- **Missing Advertisements**: If service IPs are not advertised, ensure the `serviceSelector` in `bgp-policy-legacy.yaml` correctly matches the `io.cilium/lb-ipam-pool` label on the service.
- **Peering Issues**: Check network connectivity to the BGP peer and verify ASN configurations.
- **IPAM Conflicts**: Ensure there are no duplicate IP pool definitions or conflicting service selectors.

## Related Files

- [`infrastructure/cilium-bgp/bgp-policy-legacy.yaml`](../../infrastructure/cilium-bgp/bgp-policy-legacy.yaml) - Main BGP peering policy.
- [`infrastructure/cilium-pools/loadbalancer-pools.yaml`](../../infrastructure/cilium-pools/loadbalancer-pools.yaml) - LoadBalancer IP pool definitions.
- [`infrastructure/cilium/helmrelease-bgp-only.yaml`](../../infrastructure/cilium/helmrelease-bgp-only.yaml) - Cilium CNI configuration.

Please ensure this file is created with the exact content provided. After creation, use the `attempt_completion` tool to report the successful creation of the file.
