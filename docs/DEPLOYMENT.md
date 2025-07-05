# Talos GitOps Deployment Guide

This guide walks you through deploying the complete Talos Kubernetes cluster with GitOps management.

## Prerequisites

1. **Hardware**: 3 Intel Mac mini devices with:
   - Internal disk for OS installation
   - 1TB USB SSD for Longhorn storage
   - Network connectivity to 172.29.51.0/24 subnet

2. **Network Setup**: 
   - Unifi UDM Pro at 172.29.51.1
   - Cluster VIP at 172.29.51.10
   - Node IPs: 172.29.51.11, 172.29.51.12, 172.29.51.13

3. **External Services**:
   - 1Password account with CLI access
   - Cloudflare account with API token
   - GitHub account for GitOps repository

## Step 1: Initial Setup

1. Install required tools:
   ```bash
   # Install mise for tool management
   curl https://mise.run | sh
   
   # Install tools
   mise install
   ```

2. Setup 1Password CLI:
   ```bash
   # Sign in to 1Password
   op signin
   
   # Verify access
   op account list
   ```

3. Bootstrap secrets:
   ```bash
   task bootstrap:secrets
   ```

## Step 2: Talos Configuration

1. Generate Talos configuration with secrets:
   ```bash
   task talos:generate-config
   ```

2. Boot each Mac mini with Talos ISO and apply configuration:
   ```bash
   # Apply to each node
   task talos:apply-config
   ```

3. Bootstrap the cluster:
   ```bash
   task talos:bootstrap
   ```

4. Verify cluster is running:
   ```bash
   kubectl get nodes
   ```

## Step 3: Configure BGP Peering

1. Configure Unifi UDM Pro for BGP:
   ```bash
   task bgp:configure-unifi
   ```

2. Verify BGP peering:
   ```bash
   # On UDM Pro
   vtysh -c "show bgp summary"
   
   # Check Cilium BGP status
   cilium bgp peers
   ```

## Step 4: GitOps Bootstrap

1. Initialize Flux:
   ```bash
   task flux:bootstrap
   ```

2. Wait for core infrastructure to deploy:
   ```bash
   # Monitor deployment
   flux get kustomizations --watch
   
   # Check pods
   kubectl get pods -A
   ```

## Step 5: Verification

1. Run comprehensive tests:
   ```bash
   task test:all
   ```

2. Verify services are accessible:
   - Longhorn UI: https://longhorn.homelab.local
   - Grafana: https://grafana.homelab.local
   - Prometheus: https://prometheus.homelab.local
   - Kubernetes Dashboard: https://dashboard.homelab.local

## Step 6: Post-Deployment Configuration

1. Configure monitoring dashboards in Grafana
2. Set up alerting rules in Prometheus
3. Configure backup destinations in Longhorn
4. Review and adjust resource limits as needed

## Troubleshooting

### Common Issues

1. **BGP not establishing**:
   - Check Unifi firewall rules
   - Verify Cilium BGP configuration
   - Check network connectivity between nodes and UDM Pro

2. **Pods stuck in Pending**:
   - Check Longhorn storage provisioning
   - Verify node resources
   - Check for scheduling constraints

3. **External DNS not updating**:
   - Verify Cloudflare API token
   - Check external-dns logs
   - Ensure domain is properly configured

4. **Certificates not issuing**:
   - Check cert-manager logs
   - Verify Cloudflare DNS API access
   - Check cluster issuer configuration

### Useful Commands

```bash
# Check cluster status
task cluster:status

# View logs for troubleshooting
kubectl logs -n flux-system -l app=source-controller
kubectl logs -n cilium-system -l k8s-app=cilium
kubectl logs -n longhorn-system -l app=longhorn-manager

# Force reconciliation
task flux:reconcile

# Backup cluster state
task maintenance:backup
```

## Maintenance

### Regular Tasks

1. **Weekly**:
   - Review monitoring alerts
   - Check storage usage
   - Verify backup integrity

2. **Monthly**:
   - Update tool versions in `.mise.toml`
   - Review and rotate secrets
   - Update Helm chart versions

3. **Quarterly**:
   - Upgrade Talos version
   - Review and update security policies
   - Disaster recovery testing

### Upgrade Process

1. **Talos Upgrade**:
   ```bash
   task talos:upgrade
   ```

2. **Application Updates**:
   ```bash
   # Update Helm charts in infrastructure/*/helmrelease.yaml
   # Commit changes to trigger GitOps update
   git add . && git commit -m "Update charts" && git push
   ```

## Security Considerations

1. **Secrets Management**:
   - All secrets stored in 1Password
   - External Secrets Operator for cluster secrets
   - Regular secret rotation

2. **Network Security**:
   - BGP authentication configured
   - TLS for all ingress traffic
   - Pod security policies enforced

3. **Access Control**:
   - RBAC properly configured
   - Service accounts with minimal permissions
   - Regular audit of access patterns

## Disaster Recovery

1. **Backup Strategy**:
   - Longhorn volume snapshots
   - etcd backups via Talos
   - Configuration stored in Git

2. **Recovery Process**:
   - Restore from Talos bootstrap
   - Redeploy via GitOps
   - Restore data from Longhorn backups

For additional help, see the troubleshooting guides in the `docs/` directory.