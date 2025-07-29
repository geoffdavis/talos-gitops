# Comprehensive Troubleshooting Guide

This guide provides systematic troubleshooting procedures for all major components of the Talos GitOps home-ops cluster. Use this as your primary reference for diagnosing and resolving operational issues.

## Table of Contents

- [General Diagnostic Approach](#general-diagnostic-approach)
- [Bootstrap Phase Issues](#bootstrap-phase-issues)
- [GitOps Reconciliation Failures](#gitops-reconciliation-failures)
- [Network Connectivity Problems](#network-connectivity-problems)
- [Authentication System Issues](#authentication-system-issues)
- [Storage Issues](#storage-issues)
- [Application Deployment Failures](#application-deployment-failures)
- [Emergency Recovery Procedures](#emergency-recovery-procedures)
- [Common Diagnostic Commands](#common-diagnostic-commands)

## General Diagnostic Approach

### Systematic Troubleshooting Method

1. **Identify the Scope**: Determine if the issue affects:
   - Single service/pod
   - Entire namespace
   - Multiple namespaces
   - Cluster-wide systems
   - Network connectivity

2. **Check System Health**:

   ```bash
   # Overall cluster status
   task cluster:status
   
   # Node health
   kubectl get nodes -o wide
   kubectl top nodes
   
   # Critical pods
   kubectl get pods -A | grep -v Running | grep -v Completed
   ```

3. **Review Recent Changes**:

   ```bash
   # Recent Git commits
   git log --oneline -10
   
   # Flux reconciliation status
   flux get kustomizations
   
   # Recent cluster events
   kubectl get events --sort-by='.lastTimestamp' | tail -20
   ```

4. **Check Dependencies**: Follow the dependency chain:
   - Talos OS → Kubernetes API
   - Kubernetes → Cilium CNI
   - CNI → Pod networking
   - Secrets → Application startup
   - Storage → Data persistence

## Bootstrap Phase Issues

Bootstrap phase problems affect system-level components managed via Taskfile commands rather than GitOps.

### Talos OS Issues

#### Node Boot Problems

**Symptoms**: Node fails to boot or becomes unresponsive

**Diagnostic Steps**:

```bash
# Check node accessibility
talosctl version --insecure --nodes 172.29.51.11,172.29.51.12,172.29.51.13

# Check node status
talosctl get members --nodes 172.29.51.11,172.29.51.12,172.29.51.13

# Review system logs
talosctl logs --nodes 172.29.51.11 kubelet
talosctl logs --nodes 172.29.51.11 machined
```

**Common Solutions**:

- **USB SSD disconnection**: Check physical USB connections
- **LLDPD configuration lost**: Apply LLDP configuration

  ```bash
  task talos:apply-lldpd-config
  ```

- **Node maintenance mode**: Node may need bootstrap recovery

  ```bash
  task cluster:emergency-recovery
  ```

#### Talos Configuration Issues

**Symptoms**: Configuration validation fails or nodes reject config updates

**Diagnostic Steps**:

```bash
# Validate configuration
talhelper validate-config

# Check configuration differences
talosctl get machineconfig --nodes 172.29.51.11

# Review pending configuration
talosctl get machineconfigstatus --nodes 172.29.51.11
```

**Common Solutions**:

- **Invalid disk selection**: Update `installDiskSelector` in `talconfig.yaml`
- **Network configuration conflicts**: Review networking patches
- **Certificate issues**: Regenerate certificates

  ```bash
  task talos:generate-secrets
  task talos:generate-config
  ```

### Kubernetes Cluster Issues

#### Control Plane Problems

**Symptoms**: `kubectl` commands fail or cluster is unreachable

**Diagnostic Steps**:

```bash
# Check cluster endpoint
kubectl cluster-info

# Check control plane pods
kubectl get pods -n kube-system

# Check etcd health
talosctl etcd status --nodes 172.29.51.11,172.29.51.12,172.29.51.13
```

**Common Solutions**:

- **Etcd corruption**: Restore from backup or bootstrap new cluster
- **Certificate expiration**: Regenerate cluster certificates
- **API server resource exhaustion**: Check node resources

#### CNI (Cilium) Problems

**Symptoms**: Pods fail to start, network connectivity issues

**Diagnostic Steps**:

```bash
# Check Cilium status
cilium status

# Check Cilium pods
kubectl get pods -n kube-system -l k8s-app=cilium

# Cilium connectivity test
cilium connectivity test --test-concurrency 1
```

**Common Solutions**:

- **XDP compatibility**: Ensure XDP is disabled for Mac mini

  ```bash
  task apps:deploy-cilium
  ```

- **BGP configuration**: Check BGP peering status

  ```bash
  kubectl exec -n kube-system -l k8s-app=cilium -- cilium bgp peers
  ```

## GitOps Reconciliation Failures

GitOps issues affect Flux-managed resources and prevent automated deployments.

### Flux System Issues

#### Stuck Reconciliations

**Symptoms**: Kustomizations show "not ready" or "reconciling" for extended periods

**Diagnostic Steps**:

```bash
# Check all kustomizations
flux get kustomizations

# Check specific kustomization
flux describe kustomization infrastructure-monitoring

# Check Flux controller logs
flux logs --follow

# Check for webhook issues
kubectl logs -n flux-system deploy/notification-controller
```

**Common Solutions**:

- **Circular dependencies**: Remove problematic dependencies
- **Resource conflicts**: Check for duplicate resources
- **Webhook connectivity**: Verify GitHub webhook configuration
- **Immutable resource conflicts**: Delete and recreate resources

#### Git Repository Issues

**Symptoms**: Source repositories fail to sync

**Diagnostic Steps**:

```bash
# Check Git sources
flux get sources git

# Check authentication
kubectl get secrets -n flux-system

# Test Git connectivity
flux reconcile source git flux-system
```

**Common Solutions**:

- **SSH key rotation**: Update deploy keys in GitHub and cluster
- **Repository access**: Verify repository permissions
- **Network connectivity**: Check DNS and firewall rules

### HelmRelease Failures

#### Helm Deployment Issues

**Symptoms**: HelmReleases fail to install or upgrade

**Diagnostic Steps**:

```bash
# Check HelmRelease status
flux get helmreleases -A

# Check Helm release history
helm history <release-name> -n <namespace>

# Check Helm controller logs
kubectl logs -n flux-system deploy/helm-controller
```

**Common Solutions**:

- **Chart version incompatibility**: Roll back or update chart version
- **Values validation**: Check Helm values for syntax errors
- **Resource limits**: Ensure adequate cluster resources
- **Duplicate releases**: Delete conflicting Helm releases

  ```bash
  helm delete <release-name> -n <namespace>
  ```

## Network Connectivity Problems

Network issues can affect pod-to-pod communication, external access, and load balancer functionality.

### BGP LoadBalancer Issues

#### BGP Peering Problems

**Symptoms**: LoadBalancer services don't get external IPs or services are unreachable

**Diagnostic Steps**:

```bash
# Check BGP peering status
kubectl exec -n kube-system -l k8s-app=cilium -- cilium bgp peers

# Check BGP routes
kubectl exec -n kube-system -l k8s-app=cilium -- cilium bgp routes

# Check UDM Pro BGP status (if accessible)
# ssh into UDM Pro and check BGP neighbor status

# Check LoadBalancer services
kubectl get svc -A --field-selector spec.type=LoadBalancer
```

**Common Solutions**:

- **BGP configuration mismatch**: Verify ASN configuration (cluster: 64512, UDM Pro: 64513)
- **Service label issues**: Ensure services have correct pool labels

  ```bash
  # Add required labels to services
  kubectl patch svc <service-name> -n <namespace> -p '{"metadata":{"labels":{"io.cilium/lb-ipam-pool":"bgp-default"}}}'
  ```

- **IPAM controller issues**: Restart Cilium operator

  ```bash
  kubectl delete pod -n kube-system -l io.cilium/app=operator
  ```

#### IP Pool Exhaustion

**Symptoms**: New LoadBalancer services remain in "Pending" state

**Diagnostic Steps**:

```bash
# Check IP pool usage
kubectl get ciliumloadbalancerippools -o yaml

# Check service pool assignments
kubectl get svc -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,EXTERNAL-IP:.status.loadBalancer.ingress[0].ip,POOL:.metadata.labels.io\.cilium/lb-ipam-pool"
```

**Common Solutions**:

- **Expand IP pools**: Update pool ranges in `infrastructure/cilium-pools/loadbalancer-pools.yaml`
- **Reassign services**: Move services to different pools
- **Clean up unused IPs**: Delete unused LoadBalancer services

### DNS Resolution Issues

#### External DNS Problems

**Symptoms**: DNS records not created or outdated

**Diagnostic Steps**:

```bash
# Check External DNS pods
kubectl get pods -n external-dns-internal
kubectl logs -n external-dns-internal -l app.kubernetes.io/name=external-dns

# Test DNS resolution
dig longhorn.k8s.home.geoffdavis.com
nslookup grafana.k8s.home.geoffdavis.com
```

**Common Solutions**:

- **Provider credentials**: Check External DNS secret configuration
- **Annotation issues**: Verify ingress annotations
- **Rate limiting**: Check for API rate limit errors in logs

#### Internal DNS Issues

**Symptoms**: Pod-to-pod DNS resolution fails

**Diagnostic Steps**:

```bash
# Test cluster DNS
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default.svc.cluster.local

# Check CoreDNS status
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

**Common Solutions**:

- **CoreDNS configuration**: Check CoreDNS ConfigMap
- **Network policies**: Verify DNS traffic is allowed
- **Resource limits**: Ensure CoreDNS has adequate resources

## Authentication System Issues

The external Authentik outpost system requires careful troubleshooting of multiple components.

### External Outpost Connectivity

#### Outpost Connection Failures

**Symptoms**: Services return authentication errors or redirect loops

**Diagnostic Steps**:

```bash
# Check external outpost status
kubectl get pods -n authentik-proxy
kubectl logs -n authentik-proxy -l app.kubernetes.io/name=authentik-proxy

# Check Authentik server connectivity
kubectl exec -n authentik-proxy <pod> -- curl -I http://authentik-server.authentik.svc.cluster.local:80

# Test health endpoints
curl -I https://longhorn.k8s.home.geoffdavis.com/outpost.goauthentik.io/ping
```

**Common Solutions**:

- **Token configuration**: Verify external outpost token in 1Password
- **Network connectivity**: Check service discovery between namespaces
- **Redis connectivity**: Ensure Redis session storage is working

  ```bash
  kubectl exec -n authentik-proxy <redis-pod> -- redis-cli ping
  ```

#### Proxy Provider Issues

**Symptoms**: Individual services fail authentication while others work

**Diagnostic Steps**:

```bash
# Check service endpoints
kubectl get endpoints -A | grep -E "(longhorn|grafana|prometheus|dashboard)"

# Test service connectivity from authentik-proxy namespace
kubectl exec -n authentik-proxy <pod> -- curl -I http://longhorn-frontend.longhorn-system:80

# Check ingress configuration
kubectl get ingress -A | grep k8s.home.geoffdavis.com
```

**Common Solutions**:

- **Service URL mismatch**: Update proxy provider configuration in Authentik admin
- **Port configuration**: Verify service ports match proxy provider settings
- **Ingress conflicts**: Ensure only external outpost handles authentication domains

### Authentik Server Issues

#### Database Connectivity

**Symptoms**: Authentik pods fail to start or return database errors

**Diagnostic Steps**:

```bash
# Check PostgreSQL cluster
kubectl get cluster authentik-postgresql -n authentik

# Check database connectivity
kubectl exec -n authentik <authentik-pod> -- python -c "import django; django.setup(); from django.db import connection; connection.ensure_connection(); print('Database OK')"

# Check external secrets
kubectl get externalsecrets -n authentik
```

**Common Solutions**:

- **Database credentials**: Verify 1Password integration and secret sync
- **Database initialization**: Check if database schema is properly initialized
- **Resource limits**: Ensure database has adequate resources

## Storage Issues

Storage problems can affect data persistence and application functionality.

### Longhorn Storage Issues

#### Volume Attachment Problems

**Symptoms**: Pods fail to start with volume attachment errors

**Diagnostic Steps**:

```bash
# Check Longhorn system status
kubectl get pods -n longhorn-system

# Check volume status
kubectl get pv,pvc -A

# Access Longhorn UI
# Navigate to https://longhorn.k8s.home.geoffdavis.com

# Check Longhorn logs
kubectl logs -n longhorn-system -l app=longhorn-manager
```

**Common Solutions**:

- **Node scheduling**: Ensure nodes are available for volume scheduling
- **Storage space**: Check available storage capacity
- **USB SSD issues**: Verify USB SSD connectivity and health

  ```bash
  task storage:validate-usb-ssd
  ```

#### Backup Failures

**Symptoms**: Longhorn backups fail or are incomplete

**Diagnostic Steps**:

```bash
# Check backup status in Longhorn UI
# Review backup logs in Longhorn

# Check backup credentials
kubectl get secrets -n longhorn-system | grep backup
```

**Common Solutions**:

- **S3 credentials**: Verify backup destination credentials
- **Network connectivity**: Check connectivity to backup destination
- **Storage space**: Ensure adequate space at backup destination

### USB SSD Issues

#### Physical Connectivity

**Symptoms**: Nodes report disk unavailable or read-only

**Diagnostic Steps**:

```bash
# Check disk status on nodes
talosctl ls /dev/disk/by-id/ --nodes 172.29.51.11

# Check filesystem status
talosctl read /proc/mounts --nodes 172.29.51.11 | grep usb

# Check system logs for USB errors
talosctl logs --nodes 172.29.51.11 kernel | grep -i usb
```

**Common Solutions**:

- **Physical reconnection**: Unplug and reconnect USB SSDs
- **Power management**: Check USB power management settings
- **Disk health**: Run SMART tests on SSDs

## Application Deployment Failures

### Home Assistant Stack Issues

#### PostgreSQL Database Problems

**Symptoms**: Home Assistant fails to start with database connection errors

**Diagnostic Steps**:

```bash
# Check PostgreSQL cluster status
kubectl get cluster homeassistant-postgresql -n home-automation

# Check database pods
kubectl get pods -n home-automation -l postgresql.cnpg.io/cluster=homeassistant-postgresql

# Test database connectivity
kubectl exec -n home-automation <postgres-pod> -- psql -c "\l"
```

**Common Solutions**:

- **Schema compatibility**: Check CloudNativePG version compatibility
- **Credential sync**: Verify external secrets are syncing properly
- **Resource limits**: Ensure adequate CPU and memory allocation

#### MQTT Broker Issues

**Symptoms**: IoT devices cannot connect or Home Assistant shows MQTT errors

**Diagnostic Steps**:

```bash
# Check Mosquitto status
kubectl get pods -n home-automation -l app.kubernetes.io/name=mosquitto

# Test MQTT connectivity
kubectl port-forward -n home-automation svc/mosquitto 1883:1883
# Use MQTT client to test connection

# Check Mosquitto configuration
kubectl get configmap -n home-automation mosquitto-config -o yaml
```

**Common Solutions**:

- **Port binding conflicts**: Simplify listener configuration
- **Security context**: Ensure proper Pod Security policies
- **Network policies**: Verify MQTT traffic is allowed

### Monitoring Stack Issues

#### Prometheus Deployment Problems

**Symptoms**: Prometheus fails to start or shows configuration errors

**Diagnostic Steps**:

```bash
# Check HelmRelease status
flux get helmreleases -n monitoring

# Check Prometheus pods
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus

# Check Prometheus configuration
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus
```

**Common Solutions**:

- **Configuration validation**: Check Prometheus configuration syntax
- **Resource limits**: Increase memory limits for large configurations
- **Storage issues**: Verify persistent storage is available

## Emergency Recovery Procedures

### Complete Cluster Recovery

#### Safe Reset Procedure

When cluster is unrecoverable but OS is intact:

```bash
# 1. Confirm reset intention (DANGEROUS - wipes all data)
task cluster:safe-reset CONFIRM=SAFE-RESET

# 2. Wait for nodes to enter maintenance mode
talosctl version --insecure --nodes 172.29.51.11,172.29.51.12,172.29.51.13

# 3. Re-bootstrap cluster
task bootstrap:phased
```

#### Emergency Recovery

For systematic recovery when cluster is partially functional:

```bash
# 1. Run emergency recovery procedure
task cluster:emergency-recovery

# 2. Follow the guided recovery steps
# This script will assess cluster state and provide recovery options
```

### Data Recovery

#### Longhorn Volume Recovery

```bash
# 1. Access Longhorn UI
# Navigate to https://longhorn.k8s.home.geoffdavis.com

# 2. Check volume status and snapshots
# Use Longhorn UI to restore from snapshots

# 3. If Longhorn is unavailable, check USB SSD directly
talosctl ls /var/lib/longhorn --nodes 172.29.51.11
```

#### PostgreSQL Recovery

```bash
# 1. Check available backups
kubectl get backup -n <namespace>

# 2. Restore from CloudNativePG backup
# Follow CloudNativePG restore procedures

# 3. Manual data extraction if needed
kubectl exec -n <namespace> <postgres-pod> -- pg_dump <database>
```

## Common Diagnostic Commands

### Quick Health Checks

```bash
# Overall cluster health
task cluster:status

# All pod status
kubectl get pods -A | grep -v Running | grep -v Completed

# Node resources
kubectl top nodes

# Storage health
task storage:check-longhorn

# Network health
task bgp:verify-peering

# GitOps health
flux get kustomizations

# Authentication health
curl -I https://longhorn.k8s.home.geoffdavis.com/outpost.goauthentik.io/ping
```

### Detailed Diagnostics

```bash
# Cilium connectivity
cilium status
cilium connectivity test --test-concurrency 1

# BGP routing
kubectl exec -n kube-system -l k8s-app=cilium -- cilium bgp routes
kubectl exec -n kube-system -l k8s-app=cilium -- cilium bgp peers

# DNS resolution
dig @8.8.8.8 longhorn.k8s.home.geoffdavis.com
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default.svc.cluster.local

# Certificate status
kubectl get certificates -A
kubectl get certificaterequests -A

# External secrets sync
kubectl get externalsecrets -A
kubectl describe externalsecret <name> -n <namespace>
```

### Log Analysis

```bash
# Talos system logs
talosctl logs --nodes 172.29.51.11 kubelet
talosctl logs --nodes 172.29.51.11 machined

# Flux controller logs
flux logs --follow
kubectl logs -n flux-system deploy/kustomize-controller

# Cilium logs
kubectl logs -n kube-system -l k8s-app=cilium

# Application logs
kubectl logs -n <namespace> -l app=<app-name>

# System events
kubectl get events --sort-by='.lastTimestamp' -A
```

### Performance Analysis

```bash
# Resource usage
kubectl top nodes
kubectl top pods -A

# Disk usage
talosctl read /proc/diskstats --nodes 172.29.51.11

# Network usage
kubectl exec -n kube-system -l k8s-app=cilium -- cilium metrics list
```

## Escalation Procedures

### When to Use Emergency Procedures

1. **Cluster completely unresponsive**: Use safe reset procedure
2. **Multiple system failures**: Use emergency recovery
3. **Data corruption**: Restore from backups immediately
4. **Security incident**: Follow incident response procedures

### Recovery Order

1. **Infrastructure Layer**: Talos OS → Kubernetes → CNI
2. **System Services**: DNS → Certificates → Secrets
3. **Platform Services**: Ingress → Authentication → Monitoring
4. **Applications**: Databases → Application services → User interfaces

### Documentation Updates

After resolving issues:

1. **Document root cause**: Update troubleshooting guide
2. **Update procedures**: Improve diagnostic steps
3. **Create preventive measures**: Add monitoring or automation
4. **Train team**: Share lessons learned

Remember: When in doubt, prefer safe procedures over quick fixes. The cluster's immutable infrastructure makes complete rebuilds safer than partial repairs.
