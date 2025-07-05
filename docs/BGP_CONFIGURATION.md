# BGP Configuration for UniFi UDM Pro

This document provides instructions for configuring BGP peering between the Talos Kubernetes cluster and UniFi UDM Pro router.

## Overview

The Talos cluster uses Cilium CNI with BGP for LoadBalancer service IP advertisement. The cluster supports dual-stack IPv4/IPv6 with BGP peering to the UniFi UDM Pro router.

**Network Configuration:**
- **Cluster ASN**: 64512
- **UDM Pro ASN**: 64513
- **IPv4 LoadBalancer Pool**: 172.29.51.100-172.29.51.127
- **IPv6 LoadBalancer Pool**: fd47:25e1:2f96:51:100::/120
- **VLAN**: 51 (following your ULA pattern)

## Network Architecture

```
┌─────────────────────────────────────────┐    BGP Peering    ┌─────────────────────────────────────────┐
│  Talos Cluster (ASN: 64512)             │ <────────────────> │  UniFi UDM Pro (ASN: 64513)             │
│                                         │                    │                                         │
│  IPv4:                                  │                    │  IPv4:                                  │
│  - Nodes: 172.29.51.11-13              │                    │  - Gateway: 172.29.51.1                │
│  - Pods: 10.244.0.0/16                 │                    │  - LoadBalancer Pool: 172.29.51.100/25 │
│  - Services: 10.96.0.0/12              │                    │                                         │
│  - LoadBalancer: 172.29.51.100/25      │                    │  IPv6:                                  │
│                                         │                    │  - Gateway: fd47:25e1:2f96:51::1       │
│  IPv6:                                  │                    │  - LoadBalancer Pool:                  │
│  - Nodes: fd47:25e1:2f96:51::11-13     │                    │    fd47:25e1:2f96:51:100::/120         │
│  - Pods: fd47:25e1:2f96:51:2000::/64   │                    │                                         │
│  - Services: fd47:25e1:2f96:51:1000::/108 │                 │                                         │
│  - LoadBalancer: fd47:25e1:2f96:51:100::/120 │              │                                         │
└─────────────────────────────────────────┘                    └─────────────────────────────────────────┘
```

## Configuration Methods

### Method 1: Configuration File Upload (Recommended)

Modern UniFi UDM Pro releases support direct BGP configuration file uploads through the UniFi Network UI.

#### Step 1: Access the Configuration File

The BGP configuration file is located at:
```
talos-gitops/scripts/unifi-bgp-config.conf
```

#### Step 2: Upload Configuration

1. **Open UniFi Network UI**
   - Navigate to your UniFi Network interface
   - Typically `https://unifi.ui.com` or local controller IP

2. **Navigate to BGP Settings**
   - Go to **Network** > **Settings** > **Routing** > **BGP**

3. **Upload Configuration**
   - Click **Upload Configuration** or **Import Configuration**
   - Select the file: `scripts/unifi-bgp-config.conf`
   - Click **Upload** or **Import**

4. **Apply Configuration**
   - Review the imported configuration
   - Click **Apply** or **Save Changes**
   - The UDM Pro will apply the BGP configuration

#### Step 3: Verify Configuration

Use the Task command to verify:
```bash
task bgp:verify-peering
```

### Method 2: SSH Script (Legacy)

For older UniFi UDM Pro releases or manual configuration preference.

#### Step 1: Execute Script

```bash
task bgp:configure-unifi
```

This will:
- Copy the configuration script to the UDM Pro
- Execute the script via SSH
- Configure BGP using FRRouting (FRR)

#### Step 2: Verify Configuration

```bash
task bgp:verify-peering
```

## Configuration Details

### BGP Configuration Elements

The simplified configuration includes:

1. **Router Configuration**
   - BGP ASN: 64513 (UDM Pro)
   - Router ID: 172.29.51.1

2. **IPv4 BGP Neighbors**
   - 172.29.51.11 (talos-node-1) - ASN 64512
   - 172.29.51.12 (talos-node-2) - ASN 64512
   - 172.29.51.13 (talos-node-3) - ASN 64512

