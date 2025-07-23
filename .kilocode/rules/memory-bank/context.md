# Current Context: Talos GitOps Home-Ops Cluster

## Current Work Focus

The cluster is in operational state with **completed** identity management and authentication integration. All services at *.k8s.home.geoffdavis.com now properly redirect to Authentik for authentication with fully functional SSO integration.

## Recent Changes

### Identity Management Implementation (COMPLETED)
- **Authentik Deployment**: Complete identity provider setup with PostgreSQL backend
- **Outpost Configuration**: Successfully resolved token management and embedded outpost architecture
- **External Secrets Integration**: Automated credential management through 1Password Connect
- **Ingress Security**: All internal services now properly secured with Authentik authentication
- **Authentication Resolution**: Fixed expired API tokens, standardized ingress classes, and clarified embedded vs RADIUS outpost separation

### Infrastructure Stability
- **LLDPD Configuration**: Integrated into main Talos config to prevent periodic reboots
- **Bootstrap Process**: Phased bootstrap system with resumable deployment stages
- **Safety Procedures**: Enhanced cluster reset procedures that preserve OS installation
- **USB SSD Storage**: Optimized configuration for Samsung Portable SSD T5 devices

### Network Architecture
- **Dual-Stack IPv6**: Full IPv4/IPv6 support with proper CIDR allocation
- **BGP Integration**: Cilium BGP peering with Unifi UDM Pro for load balancer IPs
- **DNS Automation**: External DNS management for both internal and external domains
- **Cloudflare Tunnel**: Secure external access without port forwarding

## Current State

### Operational Status
- **Cluster Health**: All-control-plane setup running on 3 Intel Mac mini devices
- **Storage**: Longhorn distributed storage across 3x 1TB USB SSDs
- **Networking**: Cilium CNI with BGP load balancer IP advertisement
- **Security**: 1Password Connect managing all cluster secrets
- **GitOps**: Flux v2.4.0 managing infrastructure and application deployments

### Active Components
- **Bootstrap Phase**: Talos OS, Kubernetes cluster, Cilium CNI core, 1Password Connect, External Secrets, Flux system
- **GitOps Phase**: Infrastructure services (cert-manager, ingress-nginx, monitoring), Authentik identity provider, Longhorn storage, BGP configuration

### Recent Troubleshooting (RESOLVED)
- **Authentication Issues**: Successfully resolved expired API tokens and outpost configuration problems
- **Ingress Standardization**: Standardized all services to use nginx-internal ingress class
- **Embedded Outpost Architecture**: Clarified and properly implemented embedded outpost vs RADIUS separation
- **Token Management**: Enhanced Authentik API token setup with proper regeneration procedures
- **Credential Handling**: Improved 1Password Connect credential format validation
- **Network Stability**: LLDPD configuration fixes to prevent node reboots
- **Storage Optimization**: USB SSD performance tuning and automatic detection

## Next Steps

### Immediate Priorities
1. **Application Deployment**: Add more home lab services leveraging the now-functional authentication system
2. **Monitoring Enhancement**: Expand Prometheus/Grafana dashboards for cluster observability
3. **Backup Validation**: Test and validate Longhorn backup procedures
4. **Authentication Monitoring**: Implement monitoring for Authentik token health and outpost status

### Planned Improvements
1. **Application Deployment**: Add more home lab services through GitOps
2. **Security Hardening**: Implement additional RBAC and network policies
3. **Performance Optimization**: Fine-tune resource allocation and storage performance
4. **Disaster Recovery**: Test and document complete cluster recovery procedures

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

### Ongoing Monitoring
- **Authentication Health**: Monitor Authentik token validity and outpost connectivity
- **SSO Performance**: Track authentication response times and user experience
- **Storage Capacity**: Monitoring USB SSD usage and planning for expansion
- **Network Performance**: Optimizing BGP advertisement and load balancer distribution
- **Update Management**: Balancing automated updates with stability requirements

### Technical Debt
- **Legacy Configurations**: Some components still use older configuration patterns
- **Documentation Gaps**: Certain operational procedures need better documentation
- **Testing Coverage**: Need more comprehensive disaster recovery testing
- **Monitoring Gaps**: Some services lack detailed observability

This context reflects a mature, operational cluster with sophisticated GitOps workflows and strong operational practices, with **completed** identity management integration and focus now on expanding application deployments and enhancing overall system observability.