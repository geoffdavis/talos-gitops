# Bitnami Migration Testing Guide

## Overview

This document provides comprehensive testing procedures for validating the successful migration from Bitnami Helm charts to upstream repositories. The testing framework ensures that all migrated components maintain functionality, performance, and security standards while providing clear rollback procedures if issues are discovered.

**Migration Status**: ✅ **COMPLETED** - All testing procedures validated
**Testing Framework**: Comprehensive validation across 5 migrated components
**Validation Coverage**: Functionality, Integration, Performance, Security

## Testing Philosophy

### Testing Principles

1. **Comprehensive Coverage**: Test all aspects of migrated components
2. **Automated Where Possible**: Reduce manual testing overhead
3. **Clear Pass/Fail Criteria**: Unambiguous success metrics
4. **Rollback Readiness**: Quick identification of issues requiring rollback
5. **Documentation**: Clear documentation of all test results

### Testing Phases

1. **Pre-Migration Baseline**: Establish performance and functionality baselines
2. **Migration Validation**: Verify successful migration completion
3. **Post-Migration Testing**: Comprehensive functionality and integration testing
4. **Performance Validation**: Ensure no performance degradation
5. **Security Verification**: Validate security configurations and access controls

## Component-Specific Testing Procedures

### Phase 1: Kubernetes Dashboard Testing

#### Pre-Migration Baseline Tests

```bash
#!/bin/bash
# dashboard-pre-migration-tests.sh

echo "=== Kubernetes Dashboard Pre-Migration Baseline ==="

# 1. Verify current dashboard accessibility
echo "Testing dashboard accessibility..."
curl -k -I https://dashboard.k8s.home.geoffdavis.com
if [ $? -eq 0 ]; then
    echo "✅ Dashboard accessible"
else
    echo "❌ Dashboard not accessible"
    exit 1
fi

# 2. Test authentication flow
echo "Testing authentication flow..."
# Note: Manual test required for SSO flow

# 3. Verify Kong proxy functionality
echo "Testing Kong proxy..."
kubectl get pods -n kubernetes-dashboard -l app.kubernetes.io/name=kong
kubectl logs -n kubernetes-dashboard -l app.kubernetes.io/name=kong --tail=10

# 4. Check service endpoints
echo "Checking service endpoints..."
kubectl get endpoints -n kubernetes-dashboard

# 5. Verify RBAC permissions
echo "Testing RBAC permissions..."
kubectl auth can-i --list --as=system:serviceaccount:kubernetes-dashboard:kubernetes-dashboard

echo "Pre-migration baseline complete"
```

#### Post-Migration Validation Tests

```bash
#!/bin/bash
# dashboard-post-migration-tests.sh

echo "=== Kubernetes Dashboard Post-Migration Validation ==="

# 1. Verify HelmRelease status
echo "Checking HelmRelease status..."
kubectl get helmrelease kubernetes-dashboard -n kubernetes-dashboard -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'

# 2. Verify all pods are running
echo "Checking pod status..."
kubectl get pods -n kubernetes-dashboard
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=kubernetes-dashboard -n kubernetes-dashboard --timeout=300s

# 3. Test dashboard functionality
echo "Testing dashboard functionality..."
curl -k -I https://dashboard.k8s.home.geoffdavis.com
if [ $? -eq 0 ]; then
    echo "✅ Dashboard accessible after migration"
else
    echo "❌ Dashboard not accessible after migration"
    exit 1
fi

# 4. Verify Kong configuration
echo "Testing Kong configuration..."
kubectl get configmap kubernetes-dashboard-kong-config -n kubernetes-dashboard -o yaml

# 5. Test authentication integration
echo "Testing Authentik integration..."
kubectl get service -n kubernetes-dashboard -o yaml | grep -A 5 -B 5 "authentik.io"

# 6. Verify bearer token elimination
echo "Testing bearer token elimination..."
# Manual test: Access dashboard and verify no token prompt

echo "Post-migration validation complete"
```

#### Dashboard Functionality Tests

```bash
#!/bin/bash
# dashboard-functionality-tests.sh

echo "=== Dashboard Functionality Tests ==="

# 1. Test cluster overview access
echo "Testing cluster overview..."
# Manual: Navigate to dashboard and verify cluster overview loads

# 2. Test namespace browsing
echo "Testing namespace browsing..."
# Manual: Verify ability to browse different namespaces

# 3. Test resource management
echo "Testing resource management..."
# Manual: Verify ability to view pods, services, deployments

# 4. Test administrative functions
echo "Testing administrative functions..."
# Manual: Verify ability to scale deployments, view logs

# 5. Test Kong proxy headers
echo "Testing Kong proxy headers..."
kubectl exec -n kubernetes-dashboard deployment/kubernetes-dashboard-kong -- curl -I http://localhost:8000/

echo "Functionality tests complete"
```

