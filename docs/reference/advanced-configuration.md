# Advanced Configuration Reference

This document provides comprehensive reference materials and advanced configuration examples for the Talos GitOps home-ops cluster. It's designed for experienced operators who need to customize or extend cluster functionality.

## Table of Contents

- [Talos OS Advanced Configuration](#talos-os-advanced-configuration)
- [Cilium CNI Advanced Features](#cilium-cni-advanced-features)
- [BGP LoadBalancer Configuration](#bgp-loadbalancer-configuration)
- [Authentication System Configuration](#authentication-system-configuration)
- [Storage Advanced Configuration](#storage-advanced-configuration)
- [Monitoring and Observability](#monitoring-and-observability)
- [Security Hardening](#security-hardening)
- [Network Policies](#network-policies)
- [Custom Resource Definitions](#custom-resource-definitions)
- [Performance Tuning](#performance-tuning)

## Talos OS Advanced Configuration

### All-Control-Plane Setup

The cluster uses an all-control-plane architecture for maximum resource utilization:

```yaml
# talconfig.yaml
clusterName: home-ops
allowSchedulingOnMasters: true

nodes:
  - hostname: mini01
    controlPlane: true
    installDisk: /dev/disk/by-id/usb-Samsung_Portable_SSD_T5_*
  - hostname: mini02
    controlPlane: true
    installDisk: /dev/disk/by-id/usb-Samsung_Portable_SSD_T5_*
  - hostname: mini03
    controlPlane: true
    installDisk: /dev/disk/by-id/usb-Samsung_Portable_SSD_T5_*
```

### Advanced Disk Configuration

#### USB SSD Optimization

```yaml
# talos/patches/usb-ssd-optimization.yaml
machine:
  udev:
    rules:
      - SUBSYSTEM=="block", ATTRS{idVendor}=="04e8", ATTRS{idProduct}=="61f5", ACTION=="add", RUN+="/bin/sh -c 'echo mq-deadline > /sys/block/%k/queue/scheduler'"
  sysctls:
    vm.dirty_ratio: 15
    vm.dirty_background_ratio: 5
    vm.dirty_expire_centisecs: 3000
    vm.dirty_writeback_centisecs: 500
```

#### Smart Disk Selection

```yaml
# Advanced disk selection patterns
machine:
  install:
    diskSelector:
      # Match specific Samsung Portable SSD T5
      model: "Portable SSD T5"
      # Alternative: match by size
      # size: ">= 900GB"
      # Alternative: match by type
      # type: "ssd"
```

### Network Configuration

#### Dual-Stack IPv6 Setup

```yaml
# Network configuration for IPv4/IPv6 dual-stack
machine:
  network:
    interfaces:
      - interface: eth0
        dhcp: true
        dhcpOptions:
          ipv4: true
          ipv6: true
        vlans:
          - vlanId: 51
            dhcp: true
            dhcpOptions:
              ipv4: true
              ipv6: true

cluster:
  network:
    cni:
      name: none  # Cilium deployed separately
    podSubnets:
      - 10.244.0.0/16
      - fd47:25e1:2f96:51:2000::/64
    serviceSubnets:
      - 10.96.0.0/12
      - fd47:25e1:2f96:51:1000::/108
```

#### Custom DNS Configuration

```yaml
# talos/patches/dns-configuration.yaml
machine:
  network:
    nameservers:
      - 172.29.51.1    # UDM Pro
      - 1.1.1.1        # Cloudflare
      - 2606:4700:4700::1111  # Cloudflare IPv6
  time:
    servers:
      - pool.ntp.org
      - time.cloudflare.com
```

### Security Configuration

#### LUKS Encryption

```yaml
# Disk encryption configuration
machine:
  systemDiskEncryption:
    state:
      provider: luks2
      options:
        - no_read_workqueue
        - no_write_workqueue
      keys:
        - nodeID: {}
          slot: 0
    ephemeral:
      provider: luks2
      options:
        - no_read_workqueue
        - no_write_workqueue
      keys:
        - nodeID: {}
          slot: 0
```

#### Custom Certificate Authority

```yaml
# Custom CA configuration
machine:
  ca:
    crt: |
      -----BEGIN CERTIFICATE-----
      <custom-ca-certificate>
      -----END CERTIFICATE-----
    key: |
      -----BEGIN RSA PRIVATE KEY----- # gitleaks:allow
      <custom-ca-private-key>
      -----END RSA PRIVATE KEY-----
```

## Cilium CNI Advanced Features

### LoadBalancer IPAM Configuration

```yaml
# Cilium configuration for BGP LoadBalancer
cilium:
  ipam:
    mode: "kubernetes"
  kubeProxyReplacement: "strict"
  k8sServiceHost: "172.29.51.10"
  k8sServicePort: "6443"
  loadBalancer:
    algorithm: "round_robin"
    mode: "hybrid"
    acceleration: "disabled"  # Required for Mac mini
  bgpControlPlane:
    enabled: true
  operator:
    rollOutPods: true
```

### Multiple IP Pool Configuration

```yaml
# infrastructure/cilium-pools/loadbalancer-pools.yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: bgp-default
spec:
  cidrs:
    - cidr: "172.29.52.100/26"  # 172.29.52.100-163
  serviceSelector:
    matchLabels:
      io.cilium/lb-ipam-pool: "bgp-default"
---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: bgp-ingress
spec:
  cidrs:
    - cidr: "172.29.52.200/28"  # 172.29.52.200-215
  serviceSelector:
    matchLabels:
      io.cilium/lb-ipam-pool: "bgp-ingress"
---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: bgp-default-ipv6
spec:
  cidrs:
    - cidr: "fd47:25e1:2f96:52:100::/120"
  serviceSelector:
    matchLabels:
      io.cilium/lb-ipam-pool: "bgp-default-ipv6"
```

### Advanced BGP Configuration

```yaml
# infrastructure/cilium-bgp/bgp-policy-legacy.yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumBGPPeeringPolicy
metadata:
  name: bgp-peering-policy
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/os: "linux"
  virtualRouters:
    # Virtual router for bgp-default pool
    - localASN: 64512
      exportPodCIDR: true
      serviceSelector:
        matchLabels:
          io.cilium/lb-ipam-pool: "bgp-default"
      serviceAdvertisements:
        - LoadBalancerIP
      neighbors:
        - peerAddress: "172.29.51.1/32"
          peerASN: 64513
          gracefulRestart:
            enabled: true
            restartTimeSeconds: 120
    # Virtual router for bgp-ingress pool
    - localASN: 64512
      exportPodCIDR: false
      serviceSelector:
        matchLabels:
          io.cilium/lb-ipam-pool: "bgp-ingress"
      serviceAdvertisements:
        - LoadBalancerIP
      neighbors:
        - peerAddress: "172.29.51.1/32"
          peerASN: 64513
          gracefulRestart:
            enabled: true
            restartTimeSeconds: 120
```

### Hubble Observability

```yaml
# Advanced Hubble configuration
hubble:
  enabled: true
  relay:
    enabled: true
    rollOutPods: true
  ui:
    enabled: true
    rollOutPods: true
    ingress:
      enabled: true
      annotations:
        kubernetes.io/ingress.class: "nginx-internal"
        cert-manager.io/cluster-issuer: "letsencrypt-production"
        authentik.io/proxy: "enabled"
      hosts:
        - hubble.k8s.home.geoffdavis.com
      tls:
        - secretName: hubble-tls
          hosts:
            - hubble.k8s.home.geoffdavis.com
  metrics:
    enabled:
      - dns
      - drop
      - tcp
      - flow
      - port-distribution
      - icmp
      - http
```

## BGP LoadBalancer Configuration

### Service Pool Assignment

```yaml
# Example service with specific pool assignment
apiVersion: v1
kind: Service
metadata:
  name: application-service
  labels:
    io.cilium/lb-ipam-pool: "bgp-default"  # Required for pool selection
  annotations:
    io.cilium/lb-ipam-pool: "bgp-default"  # Legacy annotation support
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 8080
  selector:
    app: application
```

### Advanced BGP Attributes

```yaml
# BGP policy with advanced attributes
apiVersion: "cilium.io/v2alpha1"
kind: CiliumBGPPeeringPolicy
metadata:
  name: advanced-bgp-policy
spec:
  virtualRouters:
    - localASN: 64512
      neighbors:
        - peerAddress: "172.29.51.1/32"
          peerASN: 64513
          connectRetryTimeSeconds: 120
          holdTimeSeconds: 90
          keepAliveTimeSeconds: 30
          gracefulRestart:
            enabled: true
            restartTimeSeconds: 120
          advertisedPathAttributes:
            - selectorType: "CiliumLoadBalancerIPPool"
              selector:
                matchLabels:
                  pool-type: "production"
              communities:
                standard: ["64512:100"]
              localPreference: 100
```

## Authentication System Configuration

### External Authentik Outpost

#### Outpost Deployment Configuration

```yaml
# infrastructure/authentik-proxy/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: authentik-proxy
  namespace: authentik-proxy
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: authentik-proxy
  template:
    metadata:
      labels:
        app.kubernetes.io/name: authentik-proxy
    spec:
      containers:
        - name: authentik-proxy
          image: ghcr.io/goauthentik/proxy:2025.6.4
          env:
            - name: AUTHENTIK_HOST
              value: "http://authentik-server.authentik.svc.cluster.local:80"
            - name: AUTHENTIK_HOST_BROWSER
              value: "https://authentik.k8s.home.geoffdavis.com"
            - name: AUTHENTIK_TOKEN
              valueFrom:
                secretKeyRef:
                  name: authentik-external-outpost-token
                  key: token
            - name: AUTHENTIK_OUTPOST_TYPE
              value: "proxy"
            - name: AUTHENTIK_OUTPOST_ID
              value: "3f0970c5-d6a3-43b2-9a36-d74665c6b24e"
          ports:
            - containerPort: 9000
              name: http
          livenessProbe:
            httpGet:
              path: /outpost.goauthentik.io/ping
              port: 9000
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /outpost.goauthentik.io/ping
              port: 9000
            initialDelaySeconds: 5
            periodSeconds: 5
```

#### Hybrid URL Architecture

```yaml
# Environment variables for hybrid URL configuration
env:
  # Internal communication (outpost to Authentik server)
  - name: AUTHENTIK_HOST
    value: "http://authentik-server.authentik.svc.cluster.local:80"
  
  # External redirects (user browser to Authentik)
  - name: AUTHENTIK_HOST_BROWSER
    value: "https://authentik.k8s.home.geoffdavis.com"
  
  # Redis session storage
  - name: AUTHENTIK_REDIS__HOST
    value: "redis.authentik-proxy.svc.cluster.local"
  - name: AUTHENTIK_REDIS__PORT
    value: "6379"
```

### Service Discovery Configuration

```yaml
# Automatic service discovery for authentication
apiVersion: batch/v1
kind: CronJob
metadata:
  name: authentik-service-discovery
  namespace: authentik-proxy
spec:
  schedule: "*/15 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: service-discovery
              image: bitnami/kubectl:latest
              command:
                - /bin/sh
                - -c
                - |
                  # Discover services with authentik.io/proxy=enabled
                  kubectl get services -A -l authentik.io/proxy=enabled \
                    -o jsonpath='{range .items[*]}{.metadata.name}.{.metadata.namespace}.svc.cluster.local{"\n"}{end}' \
                    > /tmp/discovered-services.txt
                  
                  # Update ConfigMap with discovered services
                  kubectl create configmap discovered-services \
                    --from-file=/tmp/discovered-services.txt \
                    --dry-run=client -o yaml | kubectl apply -f -
          restartPolicy: OnFailure
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
          volumeMounts:
            - name: tmp
              mountPath: /tmp
          volumes:
            - name: tmp
              emptyDir: {}
```

## Storage Advanced Configuration

### Longhorn Configuration

#### Storage Class Configuration

```yaml
# Custom storage classes for different workloads
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-fast
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "2"
  staleReplicaTimeout: "2880"
  fromBackup: ""
  diskSelector: "ssd"
  nodeSelector: ""
  recurringJobSelector: '[{"name":"backup-daily", "isGroup":false}]'
  dataLocality: "best-effort"
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-backup
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "2880"
  diskSelector: ""
  nodeSelector: ""
  recurringJobSelector: '[{"name":"backup-weekly", "isGroup":false}]'
  dataLocality: "strict-local"
```

#### Backup Configuration

```yaml
# S3-compatible backup configuration
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: backup-daily
  namespace: longhorn-system
spec:
  name: backup-daily
  task: backup
  cron: "0 2 * * *"
  retain: 14
  concurrency: 2
  labels:
    interval: daily
---
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: snapshot-hourly
  namespace: longhorn-system
spec:
  name: snapshot-hourly
  task: snapshot
  cron: "0 * * * *"
  retain: 24
  concurrency: 5
  labels:
    interval: hourly
```

### PostgreSQL with CloudNativePG

#### Advanced Cluster Configuration

```yaml
# High-availability PostgreSQL cluster
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-ha
spec:
  instances: 3
  primaryUpdateStrategy: unsupervised
  
  postgresql:
    parameters:
      max_connections: "200"
      shared_buffers: "256MB"
      effective_cache_size: "1GB"
      maintenance_work_mem: "64MB"
      checkpoint_completion_target: "0.9"
      wal_buffers: "16MB"
      default_statistics_target: "100"
      random_page_cost: "1.1"
      effective_io_concurrency: "200"
      work_mem: "4MB"
      min_wal_size: "1GB"
      max_wal_size: "4GB"
  
  bootstrap:
    initdb:
      database: appdb
      owner: appuser
      secret:
        name: postgres-credentials
  
  storage:
    size: 10Gi
    storageClass: longhorn-fast
  
  backup:
    retentionPolicy: "30d"
    barmanObjectStore:
      destinationPath: "s3://backup-bucket/postgres"
      s3Credentials:
        accessKeyId:
          name: backup-credentials
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: backup-credentials
          key: SECRET_ACCESS_KEY
      wal:
        retention: "5d"
      data:
        retention: "30d"
        jobs: 2
  
  monitoring:
    enabled: true
  
  resources:
    requests:
      memory: "512Mi"
      cpu: "500m"
    limits:
      memory: "1Gi"
      cpu: "1000m"
```

## Monitoring and Observability

### Prometheus Configuration

#### Custom Monitoring Rules

```yaml
# infrastructure/monitoring/custom-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cluster-custom-rules
  namespace: monitoring
spec:
  groups:
    - name: cluster.rules
      rules:
        - alert: NodeDiskUsage
          expr: (1 - node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 > 90
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Node disk usage is above 90%"
            description: "Node {{ $labels.instance }} disk usage is {{ $value }}%"
        
        - alert: PodMemoryUsage
          expr: (container_memory_working_set_bytes / container_spec_memory_limit_bytes) * 100 > 90
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Pod memory usage is above 90%"
            description: "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} memory usage is {{ $value }}%"
        
        - alert: CiliumAgentDown
          expr: up{job="cilium-agent"} == 0
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "Cilium agent is down"
            description: "Cilium agent on node {{ $labels.instance }} is down"
```

#### Advanced Grafana Dashboard

```yaml
# Custom dashboard for cluster monitoring
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-overview-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  cluster-overview.json: |
    {
      "dashboard": {
        "title": "Cluster Overview",
        "panels": [
          {
            "title": "Node Resource Usage",
            "type": "stat",
            "targets": [
              {
                "expr": "avg(100 - (avg by(instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100))",
                "legendFormat": "CPU Usage %"
              }
            ]
          }
        ]
      }
    }
```

### Service Monitoring

```yaml
# ServiceMonitor for custom application
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: app-monitoring
  namespace: monitoring
spec:
  selector:
    matchLabels:
      monitoring: "enabled"
  endpoints:
    - port: metrics
      path: /metrics
      interval: 30s
      scrapeTimeout: 10s
  namespaceSelector:
    matchNames:
      - app-namespace
```

## Security Hardening

### Pod Security Standards

```yaml
# Namespace with Pod Security Standards
apiVersion: v1
kind: Namespace
metadata:
  name: secure-namespace
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Network Policies

#### Default Deny Policy

```yaml
# Default deny all traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

#### Application-Specific Policy

```yaml
# Allow specific application traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-network-policy
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: web-app
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx-internal
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: database
      ports:
        - protocol: TCP
          port: 5432
    - to: []  # Allow DNS
      ports:
        - protocol: UDP
          port: 53
```

### RBAC Configuration

#### Service Account with Limited Permissions

```yaml
# Service account for application
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-service-account
  namespace: production
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-role
  namespace: production
rules:
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-role-binding
  namespace: production
subjects:
  - kind: ServiceAccount
    name: app-service-account
    namespace: production
roleRef:
  kind: Role
  name: app-role
  apiGroup: rbac.authorization.k8s.io
```

## Cilium Network Policies

### Advanced Cilium Policies

#### Layer 7 HTTP Policy

```yaml
# Layer 7 HTTP network policy
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: l7-http-policy
  namespace: production
spec:
  endpointSelector:
    matchLabels:
      app: web-server
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: client
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
          rules:
            http:
              - method: "GET"
                path: "/api/v1/.*"
              - method: "POST"
                path: "/api/v1/data"
```

#### DNS Policy

```yaml
# DNS-based network policy
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: dns-policy
  namespace: production
spec:
  endpointSelector:
    matchLabels:
      app: web-app
  egress:
    - toFQDNs:
        - matchName: "api.external-service.com"
        - matchPattern: "*.safe-domain.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
```

## Custom Resource Definitions

### Backup CRD Example

```yaml
# Custom backup resource
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: backups.storage.example.com
spec:
  group: storage.example.com
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                source:
                  type: string
                destination:
                  type: string
                schedule:
                  type: string
                retention:
                  type: string
            status:
              type: object
              properties:
                lastBackup:
                  type: string
                nextBackup:
                  type: string
  scope: Namespaced
  names:
    plural: backups
    singular: backup
    kind: Backup
```

## Performance Tuning

### Node Performance Tuning

```yaml
# Node performance configuration
machine:
  sysctls:
    # Network performance
    net.core.rmem_max: 134217728
    net.core.wmem_max: 134217728
    net.ipv4.tcp_rmem: "4096 87380 134217728"
    net.ipv4.tcp_wmem: "4096 65536 134217728"
    net.core.netdev_max_backlog: 5000
    
    # File system performance
    vm.dirty_ratio: 15
    vm.dirty_background_ratio: 5
    vm.swappiness: 1
    
    # Container performance
    kernel.pid_max: 4194304
    fs.inotify.max_user_instances: 8192
    fs.inotify.max_user_watches: 524288
```

### Resource Quotas

```yaml
# Namespace resource quota
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    persistentvolumeclaims: "20"
    pods: "50"
    services: "10"
    secrets: "20" # pragma: allowlist secret
    configmaps: "20"
```

### Pod Disruption Budget

```yaml
# Ensure application availability during updates
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: app-pdb
  namespace: production
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: critical-service
```

## Best Practices

### Configuration Management

1. **Use Kustomize**: Manage configuration variants with overlays
2. **Version Control**: Store all configurations in Git
3. **Validate Manifests**: Use kubectl dry-run and kustomize validation
4. **Resource Limits**: Always specify resource requests and limits
5. **Health Checks**: Implement proper liveness and readiness probes

### Security Best Practices

1. **Least Privilege**: Grant minimal required permissions
2. **Network Segmentation**: Use network policies to restrict traffic
3. **Secret Management**: Use external secret management systems
4. **Image Security**: Use specific image tags and scan for vulnerabilities
5. **Regular Updates**: Keep all components updated

### Monitoring Best Practices

1. **Comprehensive Coverage**: Monitor all layers of the stack
2. **Alerting**: Set up meaningful alerts with proper thresholds
3. **Log Aggregation**: Centralize logs for analysis
4. **Performance Metrics**: Track application and infrastructure performance
5. **Capacity Planning**: Monitor resource usage trends

Remember: Advanced configurations require thorough understanding of the underlying systems. Always test changes in a non-production environment first and maintain proper documentation of customizations.
