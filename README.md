# Home-Ops GitOps Repository

This repository contains the configuration and automation for managing a Talos Kubernetes cluster using GitOps principles for the "home-ops" cluster.

## Overview

- **Cluster Name**: home-ops
- **Internal DNS Domain**: k8s.home.geoffdavis.com
- **External Domain**: geoffdavis.com
- **Architecture**: All-Control-Plane cluster - 3 Intel Mac mini devices functioning as both control plane and worker nodes
- **High Availability**: etcd cluster spans all 3 nodes for maximum resilience
- **Storage**: Internal disks for OS, 1TB USB SSDs for Longhorn storage
- **CNI**: Cilium with BGP peering to Unifi UDM Pro
- **GitOps**: Flux with Kustomize
- **Secrets**: 1Password (local op command + onepassword-connect)
- **Exposure**: Cloudflare Tunnel + Local Ingress
- **Local Network**: Unifi integration, dual-stack IPv4/IPv6
  - **IPv4**: 172.29.51.0/24 (VLAN 51)
  - **IPv6**: fd47:25e1:2f96:51::/64 (ULA, VLAN 51)

## All-Control-Plane Architecture

This cluster is configured with all three nodes functioning as both control plane and worker nodes, providing:

- **Maximum Resource Utilization**: No dedicated worker nodes means all resources available for workloads
- **High Availability**: etcd cluster distributed across all 3 nodes
- **Fault Tolerance**: Cluster remains operational with 1 node failure
- **Simplified Management**: All nodes have identical configuration
- **Better Resilience**: Control plane components distributed across all nodes

For detailed information about the all-control-plane setup, conversion procedures, and troubleshooting, see:
📖 **[All-Control-Plane Setup Guide](docs/ALL_CONTROL_PLANE_SETUP.md)**

## Mac Mini Specific Features

This configuration is optimized for Intel Mac mini devices with:

- **Smart disk selection**: Uses `installDiskSelector` with `model: APPLE*` to automatically find genuine Apple internal storage
- **Hard reboot mode**: Ensures USB devices are properly detected after reboot
- **Siderolabs extensions**:
  - `iscsi-tools`: Required for Longhorn storage
  - `ext-lldpd`: LLDP daemon for network discovery
  - `usb-modem-drivers`: Enhanced USB device support
  - `thunderbolt`: Thunderbolt device support
- **USB SSD support**: External USB SSDs for Longhorn distributed storage
- **Network discovery**: LLDP configuration for network topology visibility

**Storage Layout**:
- **OS**: Apple internal storage (automatically detected by model selector)
- **Longhorn Storage**: External 1TB USB SSDs for distributed storage

## DNS Architecture (Fits Existing Home Domain)

### Internal Access (Home Network)
- **Domain**: `*.k8s.home.geoffdavis.com`
- **Fits with existing**: `iot.home.geoffdavis.com`, `not.home.geoffdavis.com`, `security.home.geoffdavis.com`
- **Ingress IP**: 172.29.51.200
- **TLS**: Let's Encrypt certificates via cert-manager
- **Services**:
  - Longhorn: https://longhorn.k8s.home.geoffdavis.com
  - Grafana: https://grafana.k8s.home.geoffdavis.com
  - Prometheus: https://prometheus.k8s.home.geoffdavis.com
  - AlertManager: https://alertmanager.k8s.home.geoffdavis.com
  - Dashboard: https://dashboard.k8s.home.geoffdavis.com