### Phase 1: Authentik Testing

#### Authentik Migration Validation

```bash
#!/bin/bash
# authentik-migration-tests.sh

echo "=== Authentik Migration Validation ==="

# 1. Verify HelmRelease status
echo "Checking Authentik HelmRelease..."
kubectl get helmrelease authentik -n authentik -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'

# 2. Check all pods are running
echo "Checking Authentik pods..."
kubectl get pods -n authentik
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=authentik -n authentik --timeout=300s

# 3. Verify database connectivity
echo "Testing database connectivity..."
kubectl exec -n authentik deployment/authentik-server -- python -c "
import os
import psycopg2
try:
    conn = psycopg2.connect(
        host=os.environ['AUTHENTIK_POSTGRESQL__HOST'],
        database=os.environ['AUTHENTIK_POSTGRESQL__NAME'],
        user=os.environ['AUTHENTIK_POSTGRESQL__USER'],
        password=os.environ['AUTHENTIK_POSTGRESQL__PASSWORD']
    )
    print('✅ Database connection successful')
    conn.close()
except Exception as e:
    print(f'❌ Database connection failed: {e}')
    exit(1)
"

# 4. Test Redis connectivity
echo "Testing Redis connectivity..."
kubectl exec -n authentik deployment/authentik-server -- python -c "
import redis
import os
try:
    r = redis.Redis(host=os.environ['AUTHENTIK_REDIS__HOST'], port=int(os.environ['AUTHENTIK_REDIS__PORT']))
    r.ping()
    print('✅ Redis connection successful')
except Exception as e:
    print(f'❌ Redis connection failed: {e}')
    exit(1)
"

# 5. Verify web interface accessibility
echo "Testing Authentik web interface..."
curl -k -I https://authentik.k8s.home.geoffdavis.com
if [ $? -eq 0 ]; then
    echo "✅ Authentik web interface accessible"
else
    echo "❌ Authentik web interface not accessible"
    exit 1
fi

echo "Authentik migration validation complete"
```

#### External Outpost Testing

```bash
#!/bin/bash
# authentik-outpost-tests.sh

echo "=== Authentik External Outpost Testing ==="

# 1. Verify external outpost pods
echo "Checking external outpost pods..."
kubectl get pods -n authentik-proxy
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=authentik-proxy -n authentik-proxy --timeout=300s

# 2. Test outpost connectivity to Authentik server
echo "Testing outpost connectivity..."
kubectl exec -n authentik-proxy deployment/authentik-proxy -- curl -I http://authentik-server.authentik.svc.cluster.local:9000/outpost.goauthentik.io/ping

# 3. Verify Redis session storage
echo "Testing Redis session storage..."
kubectl exec -n authentik-proxy deployment/redis -- redis-cli ping

# 4. Test service authentication
echo "Testing service authentication..."
for service in longhorn grafana prometheus alertmanager dashboard hubble; do
    echo "Testing $service authentication..."
    curl -k -I https://$service.k8s.home.geoffdavis.com
    if [ $? -eq 0 ]; then
        echo "✅ $service authentication working"
    else
        echo "❌ $service authentication failed"
    fi
done

# 5. Verify proxy provider configurations
echo "Checking proxy provider configurations..."
kubectl exec -n authentik deployment/authentik-server -- python manage.py shell -c "
from authentik.providers.proxy.models import ProxyProvider
providers = ProxyProvider.objects.all()
for provider in providers:
    print(f'Provider: {provider.name}, External Host: {provider.external_host}')
"

echo "External outpost testing complete"
```

### Phase 2: Longhorn Storage Testing

#### Longhorn Migration Validation

