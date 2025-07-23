# BGP LoadBalancer Troubleshooting Guide

## Overview

This guide provides systematic troubleshooting procedures for the BGP LoadBalancer system in the Talos GitOps home-ops cluster. The BGP LoadBalancer migration has been successfully completed, but this guide helps diagnose and resolve any operational issues.

## Quick Diagnostic Commands

### Immediate Status Check
```bash
# Overall BGP status
task bgp-loadbalancer:status

# Comprehensive troubleshooting
task bgp-loadbalancer:troubleshoot

# BGP peering verification
task bgp-loadbalancer:verify-bgp-peering
```

### Service Connectivity Test
```bash
# Test all LoadBalancer services
task bgp-loadbalancer:test-connectivity

# Check specific service
curl -s --connect-timeout 5 http://172.29.52.200  # Ingress
curl -s --connect-timeout 5 http://172.29.52.100  # Longhorn
```

## Common Issues and Solutions

### 1. BGP Peering Issues

#### Symptoms
- Services get external IPs but are not accessible from network
- BGP peering shows as "Idle" or "Connect" state
- Routes not appearing in UDM Pro routing table

#### Diagnosis
```bash
# Check BGP peering policy
kubectl get ciliumbgppeeringpolicy -o yaml

# Check Cilium BGP logs
kubectl logs -n kube-system -l k8s-app=cilium --tail=100 | grep -i bgp

# Verify UDM Pro BGP status
ssh unifi-admin@udm-pro "vtysh -c 'show bgp summary'"
```

#### Solutions

##### A. Network Connectivity Issues
```bash
# Test connectivity to UDM Pro from cluster nodes
kubectl exec -n kube-system -l k8s-app=cilium -- ping -c 3 172.29.51.1

# Check firewall rules on UDM Pro
# Ensure BGP port 179 is open between cluster nodes and UDM Pro
```

##### B. BGP Configuration Mismatch
```bash
# Verify ASN configuration
kubectl get ciliumbgppeeringpolicy -o yaml | grep -E "localASN|peerASN"
# Should show: localASN: 64512, peerASN: 64513

# Check UDM Pro configuration
ssh unifi-admin@udm-pro "vtysh -c 'show running-config' | grep -A 20 'router bgp'"
```

##### C. Schema Compatibility Issues
**Root Cause**: Using newer CiliumBGPClusterConfig/CiliumBGPAdvertisement with Cilium v1.17.6

**Solution**: Use legacy [`CiliumBGPPeeringPolicy`](../infrastructure/cilium-bgp/bgp-policy-legacy.yaml)
```bash
# Verify using legacy schema
kubectl get ciliumbgppeeringpolicy
# Should show the bgp-peering-policy resource

# If using newer schema, switch to legacy
kubectl apply -f infrastructure/cilium-bgp/bgp-policy-legacy.yaml
kubectl delete ciliumbgpclusterconfig --all
kubectl delete ciliumbgpadvertisement --all
```

### 2. LoadBalancer IP Assignment Issues

#### Symptoms
- LoadBalancer services stuck in "Pending" state
- Services not getting external IPs
- Wrong IP pool assignment

#### Diagnosis
```bash
# Check LoadBalancer IP pools
kubectl get ciliumloadbalancerippool -o wide

# Check service annotations
kubectl get svc --all-namespaces -o yaml | grep -A 5 -B 5 "lb-ipam-pool"

# Check Cilium IPAM logs
kubectl logs -n kube-system -l k8s-app=cilium-operator --tail=50 | grep -i ipam
```

#### Solutions

##### A. IPAM Not Enabled
```bash
# Verify Cilium IPAM is enabled
helm get values cilium -n kube-system | grep -i ipam
# Should show: enable-lb-ipam: true

# If not enabled, update Cilium
helm upgrade cilium cilium/cilium -n kube-system --reuse-values --set enable-lb-ipam=true
```

##### B. Pool Configuration Issues
```bash
# Check pool blocks and selectors
kubectl get ciliumloadbalancerippool -o yaml | grep -A 10 -B 5 "blocks\|serviceSelector"

# Verify pool has available IPs
task bgp-loadbalancer:check-pools
```

##### C. Service Pool Assignment
```bash
# Assign service to correct pool
task bgp-loadbalancer:update-service-pools \
  SERVICE=your-service \
  NAMESPACE=your-namespace \
  POOL=bgp-default
```

### 3. Route Advertisement Issues

#### Symptoms
- BGP peering established but routes not advertised
- Services get IPs but not accessible from network
- UDM Pro routing table missing LoadBalancer routes

