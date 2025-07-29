# BGP-Only Load Balancer Migration Guide

This document provides a comprehensive guide for migrating from L2 announcements to BGP-only load balancer architecture in the Talos GitOps home-ops cluster.

## Overview

### Problem Statement

The current cluster uses L2 announcements (`CiliumL2AnnouncementPolicy`) on the same network segment (172.29.51.0/24) as cluster nodes, causing:

- **ARP Conflicts**: Load balancer IPs compete with node IPs for ARP table entries
- **Network Topology Confusion**: L2 announcements cause switching fabric confusion
- **Single Point of Failure**: L2 announcements provide failover, not true load balancing
- **BGP vs L2 Conflict**: Competing announcement mechanisms create instability

### Solution Architecture

**New Architecture**: Dedicated BGP-announced network segment (172.29.52.0/24) for load balancer services, eliminating L2 announcements entirely.

## Network Architecture Changes

### Current vs New IP Allocation

| Component          | Current (172.29.51.0/24) | New (172.29.52.0/24)        |
| ------------------ | ------------------------ | --------------------------- |
| Cluster VIP        | 172.29.51.10             | 172.29.51.10 (unchanged)    |
| Node IPs           | 172.29.51.11-13          | 172.29.51.11-13 (unchanged) |
| Load Balancer Pool | 172.29.51.100-199        | 172.29.52.100-199           |
| Ingress Pool       | 172.29.51.200-220        | 172.29.52.200-220           |
| Reserved Pool      | N/A                      | 172.29.52.50-99             |

### IPv6 Changes

| Component          | Current                     | New                         |
| ------------------ | --------------------------- | --------------------------- |
| Load Balancer Pool | fd47:25e1:2f96:51:100::/120 | fd47:25e1:2f96:52:100::/120 |

## Migration Process

### Prerequisites

1. **Network Infrastructure**
   - VLAN 52 (172.29.52.0/24) configured on UDM Pro
   - IPv6 ULA segment: fd47:25e1:2f96:52::/64
   - BGP peering configured between cluster and UDM Pro

2. **Cluster Access**
   - kubectl access to the cluster
   - Flux GitOps operational
   - All required tools installed (mise, talosctl, etc.)

### Phase 1: Pre-Migration Preparation

1. **Backup Current Configuration**

   ```bash
   # Automated backup via migration script
   ./scripts/migrate-to-bgp-only-loadbalancer.sh
   ```

2. **Validate Network Setup**

   ```bash
   # Test connectivity to new network segment
   ping 172.29.52.1
   ```

3. **Update UDM Pro BGP Configuration**
   - Upload `scripts/unifi-bgp-config-bgp-only.conf`
   - Via UniFi Network UI: Network > Settings > Routing > BGP

### Phase 2: Configuration Migration

#### Step 1: Deploy New Load Balancer Pools

```bash
kubectl apply -f infrastructure/cilium/loadbalancer-pool-bgp.yaml
```

**New Pools Created:**

- `bgp-default`: 172.29.52.100-199 (100 IPs)
- `bgp-ingress`: 172.29.52.200-220 (21 IPs)
- `bgp-reserved`: 172.29.52.50-99 (50 IPs)
- `bgp-default-ipv6`: fd47:25e1:2f96:52:100::/120

#### Step 2: Update BGP Policy

```bash
kubectl apply -f infrastructure/cilium-bgp/bgp-policy-bgp-only.yaml
```

**Key Changes:**

- Enhanced BGP advertisements with communities
- Improved peer configuration
- IPv4/IPv6 dual-stack support

#### Step 3: Update Cilium Configuration

```bash
# Replace current Cilium Helm release
cp infrastructure/cilium/helmrelease-bgp-only.yaml infrastructure/cilium/helmrelease.yaml
git add infrastructure/cilium/helmrelease.yaml
git commit -m "feat: migrate to BGP-only load balancer"
git push
```

**Critical Changes:**

- `l2announcements.enabled: false` (disables L2 announcements)
- `bgpControlPlane.enabled: true` (enables BGP control plane)
- Optimized load balancer configuration

#### Step 4: Remove L2 Policies

```bash
kubectl delete ciliuml2announcementpolicy --all -n kube-system
kubectl delete ciliumloadbalancerippool default ingress default-ipv6-pool -n kube-system
```

### Phase 3: Service Migration

#### Automatic Service Migration

Services will automatically receive new IPs from the BGP pools:

```bash
# Update service labels to use new pools
kubectl patch svc <service-name> -n <namespace> -p '{"metadata":{"labels":{"io.cilium/lb-ipam-pool":"default"}}}'
```

#### Ingress Controller Migration

```bash
# Update ingress controllers to use ingress pool
kubectl patch svc -n ingress-nginx-internal -l app.kubernetes.io/name=ingress-nginx \
  -p '{"metadata":{"labels":{"io.cilium/lb-ipam-pool":"ingress"}}}'
```

### Phase 4: Validation

#### Automated Validation

```bash
./scripts/validate-bgp-loadbalancer.sh
```

#### Manual Validation Steps

1. **Verify BGP Configuration**

   ```bash
   kubectl get ciliumbgpclusterconfig -o wide
   kubectl get ciliumbgpadvertisement -o wide
   ```

2. **Check Load Balancer Pools**

   ```bash
   kubectl get ciliumloadbalancerippool -o wide
   ```

3. **Verify Service IPs**

   ```bash
   kubectl get svc --all-namespaces -o wide | grep LoadBalancer
   ```

4. **Test Connectivity**

   ```bash
   # Test each service IP
   curl -I http://<service-ip>:<port>
   ```

