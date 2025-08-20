# Technology Stack: Talos GitOps Home-Ops Cluster

## Core Technologies

### Operating System & Container Runtime

- **Talos OS v1.10.5**: Immutable Linux OS designed for Kubernetes
- **Kubernetes v1.31.1**: Container orchestration platform
- **containerd**: Container runtime (managed by Talos)

### Networking

- **Cilium v1.17.6**: CNI with eBPF-based networking and security
- **BGP**: Border Gateway Protocol for load balancer IP advertisement
- **Dual-Stack IPv6**: Full IPv4/IPv6 networking support
- **LLDP**: Link Layer Discovery Protocol for network topology

### Storage

- **Longhorn**: Distributed block storage for Kubernetes
- **Samsung Portable SSD T5**: External USB SSDs (3x 1TB)
- **XFS**: Filesystem for storage volumes
- **LUKS2**: Disk encryption for STATE and EPHEMERAL partitions

### GitOps & CI/CD

- **Flux v2.4.0**: GitOps operator for Kubernetes
- **Kustomize**: Kubernetes configuration management
- **GitHub**: Git repository hosting with webhook integration
- **Renovate**: Automated dependency updates

### Application Stack

- **Home Assistant v2025.7**: Home automation platform
- **PostgreSQL v16.4**: Database with CloudNativePG operator
- **CNPG Barman Plugin v0.5.0**: Modern plugin-based backup system for PostgreSQL clusters
- **Mosquitto MQTT v2.0.18**: IoT device communication broker
- **Redis**: Caching and session storage
- **Matter Server v8.0.0**: Thread/Matter device support for home automation

### Secret Management

- **1Password Connect**: Centralized secret management
- **External Secrets Operator**: Kubernetes secret synchronization
- **RBAC**: Role-based access control

### Monitoring & Observability

- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization and dashboards
- **AlertManager**: Alert routing and management
- **Hubble**: Cilium network observability
- **CNPG Monitoring**: Dedicated monitoring for CloudNativePG backup operations with 15+ Prometheus alerts

### Identity & Security

- **Authentik v2025.6.4**: Identity provider and SSO with external outpost architecture
- **PostgreSQL**: Database backend for Authentik
- **cert-manager**: TLS certificate automation
- **Let's Encrypt**: Certificate authority for internal services

### Ingress & Load Balancing

- **ingress-nginx**: HTTP/HTTPS ingress controller (multiple instances)
- **Cloudflare Tunnel**: Secure external access
- **External DNS**: Automatic DNS record management

## Development Tools

### Required Tools (via mise)

- **task v3.38.0+**: Task runner for automation
- **talhelper**: Talos configuration helper
- **talosctl v1.10.5+**: Talos CLI tool
- **kubectl v1.31.1+**: Kubernetes CLI
- **flux v2.4.0+**: Flux CLI
- **helm v3.16.1+**: Kubernetes package manager
- **kustomize v5.4.3+**: Configuration management
- **cilium v0.16.16+**: Cilium CLI
- **yq v4.44.3+**: YAML processor
- **jq v1.7.1+**: JSON processor
- **op v2.0.0+**: 1Password CLI
- **pre-commit**: Git hook framework for code quality

### Code Quality Tools

- **detect-secrets**: Secret detection and baseline management
- **gitleaks**: Git repository secret scanning
- **yamllint**: YAML syntax and style validation
- **shellcheck**: Shell script analysis and security
- **markdownlint**: Markdown structure validation
- **prettier**: Code formatting for YAML and Markdown
- **black**: Python code formatting
- **isort**: Python import sorting
- **flake8**: Python linting and style checking
- **pytest**: Python testing framework

### Development Environment Setup

```bash
# Install mise for tool management
curl https://mise.jdx.dev/install.sh | sh

# Install all required tools
mise install

# Configure environment
cp .env.example .env
# Edit .env to set OP_ACCOUNT
```

### Code Quality Workflow

```bash
# Pre-commit setup (one-time)
task pre-commit:setup
task pre-commit:install

# Daily development workflow
git add .
git commit -m "your changes"  # Hooks run automatically

# Manual validation
task pre-commit:run           # All enforced hooks
task pre-commit:format        # Formatting checks (warnings)
task pre-commit:security      # Security scans only

# Maintenance
task pre-commit:update        # Update hook versions
task pre-commit:clean         # Clean cache
```

## MCP Servers

The development environment includes several Model Context Protocol (MCP) servers that extend capabilities for interacting with various systems and services. These servers provide specialized tools and resources that integrate seamlessly with the development workflow.