#### Diagnosis
```bash
# Check BGP advertisements
kubectl get ciliumbgppeeringpolicy -o yaml | grep -A 10 "serviceSelector"

# Check Cilium BGP route table
kubectl exec -n kube-system -l k8s-app=cilium -- cilium bgp routes

# Check UDM Pro received routes
ssh unifi-admin@udm-pro "vtysh -c 'show bgp ipv4 unicast' | grep 172.29.52"
```

#### Solutions

##### A. Service Selector Issues
The legacy [`CiliumBGPPeeringPolicy`](../infrastructure/cilium-bgp/bgp-policy-legacy.yaml) uses `serviceSelector: {}` to advertise all LoadBalancer services.

```bash
# Verify service selector configuration
kubectl get ciliumbgppeeringpolicy bgp-peering-policy -o yaml | grep -A 5 serviceSelector
# Should show: serviceSelector: {}
```

##### B. UDM Pro Route Acceptance
```bash
# Check UDM Pro route acceptance policy
ssh unifi-admin@udm-pro "vtysh -c 'show running-config' | grep -A 10 'route-map'"

# Verify prefix-list allows LoadBalancer IPs
ssh unifi-admin@udm-pro "vtysh -c 'show running-config' | grep -A 5 'prefix-list CLUSTER-ROUTES'"
# Should include: permit 172.29.52.0/24 le 32
```

### 4. Service Accessibility Issues

#### Symptoms
- Services have external IPs and routes are advertised
- Services still not accessible from client machines
- Connection timeouts or refused connections

#### Diagnosis
```bash
# Test network path
ping 172.29.52.200  # Should reach ingress IP
telnet 172.29.52.200 80  # Should connect to service port

# Check service endpoints
kubectl get endpoints --all-namespaces | grep -E "(longhorn|grafana|prometheus)"

# Check ingress controller status
kubectl get pods -n ingress-nginx-internal -o wide
```

#### Solutions

##### A. Service Endpoint Issues
```bash
# Check if service has healthy endpoints
kubectl describe svc your-service -n your-namespace

# If no endpoints, check pod status
kubectl get pods -n your-namespace -o wide
```

##### B. Network Policy Blocking
```bash
# Check for network policies
kubectl get networkpolicies --all-namespaces

# Test with network policy disabled (temporarily)
kubectl delete networkpolicy problematic-policy -n namespace
```

##### C. Firewall or Security Groups
```bash
# Check if UDM Pro is forwarding traffic correctly
ssh unifi-admin@udm-pro "iptables -L -n | grep 172.29.52"

# Test from UDM Pro directly
ssh unifi-admin@udm-pro "curl -s --connect-timeout 5 http://172.29.52.200"
```

### 5. Cilium v1.17.6 Specific Issues

#### Mac Mini Compatibility
**Issue**: XDP acceleration causes issues on Mac mini hardware

**Solution**: Ensure XDP is disabled
```bash
# Check current Cilium configuration
helm get values cilium -n kube-system | grep acceleration
# Should show: acceleration: disabled

# If not disabled, update
helm upgrade cilium cilium/cilium -n kube-system --reuse-values --set loadBalancer.acceleration=disabled
```

#### Schema Compatibility
**Issue**: Newer BGP CRDs not compatible with Cilium v1.17.6

**Solution**: Use legacy schema only
```bash
# Remove newer BGP resources if present
kubectl delete ciliumbgpclusterconfig --all
kubectl delete ciliumbgpadvertisement --all
kubectl delete ciliumbgppeerconfig --all

# Apply legacy configuration
kubectl apply -f infrastructure/cilium-bgp/bgp-policy-legacy.yaml
```

## Systematic Troubleshooting Workflow

### Step 1: Basic Health Check
```bash
# Check cluster health
kubectl get nodes -o wide
kubectl get pods -n kube-system | grep cilium

# Check BGP resources
kubectl get ciliumbgppeeringpolicy
kubectl get ciliumloadbalancerippool
```

### Step 2: BGP Peering Verification
```bash
# Check peering status
task bgp-loadbalancer:verify-bgp-peering

# If peering down, check logs
kubectl logs -n kube-system -l k8s-app=cilium --tail=100 | grep -i "bgp\|peer\|neighbor"
```

### Step 3: Service IP Assignment
```bash
# Check service IPs
kubectl get svc --all-namespaces | grep LoadBalancer

# If no IPs assigned, check IPAM
kubectl logs -n kube-system -l k8s-app=cilium-operator --tail=50 | grep -i ipam
```

### Step 4: Route Advertisement
```bash
# Check routes on UDM Pro
ssh unifi-admin@udm-pro "vtysh -c 'show bgp ipv4 unicast' | grep 172.29.52"

# If no routes, check service selector
kubectl get ciliumbgppeeringpolicy -o yaml | grep -A 5 serviceSelector
```