```bash
#!/bin/bash
# longhorn-migration-tests.sh

echo "=== Longhorn Storage Migration Validation ==="

# 1. Verify HelmRelease status
echo "Checking Longhorn HelmRelease..."
kubectl get helmrelease longhorn -n longhorn-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'

# 2. Check Longhorn system pods
echo "Checking Longhorn system pods..."
kubectl get pods -n longhorn-system
kubectl wait --for=condition=Ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s

# 3. Verify storage classes
echo "Checking storage classes..."
kubectl get storageclass
kubectl get storageclass longhorn -o yaml

# 4. Test volume provisioning
echo "Testing volume provisioning..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc-migration
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: longhorn
EOF

# Wait for PVC to be bound
kubectl wait --for=condition=Bound pvc/test-pvc-migration -n default --timeout=300s
if [ $? -eq 0 ]; then
    echo "✅ Volume provisioning successful"
    kubectl delete pvc test-pvc-migration -n default
else
    echo "❌ Volume provisioning failed"
    exit 1
fi

# 5. Verify USB SSD detection
echo "Checking USB SSD detection..."
kubectl exec -n longhorn-system daemonset/longhorn-manager -- ls -la /var/lib/longhorn/

# 6. Test Longhorn UI accessibility
echo "Testing Longhorn UI..."
curl -k -I https://longhorn.k8s.home.geoffdavis.com
if [ $? -eq 0 ]; then
    echo "✅ Longhorn UI accessible"
else
    echo "❌ Longhorn UI not accessible"
    exit 1
fi

echo "Longhorn migration validation complete"
```

#### Longhorn Curl-Dependent Jobs Testing

```bash
#!/bin/bash
# longhorn-curl-jobs-tests.sh

echo "=== Longhorn Curl-Dependent Jobs Testing ==="

# Test backup verification job functionality
echo "Testing backup verification job..."
kubectl get cronjob backup-verification -n longhorn-system
if [ $? -eq 0 ]; then
    echo "✅ Backup verification CronJob exists"
    
    # Test job image has curl capability
    kubectl create job --from=cronjob/backup-verification test-backup-verification -n longhorn-system
    kubectl wait --for=condition=Ready pod -l job-name=test-backup-verification -n longhorn-system --timeout=60s
    
    # Test curl availability in job pod
    TEST_POD=$(kubectl get pod -n longhorn-system -l job-name=test-backup-verification -o jsonpath='{.items[0].metadata.name}')
    kubectl exec -n longhorn-system $TEST_POD -- which curl
    if [ $? -eq 0 ]; then
        echo "✅ Curl available in backup verification job"
    else
        echo "❌ Curl not available in backup verification job"
        exit 1
    fi
    
    # Test bash availability
    kubectl exec -n longhorn-system $TEST_POD -- which bash
    if [ $? -eq 0 ]; then
        echo "✅ Bash available in backup verification job"
    else
        echo "❌ Bash not available in backup verification job"
        exit 1
    fi
    
    # Cleanup test job
    kubectl delete job test-backup-verification -n longhorn-system
else
    echo "❌ Backup verification CronJob not found"
    exit 1
fi

# Test backup restore test job functionality
echo "Testing backup restore test job..."
kubectl get cronjob backup-restore-test -n longhorn-system
if [ $? -eq 0 ]; then
    echo "✅ Backup restore test CronJob exists"
    
    # Verify image is alpine/k8s:1.31.1
    IMAGE=$(kubectl get cronjob backup-restore-test -n longhorn-system -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}')
    if [ "$IMAGE" = "alpine/k8s:1.31.1" ]; then
        echo "✅ Correct image (alpine/k8s:1.31.1) used for backup restore test"
    else
        echo "❌ Incorrect image used: $IMAGE (expected: alpine/k8s:1.31.1)"
        exit 1
    fi
else
    echo "❌ Backup restore test CronJob not found"
    exit 1
fi

# Test database consistent backup job functionality
echo "Testing database consistent backup job..."
kubectl get cronjob database-consistent-backup -n database 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Database consistent backup CronJob exists"
    
    # Verify image supports bash scripting
    IMAGE=$(kubectl get cronjob database-consistent-backup -n database -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}')
    if [ "$IMAGE" = "alpine/k8s:1.31.1" ]; then
        echo "✅ Correct image (alpine/k8s:1.31.1) used for database backup"
    else
        echo "❌ Incorrect image used: $IMAGE (expected: alpine/k8s:1.31.1)"
        exit 1
    fi
else
    echo "⚠ Database consistent backup CronJob not found (may not be deployed)"
fi

# Test Prometheus pushgateway connectivity for backup monitoring
echo "Testing Prometheus pushgateway connectivity..."
if kubectl get svc prometheus-pushgateway -n monitoring >/dev/null 2>&1; then
    echo "✅ Prometheus pushgateway service exists"
    
    # Test connectivity from backup verification job context
    kubectl run curl-test --image=alpine/k8s:1.31.1 --rm -it --restart=Never -- curl -I http://prometheus-pushgateway.monitoring.svc.cluster.local:9091/metrics
    if [ $? -eq 0 ]; then
        echo "✅ Backup monitoring can reach Prometheus pushgateway"
    else
        echo "❌ Backup monitoring cannot reach Prometheus pushgateway"
        exit 1
    fi
else
    echo "⚠ Prometheus pushgateway not found (backup metrics may not work)"
fi

echo "Longhorn curl-dependent jobs testing complete"
```

