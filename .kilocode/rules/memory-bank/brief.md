# Talos GitOps Home-Ops Cluster

## Overview

This is a GitOps-driven Kubernetes cluster running on Talos OS, designed to operate services for a home network. The cluster implements a sophisticated architecture with clear separation between Bootstrap and GitOps phases for reliable operations.

## Core Architecture

- **Cluster Name**: home-ops
- **Platform**: 3x Intel Mac mini devices (all-control-plane setup)
- **OS**: Talos OS v1.10.5
- **Kubernetes**: v1.31.1
- **CNI**: Cilium with BGP peering
- **GitOps**: Flux v2.4.0
- **Storage**: Longhorn distributed storage on USB SSDs
- **Secrets**: 1Password Connect integration

## Network Configuration

- **Internal Domain**: k8s.home.geoffdavis.com
- **External Domain**: geoffdavis.com (via Cloudflare tunnel)
- **Cluster VIP**: 172.29.51.10
- **Node IPs**: 172.29.51.11-13
- **Pod CIDR**: 10.244.0.0/16 (IPv4), fd47:25e1:2f96:51:2000::/64 (IPv6)
- **Service CIDR**: 10.96.0.0/12 (IPv4), fd47:25e1:2f96:51:1000::/108 (IPv6)
- **LoadBalancer Pools**: 172.29.52.50-220 (BGP-advertised, VLAN 52)
- **Ingress IP**: 172.29.52.200 (from bgp-ingress pool)

## Key Design Principles

1. **Bootstrap vs GitOps Separation**: Clear architectural boundary between system-level components (Bootstrap) and application-level components (GitOps)
2. **All-Control-Plane**: Maximum resource utilization with all nodes as control plane
3. **Dual-Stack IPv6**: Future-proofing with IPv4/IPv6 support
4. **USB SSD Storage**: External 1TB USB SSDs for distributed storage (3TB total, ~1.35TB effective with 2-replica factor)
5. **Security-First**: 1Password integration, TLS everywhere, RBAC properly configured

## Critical Operational Boundaries

- **Bootstrap Phase**: Talos OS, Kubernetes cluster, Cilium CNI core, 1Password Connect, External Secrets, Flux system
- **GitOps Phase**: Infrastructure services, applications, BGP configuration, certificates, monitoring

## Safety Features

- **Safe Reset**: `task cluster:safe-reset` preserves OS, only wipes STATE/EPHEMERAL partitions
- **Emergency Recovery**: Comprehensive recovery procedures for various failure scenarios
- **LLDPD Stability**: Integrated configuration prevents periodic reboot issues
- **Phased Bootstrap**: Resumable bootstrap process with clear failure points
