# Partition Wipe Recovery Strategy - Post-Security Incident

**Date**: 2025-07-16  
**Status**: DIAGNOSIS COMPLETE - RECOVERY STRATEGY READY  
**Context**: Security incident requiring complete cluster rebuild with partition wiping

## DIAGNOSIS SUMMARY

### Current Node States (Confirmed)

| Node | Network | Talos API | State | Issue | Recovery Priority |
|------|---------|-----------|-------|-------|------------------|
| **mini01** (172.29.51.11) | ✅ Responsive | ✅ Authenticated | ❌ **Read-only filesystem** | Cannot write kubelet PKI | **HIGH - Manual intervention required** |
| **mini02** (172.29.51.12) | ✅ Responsive | ✅ Insecure only | ✅ **Maintenance mode** | Wipe successful | **READY - Apply new config** |
| **mini03** (172.29.51.13) | ✅ Responsive | ✅ Insecure only | ✅ **Maintenance mode** | Wipe successful | **READY - Apply new config** |

### Key Findings

1. **Wipe Configuration WAS Processed Successfully** on mini02 and mini03
2. **mini01 has a read-only filesystem issue** preventing PKI certificate updates
3. **mini02 and mini03 are in maintenance mode** - exactly what we want for security reset
4. **All nodes are network accessible** and Talos API is responding

### Root Cause Analysis

**Most Likely Sources:**
1. **Disk encryption state corruption** on mini01 - LUKS2 encryption may be in inconsistent state
2. **Filesystem mount issues** - STATE/EPHEMERAL partitions may be mounted read-only

**Evidence:**
- Error: `"error writing kubelet PKI: open /etc/kubernetes/bootstrap-kubeconfig: read-only file system"`
- mini02/mini03 successfully processed wipe and entered maintenance mode
- mini01 shows normal Talos services but cannot write to encrypted partitions

## RECOVERY STRATEGY

### Phase 1: Fix mini01 Read-Only Filesystem Issue

#### Option 1A: Force Partition Wipe on mini01 (RECOMMENDED)
```bash
# Apply wipe configuration directly to mini01
export TALOSCONFIG=clusterconfig/talosconfig
talosctl apply-config --nodes 172.29.51.11 --file clusterconfig/home-ops-mini01.yaml --mode=reboot

# Monitor for maintenance mode entry
watch "talosctl version --nodes 172.29.51.11 --endpoints 172.29.51.11 --insecure 2>&1"
```

#### Option 1B: Manual Disk Reset (If Option 1A fails)
```bash
# Reset disk encryption state
talosctl reset --nodes 172.29.51.11 --endpoints 172.29.51.11 --graceful=false --reboot

# Wait for maintenance mode
sleep 60
talosctl version --nodes 172.29.51.11 --endpoints 172.29.51.11 --insecure
```

#### Option 1C: Physical Power Cycle (Last resort)
```bash
# If software reset fails, physically power cycle mini01
# Then apply configuration in maintenance mode
```

### Phase 2: Generate Fresh Cluster Secrets

Since the security incident exposed all cluster secrets, generate completely new ones:

```bash
# Remove old compromised secrets
rm -f clusterconfig/talosconfig
rm -f talos/generated/talosconfig

# Generate fresh cluster secrets (this will create new PKI)
task talos:generate-config

# Verify new secrets are generated
ls -la clusterconfig/ talos/generated/
```

### Phase 3: Apply Fresh Configuration to All Nodes

Once all nodes are in maintenance mode:

```bash
export TALOSCONFIG=clusterconfig/talosconfig

# Apply fresh configuration to all nodes
talosctl apply-config --nodes 172.29.51.11 --endpoints 172.29.51.11 --file clusterconfig/home-ops-mini01.yaml --insecure
talosctl apply-config --nodes 172.29.51.12 --endpoints 172.29.51.12 --file clusterconfig/home-ops-mini02.yaml --insecure  
talosctl apply-config --nodes 172.29.51.13 --endpoints 172.29.51.13 --file clusterconfig/home-ops-mini03.yaml --insecure

# Wait for nodes to reboot and initialize
sleep 120
```

### Phase 4: Bootstrap New Cluster