### Configured MCP Servers

#### Git Server (`mcp-server-git`)

- **Type**: Local stdio-based server
- **Command**: `uvx mcp-server-git --repository /Users/geoff/src/personal/talos-gitops`
- **Capabilities**:
  - Git repository operations and history analysis
  - Branch and commit management
  - File change tracking and diff analysis
  - Repository structure exploration
- **Integration**: Provides direct access to the Talos GitOps repository for code analysis, change tracking, and repository management tasks
- **Usage Patterns**: Ideal for understanding project history, analyzing changes, and managing Git operations within the development workflow

#### Cloudflare Observability Server

- **Type**: Remote SSE-based server
- **Endpoint**: `https://observability.mcp.cloudflare.com/sse`
- **Command**: `npx mcp-remote https://observability.mcp.cloudflare.com/sse`
- **Capabilities**:
  - Cloudflare Workers observability and logging
  - Performance metrics and analytics
  - Error tracking and debugging
  - Workers deployment monitoring
- **Integration**: Provides observability into Cloudflare services used in the cluster (Cloudflare Tunnel, DNS management)
- **Usage Patterns**: Monitor Cloudflare Tunnel performance, analyze DNS resolution, troubleshoot external access issues

#### Flux Operator Server (`flux-operator-mcp`)

- **Type**: Local stdio-based server
- **Command**: `/opt/homebrew/bin/flux-operator-mcp serve`
- **Capabilities**:
  - Flux GitOps operations and management
  - Kubernetes resource inspection and manipulation
  - HelmRelease and Kustomization management
  - Flux reconciliation and troubleshooting
- **Integration**: Direct integration with the Talos GitOps cluster for Flux operations
- **Usage Patterns**:
  - GitOps workflow management and troubleshooting
  - Flux resource reconciliation and monitoring
  - HelmRelease and Kustomization debugging
  - Integration with emergency recovery procedures

#### Filesystem Server (`mcp-server-filesystem`)

- **Type**: Local stdio-based server
- **Command**: `npx -y @modelcontextprotocol/server-filesystem /Users/geoff/src`
- **Capabilities**:
  - File system operations and management
  - File reading, writing, and manipulation
  - Directory structure exploration
  - File search and content analysis
- **Integration**: Provides comprehensive file system access for project management
- **Usage Patterns**: File operations, content analysis, project structure management

#### Context7 Server (`context7-mcp`)

- **Type**: Remote HTTP-based server
- **Command**: `npx -y @upstash/context7-mcp`
- **Capabilities**:
  - Library documentation and code examples
  - Up-to-date documentation retrieval
  - Code pattern analysis and suggestions
- **Integration**: Enhances development workflow with library-specific guidance
- **Usage Patterns**: Documentation lookup, code examples, library integration guidance

### Development Workflow Integration

#### Cluster Operations

```bash
# MCP servers enhance these common operations:
# - Flux GitOps management via flux-operator server
# - Git operations and history analysis via git server
# - Cloudflare service monitoring via cloudflare server
# - File system operations via filesystem server
```

#### Operational Patterns

- **Troubleshooting**: Flux server provides direct cluster access for GitOps diagnostics
- **Change Management**: Git server enables comprehensive repository analysis and change tracking
- **External Service Monitoring**: Cloudflare server provides visibility into external service performance
- **Development Collaboration**: Multiple servers facilitate comprehensive project management

#### Integration Benefits

- **Unified Interface**: All servers accessible through consistent MCP protocol
- **Context Awareness**: Servers understand the specific project context and configuration
- **Operational Efficiency**: Direct access to cluster and external services without context switching
- **Enhanced Debugging**: Combined visibility across Git, Kubernetes, Flux, and external services

### Configuration Management

- **Local Configuration**: `.kilocode/mcp.json` - Project-specific MCP server configuration
- **Global Configuration**: `~/Library/Application Support/Code/User/mcp.json` - User-wide MCP server settings
- **Server Types**: Mix of local stdio servers and remote HTTP/SSE servers
- **Security**: Servers operate with appropriate permissions for their respective domains

### Usage Notes

- **Git Server**: Scoped to the specific Talos GitOps repository for focused operations
- **Flux Server**: Requires proper kubectl configuration and cluster access
- **Cloudflare Server**: Provides read-only observability into Cloudflare services
- **Filesystem Server**: Provides comprehensive file system access within allowed directories
- **Performance**: Local servers provide faster response times, remote servers offer specialized capabilities