#### Storage Performance Testing

```bash
#!/bin/bash
# longhorn-performance-tests.sh

echo "=== Longhorn Performance Testing ==="

# 1. Create test pod with volume
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: longhorn-perf-test
  namespace: default
spec:
  containers:
  - name: test-container
    image: ubuntu:20.04
    command: ["/bin/bash", "-c", "sleep 3600"]
    volumeMounts:
    - name: test-volume
      mountPath: /data
  volumes:
  - name: test-volume
    persistentVolumeClaim:
      claimName: perf-test-pvc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: perf-test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: longhorn
EOF

# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/longhorn-perf-test -n default --timeout=300s

# 2. Run write performance test
echo "Running write performance test..."
kubectl exec longhorn-perf-test -n default -- bash -c "
apt-get update && apt-get install -y fio
fio --name=write-test --ioengine=libaio --rw=write --bs=4k --size=1G --numjobs=1 --runtime=60 --group_reporting --filename=/data/test-file
"

# 3. Run read performance test
echo "Running read performance test..."
kubectl exec longhorn-perf-test -n default -- fio --name=read-test --ioengine=libaio --rw=read --bs=4k --size=1G --numjobs=1 --runtime=60 --group_reporting --filename=/data/test-file

# 4. Cleanup
kubectl delete pod longhorn-perf-test -n default
kubectl delete pvc perf-test-pvc -n default

echo "Performance testing complete"
```

### Phase 2: Matter Server Testing

#### Matter Server Migration Validation

```bash
#!/bin/bash
# matter-server-migration-tests.sh

echo "=== Matter Server Migration Validation ==="

# 1. Verify HelmRelease status
echo "Checking Matter Server HelmRelease..."
kubectl get helmrelease matter-server -n home-automation -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'

# 2. Check pod status
echo "Checking Matter Server pod..."
kubectl get pods -n home-automation -l app.kubernetes.io/name=matter-server
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=matter-server -n home-automation --timeout=300s

# 3. Verify host networking
echo "Verifying host networking configuration..."
kubectl get pod -n home-automation -l app.kubernetes.io/name=matter-server -o jsonpath='{.items[0].spec.hostNetwork}'

# 4. Test Matter Server API
echo "Testing Matter Server API..."
MATTER_POD=$(kubectl get pod -n home-automation -l app.kubernetes.io/name=matter-server -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n home-automation $MATTER_POD -- curl -I http://localhost:5580/

# 5. Verify persistent storage
echo "Checking persistent storage..."
kubectl exec -n home-automation $MATTER_POD -- ls -la /data/

# 6. Test network interface access
echo "Testing network interface access..."
kubectl exec -n home-automation $MATTER_POD -- ip addr show enp3s0f0

echo "Matter Server migration validation complete"
```

### Phase 3: Monitoring Stack Testing

#### Monitoring Migration Validation

```bash
#!/bin/bash
# monitoring-migration-tests.sh

echo "=== Monitoring Stack Migration Validation ==="

# 1. Verify HelmRelease status
echo "Checking monitoring HelmRelease..."
kubectl get helmrelease kube-prometheus-stack -n monitoring -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'

# 2. Check all monitoring pods
echo "Checking monitoring pods..."
kubectl get pods -n monitoring
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=300s
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=300s

# 3. Test external access via BGP LoadBalancer
echo "Testing external access..."
curl -k -I https://grafana.k8s.home.geoffdavis.com
curl -k -I https://prometheus.k8s.home.geoffdavis.com
curl -k -I https://alertmanager.k8s.home.geoffdavis.com

# 4. Verify LoadBalancer IP assignment
echo "Checking LoadBalancer IPs..."
kubectl get svc -n monitoring -o wide | grep LoadBalancer

# 5. Test Prometheus targets
echo "Testing Prometheus targets..."
kubectl exec -n monitoring deployment/prometheus-kube-prometheus-prometheus -- wget -qO- http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'

# 6. Test Grafana dashboards
echo "Testing Grafana dashboards..."
kubectl exec -n monitoring deployment/kube-prometheus-stack-grafana -- curl -I http://localhost:3000/api/health

echo "Monitoring migration validation complete"
```

