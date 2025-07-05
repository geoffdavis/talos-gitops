# IPv6 Configuration Guide

This guide covers the IPv6 dual-stack configuration for the Talos Kubernetes cluster, integrating with your existing ULA addressing scheme.

## IPv6 Network Architecture

### Your Existing ULA Scheme
- **Base ULA Prefix**: `fd47:25e1:2f96::/48`
- **VLAN Pattern**: `fd47:25e1:2f96:<VLAN_ID>::/64`
- **Cluster VLAN**: 51
- **Cluster IPv6 Network**: `fd47:25e1:2f96:51::/64`

### IPv6 Address Allocation

```
fd47:25e1:2f96:51::/64 (VLAN 51 - Kubernetes Cluster)
├── fd47:25e1:2f96:51::1           (UDM Pro Gateway)
├── fd47:25e1:2f96:51::11-13       (Talos Nodes)
├── fd47:25e1:2f96:51:1000::/108   (Kubernetes Services)
├── fd47:25e1:2f96:51:2000::/64    (Kubernetes Pods)
└── fd47:25e1:2f96:51:100::/120    (LoadBalancer Pool)
```

## Configuration Components

### 1. Talos Cluster Configuration

The cluster is configured with dual-stack subnets:

```yaml
# talos/patches/cluster.yaml
cluster:
  network:
    podSubnets:
      - 10.244.0.0/16                          # IPv4 pods
      - fd47:25e1:2f96:51:2000::/64            # IPv6 pods
    serviceSubnets:
      - 10.96.0.0/12                           # IPv4 services
      - fd47:25e1:2f96:51:1000::/108           # IPv6 services
```

### 2. Cilium CNI Configuration

Cilium is configured for dual-stack operation:

```yaml
# infrastructure/cilium/helmrelease.yaml
values:
  enableIPv4: true
  enableIPv6: true
  ipv6:
    enabled: true
```

### 3. LoadBalancer IP Pools

Separate pools for IPv4 and IPv6:

**IPv4 Pool** (`infrastructure/cilium/loadbalancer-pool.yaml`):
```yaml
spec:
  blocks:
  - cidr: 172.29.51.100/25
```

**IPv6 Pool** (`infrastructure/cilium/loadbalancer-pool-ipv6.yaml`):
```yaml
spec:
  blocks:
  - cidr: fd47:25e1:2f96:51:100::/120
```

### 4. BGP Configuration

The UniFi UDM Pro BGP configuration supports both address families with simplified FRR BGP format:

- **IPv4 BGP**: ASN 64512 ↔ ASN 64513
- **IPv6 BGP**: ASN 64512 ↔ ASN 64513
- **IPv6 Neighbors**: `fd47:25e1:2f96:51::11-13`
- **Configuration**: Simplified for UniFi compatibility (essential peering only)

## Benefits of IPv6 Dual-Stack

### 1. **Future-Proofing**
- Native IPv6 support for modern applications
- Preparation for IPv6-only services
- Compatibility with IPv6-native cloud services

### 2. **Network Efficiency**
- Larger address space eliminates NAT complexity
- End-to-end connectivity
- Simplified network topology

### 3. **Integration with Existing Infrastructure**
- Follows your established ULA addressing scheme
- Maintains consistency with VLAN-based network segmentation
- Seamless integration with existing home network

### 4. **Enhanced Security**
- IPSec built into IPv6 protocol
- Simplified firewall rules
- Better network visibility

## Deployment Steps

### 1. Update Network Configuration

Ensure your UDM Pro supports IPv6:

```bash
# Check IPv6 support on UDM Pro
ssh unifi-admin@udm-pro "ip -6 addr show"
```

### 2. Configure Static IPv6 Addresses

Add static IPv6 addresses for cluster nodes in UniFi Network:

- **Node 1**: `fd47:25e1:2f96:51::11`
- **Node 2**: `fd47:25e1:2f96:51::12`
- **Node 3**: `fd47:25e1:2f96:51::13`

### 3. Deploy Dual-Stack Configuration

