# Product Overview: Talos GitOps Home-Ops Cluster

## Why This Project Exists

This project provides a production-grade Kubernetes cluster for home network operations, designed to replace traditional server setups with a modern, cloud-native infrastructure. It serves as both a functional home lab and a template for enterprise-grade Kubernetes deployments.

## Problems It Solves

### Infrastructure Management

- **Manual Configuration Drift**: GitOps ensures all infrastructure is declaratively managed and version-controlled
- **Service Reliability**: High-availability setup with distributed storage and automatic failover
- **Security Complexity**: Integrated secret management with 1Password and automated TLS certificate management
- **Network Integration**: Seamless integration with existing home network infrastructure via BGP and DNS automation

### Operational Challenges

- **Cluster Recovery**: Safe reset procedures that preserve OS while allowing complete cluster rebuild
- **Upgrade Management**: Automated dependency updates via Renovate with proper testing workflows
- **Monitoring & Observability**: Comprehensive monitoring stack with Prometheus, Grafana, and Hubble
- **Storage Management**: Distributed storage with automatic replication and backup capabilities

### Development Workflow

- **GitOps Deployment**: All changes tracked in Git with automated deployment via Flux
- **Environment Consistency**: Reproducible infrastructure that can be replicated across environments
- **Collaborative Operations**: Multiple operators can safely make changes through Git workflows

## How It Should Work

### Bootstrap Phase (System Foundation)

1. **Talos OS Configuration**: Automated node setup with proper disk selection and network configuration
2. **Cluster Initialization**: All-control-plane setup for maximum resource utilization
3. **Core Networking**: Cilium CNI with dual-stack IPv6 support and BGP integration
4. **Secret Management**: 1Password Connect integration for secure credential management
5. **GitOps Foundation**: Flux deployment to enable declarative infrastructure management

### GitOps Phase (Operational Services)

1. **Infrastructure Services**: Automated deployment of cert-manager, ingress controllers, monitoring
2. **Application Deployment**: Declarative application management through Git commits
3. **Network Services**: BGP configuration, load balancer pools, and DNS automation
4. **Storage Services**: Longhorn distributed storage with backup and snapshot management

### Daily Operations

1. **Application Updates**: Simple Git commits trigger automated deployments
2. **Infrastructure Changes**: Version-controlled infrastructure modifications
3. **Monitoring**: Comprehensive observability with alerts and dashboards
4. **Maintenance**: Safe node maintenance procedures with automated failover

## User Experience Goals

### For Operators

- **Simple Operations**: Clear decision framework for Bootstrap vs GitOps changes
- **Safe Procedures**: Well-documented recovery procedures with safety guardrails
- **Comprehensive Monitoring**: Full visibility into cluster health and performance
- **Automated Updates**: Dependency management with minimal manual intervention

### For Developers

- **GitOps Workflow**: Standard Git-based deployment process
- **Self-Service**: Ability to deploy applications without cluster admin access
- **Development Environment**: Consistent environment that matches production patterns
- **Documentation**: Clear guides for common operational tasks

### For Home Network Integration

- **Seamless DNS**: Automatic DNS record management for both internal and external access
- **Network Integration**: BGP peering with existing network infrastructure
- **Security**: Proper TLS certificates and authentication integration
- **Performance**: Optimized for home network bandwidth and latency characteristics

## Success Metrics

### Reliability

- **Uptime**: Cluster maintains high availability during single node failures
- **Recovery Time**: Complete cluster rebuild possible within 30 minutes
- **Data Safety**: No data loss during normal operations and maintenance

### Operational Efficiency

- **Deployment Speed**: Applications deploy within 5 minutes of Git commit
- **Update Automation**: 90% of dependency updates handled automatically
- **Troubleshooting**: Clear diagnostic procedures with comprehensive logging

### Security

- **Secret Management**: All secrets managed through 1Password with proper rotation
- **Network Security**: Proper network segmentation and TLS everywhere
- **Access Control**: RBAC properly configured for different user roles

## Integration Points

### External Services

- **1Password**: Centralized secret management for all cluster credentials
- **Cloudflare**: External DNS and tunnel management for public services
- **GitHub**: Git repository hosting and webhook integration
- **Unifi Network**: BGP peering and network integration

### Home Network Services

- **Internal DNS**: Automatic record management for internal services
- **Load Balancing**: BGP-advertised service IPs for high availability
- **Monitoring**: Integration with existing network monitoring tools
- **Backup**: Automated backup to external storage systems

This cluster serves as both a functional home infrastructure platform and a reference implementation for modern Kubernetes operations, demonstrating best practices for GitOps, security, and operational excellence.
