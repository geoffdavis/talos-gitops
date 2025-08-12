#!/bin/bash
set -e

# Aggressive Recovery Strategy - Rollback Script
# Provides multiple rollback options if recovery fails

echo "=== AGGRESSIVE RECOVERY ROLLBACK ==="
echo "Timestamp: $(date)"
echo

# Find backup directory
BACKUP_FOUND=false
for dir in recovery-backup-*; do
    if [ -d "$dir" ]; then
        BACKUP_FOUND=true
        break
    fi
done

if [ "$BACKUP_FOUND" = false ]; then
    echo "❌ ERROR: No backup directory found!"
    echo "Cannot perform rollback without backup"
    exit 1
fi

BACKUP_DIR=$(find . -maxdepth 1 -name "recovery-backup-*" -type d 2>/dev/null | sort | tail -1)
echo "📁 Using backup: $BACKUP_DIR"

# Check current branch
CURRENT_BRANCH=$(git branch --show-current)
echo "🌿 Current branch: $CURRENT_BRANCH"

# Rollback options menu
echo
echo "🔄 ROLLBACK OPTIONS:"
echo "1. Quick Git Revert (recommended for most cases)"
echo "2. Full Configuration Restore (if Git revert insufficient)"
echo "3. Emergency Cluster State Restore (if cluster unstable)"
echo "4. Complete System Restore (nuclear option)"
echo "5. Cancel rollback"
echo

read -p "Select rollback option (1-5): " -r OPTION

case $OPTION in
    1)
        echo
        echo "🔄 Executing Quick Git Revert..."
        
        # Switch to main if on recovery branch
        if [[ $CURRENT_BRANCH == aggressive-recovery-* ]]; then
            echo "   Switching to main branch..."
            git checkout main
        fi
        
        # Revert the last commit
        echo "   Reverting last commit..."
        git revert HEAD --no-edit
        
        # Push revert
        echo "   Pushing revert..."
        git push origin main
        
        # Force Flux reconciliation
        echo "   Forcing Flux reconciliation..."
        flux reconcile source git flux-system
        
        echo "   ✅ Quick revert complete"
        ;;
        
    2)
        echo
        echo "🔄 Executing Full Configuration Restore..."
        
        # Switch to main if on recovery branch
        if [[ $CURRENT_BRANCH == aggressive-recovery-* ]]; then
            echo "   Switching to main branch..."
            git checkout main
        fi
        
        # Restore configuration files
        echo "   Restoring configuration files..."
        if [ -f "$BACKUP_DIR/identity.yaml.backup" ]; then
            cp "$BACKUP_DIR/identity.yaml.backup" clusters/home-ops/infrastructure/identity.yaml
            echo "   ✅ Restored identity.yaml"
        fi
        
        if [ -f "$BACKUP_DIR/outpost-config.yaml.backup" ]; then
            cp "$BACKUP_DIR/outpost-config.yaml.backup" clusters/home-ops/infrastructure/outpost-config.yaml
            echo "   ✅ Restored outpost-config.yaml"
        fi
        
        # Restore directories
        if [ -d "$BACKUP_DIR/gitops-lifecycle-management.backup" ]; then
            cp -r "$BACKUP_DIR/gitops-lifecycle-management.backup" infrastructure/gitops-lifecycle-management
            echo "   ✅ Restored infrastructure directory"
        fi
        
        if [ -d "$BACKUP_DIR/charts-gitops-lifecycle-management.backup" ]; then
            cp -r "$BACKUP_DIR/charts-gitops-lifecycle-management.backup" charts/gitops-lifecycle-management
            echo "   ✅ Restored chart directory"
        fi
        
        # Commit restoration
        echo "   Committing restoration..."
        git add .
        git commit -m "rollback: restore gitops-lifecycle-management component

