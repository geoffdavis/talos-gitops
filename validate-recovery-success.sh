#!/bin/bash
set -e

echo "=== RECOVERY SUCCESS VALIDATION ==="
echo "Timestamp: $(date)"
echo

# Check Flux status
echo "1. Flux Kustomizations Status:"
READY_COUNT=$(flux get kustomizations | grep -c "True.*Ready")
echo "   Ready: $READY_COUNT/31"
if [ "$READY_COUNT" -eq 31 ]; then
    echo "   ✅ SUCCESS: 100% Ready status achieved"
else
    echo "   ❌ INCOMPLETE: Missing $(( 31 - READY_COUNT )) Kustomizations"
    flux get kustomizations | grep -v "True.*Ready"
fi
echo

# Check authentication system
echo "2. Authentication System Status:"
AUTH_PODS=$(kubectl get pods -n authentik-proxy --no-headers | grep -c "Running")
echo "   Authentik Proxy Pods Running: $AUTH_PODS"
if [ "$AUTH_PODS" -gt 0 ]; then
    echo "   ✅ Authentication system operational"
else
    echo "   ❌ Authentication system not running"
fi
echo

# Test service accessibility
echo "3. Service Accessibility Test:"
services=("longhorn" "grafana" "prometheus" "alertmanager" "dashboard" "homeassistant")
success_count=0
for service in "${services[@]}"; do
    if curl -s -I -k "https://$service.k8s.home.geoffdavis.com" | grep -q "HTTP"; then
        echo "   ✅ $service.k8s.home.geoffdavis.com accessible"
        ((success_count++))
    else
        echo "   ❌ $service.k8s.home.geoffdavis.com not accessible"
    fi
done
echo "   Services accessible: $success_count/6"
echo

# Check system health
echo "4. System Health Check:"
NODE_COUNT=$(kubectl get nodes --no-headers | grep -c "Ready")
echo "   Nodes Ready: $NODE_COUNT/3"
FAILED_PODS=$(kubectl get pods -A --field-selector=status.phase!=Running --no-headers | grep -cv Completed)
echo "   Failed Pods: $FAILED_PODS"
if [ "$FAILED_PODS" -eq 0 ]; then
    echo "   ✅ All pods running successfully"
else
    echo "   ❌ $FAILED_PODS pods not running"
fi
echo

# Final assessment
echo "=== FINAL ASSESSMENT ==="
if [ "$READY_COUNT" -eq 31 ] && [ "$AUTH_PODS" -gt 0 ] && [ "$success_count" -eq 6 ] && [ "$FAILED_PODS" -eq 0 ]; then
    echo "🎉 RECOVERY SUCCESSFUL: All criteria met"
    echo "   - 100% Flux Kustomizations ready"
    echo "   - Authentication system operational"
    echo "   - All services accessible"
    echo "   - System health optimal"
    exit 0
else
    echo "⚠️  RECOVERY INCOMPLETE: Some criteria not met"
    echo "   Review failed checks above and apply corrective measures"
    exit 1
fi