# 🛡️ SUBTASK SAFETY GUIDELINES

## 🚨 CRITICAL SAFETY RULES FOR ALL OPERATIONS

These guidelines **MUST** be followed for any cluster operations, especially when performed by automated subtasks or AI assistants. Violation of these rules has previously resulted in **complete OS wipes requiring USB drive reinstallation**.

## 🔒 MANDATORY SAFETY PROTOCOLS

### Rule #1: NEVER Reset Entire Cluster Without Explicit Permission

```bash
# ❌ FORBIDDEN - Never use without explicit user approval
talosctl reset --nodes <any-nodes>

# ✅ REQUIRED - Always get explicit user confirmation first
echo "WARNING: This will reset user data on nodes. Continue? (yes/no)"
read confirmation
if [[ "$confirmation" != "yes" ]]; then
    echo "Operation cancelled for safety"
    exit 1
fi
```

### Rule #2: ALWAYS Specify Partition Limitations

```bash
# ❌ FORBIDDEN - Generic reset without partition specification
talosctl reset --nodes <node-ip>

# ✅ REQUIRED - Always specify safe partitions only
talosctl reset \
  --system-labels-to-wipe STATE \
  --system-labels-to-wipe EPHEMERAL \
  --nodes <node-ip>
```

### Rule #3: ALWAYS Ask Before Destructive Operations

Any operation that could cause data loss or downtime MUST:

- Display clear warnings about the operation's impact
- Require explicit user confirmation
- Provide safe alternatives
- Document the command before execution

### Rule #4: PREFER Configuration Fixes Over Resets

Before considering any reset operation, try these safer alternatives:

1. Service restarts: `talosctl service <service> restart`
2. Configuration reapplication: `task talos:apply-config-only`
3. Node reboots: `task talos:reboot`
4. Component-specific fixes: `task talos:fix-cilium`

### Rule #5: Document All Commands Before Execution

Every potentially destructive command must be:

- Logged with timestamp and reasoning
- Reviewed for safety compliance
- Executed with appropriate safeguards
- Monitored for successful completion

## 🚫 FORBIDDEN OPERATIONS

### Never Execute These Commands

```bash
# ❌ Complete system reset (wipes OS)
talosctl reset --nodes <any-nodes>
talosctl reset --graceful=false --nodes <any-nodes>
talosctl reset --wipe-mode=all --nodes <any-nodes>

# ❌ Destructive disk operations
talosctl reset --system-labels-to-wipe <unknown-labels>
dd if=/dev/zero of=/dev/<disk>
mkfs.<filesystem> /dev/<disk>

# ❌ Unsafe cluster operations
kubectl delete nodes --all
kubectl delete namespaces --all
etcdctl del "" --from-key
```

## ✅ APPROVED SAFE OPERATIONS

### Safe Reset Operations

```bash
# ✅ Safe user data reset with confirmation
task cluster:safe-reset NODE=<node-ip>

# ✅ Safe emergency recovery
task cluster:emergency-recovery

# ✅ Safe cluster recovery
task cluster:recover
```

### Safe Troubleshooting Operations

```bash
# ✅ Service management
talosctl service <service> restart --nodes <node-ip>
talosctl service <service> status --nodes <node-ip>

# ✅ Configuration management
task talos:apply-config-only
task talos:recover-kubeconfig

# ✅ System information gathering
talosctl get nodes --nodes <node-ip>
talosctl get services --nodes <node-ip>
talosctl logs <service> --nodes <node-ip>
```

## 🔍 PRE-OPERATION SAFETY CHECKLIST

Before executing ANY potentially destructive operation:

### Mandatory Checks

- [ ] **Verify operation necessity**: Can this be solved with safer methods?
- [ ] **Check partition specification**: Are we only targeting safe partitions?
- [ ] **Confirm user approval**: Has the user explicitly approved this operation?
- [ ] **Backup verification**: Do we have recent backups and recovery procedures?
- [ ] **Impact assessment**: What's the worst-case scenario if this fails?
- [ ] **Recovery plan**: How will we recover if something goes wrong?
- [ ] **USB installer ready**: Is the USB installer available for emergency recovery?

### Documentation Requirements

- [ ] **Log the operation**: Record what, why, when, and who
- [ ] **Document reasoning**: Why is this operation necessary?
- [ ] **Record safeguards**: What safety measures are in place?
- [ ] **Note alternatives**: What safer options were considered?

## 🛠️ SAFE OPERATION TEMPLATES

### Template: Safe Node Reset

