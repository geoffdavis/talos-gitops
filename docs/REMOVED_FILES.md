# Removed Documentation Files

This file documents the obsolete documentation files that were removed during the documentation reorganization on 2025-07-29.

## Files Removed

### Weekly Reports (Historical)

These were point-in-time reports that are now historical:

- `WEEK1_STABILIZATION_REPORT.md` - Week 1 bootstrap service stabilization
- `WEEK2_CONFIGURATION_FIXES_REPORT.md` - Week 2 configuration fixes
- `WEEK3_INFRASTRUCTURE_DEPLOYMENT_REPORT.md` - Week 3 infrastructure deployment
- `WEEK4_GITOPS_ENABLEMENT_REPORT.md` - Week 4 GitOps enablement

### Status Reports (Point-in-time)

These were status snapshots that are now outdated:

- `AUTHENTIK_DEPLOYMENT_STATUS.md` - Authentik deployment status
- `CLUSTER_RECOVERY_STATUS.md` - Cluster recovery status
- `NETWORK_RECOVERY_STATUS_REPORT.md` - Network recovery status
- `AUTHENTIK_DEPLOYMENT_FINAL_STATUS.md` - Final Authentik deployment status

### Outdated Fixes (Integrated)

These were specific fixes that are now integrated into standard procedures:

- `OAUTH2_REDIRECT_URL_FIX.md` - OAuth2 redirect URL fix
- `CERTIFICATE_ISSUE_RESOLUTION.md` - Certificate issue resolution
- `CLUSTER_REBUILD_FIXES.md` - Cluster rebuild fixes
- `AUTHENTIK_SSL_VERIFICATION_FIX.md` - SSL verification fix

### Deprecated Guides (Superseded)

These guides have been superseded by the new documentation structure:

- `BOOTSTRAP_GITOPS_SUMMARY.md` - Now covered in architecture/bootstrap-vs-gitops.md
- `BGP_ONLY_LOADBALANCER_MIGRATION.md` - Now covered in components/networking/bgp-loadbalancer.md
- `LONGHORN_USB_SSD_INTEGRATION.md` - Now covered in components/storage/usb-ssd-operations.md
- `AUTHENTIK_EXTERNAL_PROXY_FIX_PLAN.md` - Specific fix plan, now integrated

### Duplicate/Redundant Content

These files contained overlapping information now consolidated:

- `BGP_CONFIGURATION.md` - Consolidated into components/networking/bgp-loadbalancer.md
- `AUTHENTIK_ENHANCED_TOKEN_MANAGEMENT.md` - Consolidated into components/authentication/
- `FLUX_GITHUB_WEBHOOK_ARCHITECTURE.md` - Consolidated into components/infrastructure/flux-gitops.md

## Replacement Documentation

The information from these removed files has been consolidated and updated in the new documentation structure:

- **Getting Started**: [docs/getting-started/](getting-started/)
- **Architecture**: [docs/architecture/](architecture/)
- **Operations**: [docs/operations/](operations/)
- **Components**: [docs/components/](components/)
- **Reference**: [docs/reference/](reference/)
- **Development**: [docs/development/](development/)

## Migration Notes

- All relevant operational procedures have been preserved and updated
- Historical information is available in Git history if needed
- The new structure provides better organization and discoverability
- Cross-references have been updated to point to new locations

For current documentation, see the main [Documentation Index](README.md).