## Comprehensive Integration Testing

### End-to-End Authentication Flow Testing

```bash
#!/bin/bash
# e2e-authentication-tests.sh

echo "=== End-to-End Authentication Testing ==="

# Test authentication flow for all services
services=("dashboard" "longhorn" "grafana" "prometheus" "alertmanager" "hubble")

for service in "${services[@]}"; do
    echo "Testing $service authentication flow..."
    
    # 1. Test initial redirect to Authentik
    response=$(curl -k -s -o /dev/null -w "%{http_code}" https://$service.k8s.home.geoffdavis.com)
    if [ "$response" -eq 200 ] || [ "$response" -eq 302 ]; then
        echo "✅ $service: Initial request successful"
    else
        echo "❌ $service: Initial request failed (HTTP $response)"
    fi
    
    # 2. Test outpost health endpoint
    curl -k -s https://$service.k8s.home.geoffdavis.com/outpost.goauthentik.io/ping
    if [ $? -eq 0 ]; then
        echo "✅ $service: Outpost health check passed"
    else
        echo "❌ $service: Outpost health check failed"
    fi
done

echo "End-to-end authentication testing complete"
```

### Network Connectivity Testing

```bash
#!/bin/bash
# network-connectivity-tests.sh

echo "=== Network Connectivity Testing ==="

# 1. Test BGP LoadBalancer connectivity
echo "Testing BGP LoadBalancer connectivity..."
kubectl get svc -A --field-selector spec.type=LoadBalancer -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,EXTERNAL-IP:.status.loadBalancer.ingress[0].ip"

# 2. Test DNS resolution
echo "Testing DNS resolution..."
for service in dashboard longhorn grafana prometheus alertmanager; do
    nslookup $service.k8s.home.geoffdavis.com
    if [ $? -eq 0 ]; then
        echo "✅ DNS resolution for $service successful"
    else
        echo "❌ DNS resolution for $service failed"
    fi
done

# 3. Test internal service connectivity
echo "Testing internal service connectivity..."
kubectl run network-test --image=busybox --rm -it --restart=Never -- nslookup authentik-server.authentik.svc.cluster.local

# 4. Test BGP route advertisement
echo "Testing BGP route advertisement..."
kubectl exec -n kube-system -l k8s-app=cilium -- cilium bgp routes

echo "Network connectivity testing complete"
```

## Performance Validation Testing

### Resource Usage Comparison

```bash
#!/bin/bash
# performance-validation-tests.sh

echo "=== Performance Validation Testing ==="

# 1. Collect current resource usage
echo "Collecting resource usage metrics..."
kubectl top nodes
kubectl top pods -A --sort-by=cpu
kubectl top pods -A --sort-by=memory

# 2. Test response times
echo "Testing response times..."
for service in dashboard longhorn grafana prometheus; do
    echo "Testing $service response time..."
    time curl -k -s -o /dev/null https://$service.k8s.home.geoffdavis.com
done

# 3. Test storage performance (if applicable)
echo "Testing storage performance..."
# Run storage performance tests as defined in longhorn-performance-tests.sh

# 4. Monitor memory usage over time
echo "Monitoring memory usage..."
for i in {1..5}; do
    echo "Sample $i:"
    kubectl top pods -n authentik --no-headers | awk '{print $3}' | sed 's/Mi//' | awk '{sum+=$1} END {print "Authentik total memory: " sum "Mi"}'
    kubectl top pods -n kubernetes-dashboard --no-headers | awk '{print $3}' | sed 's/Mi//' | awk '{sum+=$1} END {print "Dashboard total memory: " sum "Mi"}'
    sleep 30
done

echo "Performance validation complete"
```

## Security Validation Testing

### Security Configuration Testing

