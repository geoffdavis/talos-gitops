# Current Context: Talos GitOps Home-Ops Cluster

## Current Work Focus

**BGP LoadBalancer Migration (COMPLETED)**: Major networking architecture migration from L2 announcements to BGP-only load balancer architecture successfully completed. BGP peering established between cluster (ASN 64512) and UDM Pro (ASN 64513) with working route advertisement and full service accessibility.

**Current Status**:
- ✅ BGP peering established and stable
- ✅ Cilium v1.17.6 deployed with XDP disabled for Mac mini compatibility
- ✅ LoadBalancer IPAM working (services getting IPs from BGP pools)
- ✅ **RESOLVED**: BGP routes successfully advertised using legacy CiliumBGPPeeringPolicy schema
- ✅ Schema compatibility issues resolved by switching from newer CRDs to legacy configuration
- ✅ All services accessible via BGP-advertised IPs (Longhorn: 172.29.52.100, Ingress: 172.29.52.200)

**Service Authentication Resolution (COMPLETED)**: Services at *.k8s.home.geoffdavis.com authentication issues have been successfully resolved. The root cause was conflicting ingress configurations between individual service ingresses and the embedded outpost ingress, not API token issues as initially suspected.

## Recent Changes

### BGP LoadBalancer Migration (COMPLETED - January 2025)
- **BGP Peering Success**: Established stable BGP peering between cluster nodes (ASN 64512) and UDM Pro (ASN 64513)
- **Cilium v1.17.6 Deployment**: Upgraded from v1.16.1 with XDP disabled for Mac mini compatibility
- **LoadBalancer IPAM Operational**: Services successfully getting external IPs from BGP pools (172.29.52.x range)
- **Architecture Migration**: Successfully moved from L2 announcements to BGP-only load balancer architecture
- **Root Cause Resolution**: Schema compatibility issues resolved by switching to legacy CiliumBGPPeeringPolicy
- **Route Advertisement Working**: BGP routes successfully advertised and services accessible from network
- **Network Separation**: Cluster management on VLAN 51 (172.29.51.x), load balancer IPs on VLAN 52 (172.29.52.x)
- **Service Accessibility**: All services accessible via BGP IPs (Longhorn: 172.29.52.100, Ingress: 172.29.52.200)

### Service Authentication Resolution (COMPLETED)
- **Root Cause Identified**: Conflicting ingress configurations between individual service ingresses and embedded outpost
- **Architecture Confirmed**: Embedded outpost with forward auth runs within authentik-server pods
- **Configuration Fixes Applied**:
  - Embedded outpost configuration job completed successfully
  - All 6 proxy providers created (dashboard, longhorn, hubble, grafana, prometheus, alertmanager)
  - Conflicting individual service ingresses removed
  - Service configuration fixes (Grafana service name, port configurations)
  - Network connectivity verified between authentik namespace and service namespaces

### Identity Management Implementation (FULLY OPERATIONAL)
- **Authentik Deployment**: Complete identity provider setup with PostgreSQL backend
- **Outpost Configuration**: Embedded outpost fully operational with proper proxy provider configuration
- **External Secrets Integration**: Automated credential management through 1Password Connect
- **Service Integration**: All *.k8s.home.geoffdavis.com services properly authenticated via embedded outpost

### Infrastructure Stability
- **LLDPD Configuration**: Integrated into main Talos config to prevent periodic reboots
- **Bootstrap Process**: Phased bootstrap system with resumable deployment stages
- **Safety Procedures**: Enhanced cluster reset procedures that preserve OS installation
- **USB SSD Storage**: Optimized configuration for Samsung Portable SSD T5 devices

### Network Architecture
- **Dual-Stack IPv6**: Full IPv4/IPv6 support with proper CIDR allocation
- **BGP LoadBalancer Migration**: Hybrid L2/BGP architecture with successful peering but route advertisement issues
- **Cilium v1.17.6**: Upgraded CNI with XDP disabled for Mac mini compatibility and LoadBalancer IPAM enabled
- **Network Segmentation**: Management traffic on VLAN 51, load balancer IPs on VLAN 52
- **DNS Automation**: External DNS management for both internal and external domains
- **Cloudflare Tunnel**: Secure external access without port forwarding

## Current State

### Operational Status
- **Cluster Health**: All-control-plane setup running on 3 Intel Mac mini devices
- **Storage**: Longhorn distributed storage across 3x 1TB USB SSDs
- **Networking**: Cilium v1.17.6 CNI with BGP peering established and route advertisement working
- **Security**: 1Password Connect managing all cluster secrets
- **GitOps**: Flux v2.4.0 managing infrastructure and application deployments

