#!/bin/bash
set -e

# Aggressive Recovery Strategy - Execution Script
# Eliminates gitops-lifecycle-management component to resolve HelmRelease timeouts

echo "=== AGGRESSIVE RECOVERY STRATEGY - EXECUTION ==="
echo "Timestamp: $(date)"
echo

# Verify backup exists
BACKUP_FOUND=false
for dir in recovery-backup-*; do
    if [ -d "$dir" ]; then
        BACKUP_FOUND=true
        break
    fi
done

if [ "$BACKUP_FOUND" = false ]; then
    echo "❌ ERROR: No backup directory found!"
    echo "Please run ./scripts/aggressive-recovery-backup.sh first"
    exit 1
fi

BACKUP_DIR=$(find . -maxdepth 1 -name "recovery-backup-*" -type d 2>/dev/null | sort | tail -1)
echo "📁 Using backup: $BACKUP_DIR"

# Pre-execution validation
echo "🔍 Pre-execution validation..."

# Check current system state
CURRENT_READY=$(flux get kustomizations 2>/dev/null | grep -c "True.*Ready" || echo "0")
echo "   Current ready Kustomizations: $CURRENT_READY/31"

# Verify external outpost system is operational
if kubectl get pods -n authentik-proxy --no-headers 2>/dev/null | grep -q "Running"; then
    echo "   ✅ External outpost system operational"
else
    echo "   ❌ External outpost system not running - ABORTING"
    exit 1
fi

# Test key services
echo "   Testing key services..."
if curl -s -I -k https://longhorn.k8s.home.geoffdavis.com | grep -q "HTTP"; then
    echo "   ✅ Longhorn accessible"
else
    echo "   ⚠️  Longhorn not accessible (may be expected)"
fi

# Confirm execution
echo
echo "⚠️  CRITICAL: This will eliminate the gitops-lifecycle-management component"
echo "   - Remove infrastructure-gitops-lifecycle-management Kustomization"
echo "   - Remove dependency from infrastructure-authentik-outpost-config"
echo "   - Delete infrastructure/gitops-lifecycle-management directory"
echo "   - Delete charts/gitops-lifecycle-management directory"
echo
read -p "Continue with aggressive recovery? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "❌ Recovery aborted by user"
    exit 1
fi

echo
echo "🚀 Starting aggressive recovery execution..."

# Create recovery branch
RECOVERY_BRANCH="aggressive-recovery-$(date +%Y%m%d-%H%M%S)"
echo "🌿 Creating recovery branch: $RECOVERY_BRANCH"
git checkout -b "$RECOVERY_BRANCH"

# Phase 1: Remove GitOps Lifecycle Management Kustomization
echo
echo "📝 Phase 1: Removing GitOps Lifecycle Management Kustomization..."

# Backup current identity.yaml
cp clusters/home-ops/infrastructure/identity.yaml "$BACKUP_DIR/identity.yaml.pre-execution"

# Remove the Kustomization block (lines 137-182 based on analysis)
echo "   Removing infrastructure-gitops-lifecycle-management from identity.yaml..."
sed -i.bak '/^---$/N;/name: infrastructure-gitops-lifecycle-management/,/^---$/{
    /^---$/!d
}' clusters/home-ops/infrastructure/identity.yaml

# Verify the removal worked
if grep -q "infrastructure-gitops-lifecycle-management" clusters/home-ops/infrastructure/identity.yaml; then
    echo "   ❌ Automatic removal failed, attempting manual approach..."
    
    # Manual approach - create new file without the problematic section
    awk '
    /^---$/ { 
        if (in_gitops_section) {
            in_gitops_section = 0
            next
        }
        print
        next
    }
    /name: infrastructure-gitops-lifecycle-management/ {
        in_gitops_section = 1
        next
    }
    !in_gitops_section { print }
    ' clusters/home-ops/infrastructure/identity.yaml > clusters/home-ops/infrastructure/identity.yaml.tmp
    
    mv clusters/home-ops/infrastructure/identity.yaml.tmp clusters/home-ops/infrastructure/identity.yaml
fi

echo "   ✅ Removed infrastructure-gitops-lifecycle-management Kustomization"

# Phase 2: Update Dependencies
echo
echo "🔗 Phase 2: Updating dependencies..."

# Backup current outpost-config.yaml
cp clusters/home-ops/infrastructure/outpost-config.yaml "$BACKUP_DIR/outpost-config.yaml.pre-execution"

