# Talos OS Configuration Documentation

Talos Linux is an immutable, minimal, and secure operating system designed specifically for running Kubernetes. In the Talos GitOps Home-Ops Cluster, it forms the foundational layer for all cluster operations. This document details its purpose, architecture, configuration, and operational aspects.

## Purpose

Talos OS provides:

- **Immutability**: Ensures a consistent and predictable environment by preventing runtime modifications.
- **Security**: Reduces the attack surface by including only essential components and enforcing strict security policies.
- **Minimalism**: Optimized for Kubernetes, leading to a small footprint and efficient resource utilization.
- **API-Driven Management**: All configurations and operations are managed via a declarative API, aligning with GitOps principles.

## Architecture and Integration

Talos OS is installed directly on the cluster nodes (Intel Mac minis). Its configuration is managed declaratively, and any changes require regenerating and applying new configuration files.

Key aspects of its integration include:

- **All-Control-Plane Setup**: All three Mac mini nodes function as both control plane and worker nodes, maximizing resource utilization and providing high availability.
- **Smart Disk Selection**: Configured to intelligently select internal and external USB SSDs for OS installation and data partitions.
- **Dual-Stack IPv6 Networking**: Supports both IPv4 and IPv6 networking at the OS level.
- **LUKS2 Encryption**: STATE and EPHEMERAL partitions are encrypted for enhanced data security.
- **GitOps Alignment**: While Talos OS itself is not managed by Flux, its configuration is version-controlled and applied via `talosctl` commands, complementing the GitOps workflow.

## Configuration

The primary configuration for Talos OS is defined in `talconfig.yaml` and managed through `talos/patches/`.

### `talconfig.yaml`

This file is the main source of truth for the Talos cluster configuration. Key sections include:

- **`clusterName`**: Defines the name of the Kubernetes cluster.
- **`controlPlane` / `worker`**: Specifies node roles and their respective configurations. In this all-control-plane setup, all nodes are configured as `controlPlane`.
- **`installDiskSelector`**: Defines rules for selecting the disk for OS installation (e.g., `model: "APPLE*"` for internal, `model: "Portable SSD T5"` for USB SSDs).
- **`network`**: Configures network interfaces, IP addresses, and DNS settings.
- **`extensions`**: Enables and configures extensions like `ext-lldpd` for LLDP support.
- **`allowSchedulingOnMasters: true`**: Allows pods to be scheduled on control plane nodes.

### `talos/patches/`

This directory contains patches that apply specific configurations or overrides to the base `talconfig.yaml`. Examples include:

- **USB SSD Optimizations**: Patches for `udev` rules and `sysctl` settings to optimize USB SSD performance.
- **LLDPD Configuration**: Ensures `ext-lldpd` is properly configured to prevent networking issues.

## Operational Considerations

### Applying Configuration Changes

1. **Modify `talconfig.yaml` or `talos/patches/`**: Make the desired changes to the configuration files.
2. **Generate Configuration**: Use `talhelper` to generate the final Talos configuration files.
3. **Apply Configuration**: Use `talosctl apply-config` to apply the new configuration to the nodes. This often requires a node reboot.

### Node Management

- **Rebooting Nodes**: `talosctl reboot --nodes <node-ip>`
- **Accessing Nodes**: `talosctl exec --nodes <node-ip> -- <command>` (for debugging and emergency operations).
- **Safe Reset**: `task cluster:safe-reset` can be used to wipe only the STATE and EPHEMERAL partitions while preserving the OS installation.

### Troubleshooting

- **Node Unreachable**:
  - Verify network connectivity to the node.
  - Check physical connections and power.
  - Use `talosctl health` to diagnose issues.
- **Configuration Application Failures**:
  - Review `talosctl` output for errors.
  - Check `dmesg` and `journalctl` logs on the node for more details.
- **Disk Issues**:
  - Verify disk selection rules in `talconfig.yaml`.
  - Check `udev` rules and `sysctl` settings for USB SSDs.

## Related Files

- [`talconfig.yaml`](../../talconfig.yaml) - Main Talos OS cluster configuration.
- [`talos/patches/`](../../talos/patches/) - Directory containing configuration patches.
- [`Taskfile.yml`](../../Taskfile.yml) - Contains tasks for generating and applying Talos configurations.

Please ensure this file is created with the exact content provided. After creation, use the `attempt_completion` tool to report the successful creation of the file.
