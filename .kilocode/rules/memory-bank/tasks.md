# Common Tasks and Workflows

This file documents repetitive tasks and operational workflows that follow established patterns in the cluster.

## Cluster Operations

### Complete Cluster Bootstrap
**Last performed:** Initial setup
**Files to modify:**
- `.env` - Set OP_ACCOUNT environment variable
- `talconfig.yaml` - Node configuration if needed

**Steps:**
1. Install dependencies: `mise install`
2. Configure environment: `cp .env.example .env` and set OP_ACCOUNT
3. Run phased bootstrap: `task bootstrap:phased`
4. Configure BGP on UDM Pro: `task bgp:configure-unifi`
5. Verify cluster status: `task cluster:status`

**Important notes:**
- Phased bootstrap is resumable if it fails at any stage
- Use `task bootstrap:resume` to continue from last failed phase
- Safe reset available with `task cluster:safe-reset` if needed

### Safe Cluster Reset
**Last performed:** As needed for troubleshooting
**Files to modify:** None (preserves OS)

**Steps:**
1. Confirm reset intention: `task cluster:safe-reset CONFIRM=SAFE-RESET`
2. Wait for nodes to reboot and enter maintenance mode
3. Verify nodes accessible: `talosctl version --insecure --nodes <ip>`
4. Re-bootstrap if needed: `task bootstrap:phased`

**Important notes:**
- Only wipes STATE and EPHEMERAL partitions, preserves OS
- Never use `talosctl reset` without partition specifications
- Nodes will be in maintenance mode after reset

## Application Management

### Add New Application via GitOps
**Last performed:** Regularly for new services
**Files to modify:**
- `apps/<app-name>/` - Create new application directory
- `clusters/home-ops/infrastructure/apps.yaml` - Add Kustomization

**Steps:**
1. Create application directory: `mkdir -p apps/<app-name>`
2. Create namespace.yaml, deployment.yaml, service.yaml
3. Create kustomization.yaml listing all resources
4. Add Flux Kustomization to apps.yaml with proper dependencies
5. Commit and push: `git add apps/<app-name>/ clusters/home-ops/infrastructure/apps.yaml`
6. Monitor deployment: `flux get kustomizations --watch`

**Important notes:**
- Follow existing patterns for namespace and resource naming
- Include proper dependencies in Flux Kustomization
- Use health checks for critical applications

### Update Application Configuration
**Last performed:** Ongoing maintenance
**Files to modify:**
- `apps/<app-name>/*.yaml` - Application manifests

**Steps:**
1. Update application manifests (image tags, resources, config)
2. Commit changes: `git add apps/<app-name>/`
3. Push to trigger deployment: `git push`
4. Monitor rollout: `kubectl rollout status deployment/<app> -n <namespace>`

**Important notes:**
- Test changes in development environment first
- Use semantic versioning for image tags
- Monitor application health after updates

## Infrastructure Management

### Add New Infrastructure Service
**Last performed:** When adding Redis, monitoring components
**Files to modify:**
- `infrastructure/<service>/` - Create service directory
- `clusters/home-ops/infrastructure/<category>.yaml` - Add Kustomization

**Steps:**
1. Create infrastructure directory: `mkdir -p infrastructure/<service>`
2. Create namespace.yaml and helmrelease.yaml (or raw manifests)
3. Create kustomization.yaml
4. Add Flux Kustomization to appropriate category file (core.yaml, storage.yaml, etc.)
5. Set proper dependencies and health checks
6. Commit and deploy: `git add infrastructure/<service>/ clusters/home-ops/infrastructure/`

**Important notes:**
- Choose appropriate category file for the service
- Include health checks for reliable deployments
- Consider resource requirements and node affinity

### Update Infrastructure Service
**Last performed:** Regular maintenance and upgrades
**Files to modify:**
- `infrastructure/<service>/helmrelease.yaml` - Helm chart versions and values