### Step 5: End-to-End Connectivity
```bash
# Test from client machine
curl -v http://172.29.52.200
ping 172.29.52.100

# If fails, check service endpoints
kubectl get endpoints --all-namespaces | grep your-service
```

## Recovery Procedures

### Complete BGP Reset
```bash
# 1. Remove all BGP resources
kubectl delete ciliumbgppeeringpolicy --all
kubectl delete ciliumloadbalancerippool --all

# 2. Wait for cleanup
sleep 30

# 3. Reapply configuration
kubectl apply -f infrastructure/cilium-bgp/
kubectl apply -f infrastructure/cilium/loadbalancer-pool-bgp.yaml

# 4. Verify recovery
task bgp-loadbalancer:status
```

### Cilium BGP Restart
```bash
# Restart Cilium pods to reset BGP state
kubectl delete pods -n kube-system -l k8s-app=cilium

# Wait for pods to restart
kubectl wait --for=condition=Ready pods -l k8s-app=cilium -n kube-system --timeout=300s

# Verify BGP functionality
task bgp-loadbalancer:verify-bgp-peering
```

### UDM Pro BGP Reset
```bash
# Reset BGP on UDM Pro (requires SSH access)
ssh unifi-admin@udm-pro "vtysh -c 'clear bgp *'"

# Verify peering re-establishment
ssh unifi-admin@udm-pro "vtysh -c 'show bgp summary'"
```

## Monitoring and Prevention

### Health Check Script
```bash
#!/bin/bash
# BGP LoadBalancer Health Monitor

echo "=== BGP LoadBalancer Health Check ==="
echo "Timestamp: $(date)"

# Check BGP peering
echo "1. BGP Peering Status:"
if kubectl get ciliumbgppeeringpolicy >/dev/null 2>&1; then
    echo "✓ BGP peering policy exists"
else
    echo "✗ BGP peering policy missing"
fi

# Check service IPs
echo "2. LoadBalancer Services:"
lb_services=$(kubectl get svc --all-namespaces -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer") | .metadata.name' | wc -l)
echo "   Total LoadBalancer services: $lb_services"

# Check connectivity
echo "3. Service Connectivity:"
if curl -s --connect-timeout 5 http://172.29.52.200 >/dev/null; then
    echo "✓ Ingress accessible (172.29.52.200)"
else
    echo "✗ Ingress not accessible"
fi

if curl -s --connect-timeout 5 http://172.29.52.100 >/dev/null; then
    echo "✓ Longhorn accessible (172.29.52.100)"
else
    echo "✗ Longhorn not accessible"
fi

echo "Health check completed"
```

### Automated Monitoring
- **Prometheus Metrics**: Monitor BGP peering status and route advertisement
- **Service Monitors**: Track LoadBalancer service accessibility
- **Alerting**: Set up alerts for BGP peering failures and service unavailability

## Configuration Validation

### Pre-deployment Checks
```bash
# Validate BGP configuration syntax
kubectl apply --dry-run=client -f infrastructure/cilium-bgp/bgp-policy-legacy.yaml

# Validate IP pool configuration
kubectl apply --dry-run=client -f infrastructure/cilium/loadbalancer-pool-bgp.yaml

# Check for resource conflicts
kubectl get ciliumbgpclusterconfig 2>/dev/null && echo "WARNING: Remove newer BGP resources"
```

### Post-deployment Validation
```bash
# Comprehensive validation
task bgp-loadbalancer:status
task bgp-loadbalancer:test-connectivity
task bgp-loadbalancer:verify-bgp-peering

# Generate status report
task bgp-loadbalancer:generate-report
```

## Emergency Contacts and Escalation

### Critical Issues
- **BGP Peering Complete Failure**: Check UDM Pro configuration and network connectivity
- **All Services Inaccessible**: Verify Cilium health and consider CNI restart
- **Schema Compatibility Problems**: Ensure using legacy [`CiliumBGPPeeringPolicy`](../infrastructure/cilium-bgp/bgp-policy-legacy.yaml)

### Support Resources
- **Configuration Files**: [`infrastructure/cilium-bgp/`](../infrastructure/cilium-bgp/) and [`infrastructure/cilium/`](../infrastructure/cilium/)
- **Operational Guide**: [`docs/BGP_LOADBALANCER_OPERATIONAL_GUIDE.md`](BGP_LOADBALANCER_OPERATIONAL_GUIDE.md)
- **Task Commands**: [`taskfiles/bgp-loadbalancer.yml`](../taskfiles/bgp-loadbalancer.yml)

The BGP LoadBalancer system is production-ready and stable. This troubleshooting guide helps maintain operational excellence and quickly resolve any issues that may arise.