This MCP server ecosystem significantly enhances the development and operational capabilities by providing direct, context-aware access to the key systems and services that comprise the Talos GitOps infrastructure.

## Hardware Architecture

### Node Specifications

- **Platform**: Intel Mac mini devices
- **Count**: 3 nodes (all-control-plane)
- **Role**: Each node functions as both control plane and worker
- **Storage**: Apple internal storage for OS, USB SSDs for data

### Network Configuration

- **VLAN**: 51 (172.29.51.0/24)
- **IPv6**: fd47:25e1:2f96:51::/64 (ULA)
- **BGP ASN**: Cluster 64512, Router 64513
- **Upstream**: Unifi UDM Pro with BGP peering

### Storage Architecture

- **OS Storage**: Apple internal drives (auto-detected)
- **Data Storage**: 3x Samsung Portable SSD T5 (1TB each)
- **Total Capacity**: 3TB raw, ~1.35TB effective (2-replica)
- **Performance**: Optimized with custom udev rules and sysctls

## Technical Constraints

### Hardware Limitations

- **USB Storage**: External SSDs required due to Mac mini storage limitations
- **Network**: Single network interface per node
- **Power**: No redundant power supplies (home lab environment)

### Software Constraints

- **Talos Immutability**: OS changes require configuration regeneration
- **CNI Dependency**: Cilium must be deployed before any pods can start
- **Secret Bootstrap**: 1Password Connect required before GitOps can access secrets

### Operational Constraints

- **Bootstrap Order**: Strict dependency chain must be followed
- **Network Dependencies**: BGP peering required for load balancer functionality
- **DNS Integration**: External DNS providers must be properly configured

## Cilium Configuration Details

### Cilium v1.17.6 Deployment Parameters

- **XDP Acceleration**: Disabled for Mac mini compatibility (`--set loadBalancer.acceleration=disabled`)
- **LoadBalancer IPAM**: Enabled (`--set enable-lb-ipam=true`)
- **L2 Announcements**: Disabled (`--set loadBalancer.l2.enabled=false`)
- **BGP Control Plane**: Enabled for load balancer IP advertisement
- **Kube-proxy Replacement**: Disabled in Talos configuration
- **Dual-Stack Support**: IPv4/IPv6 networking enabled

### BGP LoadBalancer Configuration

- **Cluster ASN**: 64512 (all nodes participate in BGP)
- **UDM Pro ASN**: 64513 (BGP peer and route acceptor)
- **BGP Peering Status**: ✅ Established and stable
- **Route Advertisement**: ✅ Working with legacy CiliumBGPPeeringPolicy
- **IP Pool Architecture**:
  - bgp-default: 172.29.52.100-199 (default services)
  - bgp-ingress: 172.29.52.200-220 (ingress controllers)
  - bgp-reserved: 172.29.52.50-99 (reserved for future use)
  - bgp-default-ipv6: fd47:25e1:2f96:52:100::/120 (IPv6 pool)

## Tool Usage Patterns

### Bootstrap Operations

```bash
# Cluster lifecycle
task bootstrap:phased          # Complete phased bootstrap
task cluster:safe-reset        # Safe cluster reset
task cluster:emergency-recovery # Emergency procedures

# Node operations
task talos:apply-config        # Apply Talos configuration
task talos:bootstrap          # Initialize cluster
task talos:reboot             # Reboot nodes

# Core services
task apps:deploy-cilium       # Deploy CNI (Cilium v1.17.6 with XDP disabled)
task bootstrap:1password-secrets # Bootstrap secrets
task flux:bootstrap           # Deploy GitOps
```

### GitOps Operations

```bash
# Flux management
flux get kustomizations       # Check deployment status
flux reconcile source git flux-system # Force sync
flux logs --follow           # Monitor deployments

# Application management
git add apps/my-app/         # Stage application
git commit -m "Add my-app"   # Commit changes
git push                     # Trigger deployment
```

### Emergency Recovery Operations

```bash
# Emergency recovery framework
./scripts/aggressive-recovery-backup.sh    # Create comprehensive backup
./scripts/aggressive-recovery-execute.sh   # Execute recovery strategy
./scripts/aggressive-recovery-monitor.sh   # Monitor recovery progress
./scripts/aggressive-recovery-rollback.sh  # Rollback if needed
./validate-recovery-success.sh             # Validate recovery success

# Recovery validation
flux get kustomizations                     # Check GitOps status (target: 31/31 Ready)
kubectl get pods -A | grep -v Running      # Check for failed pods
curl -I https://longhorn.k8s.home.geoffdavis.com # Test service accessibility
```

