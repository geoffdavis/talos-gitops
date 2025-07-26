# 🚨 CLUSTER RESET SAFETY GUIDE 🚨

## ⚠️ CRITICAL WARNING ⚠️

**NEVER use `talosctl reset` without explicit partition specifications!**

This guide exists because improper reset commands have caused **complete OS wipes requiring USB drive reinstallation**. Follow these guidelines strictly to prevent data loss and system destruction.

## 🛡️ SAFE RESET PRINCIPLES

### ✅ SAFE: Reset Only User Data Partitions

```bash
# SAFE - Resets only EPHEMERAL and STATE partitions, preserves OS
talosctl reset --system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL --nodes <node-ip>
```

### ❌ DANGEROUS: Never Use These Commands

```bash
# DANGEROUS - Will wipe entire OS requiring USB reinstallation
talosctl reset --nodes <node-ip>                    # ❌ NO PARTITION SPECIFICATION
talosctl reset --graceful=false --nodes <node-ip>   # ❌ FORCE RESET WITHOUT LIMITS
talosctl reset --wipe-mode=all --nodes <node-ip>    # ❌ WIPES EVERYTHING INCLUDING OS
```

## 🔧 SAFE RESET COMMANDS

### Safe Single Node Reset

```bash
# Reset only user data on a single node
talosctl reset \
  --system-labels-to-wipe STATE \
  --system-labels-to-wipe EPHEMERAL \
  --nodes 172.29.51.11 \
  --endpoints 172.29.51.11
```

### Safe Multi-Node Reset (Sequential)

```bash
# Reset nodes one at a time to maintain cluster availability
for node in 172.29.51.11 172.29.51.12 172.29.51.13; do
  echo "Resetting node $node (user data only)..."
  talosctl reset \
    --system-labels-to-wipe STATE \
    --system-labels-to-wipe EPHEMERAL \
    --nodes $node \
    --endpoints $node
  echo "Waiting for node $node to come back online..."
  sleep 60
done
```

### Safe Cluster-Wide Reset (Use with Extreme Caution)

```bash
# Only if absolutely necessary - resets user data on all nodes
# WARNING: This will cause cluster downtime
talosctl reset \
  --system-labels-to-wipe STATE \
  --system-labels-to-wipe EPHEMERAL \
  --nodes 172.29.51.11,172.29.51.12,172.29.51.13
```

## 🚨 EMERGENCY RECOVERY PROCEDURES

### When Nodes Become Unresponsive

#### Step 1: Try Safe Recovery First

```bash
# Attempt to recover kubeconfig
task talos:recover-kubeconfig

# Check node status
kubectl get nodes

# If nodes show NotReady, try Cilium fix
task talos:fix-cilium
```

#### Step 2: Safe Node Restart

```bash
# Reboot nodes instead of resetting
task talos:reboot NODES=172.29.51.11
# Or reboot all nodes
task talos:reboot
```

#### Step 3: Configuration Reapplication

```bash
# Reapply configuration without reset
task talos:apply-config-only
```

#### Step 4: Last Resort - Safe Reset

```bash
# Only if above steps fail - use safe reset
task cluster:safe-reset NODE=172.29.51.11
```

## 🛠️ SAFE TROUBLESHOOTING METHODS

### Network Issues

```bash
# Check network configuration
talosctl get addresses --nodes <node-ip>
talosctl get routes --nodes <node-ip>

# Check LLDP neighbors
task network:check-lldp

# Restart network services (safe)
talosctl service networkd restart --nodes <node-ip>
```

### Storage Issues

```bash
# Check disk usage
talosctl df --nodes <node-ip>

# Check mount points
talosctl get mounts --nodes <node-ip>

# Check USB devices
task network:check-usb
```

### Service Issues

```bash
# Restart specific services (safe)
talosctl service kubelet restart --nodes <node-ip>
talosctl service containerd restart --nodes <node-ip>

# Check service status
talosctl services --nodes <node-ip>
```

### Certificate Issues

