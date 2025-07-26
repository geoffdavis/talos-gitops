# All-Control-Plane Cluster Setup

This Talos cluster is configured to run all three nodes as both control plane and worker nodes, providing a highly available control plane while maximizing resource utilization in a small cluster.

## Architecture

- **3 nodes**: All functioning as both control plane and worker nodes
- **High Availability**: etcd cluster spans all 3 nodes
- **Load Distribution**: Workloads can be scheduled on any node
- **Fault Tolerance**: Cluster remains operational with 1 node failure

## Configuration Changes

### Key Modifications Made

1. **Taskfile.yml Updates**:

   - Removed worker configuration patch from config generation
   - Updated bootstrap process to handle multiple control plane nodes
   - Added conversion task for existing clusters
   - Enhanced cluster status reporting

2. **Control Plane Optimizations**:

   - Added leader election tuning for better performance
   - Optimized etcd settings for 3-node cluster
   - Enabled scheduling on control planes (already configured)

3. **Worker Configuration**:
   - No longer used in this all-control-plane setup
   - Kept for reference/backup purposes

## Usage

### For New Clusters

```bash
# Generate and apply configuration
task talos:generate-config

# Apply to all nodes (all get control plane config)
task talos:apply-config

# Bootstrap the cluster
task talos:bootstrap
```

### Converting Existing Cluster

If you have an existing cluster with dedicated worker nodes:

```bash
# Convert existing cluster to all-control-plane
task talos:convert-to-all-controlplane
```

This will:

1. Generate new control plane configuration
2. Apply it to all nodes
3. Wait for nodes to restart and rejoin
4. Verify the conversion

### Verification

Check cluster status:

```bash
task cluster:status
```

This will show:

- All nodes with `control-plane` role
- etcd pods running on all nodes
- Control plane components distributed across nodes

## Benefits of All-Control-Plane Setup

1. **Resource Efficiency**: No dedicated worker nodes means all resources available for workloads
2. **High Availability**: Control plane survives single node failure
3. **Simplified Management**: All nodes have identical configuration
4. **Better Resilience**: etcd distributed across all nodes

## Considerations

1. **Resource Usage**: Control plane components use some CPU/memory on each node
2. **Network Requirements**: etcd requires low-latency network between nodes
3. **Backup Strategy**: All nodes contain etcd data, ensure proper backup procedures

## etcd Health

Monitor etcd cluster health:

```bash
# Check etcd pods
kubectl get pods -n kube-system -l component=etcd

# Check etcd endpoints
kubectl get endpoints -n kube-system etcd

# Detailed etcd status via Talos
talosctl -n 172.29.51.11,172.29.51.12,172.29.51.13 service etcd
```

## Troubleshooting

### Node Not Joining as Control Plane

1. Check node configuration:

   ```bash
   talosctl get machineconfig -n <node-ip>
   ```

2. Verify control plane components:

   ```bash
   kubectl get pods -n kube-system -l tier=control-plane
   ```

3. Check etcd cluster membership:
   ```bash
   talosctl -n <node-ip> etcd members
   ```

### Control Plane Component Issues

1. Check component logs:

   ```bash
   kubectl logs -n kube-system <component-pod>
   ```

2. Verify API server accessibility:

   ```bash
   kubectl get nodes
   ```

3. Check scheduler/controller manager:
   ```bash
   kubectl get pods -n kube-system -l tier=control-plane
   ```
