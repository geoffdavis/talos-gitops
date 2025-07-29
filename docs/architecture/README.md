# Architecture

This section contains comprehensive documentation about the system architecture and design decisions.

## Quick Navigation

- [Overview](overview.md) - High-level system architecture
- [Bootstrap vs GitOps](bootstrap-vs-gitops.md) - Two-phase architecture explanation
- [Networking](networking.md) - Network architecture and BGP configuration
- [Storage](storage.md) - USB SSD and Longhorn distributed storage
- [Security](security.md) - Security architecture and practices

## Architecture Principles

The Talos GitOps cluster is built on several key architectural principles:

1. **Bootstrap vs GitOps Separation**: Clear boundary between system-level and application-level components
2. **All-Control-Plane**: Maximum resource utilization with all nodes as control plane
3. **Dual-Stack IPv6**: Future-proofing with IPv4/IPv6 support
4. **USB SSD Storage**: External storage for distributed persistence
5. **Security-First**: 1Password integration, TLS everywhere, RBAC properly configured

## Component Overview

### Bootstrap Phase Components

- Talos OS Configuration
- Kubernetes Cluster
- Cilium CNI Core
- 1Password Connect
- External Secrets Operator
- Flux GitOps System

### GitOps Phase Components

- Infrastructure Services (cert-manager, ingress, monitoring)
- Cilium BGP Configuration
- Application Deployments
- Storage Configuration
- Certificate Management

For operational guidance, see the [Operations](../operations/) section.