```bash
# Regenerate kubeconfig (safe)
talosctl kubeconfig --nodes <node-ip> --force

# Check certificate expiration
talosctl get certificates --nodes <node-ip>
```

## 📋 PRE-RESET CHECKLIST

Before performing ANY reset operation:

- [ ] **Backup cluster state**: `task maintenance:backup`
- [ ] **Verify you have working USB installer** ready
- [ ] **Confirm you're using partition-specific reset commands**
- [ ] **Test on single node first** if possible
- [ ] **Ensure 1Password secrets are accessible**
- [ ] **Have network access to remaining nodes**
- [ ] **Understand the recovery procedure**

## 🔄 PARTITION TYPES EXPLAINED

### EPHEMERAL Partition

- **Contains**: Temporary data, logs, container images
- **Safe to wipe**: Yes - will be recreated
- **Impact**: Temporary data loss, containers will restart

### STATE Partition

- **Contains**: Node configuration, certificates, etcd data
- **Safe to wipe**: Yes - can be restored from configuration
- **Impact**: Node will rejoin cluster with fresh state

### BOOT/ROOT Partitions

- **Contains**: Talos OS itself
- **Safe to wipe**: **NO** - Requires USB reinstallation
- **Impact**: Complete OS loss, manual reinstallation required

## 🚫 WHAT NOT TO DO

### Never Use These Patterns

```bash
# ❌ Generic reset without partition specification
talosctl reset --nodes <ip>

# ❌ Force reset without safety checks
talosctl reset --graceful=false

# ❌ Wipe all partitions
talosctl reset --wipe-mode=all

# ❌ Reset without understanding the impact
talosctl reset --system-labels-to-wipe <unknown-label>
```

### Never Reset When

- You don't have USB installer ready
- You don't understand the partition layout
- You haven't tried safer alternatives first
- You're not prepared for potential OS reinstallation
- You don't have access to 1Password secrets

## ✅ SAFE ALTERNATIVES TO RESET

### Instead of Reset, Try These First

1. **Service Restart**

   ```bash
   talosctl service <service-name> restart --nodes <node-ip>
   ```

2. **Configuration Reapplication**

   ```bash
   task talos:apply-config-only
   ```

3. **Node Reboot**

   ```bash
   task talos:reboot NODES=<node-ip>
   ```

4. **Cluster Recovery**

   ```bash
   task cluster:recover
   ```

5. **Component-Specific Fixes**
   ```bash
   task talos:fix-cilium
   task talos:recover-kubeconfig
   ```

## 🆘 RECOVERY FROM OS WIPE

If you accidentally wiped the OS and need to reinstall:

### Step 1: Prepare USB Installer

```bash
# Generate custom installer with extensions
task talos:generate-schematic
task talos:update-installer-images
```

### Step 2: Physical Reinstallation

1. Boot from USB installer on affected node(s)
2. Install Talos OS to internal disk
3. Ensure network connectivity

### Step 3: Rejoin Cluster

```bash
# Restore secrets and regenerate config
task talos:restore-secrets
task talos:generate-config

# Apply configuration to reinstalled node
task talos:apply-config

# If this was the bootstrap node, bootstrap again
task talos:bootstrap
```

## 📞 EMERGENCY CONTACTS

When things go wrong:

1. **Check existing documentation**: [`docs/CLUSTER_RECOVERY.md`](CLUSTER_RECOVERY.md)
2. **Review troubleshooting**: [`docs/CLUSTER_REBUILD_FIXES.md`](CLUSTER_REBUILD_FIXES.md)
3. **Use safe recovery tasks**: `task cluster:recover`

## 🎯 KEY TAKEAWAYS

1. **ALWAYS specify partitions** when using `talosctl reset`
2. **PREFER safer alternatives** like service restarts or reboots
3. **TEST on single node first** when possible
4. **BACKUP before any destructive operation**
5. **HAVE USB installer ready** as last resort
6. **UNDERSTAND the impact** before executing commands

---

**Remember: It's better to spend extra time on safe recovery than to reinstall the entire OS from USB drives.**
