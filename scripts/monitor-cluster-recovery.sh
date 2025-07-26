#!/bin/bash

# Cluster Recovery Monitoring Script
# Monitors cluster recovery after physical power cycling of affected nodes

set -e

echo "=== Cluster Recovery Monitoring ==="
echo "Monitoring recovery of mini01 (172.29.51.11) and mini03 (172.29.51.13)"
echo "Started at: $(date)"
echo

# Function to check node status
check_nodes() {
    echo "--- Node Status ---"
    mise exec -- kubectl get nodes -o wide
    echo
}

# Function to check Cilium pods
check_cilium() {
    echo "--- Cilium Pod Status ---"
    mise exec -- kubectl get pods -n kube-system | grep cilium
    echo
}

# Function to check for virtual device errors
check_virtual_device_errors() {
    echo "--- Checking for Virtual Device Errors ---"
    echo "Checking mini01 (172.29.51.11):"
    if mise exec -- talosctl dmesg --nodes 172.29.51.11 | grep -i "dead loop\|virtual device" | tail -5; then
        echo "⚠️  Virtual device errors still present on mini01"
    else
        echo "✅ No virtual device errors on mini01"
    fi
    
    echo "Checking mini03 (172.29.51.13):"
    if mise exec -- talosctl dmesg --nodes 172.29.51.13 | grep -i "dead loop\|virtual device" | tail -5; then
        echo "⚠️  Virtual device errors still present on mini03"
    else
        echo "✅ No virtual device errors on mini03"
    fi
    echo
}

# Function to check cluster health
check_cluster_health() {
    echo "--- Cluster Health Summary ---"
    
    # Count ready nodes
    READY_NODES=$(mise exec -- kubectl get nodes --no-headers | grep -c "Ready" || echo "0")
    TOTAL_NODES=$(mise exec -- kubectl get nodes --no-headers | wc -l)
    
    echo "Ready nodes: $READY_NODES/$TOTAL_NODES"
    
    # Check Cilium status
    CILIUM_RUNNING=$(mise exec -- kubectl get pods -n kube-system | grep cilium | grep -c "Running" || echo "0")
    CILIUM_TOTAL=$(mise exec -- kubectl get pods -n kube-system | grep -c cilium)
    
    echo "Cilium pods running: $CILIUM_RUNNING/$CILIUM_TOTAL"
    
    if [ "$READY_NODES" -eq 3 ] && [ "$CILIUM_RUNNING" -gt 0 ]; then
        echo "🎉 Cluster recovery appears successful!"
        return 0
    else
        echo "⏳ Cluster still recovering..."
        return 1
    fi
}

# Main monitoring loop
RECOVERY_COMPLETE=false
ATTEMPT=1
MAX_ATTEMPTS=30  # 15 minutes with 30-second intervals

while [ "$RECOVERY_COMPLETE" = false ] && [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    echo "=== Recovery Check #$ATTEMPT ($(date)) ==="
    
    check_nodes
    check_cilium
    
    # Only check for virtual device errors if nodes are responsive
    if mise exec -- talosctl version --nodes 172.29.51.11,172.29.51.13 >/dev/null 2>&1; then
        check_virtual_device_errors
    else
        echo "--- Virtual Device Error Check ---"
        echo "⏳ Nodes not yet responsive to talosctl commands"
        echo
    fi
    
    if check_cluster_health; then
        RECOVERY_COMPLETE=true
        echo
        echo "🎉 CLUSTER RECOVERY COMPLETE! 🎉"
        echo "All nodes are Ready and Cilium is running normally."
        echo "Recovery completed at: $(date)"
        break
    fi
    
    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
        echo "Waiting 30 seconds before next check..."
        echo "========================================"
        echo
        sleep 30
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
done

if [ "$RECOVERY_COMPLETE" = false ]; then
    echo "⚠️  Recovery monitoring timed out after $MAX_ATTEMPTS attempts"
    echo "Manual intervention may be required."
    exit 1
fi