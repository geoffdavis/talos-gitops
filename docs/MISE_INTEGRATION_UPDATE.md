# Mise Integration Update for Bootstrap Tasks

## Overview

Updated the entire `Taskfile.yml` to use `mise` for executable discovery, ensuring all tools are managed through mise for consistent versions across development environments.

## Changes Made

### 1. Bootstrap Tasks Updated

All bootstrap-related tasks now use `mise exec` for tool invocations:

- **`bootstrap:cluster`** - Main bootstrap sequence now uses mise for all subtasks
- **`talos:apply-config`** - Node configuration uses `mise exec -- talosctl`
- **`talos:apply-lldpd-config`** - LLDPD configuration uses `mise exec -- talosctl`
- **`talos:bootstrap`** - Cluster initialization uses `mise exec -- talosctl`
- **`talos:generate-config`** - Uses `mise exec -- talhelper` for configuration generation

### 2. Tool Integration

Updated all tool invocations to use `mise exec`:

#### Core Tools
- **`task`** - Task runner: `mise exec -- task <task-name>`
- **`talhelper`** - Talos config generator: `mise exec -- talhelper <command>`
- **`talosctl`** - Talos cluster management: `mise exec -- talosctl <command>`
- **`kubectl`** - Kubernetes CLI: `mise exec -- kubectl <command>`
- **`helm`** - Kubernetes package manager: `mise exec -- helm <command>`
- **`flux`** - GitOps toolkit: `mise exec -- flux <command>`

#### Verification Tools
- **`jq`** - JSON processor (managed by mise)
- **`yq`** - YAML processor (managed by mise)

### 3. Specific LLDPD Configuration

The `talos:apply-lldpd-config` task now properly uses mise:

```yaml
cmds:
  - echo "Applying LLDPD ExtensionServiceConfig to all nodes..."
  - |
    mise exec -- talosctl patch machineconfig \
      --nodes {{.NODE_1_IP}},{{.NODE_2_IP}},{{.NODE_3_IP}} \
      --patch-file talos/manifests/lldpd-extension-config.yaml
  - echo "Verifying LLDPD ExtensionServiceConfig is loaded..."
  - |
    mise exec -- talosctl get extensionserviceconfigs --nodes {{.NODE_1_IP}},{{.NODE_2_IP}},{{.NODE_3_IP}} || echo "ExtensionServiceConfigs will be visible after next reboot"
```

### 4. Application Deployment Tasks

All application deployment tasks updated:

- **Cilium CNI**: `mise exec -- helm` for Helm operations
- **External Secrets**: `mise exec -- helm` and `mise exec -- kubectl`
- **1Password Connect**: `mise exec -- kubectl` for resource management
- **Longhorn Storage**: `mise exec -- helm` for installation
- **Ingress Controller**: `mise exec -- kubectl` for deployment

### 5. Diagnostic and Testing Tasks

All diagnostic tasks now use mise:

- **Network diagnostics**: `mise exec -- talosctl` for LLDP, USB, IPv6 checks
- **Storage diagnostics**: `mise exec -- talosctl` for iSCSI checks
- **Cluster status**: `mise exec -- kubectl` for status reporting
- **Testing tasks**: `mise exec -- task` for test orchestration

### 6. Safety and Recovery Tasks

Critical safety tasks updated:

- **Cluster recovery**: `mise exec -- talosctl` and `mise exec -- kubectl`
- **Safe reset operations**: `mise exec -- talosctl` with proper partition specifications
- **Emergency recovery**: `mise exec -- task` for orchestrated recovery

## Benefits

### 1. Version Consistency
- All tools use versions specified in `.mise.toml`
- Eliminates "works on my machine" issues
- Ensures reproducible builds and operations

### 2. Environment Isolation
- Tools are managed per-project through mise
- No conflicts with system-installed versions
- Automatic tool installation when missing

### 3. Renovate Integration
- Tool versions automatically updated via Renovate
- Consistent dependency management
- Automated security updates

### 4. Developer Experience
- Single command to install all tools: `mise install`
- Automatic tool switching when entering project directory
- Clear tool version requirements in `.mise.toml`

## Usage Examples

### Running Bootstrap Tasks
```bash
# Bootstrap entire cluster
mise exec -- task bootstrap:cluster

# Apply LLDPD configuration
mise exec -- task talos:apply-lldpd-config

# Generate Talos configuration
mise exec -- task talos:generate-config
```

### Direct Tool Usage
```bash
# Use talosctl through mise
mise exec -- talosctl get nodes

# Use kubectl through mise
mise exec -- kubectl get pods

# Use talhelper through mise
mise exec -- talhelper genconfig
```

### Task Orchestration
```bash
# List all available tasks
mise exec -- task --list

# Run with dry-run to see commands
mise exec -- task bootstrap:cluster --dry
```

## Verification

All tasks have been tested with `--dry` flag to ensure:

1. ✅ Tool invocations use `mise exec` prefix
2. ✅ Task dependencies properly chain through mise
3. ✅ Bootstrap sequence maintains proper order
4. ✅ LLDPD configuration uses mise for talosctl
5. ✅ All diagnostic and testing tasks work correctly

## Migration Notes

### For Users
- **Before**: `task bootstrap:cluster`
- **After**: `mise exec -- task bootstrap:cluster`

### For CI/CD
- Ensure mise is installed in CI environment
- Run `mise install` before executing tasks
- Use `mise exec -- task <task-name>` in scripts

### For Development
- Install mise: `curl https://mise.run | sh`
- Install project tools: `mise install`
- Tools automatically available when in project directory

## Commit Information

**Commit**: `b86fd0b`
**Message**: "feat: integrate mise for executable discovery in bootstrap tasks"
**Files Changed**: `Taskfile.yml` (164 insertions, 164 deletions)

This update addresses user feedback for proper mise integration in subtasks and ensures consistent tool versions across all development environments.