5. **Verify BGP Peering**

   ```bash
   ssh unifi-admin@udm-pro "vtysh -c 'show bgp summary'"
   ```

## Configuration Files

### New Configuration Files

1. **`infrastructure/cilium/loadbalancer-pool-bgp.yaml`**
   - BGP-only load balancer IP pools
   - Dedicated network segment (172.29.52.0/24)
   - IPv4/IPv6 dual-stack support

2. **`infrastructure/cilium-bgp/bgp-policy-bgp-only.yaml`**
   - Enhanced BGP advertisements
   - Community tagging for route identification
   - Improved peer configuration

3. **`infrastructure/cilium/helmrelease-bgp-only.yaml`**
   - L2 announcements disabled
   - BGP control plane enabled
   - Optimized for BGP-only operation

4. **`scripts/unifi-bgp-config-bgp-only.conf`**
   - UDM Pro BGP configuration
   - Route maps and prefix lists
   - IPv4/IPv6 dual-stack support

### Migration Scripts

1. **`scripts/migrate-to-bgp-only-loadbalancer.sh`**
   - Automated migration process
   - Backup and rollback capabilities
   - Comprehensive validation

2. **`scripts/validate-bgp-loadbalancer.sh`**
   - Post-migration validation
   - Connectivity testing
   - Configuration verification

## Rollback Procedures

### Automated Rollback

```bash
./scripts/migrate-to-bgp-only-loadbalancer.sh --rollback
```

### Manual Rollback Steps

1. **Restore Original Configuration**

   ```bash
   kubectl apply -f backups/bgp-migration-<timestamp>/current-loadbalancer-pools.yaml
   kubectl apply -f backups/bgp-migration-<timestamp>/current-l2-policies.yaml
   kubectl apply -f backups/bgp-migration-<timestamp>/current-cilium-helmrelease.yaml
   ```

2. **Update DNS Records**
   - Revert DNS records to original IP addresses
   - Wait for DNS propagation

3. **Verify Service Accessibility**
   - Test all services with original IPs
   - Monitor for connectivity issues

## Post-Migration Tasks

### DNS Updates

Update DNS records for all services to point to new IP addresses:

```bash
# Example DNS updates needed
longhorn.k8s.home.geoffdavis.com -> 172.29.52.xxx
grafana.k8s.home.geoffdavis.com -> 172.29.52.xxx
prometheus.k8s.home.geoffdavis.com -> 172.29.52.xxx
```

### Monitoring Updates

1. **Update Monitoring Dashboards**
   - Modify Grafana dashboards for new IP ranges
   - Update Prometheus targets if using static configuration

2. **Update Alerting Rules**
   - Modify alert rules that reference specific IP addresses
   - Update network monitoring for new IP ranges

### Documentation Updates

1. **Update Network Documentation**
   - Document new IP allocation scheme
   - Update network diagrams

2. **Update Operational Procedures**
   - Modify troubleshooting guides
   - Update service access documentation

## Troubleshooting

### Common Issues

1. **Services Not Getting IPs**

   ```bash
   # Check load balancer pools
   kubectl get ciliumloadbalancerippool -o wide

   # Check service labels
   kubectl get svc <service-name> -o yaml | grep labels -A 10
   ```

2. **BGP Peering Issues**

   ```bash
   # Check BGP configuration
   kubectl get ciliumbgpclusterconfig -o yaml

   # Verify UDM Pro BGP status
   ssh unifi-admin@udm-pro "vtysh -c 'show bgp summary'"
   ```

3. **Connectivity Issues**

   ```bash
   # Test network connectivity
   ping 172.29.52.1

   # Check routing
   ip route show | grep 172.29.52
   ```

### Diagnostic Commands

```bash
# Cilium BGP status
kubectl exec -n kube-system -l k8s-app=cilium -- cilium bgp routes

# Service endpoints
kubectl get endpoints --all-namespaces

# Load balancer IP allocation
kubectl get svc --all-namespaces -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,TYPE:.spec.type,EXTERNAL-IP:.status.loadBalancer.ingress[0].ip
```

## Benefits of BGP-Only Architecture

1. **Clean Network Separation**
   - Load balancer traffic isolated from cluster management
   - Eliminates ARP conflicts and L2/L3 boundary confusion

2. **True Load Balancing**
   - BGP provides actual load balancing across multiple nodes
   - Better failover and traffic distribution

3. **Scalability**
   - Dedicated /24 network provides 254 usable IPs
   - Easy to expand with additional network segments

4. **Operational Simplicity**
   - Single announcement mechanism (BGP only)
   - Consistent with enterprise networking practices

5. **Performance Improvements**
   - Reduced network overhead
   - Better traffic engineering capabilities

## Maintenance

### Regular Checks

1. **Weekly BGP Health Check**

   ```bash
   ./scripts/validate-bgp-loadbalancer.sh
   ```

2. **Monthly IP Utilization Review**

   ```bash
   kubectl get ciliumloadbalancerippool -o yaml | grep -A 5 -B 5 "start\|stop"
   ```

3. **Quarterly Network Architecture Review**
   - Review IP allocation efficiency
   - Plan for capacity expansion if needed

### Capacity Planning

- **Current Capacity**: 171 usable IPs (50 reserved + 100 default + 21 ingress)
- **Expansion Options**: Additional /24 networks (172.29.53.0/24, etc.)
- **IPv6 Capacity**: Virtually unlimited with /120 allocation

This migration provides a robust, scalable foundation for load balancer services while eliminating the issues inherent in L2 announcement architectures.