### Monitoring & Diagnostics

```bash
# Cluster health
task cluster:status          # Overall cluster status
kubectl get nodes           # Node status
kubectl get pods -A         # Pod status

# Network diagnostics
cilium status               # CNI status
task bgp:verify-peering     # BGP status
task network:check-ipv6     # IPv6 configuration

# BGP troubleshooting
kubectl get ciliumbgppeeringpolicies # BGP peering policy status
kubectl exec -n kube-system -l k8s-app=cilium -- cilium bgp routes # BGP routes
kubectl exec -n kube-system -l k8s-app=cilium -- cilium bgp peers # BGP peer status
kubectl logs -n kube-system -l k8s-app=cilium | grep -i bgp # BGP logs

# Home Assistant stack
kubectl get pods -n home-automation # Stack health
kubectl logs -n home-automation -l app.kubernetes.io/name=home-assistant # Home Assistant logs
kubectl get cluster homeassistant-postgresql -n home-automation # Database status

# CNPG backup monitoring
kubectl get backup,scheduledbackup -A # Backup operations status
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg # CNPG operator logs
kubectl get servicemonitor,prometheusrule -n cnpg-monitoring # Monitoring resources

# Storage diagnostics
task storage:check-longhorn  # Storage health
task storage:validate-usb-ssd # USB SSD validation
```

## Integration Patterns

### External Service Integration

- **1Password**: API-based secret retrieval and management
- **Cloudflare**: DNS management and tunnel configuration
- **GitHub**: Git repository with webhook integration
- **Unifi**: BGP peering and network integration

### Internal Service Dependencies

- **Bootstrap → GitOps**: Sequential deployment phases
- **Secrets → Applications**: External secrets provide credentials
- **Networking → Storage**: CNI required for distributed storage
- **Monitoring → Everything**: Observability across all components

## Security Architecture

### Encryption

- **Disk Encryption**: LUKS2 for STATE and EPHEMERAL partitions
- **Network Encryption**: TLS for all service communication
- **Secret Encryption**: Kubernetes secrets encrypted at rest

### Access Control

- **RBAC**: Kubernetes role-based access control
- **Network Policies**: Cilium-based network segmentation
- **Pod Security**: Pod Security Standards enforcement

### Certificate Management

- **Internal**: Let's Encrypt via cert-manager
- **External**: Cloudflare-managed certificates
- **Cluster**: Talos-generated cluster certificates

## Code Quality and Security

### Pre-commit Framework

- **Philosophy**: Balanced enforcement approach
  - **ENFORCED**: Security issues, syntax errors, critical validation
  - **WARNING**: Code formatting, style preferences, non-critical issues
- **Coverage**: YAML, Python, Shell, Markdown, Kubernetes manifests
- **Integration**: Task-based workflow with simple commands
- **Real Issue Detection**: 600+ actual issues identified across repository

### Security Validation

- **Secret Detection**: detect-secrets with baseline management
- **Git Leaks**: Additional layer of credential protection
- **Shell Security**: shellcheck for security best practices
- **File Validation**: Large file detection, encoding checks
- **Access Control**: Proper RBAC and security contexts

### Development Standards

- **Syntax Validation**: Prevents broken YAML, Python, shell scripts
- **Kubernetes Validation**: kubectl dry-run and kustomize validation
- **Code Formatting**: Consistent style across all file types
- **Testing**: Automated testing for critical scripts
- **Documentation**: Markdown validation for readable documentation

## Home Automation Integration

### Home Assistant Stack

- **Platform**: Home Assistant Core v2025.7 running on Kubernetes with comprehensive troubleshooting recovery completed
- **Database**: PostgreSQL cluster with CloudNativePG for high availability, automatic certificate management, and schema compatibility fixes
- **Backup System**: CNPG Barman Plugin v0.5.0 provides modern plugin-based backup architecture with S3 ObjectStore integration
- **Communication**: Mosquitto MQTT broker for IoT device integration with resolved port binding conflicts and simplified listener configuration
- **Performance**: Redis cache for session storage and optimization
- **Authentication**: Seamless SSO integration via external Authentik outpost with complete proxy configuration
- **Access**: <https://homeassistant.k8s.home.geoffdavis.com>
- **Production Status**: **PRODUCTION-READY** - Successfully recovered from complete non-functional state through systematic troubleshooting

