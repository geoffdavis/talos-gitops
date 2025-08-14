#!/bin/bash
set -e

# Aggressive Recovery Strategy - Pre-Recovery Backup Script
# Creates comprehensive backup before eliminating gitops-lifecycle-management

echo "=== AGGRESSIVE RECOVERY STRATEGY - BACKUP CREATION ==="
echo "Timestamp: $(date)"
echo

# Create backup directory with timestamp
BACKUP_DIR="recovery-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo "📁 Created backup directory: $BACKUP_DIR"

# Backup current Flux state
echo "🔄 Backing up Flux state..."
flux export source git flux-system > "$BACKUP_DIR/flux-source.yaml"
flux export kustomization --all > "$BACKUP_DIR/flux-kustomizations.yaml"
flux export helmrelease --all > "$BACKUP_DIR/flux-helmreleases.yaml"
echo "✅ Flux state backed up"

# Backup current cluster state
echo "🔄 Backing up cluster state..."
kubectl get kustomizations.kustomize.toolkit.fluxcd.io -A -o yaml > "$BACKUP_DIR/cluster-kustomizations.yaml"
kubectl get helmreleases.helm.toolkit.fluxcd.io -A -o yaml > "$BACKUP_DIR/cluster-helmreleases.yaml"
echo "✅ Cluster state backed up"

# Backup authentication system state
echo "🔄 Backing up authentication system..."
kubectl get secrets -n authentik-proxy -o yaml > "$BACKUP_DIR/authentik-proxy-secrets.yaml"
kubectl get configmaps -n authentik-proxy -o yaml > "$BACKUP_DIR/authentik-proxy-configmaps.yaml"
kubectl get pods -n authentik-proxy -o yaml > "$BACKUP_DIR/authentik-proxy-pods.yaml"
kubectl get ingress -n authentik-proxy -o yaml > "$BACKUP_DIR/authentik-proxy-ingress.yaml"
echo "✅ Authentication system backed up"

# Backup Git repository state
echo "🔄 Backing up Git repository state..."
git log --oneline -10 > "$BACKUP_DIR/git-recent-commits.txt"
git status > "$BACKUP_DIR/git-status.txt"
git branch -v > "$BACKUP_DIR/git-branches.txt"
echo "✅ Git repository state backed up"

# Backup specific files that will be modified
echo "🔄 Backing up files to be modified..."
cp clusters/home-ops/infrastructure/identity.yaml "$BACKUP_DIR/identity.yaml.backup"
cp clusters/home-ops/infrastructure/outpost-config.yaml "$BACKUP_DIR/outpost-config.yaml.backup"
cp -r infrastructure/gitops-lifecycle-management "$BACKUP_DIR/gitops-lifecycle-management.backup" 2>/dev/null || echo "⚠️  gitops-lifecycle-management directory not found"
cp -r charts/gitops-lifecycle-management "$BACKUP_DIR/charts-gitops-lifecycle-management.backup" 2>/dev/null || echo "⚠️  gitops-lifecycle-management chart not found"
echo "✅ Configuration files backed up"

# Document current system state
echo "🔄 Documenting current system state..."
flux get kustomizations > "$BACKUP_DIR/current-flux-kustomizations.txt"
flux get helmreleases > "$BACKUP_DIR/current-flux-helmreleases.txt"
kubectl get nodes > "$BACKUP_DIR/current-nodes.txt"
kubectl get pods -A | grep -v Running | grep -v Completed > "$BACKUP_DIR/current-failed-pods.txt" || echo "No failed pods" > "$BACKUP_DIR/current-failed-pods.txt"
echo "✅ System state documented"

# Create recovery information file
cat > "$BACKUP_DIR/RECOVERY_INFO.md" << EOF
# Aggressive Recovery Strategy Backup

**Created**: $(date)
**Strategy**: Complete elimination of gitops-lifecycle-management component
**Current Status**: $(flux get kustomizations | grep -c "True.*Ready")/31 Kustomizations Ready

## Backup Contents

- \`flux-source.yaml\` - Flux GitRepository source configuration
- \`flux-kustomizations.yaml\` - All Flux Kustomizations export
- \`flux-helmreleases.yaml\` - All Flux HelmReleases export
- \`cluster-kustomizations.yaml\` - Cluster Kustomizations state
- \`cluster-helmreleases.yaml\` - Cluster HelmReleases state
- \`authentik-proxy-*\` - Complete authentication system backup
- \`git-*\` - Git repository state information
- \`*.backup\` - Original configuration files
- \`current-*\` - Current system state snapshots

## Rollback Instructions

### Quick Rollback (Git only)
\`\`\`bash
git revert HEAD --no-edit
git push origin main
flux reconcile source git flux-system
\`\`\`

### Full Restore
\`\`\`bash
# Restore configuration files
cp identity.yaml.backup ../clusters/home-ops/infrastructure/identity.yaml
cp outpost-config.yaml.backup ../clusters/home-ops/infrastructure/outpost-config.yaml
cp -r gitops-lifecycle-management.backup ../infrastructure/gitops-lifecycle-management
cp -r charts-gitops-lifecycle-management.backup ../charts/gitops-lifecycle-management

# Commit and deploy
git add .
git commit -m "rollback: restore gitops-lifecycle-management component"
git push origin main
flux reconcile source git flux-system
\`\`\`

### Cluster State Restore (Emergency)
\`\`\`bash
kubectl apply -f cluster-kustomizations.yaml
kubectl apply -f cluster-helmreleases.yaml
\`\`\`

## Validation Commands

\`\`\`bash
# Check recovery progress
flux get kustomizations | grep -c "True.*Ready"

# Test authentication system
curl -I -k https://longhorn.k8s.home.geoffdavis.com

# Validate system health
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed
\`\`\`
EOF

echo "✅ Recovery information documented"

# Set appropriate permissions
chmod -R 600 "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# Final summary
echo
echo "=== BACKUP SUMMARY ==="
echo "📁 Backup Location: $BACKUP_DIR"
echo "📊 Files Backed Up: $(find "$BACKUP_DIR" -type f | wc -l)"
echo "💾 Backup Size: $(du -sh "$BACKUP_DIR" | cut -f1)"
echo "🔒 Permissions: Secure (700/600)"
echo
echo "✅ BACKUP COMPLETE - Ready for aggressive recovery execution"
echo "📖 Review: $BACKUP_DIR/RECOVERY_INFO.md"
echo
echo "Next steps:"
echo "1. Review backup contents"
echo "2. Execute aggressive recovery strategy"
echo "3. Monitor recovery progress"
echo "4. Validate success with ./validate-recovery-success.sh"
