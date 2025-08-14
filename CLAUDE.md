# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Talos Kubernetes GitOps repository managing a home-ops cluster with 3 Intel Mac mini nodes. The cluster uses Flux for GitOps, Authentik for authentication, and integrates with 1Password for secrets management.

## Essential Commands

### Daily Operations

```bash
# Check cluster and GitOps status
task cluster:status           # Overall cluster health
flux get kustomizations       # GitOps deployment status
task applications:status      # Application deployment status

# Validate system health
task applications:health      # Comprehensive health check
task bgp-loadbalancer:status  # BGP peering and LoadBalancer status

# View logs
task applications:logs        # Application logs
kubectl logs -n authentik-proxy -l app.kubernetes.io/name=authentik-proxy  # Auth proxy logs
```

### Testing and Validation

```bash
# Run pre-commit checks (enforced: security/syntax, warnings: formatting)
task pre-commit:run           # Run all pre-commit hooks
task pre-commit:run-security  # Run security checks only
task pre-commit:fix-format    # Auto-fix formatting issues

# Test authentication
kubectl apply -f infrastructure/authentik-proxy/test-authentication-flow.yaml
```

### Emergency Procedures

```bash
# SAFE cluster operations (preserves OS)
task cluster:safe-reset       # Wipes STATE/EPHEMERAL only, preserves OS
task cluster:safe-reboot      # Safe cluster reboot
task cluster:emergency-recovery # Systematic troubleshooting

# NEVER USE: talosctl reset (without partition specs) - WILL WIPE OS
```

### Deployment Operations

```bash
# Bootstrap phases (for new cluster or recovery)
task bootstrap:phased         # Interactive phased bootstrap
task bootstrap:phase -- --phase 3  # Resume from specific phase

# Deploy core services (pre-Flux)
task apps:deploy-cilium       # Deploy CNI
task apps:deploy-core         # Deploy 1Password, External Secrets
task flux:bootstrap           # Deploy Flux GitOps

# Force reconciliation
flux reconcile kustomization flux-system --with-source
flux reconcile hr <release-name> -n <namespace>
```

## High-Level Architecture

### Two-Phase Architecture Pattern

The cluster separates **Bootstrap Phase** (foundational components) from **GitOps Phase** (operational services):

1. **Bootstrap Phase** - Direct deployment via Taskfile:
   - Talos OS configuration
   - Cilium CNI core
   - 1Password Connect + External Secrets
   - Flux GitOps system

2. **GitOps Phase** - Git-managed via Flux:
   - All infrastructure services
   - Applications
   - Configuration changes

### Authentication Architecture

**External Authentik Outpost** handles all `*.k8s.home.geoffdavis.com` authentication:

- External outpost in `authentik-proxy` namespace (ID: `3f0970c5-d6a3-43b2-9a36-d74665c6b24e`)
- Single ingress handles all authenticated domains
- Backend services discovered via ConfigMap
- Redis for session storage
- Hybrid URL architecture: internal URLs for outpost-to-Authentik, external for user redirects

**Critical**: Services must NOT have their own ingresses for authenticated domains - all traffic flows through the external outpost.

### Network Architecture

- **Management**: VLAN 51 (172.29.51.0/24) - Cluster nodes
- **LoadBalancer**: VLAN 52 (172.29.52.0/24) - BGP-advertised service IPs
- **BGP Peering**: Cluster ASN 64512 ↔ UDM Pro ASN 64513
- **IP Pools**:
  - bgp-default: 172.29.52.100-199 (services)
  - bgp-ingress: 172.29.52.200-220 (ingress controllers)
  - bgp-reserved: 172.29.52.50-99 (future use)

### Storage Architecture

- **OS**: Apple internal storage (auto-detected via `model: APPLE*`)
- **Longhorn**: 3x 1TB USB SSDs (Samsung T5)
- **PostgreSQL**: CloudNativePG with CNPG Barman Plugin v0.5.0 for backups

### GitOps Dependency Chain

```
Flux System → Sources/External Secrets → 1Password Connect →
Cert Manager → Ingress Controllers → Storage/Database →
Authentik Identity → Applications
```

Critical dependencies block downstream components. Check `flux get kustomizations` to identify blocking issues.

### Secret Management

1Password integration with two credential formats:

- **Legacy**: Single "1password connect" entry (may have truncation)
- **Separate** (preferred): Individual credentials and token entries

Bootstrap scripts handle both formats automatically.

## Critical Safety Guidelines

1. **NEVER** use `talosctl reset` without specifying partitions - it will wipe the OS
2. **Always** use `task cluster:safe-reset` for partition-only resets
3. **Check** blocking Flux kustomizations before forcing reconciliation
4. **Clear browser cache** after authentication configuration changes
5. **Verify** BGP peering before deploying LoadBalancer services

## Authentication Testing

To validate authentication is working:

1. Check outpost connection: `kubectl logs -n authentik-proxy -l app.kubernetes.io/name=authentik-proxy | grep "Connected to outpost"`
2. Test service access: Visit any `*.k8s.home.geoffdavis.com` service
3. Verify redirect to Authentik login page
4. After login, confirm redirect back to service

## Flux Reconciliation Issues

If Flux gets stuck:

1. Check for failed Jobs: `kubectl get jobs -A | grep -E "0/1|Failed"`
2. Delete immutable failed Jobs blocking reconciliation
3. Check health checks: `flux get hr -A | grep False`
4. Suspend/resume if needed: `flux suspend hr <name> -n <namespace>` then `flux resume hr <name> -n <namespace>`

## Pre-commit Enforcement

The repository uses balanced pre-commit enforcement:

- **Blocking** (must fix): Security issues, syntax errors, API keys
- **Warnings** (suggestions): Formatting, line endings, trailing whitespace

Run `task pre-commit:run` before commits. Use `task pre-commit:fix-format` for auto-formatting.