### Active Components
- **Bootstrap Phase**: Talos OS, Kubernetes cluster, Cilium CNI core, 1Password Connect, External Secrets, Flux system
- **GitOps Phase**: Infrastructure services (cert-manager, ingress-nginx, monitoring), Authentik identity provider, Longhorn storage, BGP configuration

### Service Authentication Status (RESOLVED)
- **Backend Services**: All running properly (Dashboard, Hubble UI, Longhorn, Grafana, Prometheus, AlertManager)
- **Service Endpoints**: All have proper endpoints and are discoverable
- **Ingress Configuration**: Embedded outpost ingress handling all *.k8s.home.geoffdavis.com domains
- **Authentication System**: Embedded outpost fully operational with all proxy providers configured
- **Network Connectivity**: Verified clear network path between authentik namespace and service namespaces

### Resolution Findings (COMPLETED)
- **Root Cause**: Conflicting ingress configurations between individual service ingresses and embedded outpost
- **Architecture Validated**: Embedded outpost with forward auth (runs within authentik-server pods)
- **Configuration Success**: All 6 proxy providers created and operational
- **Network Path Clear**: Only embedded outpost handling *.k8s.home.geoffdavis.com domains
- **Service Integration**: All services properly authenticated and accessible

## Next Steps

### Immediate Priorities
1. **BGP Monitoring Enhancement**: Implement comprehensive monitoring for BGP peering health and route advertisement status
2. **Documentation Maintenance**: Keep BGP LoadBalancer operational documentation updated
3. **Performance Optimization**: Monitor and optimize BGP-based load balancer performance
4. **Backup Procedures**: Ensure BGP configuration is properly backed up and recoverable

### Planned Improvements
1. **Automated Configuration**: Improve automated proxy provider setup to reduce manual configuration needs
2. **Service Integration**: Streamline process for adding new authenticated services
3. **Monitoring Enhancement**: Expand cluster observability with authentication-specific metrics
4. **Security Hardening**: Implement additional RBAC and network policies

## Key Operational Patterns

### Bootstrap vs GitOps Decision Framework
- **Bootstrap Phase**: Use for system-level changes, node configuration, core networking, secret management foundation
- **GitOps Phase**: Use for application deployments, infrastructure services, operational configuration, scaling operations

### Daily Operations
- **Health Checks**: `task cluster:status` for overall cluster health
- **GitOps Monitoring**: `flux get kustomizations` for deployment status
- **Application Updates**: Git commits to trigger automated deployments
- **Infrastructure Changes**: Version-controlled modifications through Git

### Emergency Procedures
- **Safe Reset**: `task cluster:safe-reset` preserves OS, wipes only user data
- **Recovery**: `task cluster:emergency-recovery` for systematic troubleshooting
- **Network Issues**: `task apps:deploy-cilium` for CNI problems

## Current Challenges

### Network Architecture Maintenance
- **BGP Health Monitoring**: Ongoing monitoring of BGP peering status and route advertisement
- **Schema Compatibility**: Maintain legacy CiliumBGPPeeringPolicy for Cilium v1.17.6 compatibility
- **Service Accessibility**: Ensure continued accessibility of all BGP-advertised services
- **Network Documentation**: Keep BGP LoadBalancer documentation current with operational changes

### Operational Excellence
- **BGP Monitoring**: Implement comprehensive monitoring for BGP peering health and route advertisement status
- **Network Architecture**: Maintain BGP-only load balancer architecture and troubleshooting procedures
- **Service Integration**: Streamline process for adding new authenticated services to prevent configuration conflicts
- **Automation**: Improve automated configuration to reduce manual intervention needs

### Ongoing Monitoring
- **BGP Health**: Monitor BGP peering status, route advertisement, and load balancer IP assignment
- **Authentication Health**: Monitor Authentik token validity and outpost connectivity
- **Service Availability**: Track service access and authentication response times
- **Storage Capacity**: Monitoring USB SSD usage and planning for expansion
- **Update Management**: Balancing automated updates with stability requirements

### Technical Debt
- **BGP Monitoring**: Implement automated monitoring and alerting for BGP health
- **Network Documentation**: Keep BGP LoadBalancer documentation updated with operational changes
- **Configuration Validation**: Implement checks to prevent conflicting ingress configurations
- **Testing Coverage**: Add comprehensive tests for BGP functionality and authentication system integrity

This context reflects a mature, operational cluster with sophisticated GitOps workflows and strong operational practices. The service authentication system is **fully resolved and operational** with all services properly authenticated via the embedded outpost architecture. The **BGP LoadBalancer migration is complete and successful** with working route advertisement and full service accessibility via BGP-only load balancer architecture.