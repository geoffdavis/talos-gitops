# Current Context: Talos GitOps Home-Ops Cluster

## Current Work Focus

The cluster is in operational state with a focus on identity management and authentication integration. Recent work has centered around Authentik deployment and outpost configuration for securing cluster services.

## Recent Changes

### Identity Management Implementation
- **Authentik Deployment**: Complete identity provider setup with PostgreSQL backend
- **Outpost Configuration**: Enhanced token management for Kubernetes service authentication
- **External Secrets Integration**: Automated credential management through 1Password Connect
- **Ingress Security**: Authentication proxy configuration for internal services

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

### Recent Troubleshooting
- **Token Management**: Enhanced Authentik API token setup for outpost authentication
- **Credential Handling**: Improved 1Password Connect credential format validation
- **Network Stability**: LLDPD configuration fixes to prevent node reboots
- **Storage Optimization**: USB SSD performance tuning and automatic detection

## Next Steps

### Immediate Priorities
1. **Complete Authentik Integration**: Finalize outpost configuration for all internal services
2. **Monitoring Enhancement**: Expand Prometheus/Grafana dashboards for cluster observability
3. **Backup Validation**: Test and validate Longhorn backup procedures
4. **Documentation Updates**: Ensure operational procedures are current

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
- **Token Rotation**: Ensuring Authentik API tokens remain valid for outpost authentication
- **Storage Capacity**: Monitoring USB SSD usage and planning for expansion
- **Network Performance**: Optimizing BGP advertisement and load balancer distribution
- **Update Management**: Balancing automated updates with stability requirements

### Technical Debt
- **Legacy Configurations**: Some components still use older configuration patterns
- **Documentation Gaps**: Certain operational procedures need better documentation
- **Testing Coverage**: Need more comprehensive disaster recovery testing
- **Monitoring Gaps**: Some services lack detailed observability

This context reflects a mature, operational cluster with sophisticated GitOps workflows and strong operational practices, currently focused on completing identity management integration and enhancing overall system observability.