### Matter Server Integration

- **Platform**: Python Matter Server v8.0.0 for Thread/Matter device support
- **Network Configuration**: Host networking with `enp3s0f0` interface for device discovery
- **Bluetooth Support**: Enabled for Matter device commissioning
- **Storage**: 5GB Longhorn persistent volume for certificates and device data
- **Communication**: WebSocket API at `ws://localhost:5580/ws` for Home Assistant integration
- **Security Context**: Privileged mode with NET_ADMIN, NET_RAW, SYS_ADMIN capabilities
- **Chart**: home-assistant-matter-server v3.0.0 via Helm

### IoT Device Integration

- **MQTT Protocol**: Secure communication with IoT devices via Mosquitto with resolved configuration conflicts
- **Network Isolation**: Proper network policies for IoT device security with updated PodSecurity policies
- **Device Discovery**: Automatic device discovery and integration with proper security contexts
- **Data Persistence**: PostgreSQL storage for device states and history with CloudNativePG automatic certificate management
- **Matter/Thread**: Advanced IoT protocol support via dedicated Matter Server

### Home Assistant Troubleshooting Recovery

- **Schema Compatibility**: Resolved CloudNativePG v1.26.1 compatibility issues by removing invalid backup resource fields
- **Backup Architecture Migration**: Migrated from legacy `barmanObjectStore` to CNPG Barman Plugin v0.5.0 for CloudNativePG v1.28.0+ compatibility
- **Credential Management**: Implemented optimized 1Password entry structure for Home Assistant stack components
- **Certificate Management**: Enabled CloudNativePG automatic certificate generation removing manual configuration conflicts
- **Container Security**: Configured proper security contexts for s6-overlay container init system requirements
- **MQTT Configuration**: Resolved listener configuration conflicts causing service startup failures
- **End-to-End Validation**: Confirmed complete stack functionality with SSO authentication via external Authentik outpost

### CNPG Backup and Monitoring Architecture

- **Plugin System**: CNPG Barman Plugin v0.5.0 replaces legacy `barmanObjectStore` configuration for modern backup management
- **Storage Backend**: S3-compatible ObjectStore with MinIO for backup storage and configurable retention policies
- **Monitoring Integration**: Comprehensive monitoring namespace with ServiceMonitor resources and Prometheus alerting rules
- **Alert Coverage**: 15+ Prometheus alerts covering backup health, restoration capabilities, and plugin operational status
- **GitOps Management**: Full integration with Flux GitOps for monitoring system deployment and configuration management
- **Zero Downtime Operations**: Blue-green deployment strategy enables configuration changes without service interruption

## Chart Development

### Authentik-Proxy-Config Chart

- **Chart Versions**: 0.1.0 through 0.2.0 with comprehensive feature development
- **Location**: [`charts/authentik-proxy-config/`](../charts/authentik-proxy-config/)
- **Purpose**: Automated Authentik proxy provider configuration and management
- **Architecture**: Comprehensive Helm chart with templates, values, and RBAC integration

#### Chart Components

- **Templates**: Complete template system with helpers, RBAC, and configuration management
  - [`_helpers.tpl`](../charts/authentik-proxy-config/templates/_helpers.tpl): Standard Helm helper functions
  - [`configmaps/service-config.tpl`](../charts/authentik-proxy-config/templates/configmaps/service-config.tpl): Service configuration management
  - [`rbac/`](../charts/authentik-proxy-config/templates/rbac/): Complete RBAC system with ClusterRole, ClusterRoleBinding, Role, RoleBinding, ServiceAccount
- **Values**: [`values.yaml`](../charts/authentik-proxy-config/values.yaml) - 122-line comprehensive configuration
- **Service Management**: Configuration for 7 services (Dashboard, Hubble, Grafana, Prometheus, AlertManager, Longhorn, Home Assistant)

#### Chart Features

- **RBAC Integration**: Comprehensive role-based access control with proper permissions
- **Security Context**: Proper security contexts with non-root execution and restricted capabilities
- **Hook Management**: Pre-install and pre-upgrade hooks with timeout and retry configuration
- **External Secrets**: Integration with 1Password via ExternalSecrets for secure token management
- **Service Discovery**: Automated service discovery and configuration management capabilities

This technology stack provides a robust, secure, and scalable foundation for home lab operations while demonstrating enterprise-grade Kubernetes practices, GitOps workflows, comprehensive code quality standards, emergency recovery capabilities, and full home automation capabilities with proven troubleshooting and recovery procedures.