```bash
# Bootstrap the cluster with fresh secrets
talosctl bootstrap --nodes 172.29.51.11 --endpoints 172.29.51.11

# Wait for cluster initialization
sleep 60

# Generate fresh kubeconfig
talosctl kubeconfig --nodes 172.29.51.11 --endpoints 172.29.51.11 --force

# Verify cluster is healthy
kubectl get nodes
```

### Phase 5: Restore GitOps and Applications

```bash
# Deploy Cilium CNI first (required for networking)
task apps:deploy-cilium

# Wait for nodes to become Ready
watch kubectl get nodes

# Deploy core infrastructure
kubectl apply -k clusters/homelab/infrastructure/

# Verify 1Password Connect and External Secrets
kubectl get clustersecretstore
kubectl get pods -n onepassword-connect
```

## ESCALATED RECOVERY OPTIONS

### If Standard Recovery Fails

#### Option A: Manual Talos Installer Boot
1. Create Talos installer USB/network boot
2. Boot each node from installer
3. Apply configuration during installation
4. Ensures complete disk wipe and fresh installation

#### Option B: Direct Partition Manipulation
```bash
# If accessible via rescue mode
# WARNING: Only if other methods fail
talosctl reset --nodes <node> --endpoints <node> --graceful=false --wipe-mode=all
```

#### Option C: Complete Reinstallation
1. Download latest Talos installer image
2. Create bootable media
3. Physically boot each node from installer
4. Apply fresh configuration during installation

## VALIDATION STEPS

### After Each Phase
```bash
# Verify node states
talosctl version --nodes 172.29.51.11,172.29.51.12,172.29.51.13 --endpoints 172.29.51.11

# Check services
talosctl services --nodes 172.29.51.11,172.29.51.12,172.29.51.13 --endpoints 172.29.51.11

# Verify no read-only filesystem errors
talosctl dmesg --nodes 172.29.51.11 --endpoints 172.29.51.11 | grep -i "read-only"

# Check cluster health
kubectl get nodes
kubectl get pods --all-namespaces
```

### Security Validation
```bash
# Verify new cluster secrets are in use
kubectl get secrets -n kube-system | grep -E "(bootstrap|kubelet)"

# Check certificate dates (should be recent)
kubectl get csr

# Verify 1Password Connect with new credentials
kubectl get clustersecretstore -o yaml
```

## FALLBACK PROCEDURES

### If mini01 Cannot Be Recovered
1. **Remove mini01 from cluster configuration**
2. **Proceed with 2-node cluster** (mini02 + mini03)
3. **Add mini01 back later** after manual disk replacement/repair

### If Multiple Nodes Fail
1. **Complete hardware reset** of all nodes
2. **Fresh Talos installation** from scratch
3. **Restore from GitOps** once cluster is operational

## TIMELINE ESTIMATES

| Phase | Estimated Time | Dependencies |
|-------|---------------|--------------|
| Phase 1: Fix mini01 | 15-30 minutes | Physical access if needed |
| Phase 2: Generate secrets | 5 minutes | None |
| Phase 3: Apply configs | 10-15 minutes | All nodes in maintenance |
| Phase 4: Bootstrap cluster | 10-15 minutes | Successful config apply |
| Phase 5: Restore apps | 20-30 minutes | Cluster operational |
| **Total Recovery** | **60-95 minutes** | No major complications |

## SUCCESS CRITERIA

- [ ] All nodes show "Ready" status in kubectl
- [ ] No read-only filesystem errors in logs
- [ ] Fresh PKI certificates generated and applied
- [ ] Cluster API accessible with new kubeconfig
- [ ] 1Password Connect operational with new credentials
- [ ] External Secrets validating successfully
- [ ] All GitOps applications deployed and healthy

## EMERGENCY CONTACTS

- **Physical Access**: Required for power cycling if software reset fails
- **1Password Admin**: For Connect server regeneration
- **Network Admin**: For any routing/firewall issues during recovery

---

**CRITICAL**: This recovery addresses the catastrophic security incident where complete Talos cluster secrets were exposed. The partition wipe was successful on 2/3 nodes, with mini01 requiring additional intervention due to filesystem issues.