Restored from backup: $BACKUP_DIR
- Restored infrastructure-gitops-lifecycle-management Kustomization
- Restored dependency in infrastructure-authentik-outpost-config
- Restored infrastructure/gitops-lifecycle-management directory
- Restored charts/gitops-lifecycle-management directory"
        
        git push origin main
        
        # Force Flux reconciliation
        echo "   Forcing Flux reconciliation..."
        flux reconcile source git flux-system
        
        echo "   ✅ Full configuration restore complete"
        ;;
        
    3)
        echo
        echo "🔄 Executing Emergency Cluster State Restore..."
        
        # Restore cluster Kustomizations
        if [ -f "$BACKUP_DIR/cluster-kustomizations.yaml" ]; then
            echo "   Restoring cluster Kustomizations..."
            kubectl apply -f "$BACKUP_DIR/cluster-kustomizations.yaml"
            echo "   ✅ Cluster Kustomizations restored"
        fi
        
        # Restore cluster HelmReleases
        if [ -f "$BACKUP_DIR/cluster-helmreleases.yaml" ]; then
            echo "   Restoring cluster HelmReleases..."
            kubectl apply -f "$BACKUP_DIR/cluster-helmreleases.yaml"
            echo "   ✅ Cluster HelmReleases restored"
        fi
        
        # Restore authentication system
        if [ -f "$BACKUP_DIR/authentik-proxy-secrets.yaml" ]; then
            echo "   Restoring authentication secrets..."
            kubectl apply -f "$BACKUP_DIR/authentik-proxy-secrets.yaml"
        fi
        
        if [ -f "$BACKUP_DIR/authentik-proxy-configmaps.yaml" ]; then
            echo "   Restoring authentication configmaps..."
            kubectl apply -f "$BACKUP_DIR/authentik-proxy-configmaps.yaml"
        fi
        
        echo "   ✅ Emergency cluster state restore complete"
        ;;
        
    4)
        echo
        echo "🔄 Executing Complete System Restore..."
        echo "⚠️  This will perform ALL rollback operations"
        
        read -p "Are you sure? This is the nuclear option (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            echo "❌ Complete restore cancelled"
            exit 1
        fi
        
        # Execute all rollback steps
        echo "   Step 1: Cluster state restore..."
        if [ -f "$BACKUP_DIR/cluster-kustomizations.yaml" ]; then
            kubectl apply -f "$BACKUP_DIR/cluster-kustomizations.yaml"
        fi
        if [ -f "$BACKUP_DIR/cluster-helmreleases.yaml" ]; then
            kubectl apply -f "$BACKUP_DIR/cluster-helmreleases.yaml"
        fi
        
        echo "   Step 2: Configuration restore..."
        if [[ $CURRENT_BRANCH == aggressive-recovery-* ]]; then
            git checkout main
        fi
        
        if [ -f "$BACKUP_DIR/identity.yaml.backup" ]; then
            cp "$BACKUP_DIR/identity.yaml.backup" clusters/home-ops/infrastructure/identity.yaml
        fi
        if [ -f "$BACKUP_DIR/outpost-config.yaml.backup" ]; then
            cp "$BACKUP_DIR/outpost-config.yaml.backup" clusters/home-ops/infrastructure/outpost-config.yaml
        fi
        if [ -d "$BACKUP_DIR/gitops-lifecycle-management.backup" ]; then
            cp -r "$BACKUP_DIR/gitops-lifecycle-management.backup" infrastructure/gitops-lifecycle-management
        fi
        if [ -d "$BACKUP_DIR/charts-gitops-lifecycle-management.backup" ]; then
            cp -r "$BACKUP_DIR/charts-gitops-lifecycle-management.backup" charts/gitops-lifecycle-management
        fi
        
        git add .
        git commit -m "rollback: complete system restore from $BACKUP_DIR"
        git push origin main
        
        echo "   Step 3: Force reconciliation..."
        flux reconcile source git flux-system
        
        echo "   ✅ Complete system restore finished"
        ;;
        
    5)
        echo "❌ Rollback cancelled by user"
        exit 0
        ;;
        
    *)
        echo "❌ Invalid option selected"
        exit 1
        ;;
esac

# Post-rollback monitoring
echo
echo "📊 Post-Rollback Status Check..."
sleep 10

READY_COUNT=$(flux get kustomizations 2>/dev/null | grep -c "True.*Ready" || echo "0")
echo "   Ready Kustomizations: $READY_COUNT/31"

AUTH_PODS=$(kubectl get pods -n authentik-proxy --no-headers 2>/dev/null | grep -c "Running" || echo "0")
echo "   Auth System Pods: $AUTH_PODS"

if kubectl get kustomization infrastructure-gitops-lifecycle-management -n flux-system >/dev/null 2>&1; then
    echo "   ✅ gitops-lifecycle-management Kustomization restored"
else
    echo "   ❌ gitops-lifecycle-management Kustomization not found"
fi

echo
echo "=== ROLLBACK COMPLETE ==="
echo "📁 Backup used: $BACKUP_DIR"
echo "⏱️  Wait 5-10 minutes for full system stabilization"
echo
echo "Next steps:"
echo "1. Monitor system recovery:"
echo "   watch -n 5 'flux get kustomizations | head -20'"
echo
echo "2. Validate system health:"
echo "   ./validate-recovery-success.sh"
echo
echo "3. If issues persist, consider:"
echo "   - Checking individual component logs"
echo "   - Running emergency cluster procedures"
echo "   - Contacting system administrator"