**Steps:**
1. Update Helm chart version or values in helmrelease.yaml
2. Commit changes: `git add infrastructure/<service>/`
3. Push to deploy: `git push`
4. Monitor deployment: `flux get helmreleases -n <namespace>`
5. Verify service health: `kubectl get pods -n <namespace>`

**Important notes:**
- Check Helm chart changelog for breaking changes
- Update dependencies if chart version requires it
- Test in development environment for major updates

## Network Configuration

### Update BGP Configuration
**Last performed:** When adding new network segments
**Files to modify:**
- `infrastructure/cilium-bgp/bgp-policy.yaml` - BGP peering configuration
- `infrastructure/cilium/loadbalancer-pool*.yaml` - IP pools

**Steps:**
1. Update BGP policy with new peer configurations
2. Update load balancer IP pools if needed
3. Commit changes: `git add infrastructure/cilium-bgp/ infrastructure/cilium/`
4. Push to deploy: `git push`
5. Verify BGP peering: `task bgp:verify-peering`
6. Test load balancer functionality: `kubectl get svc --all-namespaces | grep LoadBalancer`

**Important notes:**
- Coordinate with network team for BGP ASN and IP ranges
- Test connectivity after BGP changes
- Monitor for route flapping or connectivity issues

### Add DNS Records
**Last performed:** When exposing new services
**Files to modify:**
- Service ingress configurations
- External DNS automatically manages records

**Steps:**
1. Create or update ingress with proper hostname
2. Ensure external-dns annotations are correct
3. Commit and deploy ingress changes
4. Verify DNS record creation: `dig <hostname>`
5. Test service accessibility

**Important notes:**
- Use consistent domain patterns (k8s.home.geoffdavis.com for internal)
- Ensure TLS certificates are properly configured
- Monitor external-dns logs for any issues

## Secret Management

### Add New Secret from 1Password
**Last performed:** When adding new services requiring credentials
**Files to modify:**
- `infrastructure/<service>/external-secret.yaml` - ExternalSecret resource

**Steps:**
1. Add secret to appropriate 1Password vault
2. Create ExternalSecret resource referencing the 1Password item
3. Include in service kustomization.yaml
4. Commit and deploy: `git add infrastructure/<service>/`
5. Verify secret creation: `kubectl get secrets -n <namespace>`

**Important notes:**
- Use consistent naming patterns for 1Password items
- Test secret access before deploying dependent services
- Monitor external-secrets-operator logs for sync issues

### Rotate 1Password Connect Credentials
**Last performed:** As needed for security
**Files to modify:** None (handled by bootstrap script)

**Steps:**
1. Create new 1Password Connect server: `task onepassword:create-connect-server`
2. Restart 1Password Connect deployment
3. Validate secret synchronization: `task bootstrap:validate-1password-secrets`
4. Monitor external secrets for any sync failures

**Important notes:**
- Coordinate with team to minimize service disruption
- Verify all external secrets sync properly after rotation
- Keep backup of old credentials until rotation is confirmed

### Maintain Authentik Authentication System
**Last performed:** Ongoing maintenance
**Files to modify:**
- `infrastructure/authentik/admin-api-token-setup-job.yaml` - Token management
- `infrastructure/authentik-outpost-config/` - Outpost configurations

**Steps:**
1. **Regular Health Checks**:
   - Verify all services accessible: Test key services like Longhorn, Grafana, Dashboard
   - Check outpost status in Authentik admin interface
   - Monitor authentication response times

2. **Token Health Monitoring**:
   - Check API token expiration dates in Authentik admin
   - Verify outpost connectivity status
   - Review authentication logs for errors

3. **Proactive Token Rotation**:
   - Schedule token regeneration before expiration (monthly recommended)
   - Follow token regeneration procedure from troubleshooting task
   - Test all services after token rotation

4. **Service Integration Validation**:
   - Ensure new services use nginx-internal ingress class
   - Verify proper Authentik annotations on ingress resources
   - Test SSO functionality for newly deployed services

**Important notes:**
- Embedded outpost architecture requires API token connectivity
- Monitor for authentication failures and address promptly
- Keep documentation updated with any configuration changes
- Test authentication system after any Authentik upgrades