```bash
# Deploy updated Talos configuration
task talos:generate-config
task talos:apply-config

# Deploy updated Cilium configuration
task apps:deploy-cilium

# Configure BGP with IPv6 support
task bgp:generate-config
# Upload scripts/unifi-bgp-config.conf through UniFi UI
```

### 4. Verify IPv6 Connectivity

```bash
# Check IPv6 addresses on nodes
task network:check-ipv6

# Verify BGP IPv6 peering
task bgp:verify-peering-ipv6

# Test IPv6 LoadBalancer services
kubectl get svc -o wide
```

## IPv6 Service Examples

### 1. Dual-Stack LoadBalancer Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: example-service
spec:
  type: LoadBalancer
  ipFamilyPolicy: PreferDualStack
  ipFamilies:
  - IPv4
  - IPv6
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: example
```

### 2. IPv6-Only Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ipv6-only-service
spec:
  type: LoadBalancer
  ipFamilyPolicy: SingleStack
  ipFamilies:
  - IPv6
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: example
```

## Monitoring and Troubleshooting

### 1. Check IPv6 Connectivity

```bash
# From cluster nodes
ping6 fd47:25e1:2f96:51::1

# From UDM Pro
ping6 fd47:25e1:2f96:51::11
```

### 2. Verify BGP IPv6 Routes

```bash
# On UDM Pro
vtysh -c "show bgp ipv6 unicast summary"
vtysh -c "show bgp ipv6 unicast neighbors"
```

### 3. Check Cilium IPv6 Status

```bash
# Cilium connectivity test
kubectl exec -n kube-system cilium-xxx -- cilium connectivity test --include-conn-disrupt-test=false --test-ipv6

# Check IPv6 routes
kubectl exec -n kube-system cilium-xxx -- cilium bpf lb list
```

### 4. LoadBalancer IPv6 Verification

```bash
# Check LoadBalancer IPs
kubectl get svc -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,IP:.status.loadBalancer.ingress[*].ip

# Test connectivity to IPv6 LoadBalancer
curl -6 http://[fd47:25e1:2f96:51:100::1]:80
```

## Task Commands

Add these IPv6-specific tasks to your workflow:

```bash
# Check IPv6 network configuration
task network:check-ipv6

# Verify IPv6 BGP peering
task bgp:verify-peering-ipv6

# Test IPv6 LoadBalancer services
task test:ipv6-connectivity

# Monitor IPv6 traffic
task monitoring:ipv6-stats
```

## Security Considerations

### 1. **Firewall Rules**
- Configure UDM Pro firewall for IPv6 traffic
- Allow BGP (port 179) for IPv6 neighbors
- Restrict LoadBalancer pool access as needed

### 2. **Network Segmentation**
- IPv6 maintains network isolation
- VLAN-based segmentation continues to work
- Consider IPv6 privacy extensions for client networks

### 3. **Monitoring**
- Monitor IPv6 BGP peering status
- Track IPv6 LoadBalancer IP allocation
- Alert on IPv6 connectivity issues

## Integration with Existing Services

### 1. **DNS**
- Add AAAA records for IPv6 services
- Update external-dns configuration for IPv6
- Consider dual-stack DNS resolution

### 2. **Ingress**
- Configure ingress controllers for IPv6
- Update DNS records for ingress endpoints
- Test IPv6 accessibility from external networks

### 3. **Monitoring**
- Update Prometheus targets for IPv6
- Configure Grafana dashboards for IPv6 metrics
- Monitor IPv6 traffic patterns

## Migration Strategy

### 1. **Phase 1: Infrastructure**
- ✅ Enable IPv6 on network infrastructure
- ✅ Configure BGP dual-stack peering
- ✅ Deploy IPv6 LoadBalancer pools

### 2. **Phase 2: Services**
- Deploy dual-stack services
- Update DNS records
- Test IPv6 connectivity

### 3. **Phase 3: Optimization**
- Monitor IPv6 traffic patterns
- Optimize routing policies
- Consider IPv6-only services where appropriate

This configuration provides a solid foundation for IPv6 deployment while maintaining compatibility with your existing IPv4 infrastructure and network addressing scheme.