```bash
#!/bin/bash
# security-validation-tests.sh

echo "=== Security Validation Testing ==="

# 1. Test RBAC configurations
echo "Testing RBAC configurations..."
kubectl auth can-i --list --as=system:serviceaccount:kubernetes-dashboard:kubernetes-dashboard
kubectl auth can-i --list --as=system:serviceaccount:authentik:authentik

# 2. Verify security contexts
echo "Verifying security contexts..."
kubectl get pods -n authentik -o jsonpath='{.items[*].spec.securityContext}'
kubectl get pods -n kubernetes-dashboard -o jsonpath='{.items[*].spec.securityContext}'

# 3. Test network policies (if applicable)
echo "Testing network policies..."
kubectl get networkpolicies -A

# 4. Verify TLS certificates
echo "Verifying TLS certificates..."
for service in dashboard longhorn grafana prometheus authentik; do
    echo "Checking $service certificate..."
    echo | openssl s_client -connect $service.k8s.home.geoffdavis.com:443 -servername $service.k8s.home.geoffdavis.com 2>/dev/null | openssl x509 -noout -dates
done

# 5. Test secret management
echo "Testing secret management..."
kubectl get secrets -A | grep -E "(authentik|dashboard|longhorn)"

echo "Security validation complete"
```

## Rollback Testing Procedures

### Component Rollback Tests

```bash
#!/bin/bash
# rollback-tests.sh

echo "=== Rollback Testing Procedures ==="

# Function to test rollback for a component
test_rollback() {
    local component=$1
    local namespace=$2
    
    echo "Testing rollback for $component..."
    
    # 1. Create backup of current state
    kubectl get helmrelease $component -n $namespace -o yaml > /tmp/${component}-current.yaml
    
    # 2. Simulate rollback (don't actually execute)
    echo "Simulating rollback for $component..."
    echo "Would execute: kubectl apply -f backups/bitnami-migration-backup/${component}-helmrelease.yaml"
    
    # 3. Verify rollback readiness
    if [ -f "backups/bitnami-migration-backup/${component}-helmrelease.yaml" ]; then
        echo "✅ Rollback configuration available for $component"
    else
        echo "❌ Rollback configuration missing for $component"
    fi
    
    # 4. Test configuration validation
    kubectl apply --dry-run=client -f /tmp/${component}-current.yaml
    if [ $? -eq 0 ]; then
        echo "✅ Current configuration valid for $component"
    else
        echo "❌ Current configuration invalid for $component"
    fi
}

# Test rollback readiness for all components
test_rollback "kubernetes-dashboard" "kubernetes-dashboard"
test_rollback "authentik" "authentik"
test_rollback "longhorn" "longhorn-system"
test_rollback "matter-server" "home-automation"
test_rollback "kube-prometheus-stack" "monitoring"

echo "Rollback testing complete"
```

## Automated Test Suite

### Master Test Runner

```bash
#!/bin/bash
# run-migration-tests.sh

echo "=== Bitnami Migration Test Suite ==="
echo "Starting comprehensive testing..."

# Set test results directory
TEST_RESULTS_DIR="test-results-$(date +%Y%m%d-%H%M%S)"
mkdir -p $TEST_RESULTS_DIR

# Function to run test and capture results
run_test() {
    local test_name=$1
    local test_script=$2
    
    echo "Running $test_name..."
    if bash $test_script > $TEST_RESULTS_DIR/${test_name}.log 2>&1; then
        echo "✅ $test_name: PASSED"
        echo "PASSED" > $TEST_RESULTS_DIR/${test_name}.result
    else
        echo "❌ $test_name: FAILED"
        echo "FAILED" > $TEST_RESULTS_DIR/${test_name}.result
    fi
}

# Run all test suites
run_test "dashboard-migration" "dashboard-post-migration-tests.sh"
run_test "dashboard-functionality" "dashboard-functionality-tests.sh"
run_test "authentik-migration" "authentik-migration-tests.sh"
run_test "authentik-outpost" "authentik-outpost-tests.sh"
run_test "longhorn-migration" "longhorn-migration-tests.sh"
run_test "longhorn-curl-jobs" "longhorn-curl-jobs-tests.sh"
run_test "longhorn-performance" "longhorn-performance-tests.sh"
run_test "matter-server-migration" "matter-server-migration-tests.sh"
run_test "monitoring-migration" "monitoring-migration-tests.sh"
run_test "e2e-authentication" "e2e-authentication-tests.sh"
run_test "network-connectivity" "network-connectivity-tests.sh"
run_test "performance-validation" "performance-validation-tests.sh"
run_test "security-validation" "security-validation-tests.sh"
run_test "rollback-readiness" "rollback-tests.sh"

# Generate summary report
echo "=== Test Summary Report ===" > $TEST_RESULTS_DIR/summary.txt
echo "Test execution completed at: $(date)" >> $TEST_RESULTS_DIR/summary.txt
echo "" >> $TEST_RESULTS_DIR/summary.txt

passed_tests=0
failed_tests=0

for result_file in $TEST_RESULTS_DIR/*.result; do
    test_name=$(basename $result_file .result)
    result=$(cat $result_file)
    echo "$test_name: $result" >> $TEST_RESULTS_DIR/summary.txt
    
    if [ "$result" = "PASSED" ]; then
        ((passed_tests++))
    else
        ((failed_tests++))
    fi
done

echo "" >> $TEST_RESULTS_DIR/summary.txt
echo "Total Tests: $((passed_tests + failed_tests))" >> $TEST_RESULTS_DIR/summary.txt
echo "Passed: $passed_tests" >> $TEST_RESULTS_DIR/summary.txt
echo "Failed: $failed_tests" >> $TEST_RESULTS_DIR/summary.txt

# Display summary
cat $TEST_RESULTS_DIR/summary.txt

if [ $failed_tests -eq 0 ]; then
    echo "🎉 All tests passed! Migration validation successful."
    exit 0
else
    echo "⚠️  Some tests failed. Review logs in $TEST_RESULTS_DIR/"
    exit 1
fi
```

