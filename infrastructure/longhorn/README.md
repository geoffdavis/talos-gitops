# Longhorn Storage Documentation

Longhorn is a lightweight, reliable, and easy-to-use distributed block storage system for Kubernetes. In the Talos GitOps Home-Ops Cluster, it provides persistent storage for applications, leveraging USB SSDs attached to the cluster nodes. This document details its purpose, architecture, configuration, and operational aspects.

## Purpose

Longhorn enables:

- **Persistent Storage**: Providing durable block storage volumes for stateful applications.
- **High Availability**: Replicating data across multiple nodes to ensure data availability even if a node fails.
- **Snapshots and Backups**: Facilitating point-in-time recovery and disaster recovery capabilities.
- **Dynamic Provisioning**: Automatically provisioning storage volumes as needed by applications.

## Architecture and Integration

Longhorn is deployed as a set of microservices within the Kubernetes cluster. It creates a distributed block device that can be mounted by pods, with data replicated across configured storage nodes. In this cluster, Longhorn is integrated with USB SSDs attached to the Mac mini nodes.

Key aspects of its integration include:

- **GitOps Management**: Deployed and managed declaratively via HelmRelease in `infrastructure/longhorn/helmrelease.yaml`.
- **USB SSD Integration**: Utilizes dedicated USB SSDs on each node as storage devices for Longhorn, optimizing for performance and capacity.
- **Data Replication**: Configured with a 2-replica factor to ensure data redundancy across two different nodes.
- **Snapshot and Backup Targets**: Backups are configured to an S3-compatible object storage (e.g., MinIO, AWS S3).

## Configuration

The primary configuration for Longhorn is managed through its HelmRelease in `infrastructure/longhorn/helmrelease.yaml`. Key configurable parameters include:

- **`defaultSettings.defaultDataPath`**: Specifies the path on the host where Longhorn stores data (e.g., `/mnt/longhorn`).
- **`defaultSettings.replicaAutoBalance`**: Configures automatic rebalancing of replicas across nodes.
- **`persistence.defaultClass`**: Sets Longhorn as the default StorageClass for dynamic provisioning.
- **`defaultSettings.backupTarget`**: Configures the S3-compatible backup target.
- **`defaultSettings.createDefaultDiskAndNode`**: Ensures default disks and nodes are created automatically.

## Operational Considerations

### Accessing the Longhorn UI

The Longhorn UI provides a graphical interface for managing volumes, nodes, and backups.

- Access via `https://longhorn.k8s.home.geoffdavis.com` (or directly via its LoadBalancer IP `172.29.52.100`).
- Authentication is integrated with Authentik for seamless SSO.

### Verifying Longhorn Status

- Check Longhorn pods: `kubectl get pods -n longhorn-system`
- Verify node status in Longhorn UI: Ensure all nodes are active and have available storage.
- Check volume status: Ensure all volumes are healthy and attached to the correct pods.

### Troubleshooting

- **Volume Attachment Issues**:
  - Verify the node where the pod is scheduled has sufficient disk space and is marked as schedulable in Longhorn.
  - Check Longhorn manager and engine logs for errors.
- **Performance Degradation**:
  - Monitor disk I/O on the underlying USB SSDs.
  - Ensure sufficient network bandwidth between nodes for replication traffic.
- **Backup Failures**:
  - Verify connectivity to the S3 backup target.
  - Check backup job logs for errors.

## Related Files

- [`infrastructure/longhorn/helmrelease.yaml`](../../infrastructure/longhorn/helmrelease.yaml) - Longhorn HelmRelease configuration.
- [`infrastructure/longhorn/kustomization.yaml`](../../infrastructure/longhorn/kustomization.yaml) - Kustomization for Longhorn.
- [`docs/USB_SSD_OPERATIONAL_PROCEDURES.md`](../../docs/USB_SSD_OPERATIONAL_PROCEDURES.md) - Documentation for USB SSD operational procedures.