3. **IPv6 BGP Neighbors**
   - fd47:25e1:2f96:51::11 (talos-node-1) - ASN 64512
   - fd47:25e1:2f96:51::12 (talos-node-2) - ASN 64512
   - fd47:25e1:2f96:51::13 (talos-node-3) - ASN 64512

4. **Address Families**
   - IPv4 unicast: Activated for all IPv4 neighbors
   - IPv6 unicast: Activated for all IPv6 neighbors

**Note**: This simplified configuration focuses on essential BGP peering compatible with UniFi's FRR BGP format. UniFi will handle route advertisement and filtering automatically. Advanced features like route maps and prefix lists can be configured through the UniFi UI if needed.

### Cluster-Side Configuration

The Talos cluster BGP configuration is managed by Cilium:

- **File**: `infrastructure/cilium/bgp-policy.yaml`
- **CiliumBGPClusterConfig**: Defines cluster-wide BGP settings
- **CiliumBGPPeerConfig**: Defines UDM Pro as BGP peer

## Troubleshooting

### Verify BGP Status

1. **Check BGP Peering Status**
   ```bash
   task bgp:verify-peering
   ```

2. **Check Cluster BGP Status**
   ```bash
   task cluster:status
   ```

3. **Check Individual Node BGP Status**
   ```bash
   kubectl get ciliumbgpclusterconfig
   kubectl get ciliumbgppeerconfig
   ```

### Common Issues

#### BGP Neighbors Not Establishing

**Symptoms**: BGP peers show as "Idle" or "Active"

**Solutions**:
1. Verify network connectivity between nodes and UDM Pro
2. Check firewall rules on UDM Pro
3. Ensure BGP port 179 is open
4. Verify IP addresses in configuration

#### LoadBalancer IPs Not Advertised

**Symptoms**: LoadBalancer services get IPs but are not reachable

**Solutions**:
1. Check Cilium LoadBalancer pool configuration
2. Verify BGP policy allows the IP range
3. Check route maps and prefix lists
4. Ensure LoadBalancer pool matches BGP advertisement range

#### Configuration Upload Fails

**Symptoms**: UniFi UI rejects configuration file

**Solutions**:
1. Verify UniFi UDM Pro firmware version supports BGP config upload
2. Check configuration file syntax
3. Try SSH script method instead
4. Restart UniFi Network application

### Debug Commands

#### On UDM Pro (via SSH)

```bash
# Check BGP summary
vtysh -c "show bgp summary"

# Check BGP neighbors
vtysh -c "show bgp neighbors"

# Check advertised routes
vtysh -c "show bgp ipv4 unicast advertised-routes"

# Check received routes
vtysh -c "show bgp ipv4 unicast received-routes"

# Show running configuration
vtysh -c "show running-config"
```

#### On Talos Cluster

```bash
# Check Cilium BGP status
kubectl get ciliumbgpclusterconfig -o yaml
kubectl get ciliumbgppeerconfig -o yaml

# Check LoadBalancer pool
kubectl get ciliumbgppeeringpolicy -o yaml

# Check Cilium agent logs
kubectl logs -n kube-system -l k8s-app=cilium -f
```

## Task Commands Reference

```bash
# View BGP configuration file
task bgp:show-config

# Generate/display upload instructions
task bgp:generate-config

# Configure via SSH (legacy method)
task bgp:configure-unifi

# Verify BGP peering
task bgp:verify-peering

# Check overall cluster status
task cluster:status
```

## Security Considerations

1. **SSH Access**: Ensure SSH access to UDM Pro is properly secured
2. **BGP Authentication**: Consider enabling BGP MD5 authentication for production
3. **Route Filtering**: Prefix lists and route maps provide route filtering
4. **Network Segmentation**: BGP peering should be on management network

## References

- [Cilium BGP Documentation](https://docs.cilium.io/en/latest/network/bgp/)
- [UniFi UDM Pro BGP Configuration](https://help.ui.com/hc/en-us/articles/360061133113)
- [FRRouting BGP Documentation](https://docs.frrouting.org/en/latest/bgp.html)
- [Talos Kubernetes BGP Guide](https://www.talos.dev/latest/kubernetes-guides/network/bgp/)