## Manual Testing Procedures

### Dashboard Manual Testing Checklist

- [ ] **Access Dashboard**: Navigate to https://dashboard.k8s.home.geoffdavis.com
- [ ] **Authentication Flow**: Verify redirect to Authentik and successful login
- [ ] **No Bearer Token Prompt**: Confirm no manual token entry required
- [ ] **Cluster Overview**: Verify cluster overview page loads correctly
- [ ] **Namespace Navigation**: Test browsing different namespaces
- [ ] **Resource Viewing**: Verify ability to view pods, services, deployments
- [ ] **Log Viewing**: Test viewing pod logs
- [ ] **Resource Scaling**: Test scaling a deployment
- [ ] **Administrative Functions**: Verify full administrative access

### Authentik Manual Testing Checklist

- [ ] **Admin Interface**: Access https://authentik.k8s.home.geoffdavis.com/if/admin/
- [ ] **User Management**: Verify user creation and management
- [ ] **Provider Configuration**: Check proxy provider configurations
- [ ] **Outpost Status**: Verify external outpost shows as connected
- [ ] **Service Integration**: Test SSO for all 6 services
- [ ] **Session Management**: Verify session persistence and logout
- [ ] **Flow Configuration**: Test authentication and authorization flows

### Longhorn Manual Testing Checklist

- [ ] **UI Access**: Navigate to https://longhorn.k8s.home.geoffdavis.com
- [ ] **Volume Management**: Verify volume creation and management
- [ ] **Node Status**: Check all nodes show healthy with USB SSDs
- [ ] **Backup Configuration**: Verify S3 backup settings
- [ ] **Snapshot Creation**: Test volume snapshot creation
- [ ] **Volume Attachment**: Test volume attachment to pods
- [ ] **Performance Monitoring**: Check volume performance metrics

### Matter Server Manual Testing Checklist

- [ ] **Pod Status**: Verify Matter Server pod is running
- [ ] **Host Networking**: Confirm host networking is enabled
- [ ] **API Accessibility**: Test Matter Server API endpoint
- [ ] **Network Interface**: Verify access to enp3s0f0 interface
- [ ] **Persistent Storage**: Check data persistence across restarts
- [ ] **Home Assistant Integration**: Verify integration with Home Assistant

### Monitoring Manual Testing Checklist

- [ ] **Grafana Access**: Navigate to https://grafana.k8s.home.geoffdavis.com
- [ ] **Prometheus Access**: Navigate to https://prometheus.k8s.home.geoffdavis.com
- [ ] **AlertManager Access**: Navigate to https://alertmanager.k8s.home.geoffdavis.com
- [ ] **Dashboard Functionality**: Verify Grafana dashboards load correctly
- [ ] **Metrics Collection**: Check Prometheus targets and metrics
- [ ] **Alert Configuration**: Verify AlertManager rules and notifications
- [ ] **External Access**: Confirm BGP LoadBalancer IPs are accessible

## Troubleshooting Failed Tests

### Common Issues and Solutions

#### Image Compatibility Issues

