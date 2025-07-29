# Disaster Recovery Procedures

This document outlines comprehensive disaster recovery procedures for the Talos GitOps home-ops cluster. These procedures are designed to restore service availability with minimal data loss across various failure scenarios.

## Table of Contents

- [Overview](#overview)
- [Recovery Time Objectives](#recovery-time-objectives)
- [Disaster Scenarios](#disaster-scenarios)
- [Complete Cluster Failure](#complete-cluster-failure)
- [Data Loss Scenarios](#data-loss-scenarios)
- [Network Infrastructure Failure](#network-infrastructure-failure)
- [Hardware Failure](#hardware-failure)
- [Security Incidents](#security-incidents)
- [Backup and Restore Procedures](#backup-and-restore-procedures)
- [Emergency Contact Procedures](#emergency-contact-procedures)
- [Post-Recovery Procedures](#post-recovery-procedures)

## Overview

### Disaster Recovery Philosophy

The cluster is designed with recovery-first principles:

1. **Immutable Infrastructure**: Talos OS enables complete rebuilds from configuration
2. **Persistent Data Protection**: Critical data stored with multiple backup strategies
3. **Rapid Reconstruction**: Bootstrap automation enables quick cluster recreation
4. **Configuration as Code**: All configurations stored in Git for reproducibility

### Critical Systems Priority

Recovery prioritization based on business impact:

1. **Priority 1 (Critical)**: Cluster foundation (Talos, Kubernetes, CNI)
2. **Priority 2 (High)**: Authentication, networking, storage systems
3. **Priority 3 (Medium)**: Infrastructure services (monitoring, ingress)
4. **Priority 4 (Low)**: Applications and user services

## Recovery Time Objectives

| Scenario | Detection Time | Recovery Time | Data Loss Tolerance |
|----------|----------------|---------------|-------------------|
| Single node failure | < 5 minutes | < 15 minutes | None |
| Complete cluster failure | < 10 minutes | < 60 minutes | < 24 hours |
| Storage system failure | < 5 minutes | < 30 minutes | < 1 hour |
| Network failure | < 2 minutes | < 20 minutes | None |
| Security incident | Immediate | < 2 hours | Varies |
| Complete site disaster | < 30 minutes | < 4 hours | < 24 hours |

## Disaster Scenarios

### Scenario Classification

#### Level 1: Service Degradation

- Single pod/service failure
- Temporary network issues
- Non-critical component failure

#### Level 2: System Outage

- Single node failure
- Storage volume corruption
- Authentication system failure

#### Level 3: Cluster Failure

- Multiple node failure
- Complete network failure
- Storage system complete failure

#### Level 4: Site Disaster

- Complete hardware loss
- Extended power/network outage
- Physical facility damage

## Complete Cluster Failure

### Scenario: All Nodes Unresponsive

#### Immediate Assessment

```bash
# 1. Check node accessibility
talosctl version --insecure --nodes 172.29.51.11,172.29.51.12,172.29.51.13

# 2. Check network connectivity
ping 172.29.51.11
ping 172.29.51.12
ping 172.29.51.13

# 3. Check power status (if accessible)
# Physical inspection of Mac mini devices

# 4. Check external services
curl -I https://github.com/your-username/talos-gitops
```

#### Recovery Procedure

**Option A: Soft Recovery (OS Intact)**

```bash
# 1. Attempt node recovery
talosctl reboot --nodes 172.29.51.11,172.29.51.12,172.29.51.13

# 2. Wait for nodes to return online
sleep 300

# 3. Check cluster status
kubectl get nodes

# 4. If cluster API unavailable, bootstrap first node
talosctl bootstrap --nodes 172.29.51.11

# 5. Wait for control plane
kubectl wait --for=condition=Ready nodes --all --timeout=600s

# 6. Verify system pods
kubectl get pods -n kube-system

# 7. Redeploy CNI if needed
task apps:deploy-cilium

# 8. Verify Flux system
flux get kustomizations
```

**Option B: Hard Recovery (OS Damaged)**

```bash
# 1. Prepare for complete rebuild
cd /path/to/talos-gitops

# 2. Verify environment configuration
cp .env.example .env
# Edit .env with correct OP_ACCOUNT

# 3. Execute complete bootstrap
task bootstrap:phased

# 4. Monitor bootstrap progress
# Follow prompts and verify each phase completion

# 5. Restore from backups (see backup procedures below)
```

### Scenario: etcd Corruption

#### Detection Signs

- Kubernetes API timeouts
- etcd pods crash-looping
- Cluster certificates invalid

#### Recovery Procedure

```bash
# 1. Check etcd cluster health
talosctl etcd status --nodes 172.29.51.11,172.29.51.12,172.29.51.13

# 2. If majority healthy, remove corrupted member
talosctl etcd remove-member <member-id> --nodes <healthy-nodes>

# 3. Reset corrupted node
talosctl reset --graceful=false --reboot --nodes <corrupted-node>

# 4. Re-join node to cluster
talosctl apply-config --nodes <corrupted-node> --file clusterconfig/<node-config>.yaml

# 5. If majority corrupted, restore from backup
talosctl etcd snapshot /var/lib/etcd/member/snap/db --nodes <healthy-node>

# 6. Bootstrap new cluster with restored data
# Follow complete rebuild procedure with etcd restore
```

## Data Loss Scenarios

### Longhorn Storage Failure

#### Scenario: Complete Storage System Failure

**Assessment**:

```bash
# 1. Check Longhorn system status
kubectl get pods -n longhorn-system

# 2. Access Longhorn UI (if available)
# Navigate to https://longhorn.k8s.home.geoffdavis.com

# 3. Check volume status
kubectl get pv,pvc -A

# 4. Check USB SSD connectivity
talosctl ls /dev/disk/by-id/ --nodes 172.29.51.11,172.29.51.12,172.29.51.13
```

**Recovery Options**:

**Option 1: Volume Recovery**

```bash
# 1. Check for available replicas
# Use Longhorn UI to identify healthy replicas

# 2. Rebuild missing replicas
# Use Longhorn UI to trigger replica rebuilding

# 3. If UI unavailable, check volume CRDs
kubectl get volumes.longhorn.io -n longhorn-system

# 4. Manual replica recovery
kubectl patch volume.longhorn.io <volume-name> -n longhorn-system \
  --type='merge' -p='{"spec":{"numberOfReplicas":2}}'
```

**Option 2: Snapshot Restore**

```bash
# 1. List available snapshots
kubectl get volumesnapshots -A

# 2. Create new PVC from snapshot
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: restored-data
spec:
  dataSource:
    name: <snapshot-name>
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

**Option 3: Backup Restore**

```bash
# 1. Check available backups in Longhorn UI
# 2. Restore volume from S3 backup
# 3. Create new PVC pointing to restored volume
# 4. Update application to use new PVC
```

### Database Corruption

#### PostgreSQL Database Recovery

**For Authentik Database**:

```bash
# 1. Check cluster status
kubectl get cluster authentik-postgresql -n authentik

# 2. Check available backups
kubectl get backup -n authentik

# 3. Restore from backup
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: authentik-postgresql-restored
  namespace: authentik
spec:
  instances: 3
  bootstrap:
    recovery:
      backup:
        name: <backup-name>
EOF

# 4. Update application to use restored cluster
kubectl patch helmrelease authentik -n authentik \
  --type='merge' -p='{"spec":{"values":{"postgresql":{"host":"authentik-postgresql-restored-rw"}}}}'
```

**For Home Assistant Database**:

```bash
# 1. Check cluster status
kubectl get cluster homeassistant-postgresql -n home-automation

# 2. Manual backup extraction
kubectl exec -n home-automation <postgres-pod> -- \
  pg_dump homeassistant > homeassistant-emergency-backup.sql

# 3. Restore to new cluster
kubectl exec -n home-automation <new-postgres-pod> -- \
  psql homeassistant < homeassistant-emergency-backup.sql
```

## Network Infrastructure Failure

### BGP Peering Failure

#### Scenario: Complete BGP Connectivity Loss

**Assessment**:

```bash
# 1. Check BGP peering status
kubectl exec -n kube-system -l k8s-app=cilium -- cilium bgp peers

# 2. Check LoadBalancer service status
kubectl get svc -A --field-selector spec.type=LoadBalancer

# 3. Test external connectivity
curl -I https://longhorn.k8s.home.geoffdavis.com
```

**Recovery Procedure**:

```bash
# 1. Check UDM Pro BGP configuration
# SSH to UDM Pro and verify BGP neighbor configuration

# 2. Restart Cilium agent
kubectl delete pods -n kube-system -l k8s-app=cilium

# 3. Verify BGP policy configuration
kubectl get ciliumbgppeeringpolicies -o yaml

# 4. If policy corrupted, restore from Git
git checkout infrastructure/cilium-bgp/bgp-policy-legacy.yaml
kubectl apply -f infrastructure/cilium-bgp/bgp-policy-legacy.yaml

# 5. Test connectivity restoration
kubectl exec -n kube-system -l k8s-app=cilium -- cilium bgp routes
```

### DNS Resolution Failure

#### External DNS Recovery

```bash
# 1. Check External DNS pods
kubectl get pods -n external-dns-internal

# 2. Check DNS provider credentials
kubectl get secrets -n external-dns-internal

# 3. Restart External DNS
kubectl rollout restart deployment external-dns -n external-dns-internal

# 4. Manual DNS record creation (emergency)
# Use DNS provider web interface to create critical records:
# - longhorn.k8s.home.geoffdavis.com -> 172.29.52.100
# - grafana.k8s.home.geoffdavis.com -> 172.29.52.101
# - authentik.k8s.home.geoffdavis.com -> 172.29.52.200
```

#### Internal DNS Recovery

```bash
# 1. Check CoreDNS status
kubectl get pods -n kube-system -l k8s-app=kube-dns

# 2. Restart CoreDNS
kubectl rollout restart deployment coredns -n kube-system

# 3. Test internal resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup kubernetes.default.svc.cluster.local

# 4. Check CoreDNS configuration
kubectl get configmap coredns -n kube-system -o yaml
```

## Hardware Failure

### Single Node Failure

#### Assessment and Recovery

```bash
# 1. Identify failed node
kubectl get nodes

# 2. Check node conditions
kubectl describe node <failed-node>

# 3. Cordone and drain node
kubectl cordon <failed-node>
kubectl drain <failed-node> --ignore-daemonsets --delete-emptydir-data

# 4. Check USB SSD status on remaining nodes
talosctl ls /dev/disk/by-id/ --nodes <healthy-nodes>

# 5. For Mac mini hardware replacement:
# a. Power down failed node
# b. Replace hardware
# c. Re-image with Talos OS
talosctl apply-config --insecure --nodes <new-node-ip> \
  --file clusterconfig/<node-config>.yaml

# 6. Wait for node to join cluster
kubectl get nodes --watch

# 7. Uncordon node when ready
kubectl uncordon <new-node>
```

### Multiple Node Failure

#### Assessment

```bash
# 1. Count healthy nodes
kubectl get nodes | grep Ready | wc -l

# 2. Check etcd quorum
talosctl etcd status --nodes <healthy-nodes>

# 3. Check critical workload distribution
kubectl get pods -A -o wide | grep <healthy-nodes>
```

#### Recovery Strategy

**If Quorum Maintained (2+ nodes healthy)**:

```bash
# 1. Follow single node recovery for each failed node
# 2. Stagger node replacements to maintain stability
# 3. Ensure storage replicas are rebuilt between recoveries
```

**If Quorum Lost (1 node remaining)**:

```bash
# 1. Promote remaining node to single-node etcd
talosctl etcd forfeit-leadership --nodes <surviving-node>

# 2. Bootstrap new cluster from surviving node
# 3. Add replacement nodes one by one
# 4. Restore data from backups if needed
```

### Storage Hardware Failure

#### USB SSD Failure

```bash
# 1. Identify failed storage
kubectl get pv | grep Bound
talosctl ls /dev/disk/by-id/ --nodes 172.29.51.11,172.29.51.12,172.29.51.13

# 2. Check Longhorn volume replicas
# Use Longhorn UI to identify affected volumes

# 3. Replace failed USB SSD
# a. Power down node
# b. Replace USB SSD
# c. Power up node

# 4. Re-add storage to Longhorn
# Use Longhorn UI to add new disk

# 5. Rebuild volume replicas
# Use Longhorn UI to trigger replica rebuilding
```

## Security Incidents

### Compromised Credentials

#### 1Password Credential Rotation

```bash
# 1. Immediately revoke compromised credentials in 1Password

# 2. Rotate 1Password Connect credentials
task onepassword:create-connect-server

# 3. Update cluster 1Password integration
task bootstrap:1password-secrets

# 4. Restart external-secrets-operator
kubectl rollout restart deployment external-secrets -n external-secrets-system

# 5. Monitor secret synchronization
kubectl get externalsecrets -A --watch
```

#### Authentik System Compromise

```bash
# 1. Suspend all user sessions
# Access Authentik admin UI and revoke all sessions

# 2. Rotate Authentik database credentials
kubectl delete secret authentik-postgresql-app -n authentik

# 3. Restart Authentik pods
kubectl rollout restart deployment authentik -n authentik

# 4. Update external outpost tokens
# Generate new token in Authentik admin
# Update 1Password entry
# Restart authentik-proxy deployment

# 5. Force re-authentication for all services
kubectl rollout restart deployment authentik-proxy -n authentik-proxy
```

### Malicious Code Deployment

#### GitOps Repository Compromise

```bash
# 1. Immediately suspend all Flux reconciliation
flux suspend kustomization --all

# 2. Analyze Git history for malicious commits
git log --oneline --since="1 week ago"
git show <suspicious-commit>

# 3. Revert to known good state
git revert <malicious-commit>
git push origin main

# 4. Restart Flux with clean state
flux resume kustomization --all

# 5. Audit all deployed resources
kubectl get all -A
kubectl get secrets -A
kubectl get configmaps -A
```

## Backup and Restore Procedures

### Critical Data Backup

#### 1. Configuration Backup

```bash
# Git repository (automated via GitHub)
git push origin main

# Talos configuration
cp -r clusterconfig/ /backup/talos-config-$(date +%Y%m%d)/

# 1Password vault export (manual process)
# Use 1Password desktop app to export vault
```

#### 2. Application Data Backup

**Longhorn Volume Snapshots**:

```bash
# Automated via Longhorn recurring jobs
# Manual snapshot creation:
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: manual-backup-$(date +%Y%m%d)
  namespace: <namespace>
spec:
  source:
    persistentVolumeClaimName: <pvc-name>
EOF
```

**PostgreSQL Database Backups**:

```bash
# CloudNativePG automated backups to S3
# Manual backup:
kubectl exec -n <namespace> <postgres-pod> -- \
  pg_dump <database> | gzip > backup-$(date +%Y%m%d).sql.gz
```

### Restore Procedures

#### Complete System Restore

**Prerequisites**:

- Physical hardware available
- Network connectivity restored
- Backup data accessible

**Procedure**:

```bash
# 1. Restore cluster configuration
git clone https://github.com/your-username/talos-gitops.git
cd talos-gitops

# 2. Bootstrap cluster
task bootstrap:phased

# 3. Restore 1Password integration
task bootstrap:1password-secrets

# 4. Wait for GitOps to deploy infrastructure
flux get kustomizations --watch

# 5. Restore application data
# Follow database and volume restore procedures above

# 6. Verify all services
task cluster:status
```

#### Selective Data Restore

**Volume Restore**:

```bash
# 1. Create PVC from backup
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: restored-data
spec:
  dataSource:
    name: <backup-snapshot>
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: <size>
EOF

# 2. Update application to use restored PVC
kubectl patch deployment <app> --type='merge' \
  -p='{"spec":{"template":{"spec":{"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"restored-data"}}]}}}}'
```

## Emergency Contact Procedures

### Escalation Matrix

| Severity | Response Time | Contact Method | Personnel |
|----------|---------------|----------------|-----------|
| Critical | Immediate | Phone/SMS | Primary operator |
| High | 30 minutes | Email/Slack | Primary + Secondary |
| Medium | 2 hours | Email | Primary operator |
| Low | Next business day | Email | Any operator |

### Emergency Communication

#### Internal Notifications

```bash
# Automated alerting via monitoring stack
# Manual notification:
curl -X POST <slack-webhook-url> \
  -H 'Content-type: application/json' \
  --data '{"text":"EMERGENCY: Cluster disaster recovery in progress"}'
```

#### External Dependencies

- **Internet Provider**: Contact for network issues
- **UDM Pro Support**: For BGP/networking problems
- **Hardware Vendor**: For Mac mini hardware issues
- **1Password Support**: For critical secret management issues

### Status Communication

#### Internal Status Page

```bash
# Update status in Git repository
echo "$(date): Disaster recovery in progress" >> STATUS.md
git add STATUS.md
git commit -m "Emergency: Update status"
git push
```

#### External Communication

- Update external monitoring if available
- Notify users of expected downtime
- Provide recovery progress updates

## Post-Recovery Procedures

### Immediate Validation

```bash
# 1. Cluster health check
task cluster:status

# 2. Application functionality test
curl -I https://longhorn.k8s.home.geoffdavis.com
curl -I https://grafana.k8s.home.geoffdavis.com
curl -I https://homeassistant.k8s.home.geoffdavis.com

# 3. Authentication system test
# Log in to each service via SSO

# 4. Data integrity verification
# Check critical application data
# Verify backup timestamps
# Test restore procedures
```

### Documentation Updates

#### Incident Report

Create incident report including:

- **Timeline**: Detailed timeline of events
- **Root Cause**: Technical analysis of failure
- **Impact Assessment**: Services affected and duration
- **Recovery Actions**: Steps taken to restore service
- **Lessons Learned**: What worked well and what didn't
- **Action Items**: Improvements to prevent recurrence

#### Procedure Updates

```bash
# Update disaster recovery procedures
vim docs/operations/disaster-recovery.md

# Update monitoring and alerting
vim infrastructure/monitoring/alert-rules.yaml

# Commit improvements
git add docs/ infrastructure/
git commit -m "disaster-recovery: update procedures based on incident"
git push
```

### System Hardening

#### Preventive Measures

```bash
# 1. Enhance monitoring
# Add alerts for identified failure modes

# 2. Improve backup frequency
# Update backup schedules if needed

# 3. Test recovery procedures
# Schedule regular disaster recovery tests

# 4. Update documentation
# Capture new procedures and lessons learned

# 5. Training
# Train team on new procedures
```

#### Backup Validation

```bash
# 1. Test backup restoration
# Perform test restore in isolated environment

# 2. Verify backup integrity
# Check backup checksums and data consistency

# 3. Update backup procedures
# Improve backup coverage based on recovery experience

# 4. Automate validation
# Add automated backup testing
```

## Regular Disaster Recovery Testing

### Monthly Tests

- Single node failure simulation
- Network partition recovery
- Service endpoint failure
- Backup restoration testing

### Quarterly Tests

- Complete cluster rebuild
- Cross-site backup restoration
- Security incident response
- Communication procedure testing

### Annual Tests

- Full disaster scenario simulation
- Off-site backup restoration
- Complete hardware replacement
- End-to-end recovery documentation validation

Remember: Disaster recovery is not just about technical procedures—it's about maintaining service availability for users while protecting data integrity. Always prioritize safety over speed, and thoroughly validate recovery before declaring success.
