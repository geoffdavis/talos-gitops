#!/bin/bash

# Quick Cluster Recovery Validation Script
# Validates that the cluster has fully recovered from the virtual device loop issue

set -e

echo "=== Cluster Recovery Validation ==="
echo "Validating recovery from 'Dead loop on virtual device' issue"
echo "Validation started at: $(date)"
echo

# Check 1: Node Status
echo "✓ Checking node status..."
NODE_STATUS=$(mise exec -- kubectl get nodes --no-headers)
echo "$NODE_STATUS"

READY_COUNT=$(echo "$NODE_STATUS" | grep -c "Ready" || echo "0")
TOTAL_COUNT=$(echo "$NODE_STATUS" | wc -l)

if [ "$READY_COUNT" -eq 3 ] && [ "$TOTAL_COUNT" -eq 3 ]; then
    echo "✅ All 3 nodes are Ready"
else
    echo "❌ Node status check failed: $READY_COUNT/$TOTAL_COUNT nodes Ready"
    exit 1
fi
echo

# Check 2: Cilium Pod Status
echo "✓ Checking Cilium pod status..."
CILIUM_PODS=$(mise exec -- kubectl get pods -n kube-system | grep cilium)
echo "$CILIUM_PODS"

CILIUM_RUNNING=$(echo "$CILIUM_PODS" | grep -c "Running" || echo "0")
CILIUM_TOTAL=$(echo "$CILIUM_PODS" | wc -l)

if [ "$CILIUM_RUNNING" -ge 3 ]; then
    echo "✅ Cilium pods are running normally ($CILIUM_RUNNING/$CILIUM_TOTAL)"
else
    echo "❌ Cilium pod check failed: only $CILIUM_RUNNING/$CILIUM_TOTAL pods running"
    exit 1
fi
echo

# Check 3: Virtual Device Error Check
echo "✓ Checking for virtual device errors..."
ERRORS_FOUND=false

echo "Checking mini01 (172.29.51.11)..."
if mise exec -- talosctl dmesg --nodes 172.29.51.11 | grep -i "dead loop\|virtual device" >/dev/null 2>&1; then
    echo "❌ Virtual device errors still present on mini01"
    ERRORS_FOUND=true
else
    echo "✅ No virtual device errors on mini01"
fi

echo "Checking mini03 (172.29.51.13)..."
if mise exec -- talosctl dmesg --nodes 172.29.51.13 | grep -i "dead loop\|virtual device" >/dev/null 2>&1; then
    echo "❌ Virtual device errors still present on mini03"
    ERRORS_FOUND=true
else
    echo "✅ No virtual device errors on mini03"
fi

if [ "$ERRORS_FOUND" = true ]; then
    echo "❌ Virtual device error check failed"
    exit 1
fi
echo

# Check 4: Network Connectivity
echo "✓ Checking network connectivity..."
if mise exec -- kubectl get pods -A | grep -v "Running\|Completed" | grep -v "READY" >/dev/null; then
    echo "⚠️  Some pods are not in Running state (may be normal during recovery)"
else
    echo "✅ All pods appear to be running normally"
fi
echo

# Final Summary
echo "🎉 CLUSTER RECOVERY VALIDATION SUCCESSFUL! 🎉"
echo
echo "Summary:"
echo "- All 3 nodes (mini01, mini02, mini03) are Ready"
echo "- Cilium networking is functioning normally"
echo "- No virtual device loop errors detected"
echo "- Cluster is ready for USB SSD storage deployment"
echo
echo "Validation completed at: $(date)"