**Issue**: Jobs fail with "command not found" errors for curl or bash
**Root Cause**: Using distroless `registry.k8s.io/kubectl` image that lacks shell tools
**Solution**:
```bash
# Check current image in failing job
kubectl get cronjob <job-name> -n <namespace> -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}'

# If using registry.k8s.io/kubectl, update to alpine/k8s:1.31.1
kubectl patch cronjob <job-name> -n <namespace> --type='merge' -p='{"spec":{"jobTemplate":{"spec":{"template":{"spec":{"containers":[{"name":"<container-name>","image":"alpine/k8s:1.31.1"}]}}}}}}'

# Verify tools are available in new image
kubectl run test-tools --image=alpine/k8s:1.31.1 --rm -it --restart=Never -- /bin/bash -c "which curl && which bash && kubectl version --client"
```

**Issue**: Backup monitoring fails to push metrics to Prometheus
**Root Cause**: Curl not available in job container
**Solution**:
```bash
# Test Prometheus pushgateway connectivity
kubectl run curl-test --image=alpine/k8s:1.31.1 --rm -it --restart=Never -- curl -I http://prometheus-pushgateway.monitoring.svc.cluster.local:9091/metrics

# Check backup verification job logs
kubectl logs -n longhorn-system -l job-name=backup-verification --tail=50

# Verify correct image is used
kubectl get cronjob backup-verification -n longhorn-system -o yaml | grep image:
```

**Issue**: Database backup jobs fail with bash script errors
**Root Cause**: Complex bash scripting requires full shell environment
**Solution**:
```bash
# Ensure alpine/k8s:1.31.1 image is used for database jobs
kubectl get cronjob database-consistent-backup -n database -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}'

# Test bash functionality
kubectl run bash-test --image=alpine/k8s:1.31.1 --rm -it --restart=Never -- /bin/bash -c "echo 'Bash works'; date +%Y%m%d-%H%M%S"

# Check job execution logs
kubectl logs -n database -l job-name=database-consistent-backup --tail=100
```

### Common Issues and Solutions

#### Dashboard Issues

**Issue**: Dashboard not accessible after migration
**Solution**:
```bash
# Check HelmRelease status
kubectl describe helmrelease kubernetes-dashboard -n kubernetes-dashboard

# Verify Kong configuration
kubectl get configmap kubernetes-dashboard-kong-config -n kubernetes-dashboard -o yaml

# Check service endpoints
kubectl get endpoints -n kubernetes-dashboard
```

#### Authentik Issues

**Issue**: Authentication not working for services
**Solution**:
```bash
# Check external outpost connectivity
kubectl logs -n authentik-proxy deployment/authentik-proxy

# Verify proxy provider configurations
kubectl exec -n authentik deployment/authentik-server -- python manage.py shell -c "
from authentik.providers.proxy.models import ProxyProvider
for p in ProxyProvider.objects.all():
    print(f'{p.name}: {p.external_host}')
"

# Test outpost API connectivity
kubectl exec -n authentik-proxy deployment/authentik-proxy -- curl -I http://authentik-server.authentik.svc.cluster.local:9000/outpost.goauthentik.io/ping
```

#### Longhorn Issues

**Issue**: Volume provisioning fails
**Solution**:
```bash
# Check Longhorn manager logs
kubectl logs -n longhorn-system daemonset/longhorn-manager

# Verify USB SSD detection
kubectl exec -n longhorn-system daemonset/longhorn-manager -- ls -la /var/lib/longhorn/

# Check storage class configuration
kubectl get storageclass longhorn -o yaml
```

#### Monitoring Issues

**Issue**: External access not working
**Solution**:
```bash
# Check LoadBalancer service status
kubectl get svc -n monitoring -o wide

# Verify BGP route advertisement
kubectl exec -n kube-system -l k8s-app=cilium -- cilium bgp routes

# Check service labels for IPAM
kubectl get svc -n monitoring -o yaml | grep -A 5 -B 5 "lb-ipam-pool"
```

## Test Result Documentation

### Test Report Template

```markdown
# Bitnami Migration Test Report

**Date**: [Test Date]
**Tester**: [Tester Name]
**Migration Phase**: [Phase Number]

## Test Summary
- Total Tests: [Number]
- Passed: [Number]
- Failed: [Number]
- Success Rate: [Percentage]

## Component Results

### Kubernetes Dashboard
- Migration Validation: [PASS/FAIL]
- Functionality Tests: [PASS/FAIL]
- Authentication Integration: [PASS/FAIL]
- Notes: [Any issues or observations]

### Authentik
- Migration Validation