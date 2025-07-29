# Architecture Overview

This document provides a comprehensive overview of the Talos GitOps home-ops cluster architecture, designed to help operators understand the system structure, component relationships, and operational patterns.

## System Philosophy

The cluster implements a **two-phase architecture** that separates foundational system components (Bootstrap Phase) from operational services (GitOps Phase), enabling both reliable cluster operations and collaborative development workflows.

### Core Design Principles

1. **Bootstrap vs GitOps Separation**: Clear architectural boundary between system-level and application-level components
2. **All-Control-Plane**: Maximum resource utilization with all nodes functioning as both control plane and worker
3. **Security-First**: 1Password integration, TLS everywhere, RBAC properly configured
4. **Immutable Infrastructure**: GitOps-driven declarative management with version control
5. **High Availability**: Distributed storage and automatic failover capabilities

## High-Level Architecture

```text
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Mini01        │    │   Mini02        │    │   Mini03        │
│ Control+Worker  │    │ Control+Worker  │    │ Control+Worker  │
│                 │    │                 │    │                 │
│ Talos OS        │    │ Talos OS        │    │ Talos OS        │
│ USB SSD Storage │    │ USB SSD Storage │    │ USB SSD Storage │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────────┐
                    │   UDM Pro Router    │
                    │   BGP Peer (64513)  │
                    │   DNS + DHCP        │
                    └─────────────────────┘
```

## Network Architecture

### Network Segmentation

- **Management Network**: VLAN 51 (172.29.51.0/24) - Node management and cluster communication
- **LoadBalancer Network**: VLAN 52 (172.29.52.0/24) - BGP-advertised service IPs
- **Pod Network**: 10.244.0.0/16 (IPv4), fd47:25e1:2f96:51:2000::/64 (IPv6)
- **Service Network**: 10.96.0.0/12 (IPv4), fd47:25e1:2f96:51:1000::/108 (IPv6)

### BGP LoadBalancer Architecture

- **Cluster ASN**: 64512 (all nodes participate in BGP)
- **Router ASN**: 64513 (UDM Pro accepts and routes BGP advertisements)
- **IP Pool Strategy**:
  - `bgp-default`: 172.29.52.100-199 (general services)
  - `bgp-ingress`: 172.29.52.200-220 (ingress controllers)
  - `bgp-reserved`: 172.29.52.50-99 (reserved for future use)

### DNS Strategy

- **Internal Domain**: k8s.home.geoffdavis.com (managed by External DNS)
- **External Domain**: geoffdavis.com (via Cloudflare tunnel)
- **Certificate Management**: Let's Encrypt for internal, Cloudflare for external

## Component Architecture

### Bootstrap Phase (System Foundation)

These components are deployed directly via Taskfile commands and form the cluster foundation:

#### 1. Talos OS Configuration

- **Purpose**: Immutable operating system for Kubernetes nodes
- **Key Features**: All-control-plane setup, LUKS2 encryption, smart disk selection
- **Management**: Direct talosctl commands during bootstrap

#### 2. Cilium CNI Core

- **Purpose**: Container networking foundation with eBPF-based security
- **Configuration**: Dual-stack IPv6, BGP control plane, LoadBalancer IPAM
- **Special Settings**: XDP disabled for Mac mini compatibility

#### 3. Secret Management Foundation

- **Components**: 1Password Connect + External Secrets Operator
- **Purpose**: Secure credential management enabling GitOps operations
- **Bootstrap**: Dedicated script creates initial Kubernetes secrets

#### 4. Flux GitOps System

- **Purpose**: GitOps operator enabling declarative infrastructure management
- **Integration**: GitHub repository with webhook support

### GitOps Phase (Operational Services)

These components are managed declaratively through Git commits and Flux reconciliation:

#### 1. Infrastructure Services

- **cert-manager**: Automated TLS certificate management
- **ingress-nginx**: HTTP/HTTPS ingress controllers (multiple instances)
- **external-dns**: Automatic DNS record management
- **monitoring**: Prometheus, Grafana, AlertManager observability stack
- **longhorn**: Distributed block storage system

#### 2. Identity Management

- **Authentik**: Centralized SSO identity provider with PostgreSQL backend
- **External Authentik-Proxy**: Dedicated outpost deployment for Kubernetes service authentication
- **Architecture**: Hybrid URL design with internal service URLs and external user redirects

#### 3. Application Services

- **Home Assistant Stack**: Comprehensive home automation platform
  - Home Assistant Core v2025.7
  - PostgreSQL database with CloudNativePG operator
  - Mosquitto MQTT broker for IoT devices
  - Redis cache for performance optimization
- **Kubernetes Dashboard**: Cluster management interface with seamless SSO
- **Monitoring Applications**: Application-specific monitoring components