# Remove the gitops-lifecycle-management dependency
echo "   Removing dependency from outpost-config.yaml..."
sed -i.bak '/- name: infrastructure-gitops-lifecycle-management/d' clusters/home-ops/infrastructure/outpost-config.yaml

echo "   ✅ Updated outpost-config.yaml dependencies"

# Phase 3: Remove Infrastructure Directories
echo
echo "🗂️  Phase 3: Removing infrastructure directories..."

# Remove the infrastructure directory
if [ -d "infrastructure/gitops-lifecycle-management" ]; then
    echo "   Removing infrastructure/gitops-lifecycle-management..."
    rm -rf infrastructure/gitops-lifecycle-management/
    echo "   ✅ Removed infrastructure directory"
else
    echo "   ⚠️  infrastructure/gitops-lifecycle-management not found"
fi

# Remove the chart directory
if [ -d "charts/gitops-lifecycle-management" ]; then
    echo "   Removing charts/gitops-lifecycle-management..."
    rm -rf charts/gitops-lifecycle-management/
    echo "   ✅ Removed chart directory"
else
    echo "   ⚠️  charts/gitops-lifecycle-management not found"
fi

# Phase 4: Verify Changes
echo
echo "🔍 Phase 4: Verifying changes..."

# Check what files were modified
echo "   Modified files:"
git status --porcelain | sed 's/^/   /'

# Verify no references remain
if grep -r "infrastructure-gitops-lifecycle-management" clusters/home-ops/infrastructure/ 2>/dev/null; then
    echo "   ❌ WARNING: References to gitops-lifecycle-management still found"
    grep -r "infrastructure-gitops-lifecycle-management" clusters/home-ops/infrastructure/ | sed 's/^/   /'
else
    echo "   ✅ No remaining references to gitops-lifecycle-management"
fi

# Phase 5: Commit Changes
echo
echo "💾 Phase 5: Committing changes..."

git add .
git commit -m "feat: eliminate gitops-lifecycle-management component

- Remove infrastructure-gitops-lifecycle-management Kustomization
- Remove dependency from infrastructure-authentik-outpost-config  
- Delete infrastructure/gitops-lifecycle-management directory
- Delete charts/gitops-lifecycle-management directory

This resolves HelmRelease installation timeout issues blocking
cluster recovery. External outpost system already provides all
required functionality.

Backup: $BACKUP_DIR"

echo "   ✅ Changes committed to branch: $RECOVERY_BRANCH"

# Phase 6: Deploy Changes
echo
echo "🚀 Phase 6: Deploying changes..."

echo "   Pushing recovery branch..."
git push origin "$RECOVERY_BRANCH"

echo "   Forcing Flux reconciliation..."
flux reconcile source git flux-system

echo "   ✅ Changes deployed"

# Phase 7: Initial Monitoring
echo
echo "📊 Phase 7: Initial recovery monitoring..."

echo "   Waiting 30 seconds for initial reconciliation..."
sleep 30

echo "   Current Flux status:"
flux get kustomizations | head -10 | sed 's/^/   /'

echo "   Checking target components:"
kubectl get kustomization infrastructure-authentik-outpost-config -n flux-system 2>/dev/null | sed 's/^/   /' || echo "   infrastructure-authentik-outpost-config: Not found yet"
kubectl get kustomization infrastructure-authentik-proxy -n flux-system 2>/dev/null | sed 's/^/   /' || echo "   infrastructure-authentik-proxy: Status unknown"

# Final instructions
echo
echo "=== EXECUTION COMPLETE ==="
echo "🎯 Recovery branch created: $RECOVERY_BRANCH"
echo "📁 Backup location: $BACKUP_DIR"
echo "⏱️  Initial deployment started"
echo
echo "Next steps:"
echo "1. Monitor recovery progress:"
echo "   watch -n 5 'flux get kustomizations | head -20'"
echo
echo "2. Check specific components:"
echo "   kubectl get kustomization infrastructure-authentik-outpost-config -n flux-system"
echo "   kubectl get kustomization infrastructure-authentik-proxy -n flux-system"
echo
echo "3. Validate success (after 5-10 minutes):"
echo "   ./validate-recovery-success.sh"
echo
echo "4. If successful, merge to main:"
echo "   git checkout main"
echo "   git merge $RECOVERY_BRANCH"
echo "   git push origin main"
echo
echo "5. If rollback needed:"
echo "   git checkout main"
echo "   git revert HEAD --no-edit"
echo "   git push origin main"
echo
echo "🔍 Monitor the recovery and validate success before merging!"