```bash
#!/bin/bash
# Safe node reset template with all required safeguards

NODE_IP="$1"
if [[ -z "$NODE_IP" ]]; then
    echo "ERROR: Node IP required"
    exit 1
fi

echo "🚨 WARNING: This will reset user data on node $NODE_IP"
echo "This operation will:"
echo "  - Wipe EPHEMERAL partition (temporary data, logs)"
echo "  - Wipe STATE partition (node configuration, will rejoin cluster)"
echo "  - PRESERVE OS partition (no USB reinstallation needed)"
echo ""
echo "Safer alternatives to try first:"
echo "  - Service restart: talosctl service kubelet restart --nodes $NODE_IP"
echo "  - Node reboot: task talos:reboot NODES=$NODE_IP"
echo "  - Config reapply: task talos:apply-config-only"
echo ""
read -p "Continue with safe reset? (type 'yes' to confirm): " confirmation

if [[ "$confirmation" != "yes" ]]; then
    echo "Operation cancelled for safety"
    exit 1
fi

echo "Executing safe reset on node $NODE_IP..."
talosctl reset \
  --system-labels-to-wipe STATE \
  --system-labels-to-wipe EPHEMERAL \
  --nodes "$NODE_IP" \
  --endpoints "$NODE_IP"

echo "Safe reset completed. Monitor node recovery..."
```

### Template: Safe Service Restart

```bash
#!/bin/bash
# Safe service restart template

SERVICE="$1"
NODE_IP="$2"

if [[ -z "$SERVICE" || -z "$NODE_IP" ]]; then
    echo "ERROR: Service name and node IP required"
    exit 1
fi

echo "Restarting service $SERVICE on node $NODE_IP..."
talosctl service "$SERVICE" restart --nodes "$NODE_IP"

echo "Checking service status..."
talosctl service "$SERVICE" status --nodes "$NODE_IP"
```

## 🚨 EMERGENCY PROCEDURES

### If You Accidentally Execute a Dangerous Command

#### Immediate Actions

1. **Stop the operation** if still in progress:

   ```bash
   # Try to interrupt if possible
   Ctrl+C
   ```

2. **Assess the damage**:

   ```bash
   # Check node status
   kubectl get nodes
   talosctl get nodes --nodes <affected-node>
   ```

3. **Prepare for recovery**:

   ```bash
   # Ensure USB installer is ready
   task talos:generate-schematic
   # Backup current state if possible
   task maintenance:backup
   ```

#### Recovery Steps

1. **If OS is intact**: Use cluster recovery procedures
2. **If OS is wiped**: Follow USB reinstallation process
3. **Document the incident**: Record what happened and how to prevent it

## 📋 OPERATION APPROVAL MATRIX

### Operations Requiring NO Approval (Always Safe)

- Reading system information (`talosctl get`, `kubectl get`)
- Checking service status (`talosctl service status`)
- Viewing logs (`talosctl logs`)
- Network diagnostics (`task network:check-*`)

### Operations Requiring USER CONFIRMATION

- Service restarts (`talosctl service restart`)
- Node reboots (`task talos:reboot`)
- Configuration reapplication (`task talos:apply-config`)
- Safe resets (`task cluster:safe-reset`)

### Operations REQUIRING EXPLICIT APPROVAL

- Any `talosctl reset` command
- Cluster-wide operations affecting multiple nodes
- Operations that could cause downtime
- Any command not in the approved safe operations list

## 🎯 COMPLIANCE VERIFICATION

### Before Any Operation

```bash
# Verify compliance with safety guidelines
echo "Safety Checklist:"
echo "1. Is this operation necessary? (safer alternatives considered?)"
echo "2. Does this operation specify safe partitions only?"
echo "3. Has the user explicitly approved this operation?"
echo "4. Do we have backup and recovery procedures ready?"
echo "5. Is the impact clearly understood and documented?"
```

### After Any Operation

```bash
# Verify successful completion
echo "Post-operation verification:"
echo "1. Did the operation complete successfully?"
echo "2. Are all nodes still accessible?"
echo "3. Is the cluster in a healthy state?"
echo "4. Were any unexpected side effects observed?"
```

## 🔗 RELATED DOCUMENTATION

- **Critical Safety Guide**: [`docs/CLUSTER_RESET_SAFETY.md`](CLUSTER_RESET_SAFETY.md)
- **Recovery Procedures**: [`docs/CLUSTER_RECOVERY.md`](CLUSTER_RECOVERY.md)
- **Troubleshooting Guide**: [`docs/CLUSTER_REBUILD_FIXES.md`](CLUSTER_REBUILD_FIXES.md)

---

**Remember: These guidelines exist because improper operations have caused complete OS wipes requiring USB drive reinstallation. Always err on the side of caution.**