## Storage Architecture

### USB SSD Strategy

- **Hardware**: 3x Samsung Portable SSD T5 (1TB each)
- **Total Capacity**: 3TB raw, ~1.35TB effective with 2-replica factor
- **Distribution**: Longhorn manages automatic replication and scheduling
- **Performance**: Custom udev rules and sysctls optimize SSD performance

### Storage Classes

- **longhorn**: Default replicated storage (2 replicas)
- **longhorn-single**: Single replica for non-critical data
- **longhorn-encrypted**: Encrypted storage for sensitive data

## Security Architecture

### Defense in Depth

1. **OS Level**: Talos immutable OS with LUKS2 disk encryption
2. **Network Level**: Cilium network policies and eBPF-based security
3. **Cluster Level**: RBAC, Pod Security Standards, service meshes
4. **Application Level**: TLS everywhere, secure defaults, secret management

### Secret Management Flow

```text
1Password Vault → 1Password Connect → External Secrets → Kubernetes Secrets → Applications
```

### Authentication Flow

```text
User → External Authentik-Proxy → Authentik Server → Application Access
```

## Operational Patterns

### Decision Framework: Bootstrap vs GitOps

**Use Bootstrap Phase for:**

- Node configuration changes
- Core networking modifications
- Secret management foundation updates
- System-level troubleshooting

**Use GitOps Phase for:**

- Application deployments
- Infrastructure service updates
- Operational configuration changes
- Scaling and resource adjustments

### Change Management

- **Bootstrap Changes**: Update configuration files → regenerate → apply via tasks
- **GitOps Changes**: Update manifests → commit to Git → Flux deploys automatically
- **Rollback**: Git revert for GitOps, configuration restore for Bootstrap

### Safety Procedures

- **Safe Reset**: `task cluster:safe-reset` preserves OS, wipes only STATE/EPHEMERAL
- **Emergency Recovery**: Comprehensive procedures for various failure scenarios
- **Phased Bootstrap**: Resumable process with clear failure points

## Monitoring and Observability

### Monitoring Stack

- **Prometheus**: Metrics collection from 29+ targets
- **Grafana**: Visualization with external access (172.29.52.101)
- **AlertManager**: Alert routing and management (172.29.52.103)
- **Hubble**: Cilium network observability

### Key Metrics

- **Cluster Health**: Node status, resource utilization, pod failures
- **Network Performance**: BGP peering status, ingress response times
- **Storage Health**: Longhorn volume status, USB SSD performance
- **Application Performance**: Home Assistant, authentication system response times

## Development Quality

### Pre-commit Framework

- **Philosophy**: Balanced enforcement (security enforced, formatting warnings)
- **Coverage**: YAML, Python, Shell, Markdown, Kubernetes manifests
- **Real Issue Detection**: 600+ actual issues identified across repository

### Testing Strategy

- **Infrastructure**: Kubernetes manifest validation, kustomize validation
- **Security**: Secret detection, shell script security analysis
- **Syntax**: YAML, Python, shell script syntax validation

## Scalability Considerations

### Current Limits

- **Nodes**: 3 nodes (all-control-plane architecture)
- **Storage**: ~1.35TB effective capacity with current USB SSD setup
- **Network**: Single network interface per node
- **Power**: No redundant power supplies (home lab environment)

### Growth Paths

- **Storage Expansion**: Add additional USB SSDs or migrate to internal NVMe
- **Network Optimization**: Additional network interfaces or link aggregation
- **Application Scaling**: Horizontal pod autoscaling for applications
- **Monitoring Enhancement**: Additional metrics and alerting rules

## Integration Points

### External Services

- **1Password**: Centralized secret management
- **Cloudflare**: External DNS and tunnel management
- **GitHub**: Git repository hosting and webhook integration
- **Unifi Network**: BGP peering and network integration

### Internal Dependencies

- **Critical Path**: Talos → Kubernetes → Cilium → Pods → 1Password Connect → Secrets → Flux → Everything Else
- **Service Mesh**: All services interconnected through Cilium CNI
- **Data Flow**: PostgreSQL clusters support Authentik and Home Assistant
- **Authentication**: External Authentik-Proxy provides SSO for all cluster services

---

For detailed implementation guides, see:

- [Bootstrap vs GitOps Decision Framework](bootstrap-vs-gitops.md)
- [BGP LoadBalancer Configuration](../components/networking/bgp-loadbalancer.md)
- [Home Assistant Deployment](../components/applications/home-assistant.md)
- [Authentik External Outpost Setup](../AUTHENTIK_EXTERNAL_OUTPOST_CONNECTION_FIX_DOCUMENTATION.md)
