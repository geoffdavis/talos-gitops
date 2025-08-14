#!/bin/bash

# Aggressive Recovery Strategy - Monitoring Script
# Real-time monitoring of recovery progress

echo "=== AGGRESSIVE RECOVERY MONITORING ==="
echo "Timestamp: $(date)"
echo "Press Ctrl+C to exit monitoring"
echo

# Function to get ready count
get_ready_count() {
    flux get kustomizations 2>/dev/null | grep -c "True.*Ready" || echo "0"
}

# Function to check authentication system
check_auth_system() {
    kubectl get pods -n authentik-proxy --no-headers 2>/dev/null | grep -c "Running" || echo "0"
}

# Function to test service accessibility
test_services() {
    local success=0
    local services=("longhorn" "grafana" "prometheus" "alertmanager" "dashboard" "homeassistant")

    for service in "${services[@]}"; do
        if curl -s -I -k "https://$service.k8s.home.geoffdavis.com" --max-time 5 | grep -q "HTTP"; then
            ((success++))
        fi
    done
    echo "$success"
}

# Initial state
echo "📊 Initial State Assessment:"
INITIAL_READY=$(get_ready_count)
INITIAL_AUTH=$(check_auth_system)
echo "   Ready Kustomizations: $INITIAL_READY/31"
echo "   Auth System Pods: $INITIAL_AUTH"
echo

# Monitoring loop
COUNTER=0
LAST_READY=$INITIAL_READY
LAST_AUTH=$INITIAL_AUTH

while true; do
    ((COUNTER++))

    # Clear previous output (keep header)
    if [ $COUNTER -gt 1 ]; then
        tput cuu 15  # Move cursor up 15 lines
        tput ed      # Clear from cursor to end of screen
    fi

    echo "🔄 Monitoring Cycle #$COUNTER ($(date +%H:%M:%S))"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Get current status
    CURRENT_READY=$(get_ready_count)
    CURRENT_AUTH=$(check_auth_system)

    # Show progress
    echo "📈 Progress Tracking:"
    echo "   Ready Kustomizations: $CURRENT_READY/31"
    if [ "$CURRENT_READY" -gt "$LAST_READY" ]; then
        echo "   ✅ IMPROVEMENT: +$(( CURRENT_READY - LAST_READY )) since last check"
    elif [ "$CURRENT_READY" -lt "$LAST_READY" ]; then
        echo "   ⚠️  REGRESSION: -$(( LAST_READY - CURRENT_READY )) since last check"
    else
        echo "   ➡️  No change since last check"
    fi

    echo "   Auth System Pods: $CURRENT_AUTH"
    if [ "$CURRENT_AUTH" -gt "$LAST_AUTH" ]; then
        echo "   ✅ AUTH IMPROVED: +$(( CURRENT_AUTH - LAST_AUTH )) pods"
    elif [ "$CURRENT_AUTH" -lt "$LAST_AUTH" ]; then
        echo "   ⚠️  AUTH REGRESSION: -$(( LAST_AUTH - CURRENT_AUTH )) pods"
    fi

    # Show failing components
    echo
    echo "❌ Failing Components:"
    FAILING=$(flux get kustomizations 2>/dev/null | grep -v "True.*Ready" | tail -n +2)
    if [ -z "$FAILING" ]; then
        echo "   🎉 NO FAILING COMPONENTS!"
    else
        echo "$FAILING" | head -5 | sed 's/^/   /'
        FAILING_COUNT=$(echo "$FAILING" | wc -l)
        if [ "$FAILING_COUNT" -gt 5 ]; then
            echo "   ... and $(( FAILING_COUNT - 5 )) more"
        fi
    fi

    # Test services periodically (every 5th cycle)
    if [ $(( COUNTER % 5 )) -eq 0 ]; then
        echo
        echo "🌐 Service Accessibility Test:"
        SERVICE_COUNT=$(test_services)
        echo "   Accessible Services: $SERVICE_COUNT/6"
        if [ "$SERVICE_COUNT" -eq 6 ]; then
            echo "   ✅ All services accessible"
        elif [ "$SERVICE_COUNT" -gt 3 ]; then
            echo "   ⚠️  Some services accessible"
        else
            echo "   ❌ Most services not accessible"
        fi
    fi

    # Success check
    if [ "$CURRENT_READY" -eq 31 ] && [ "$CURRENT_AUTH" -gt 0 ]; then
        echo
        echo "🎉 SUCCESS DETECTED!"
        echo "   ✅ All 31 Kustomizations Ready"
        echo "   ✅ Authentication system operational"
        echo
        echo "Run './validate-recovery-success.sh' for full validation"
        break
    fi

    # Update tracking variables
    LAST_READY=$CURRENT_READY
    LAST_AUTH=$CURRENT_AUTH

    # Wait before next check
    sleep 10
done

echo
echo "=== MONITORING COMPLETE ==="
echo "Final Status: $CURRENT_READY/31 Ready, $CURRENT_AUTH Auth Pods"
echo "Duration: $(( COUNTER * 10 )) seconds"