## Monitoring and Maintenance

### Update Monitoring Dashboards
**Last performed:** When adding new services or metrics
**Files to modify:**
- `infrastructure/monitoring/` - Dashboard ConfigMaps

**Steps:**
1. Export dashboard JSON from Grafana UI
2. Create or update ConfigMap with dashboard JSON
3. Add grafana_dashboard label for auto-discovery
4. Commit and deploy: `git add infrastructure/monitoring/`
5. Verify dashboard appears in Grafana

**Important notes:**
- Use consistent dashboard naming and organization
- Include proper data source configurations
- Test dashboard functionality after deployment

### Cluster Health Check
**Last performed:** Daily operational routine
**Files to modify:** None

**Steps:**
1. Check overall status: `task cluster:status`
2. Check GitOps health: `flux get kustomizations`
3. Check for failed pods: `kubectl get pods -A | grep -v Running | grep -v Completed`
4. Check node resources: `kubectl top nodes`
5. Check storage health: `task storage:check-longhorn`
6. Review recent events: `kubectl get events --sort-by='.lastTimestamp' | tail -20`

**Important notes:**
- Document any issues found for trending analysis
- Address failed pods and resource constraints promptly
- Monitor storage capacity and plan for expansion

### Troubleshoot Authentik Authentication Issues
**Last performed:** January 2025 (successful resolution)
**Files to modify:**
- `infrastructure/authentik/admin-api-token-setup-job.yaml` - Token regeneration job
- `infrastructure/authentik-outpost-config/outpost-config-job.yaml` - Outpost configuration
- Various service ingress files - Ingress class standardization

**Steps:**
1. **Diagnose Authentication Failures**:
   - Check service accessibility: `curl -I https://<service>.k8s.home.geoffdavis.com`
   - Verify ingress configuration: `kubectl get ingress -A`
   - Check Authentik outpost logs: `kubectl logs -n authentik -l app.kubernetes.io/name=authentik`

2. **Check API Token Status**:
   - Verify token exists: `kubectl get secrets -n authentik | grep api-token`
   - Check token expiration in Authentik admin interface
   - Review outpost connectivity in Authentik admin

3. **Regenerate API Tokens**:
   - Delete existing token job: `kubectl delete job -n authentik admin-api-token-setup`
   - Apply token setup job: `kubectl apply -f infrastructure/authentik/admin-api-token-setup-job.yaml`
   - Monitor job completion: `kubectl logs -n authentik job/admin-api-token-setup`

4. **Reconfigure Outpost**:
   - Delete outpost config job: `kubectl delete job -n authentik outpost-config`
   - Apply outpost config: `kubectl apply -f infrastructure/authentik-outpost-config/outpost-config-job.yaml`
   - Verify outpost registration in Authentik admin interface

5. **Standardize Ingress Classes**:
   - Review all service ingress files for consistent `ingressClassName: nginx-internal`
   - Update any services using different ingress classes
   - Commit and deploy changes: `git add . && git commit -m "Standardize ingress classes"`

6. **Verify Resolution**:
   - Test service access: Navigate to https://<service>.k8s.home.geoffdavis.com
   - Confirm redirect to Authentik login
   - Verify successful authentication and service access
   - Check all monitored services (Longhorn, Grafana, etc.)

**Important notes:**
- Root cause is typically expired API tokens or outpost configuration drift
- Embedded outpost architecture is used (not RADIUS) for Kubernetes services
- All *.k8s.home.geoffdavis.com services should use nginx-internal ingress class
- Token regeneration requires both API token setup and outpost reconfiguration
- SSL verification must be properly configured between outpost and Authentik server

**Common Issues and Solutions:**
- **502/503 errors**: Usually indicates outpost connectivity issues - regenerate tokens
- **Authentication loops**: Check ingress class consistency and outpost configuration
- **SSL errors**: Verify certificate configuration and trust relationships
- **Token expiration**: Implement monitoring for token health and proactive rotation

This task documentation helps maintain consistency and reduces the learning curve for common operational procedures.