### External Access (Cloudflare Tunnel)
- **Domain**: `*.geoffdavis.com` (root domain)
- **TLS**: Handled by Cloudflare (no Let's Encrypt needed)
- **Tunnel**: home-ops-tunnel
- **Services Exposed**:
  - Grafana: https://grafana.geoffdavis.com
  - Prometheus: https://prometheus.geoffdavis.com
  - Longhorn: https://longhorn.geoffdavis.com (with auth)
  - Kubernetes Dashboard: https://k8s.geoffdavis.com (secured)
  - AlertManager: https://alerts.geoffdavis.com
  - Hubble UI: https://hubble.geoffdavis.com

## Why This DNS Strategy Works Perfectly

✅ **Fits Existing Infrastructure**: `k8s.home.geoffdavis.com` fits naturally with your existing subdomains

✅ **Complete Separation**: No overlap between internal (`*.k8s.home.geoffdavis.com`) and external (`*.geoffdavis.com`)

✅ **No DNS Conflicts**: Local and external services never conflict in resolution

✅ **Familiar Pattern**: Follows your existing domain structure (iot.home, not.home, security.home, k8s.home)

✅ **Clear Intent**: Domain names clearly indicate internal vs external access

✅ **Future-Proof**: Easy to add more k8s services without conflicting with other home services

## Domain Layout
```
home.geoffdavis.com
├── iot.home.geoffdavis.com          (existing)
├── not.home.geoffdavis.com          (existing)  
├── security.home.geoffdavis.com     (existing)
└── k8s.home.geoffdavis.com          (new - Kubernetes services)
    ├── grafana.k8s.home.geoffdavis.com
    ├── longhorn.k8s.home.geoffdavis.com
    ├── prometheus.k8s.home.geoffdavis.com
    └── dashboard.k8s.home.geoffdavis.com

geoffdavis.com (external via Cloudflare tunnel)
├── grafana.geoffdavis.com
├── prometheus.geoffdavis.com  
├── longhorn.geoffdavis.com
└── k8s.geoffdavis.com
```

## Certificate Strategy

- **Internal Services**: Use Let's Encrypt certificates for `*.k8s.home.geoffdavis.com`
- **External Services**: Cloudflare provides TLS termination at their edge
- **Benefits**: 
  - Simplified certificate management
  - Cloudflare handles certificate renewal for external domains
  - Internal services maintain proper TLS for local access
  - No certificate conflicts or overlap

## Prerequisites

- [mise](https://mise.jdx.dev/) - Tool version management
- [task](https://taskfile.dev/) - Task runner
- [op](https://1password.com/downloads/command-line/) - 1Password CLI
- Cloudflare account with:
  - API tokens for DNS management
  - Cloudflare tunnel configured
  - TLS certificates managed by Cloudflare
- Unifi UDM Pro with SSH access
- 3 Intel Mac mini devices with USB SSDs
- Existing `home.geoffdavis.com` domain setup

## Environment Setup

1. **Create environment file**:
   ```bash
   cp .env.example .env
   ```

2. **Configure 1Password account**:
   Edit `.env` and set your 1Password account:
   ```bash
   OP_ACCOUNT=YourAccountName
   ```

3. **Install tools**:
   ```bash
   mise install
   ```

## Cloudflare Setup

Before deploying, set up your Cloudflare tunnel:

1. **Create Tunnel**:
   ```bash
   cloudflared tunnel create home-ops-tunnel
   ```

2. **Store Credentials in 1Password**:
   - Create item "Cloudflare Tunnel Credentials"
   - Add `credentials.json` field with tunnel credentials
   - Add `tunnel-token` field with tunnel token

3. **Configure DNS Records** in Cloudflare dashboard:
   ```
   # External services (root domain via tunnel)
   grafana.geoffdavis.com → home-ops-tunnel.cfargotunnel.com
   prometheus.geoffdavis.com → home-ops-tunnel.cfargotunnel.com
   longhorn.geoffdavis.com → home-ops-tunnel.cfargotunnel.com
   k8s.geoffdavis.com → home-ops-tunnel.cfargotunnel.com
   alerts.geoffdavis.com → home-ops-tunnel.cfargotunnel.com
   hubble.geoffdavis.com → home-ops-tunnel.cfargotunnel.com
   
   # Internal services (A record to ingress IP)
   *.k8s.home.geoffdavis.com → 172.29.51.200
   ```

4. **Local DNS** (on your existing home network):
   - Your existing setup should already resolve `*.home.geoffdavis.com`
   - Add `*.k8s.home.geoffdavis.com → 172.29.51.200` to your local DNS

## Quick Start

### For New All-Control-Plane Clusters

1. Install dependencies:
   ```bash
   mise install
   ```

2. Bootstrap secrets:
   ```bash
   task bootstrap:secrets
   ```

3. Generate Talos configuration (all-control-plane setup):
   ```bash
   task talos:generate-config
   ```

4. Apply configuration to nodes (ensure DHCP assigns correct IPs):
   ```bash
   task talos:apply-config
   ```

5. Bootstrap cluster:
   ```bash
   task talos:bootstrap
   ```

6. If USB devices aren't detected, perform hard reboot:
   ```bash
   task talos:reboot
   ```

7. Configure BGP on Unifi UDM Pro:
   ```bash
   task bgp:configure-unifi
   ```

8. Deploy GitOps stack:
   ```bash
   task flux:bootstrap
   ```

### Converting Existing Cluster to All-Control-Plane

If you have an existing cluster with dedicated worker nodes:

```bash
task talos:convert-to-all-controlplane
```

This will safely convert all nodes to control plane nodes with proper configuration updates.

## Network Configuration

### DHCP Setup
Configure your Unifi UDM Pro DHCP server to assign static IPs:
- Node 1: 172.29.51.11
- Node 2: 172.29.51.12  
- Node 3: 172.29.51.13
- VIP: 172.29.51.10

### BGP Peering
- **Cluster ASN**: 64512
- **UDM Pro ASN**: 64513
- **IPv4 LoadBalancer Pool**: 172.29.51.100-199
- **IPv6 LoadBalancer Pool**: fd47:25e1:2f96:51:100::/120
- **Ingress IP**: 172.29.51.200 (IPv4)

### IPv6 Dual-Stack Configuration
- **IPv6 Base**: fd47:25e1:2f96:51::/64 (follows your ULA VLAN pattern)
- **Node IPs**: fd47:25e1:2f96:51::11-13
- **Pod Network**: fd47:25e1:2f96:51:2000::/64
- **Service Network**: fd47:25e1:2f96:51:1000::/108
- **Benefits**: Future-proofing, simplified routing, end-to-end connectivity

### DNS Management
- **External DNS**: Manages both geoffdavis.com and k8s.home.geoffdavis.com zones
- **Internal Resolution**: Services resolve to internal IPs with Let's Encrypt TLS
- **External Resolution**: Cloudflare tunnel with Cloudflare-managed TLS
- **Fits Existing Structure**: Integrates seamlessly with your current home domain layout
## BGP Configuration

The cluster uses Cilium BGP to advertise LoadBalancer service IPs. Two methods are available for configuring BGP peering with UniFi UDM Pro:

### Method 1: Configuration File Upload (Recommended)
For newer UniFi UDM Pro releases with BGP configuration upload support:
```bash
task bgp:generate-config
```

### Method 2: SSH Script (Legacy)
For older UniFi UDM Pro releases or manual configuration:
```bash
task bgp:configure-unifi
```

### Verify BGP Peering
```bash
task bgp:verify-peering
```

For detailed BGP configuration instructions, troubleshooting, and network architecture details, see:
📖 **[BGP Configuration Guide](docs/BGP_CONFIGURATION.md)**

For comprehensive IPv6 dual-stack setup and configuration details, see:
📖 **[IPv6 Configuration Guide](docs/IPV6_CONFIGURATION.md)**

## Access Patterns

### Local Development (Home Network)
```bash
# Access internal services directly (fits with your existing pattern)
curl https://grafana.k8s.home.geoffdavis.com
curl https://longhorn.k8s.home.geoffdavis.com

# Your existing services continue to work
curl https://iot.home.geoffdavis.com
curl https://security.home.geoffdavis.com
```

### Remote Access (Internet)
```bash
# Access external services via Cloudflare tunnel
curl https://grafana.geoffdavis.com
curl https://longhorn.geoffdavis.com
```

### No Conflicts with Existing Infrastructure
- Internal k8s services use `k8s.home.geoffdavis.com` subdomain
- Existing services remain on their current subdomains
- External services use root domain via tunnel
- DNS resolution is always unambiguous

## Testing

Run comprehensive tests before deployment:
```bash
task test:all
```

Specific test categories:
```bash
task test:config       # Configuration validation
task test:connectivity # Network connectivity
task test:extensions   # Talos extensions
```

## Troubleshooting

### USB Devices Not Detected
1. Ensure hard reboot mode is configured
2. Run `task talos:reboot` to perform hard reboot
3. Check USB detection with `task network:check-usb`

### Disk Configuration Issues
**Problem**: Talos installation fails with disk not found

**Solutions**:
1. **Default configuration uses smart selection**: The configuration uses `installDiskSelector` with `model: APPLE*` to automatically find genuine Apple internal storage
   ```yaml
   machine:
     install:
       installDiskSelector:
         model: APPLE*  # Automatically selects Apple internal storage
   ```

2. **Verify disk detection**: Boot from Talos ISO and check available disks:
   ```bash
   # From Talos ISO console
   lsblk
   # Look for disks with "APPLE" in the model name
   lsblk -o NAME,SIZE,MODEL
   ```

3. **Alternative selectors** (if needed):
   ```yaml
   # For replaced non-Apple drives, use size selector
   installDiskSelector:
     size: ">= 240GB"  # Select drives larger than 240GB
   
   # Or use specific disk path (last resort)
   disk: /dev/sda
   ```

4. **Benefits of `installDiskSelector`**:
   - Automatically finds Apple internal storage regardless of device path
   - Works even if internal drive has been replaced (with size selector)
   - More reliable than fixed device paths
   - Prevents accidentally installing on USB devices

### DNS Resolution Issues
- **Internal services**: Check Let's Encrypt certificates and internal DNS
- **External services**: Verify Cloudflare tunnel configuration and DNS records
- **Integration**: Ensure k8s.home.geoffdavis.com doesn't conflict with existing home services

### Certificate Issues
- **Internal services**: Check cert-manager logs and Let's Encrypt rate limits
- **External services**: Verify Cloudflare TLS settings and tunnel configuration

## Security

- All secrets managed through 1Password
- TLS certificates: Let's Encrypt for internal, Cloudflare for external
- RBAC properly configured for all components
- Network segmentation via BGP and firewall rules
- External services secured with authentication where appropriate
- Cloudflare provides DDoS protection and edge security
- Integrates securely with existing home network infrastructure

## Maintenance

### Regular Tasks
```bash
task maintenance:backup    # Backup cluster state
task maintenance:cleanup   # Clean up old resources
```

### Updates
```bash
task talos:upgrade        # Upgrade Talos version
task flux:reconcile       # Force GitOps reconciliation
```

## Dependency Management

This repository uses Renovate for automated dependency updates. You can also run Renovate manually:

### Manual Renovate Operations
```bash
# Install Renovate CLI
task renovate:install

# Validate Renovate configuration
task renovate:validate

# Dry-run to see available updates (no changes made)
task renovate:dry-run

# Run Renovate to create actual PRs (use with caution)
task renovate:run
```

### What Renovate Manages
- **Talos OS versions** (manual review required)
- **Helm chart versions** in all HelmRelease files
- **Container images** in all Kubernetes manifests
- **CLI tools** in `.mise.toml` (kubectl, talosctl, flux, etc.)
- **Siderolabs extensions** (auto-merged)
- **Security updates** (prioritized)

Renovate runs automatically on schedule and creates PRs for updates. Check the dependency dashboard issue in your repository for current status.

For detailed deployment instructions, see [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).