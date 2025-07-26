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

### Maintain External Authentik-Proxy Authentication System
**Last performed:** July 2025 (successful migration to external outpost)
**Files to modify:**
- `infrastructure/authentik-proxy/secret.yaml` - External outpost token management
- `infrastructure/authentik-proxy/deployment.yaml` - External outpost configuration
- `infrastructure/authentik-proxy/redis.yaml` - Redis session storage configuration

**Steps:**
1. **Regular Health Checks**:
   - Verify all services accessible: Test key services like Longhorn, Grafana, Dashboard
   - Check external outpost status in Authentik admin interface (outpost ID: `3f0970c5-d6a3-43b2-9a36-d74665c6b24e`)
   - Monitor authentication response times and Redis connectivity

2. **External Outpost Health Monitoring**:
   - Check external outpost API token expiration dates in 1Password
   - Verify outpost connectivity status in Authentik admin interface
   - Monitor authentik-proxy pod logs for connection issues
   - Check Redis instance health and session storage functionality

3. **Proactive Token Rotation**:
   - Schedule external outpost token regeneration before expiration (monthly recommended)
   - Update token in 1Password and force ExternalSecret sync
   - Restart authentik-proxy deployment after token rotation
   - Test all services after token rotation

4. **Service Integration Validation**:
   - Ensure new services use nginx-internal ingress class
   - Verify NO individual service ingresses for *.k8s.home.geoffdavis.com domains
   - Test SSO functionality for newly deployed services through external outpost
   - Validate proxy provider configurations in Authentik admin interface

5. **Redis Session Storage Maintenance**:
   - Monitor Redis instance resource usage and performance
   - Check Redis connectivity from authentik-proxy pods
   - Validate session persistence and cleanup
   - Scale Redis if needed for performance

**Important notes:**
- **External outpost architecture** requires dedicated deployment and Redis instance
- Monitor for authentication failures and address promptly
- Keep documentation updated with any configuration changes
- Test authentication system after any Authentik or authentik-proxy upgrades
- **CRITICAL**: Only external outpost ingress should handle *.k8s.home.geoffdavis.com domains

### Deploy External Authentik-Proxy System
**Last performed:** July 2025 (successful deployment and migration)
**Files to modify:**
- `infrastructure/authentik-proxy/` - Complete external outpost deployment
- `clusters/home-ops/infrastructure/identity.yaml` - Flux Kustomization

**Steps:**
1. **Prerequisites Validation**:
   - Verify Authentik server is operational and accessible
   - Confirm 1Password Connect is working for secret management
   - Check BGP load balancer and ingress controller functionality
   - Validate network connectivity between namespaces

2. **External Outpost Token Setup**:
   - Create external outpost in Authentik admin interface
   - Generate API token for external outpost (not admin user token)
   - Store token in 1Password with proper naming convention
   - Configure ExternalSecret to sync token from 1Password

3. **Deploy External Outpost Infrastructure**:
   - Deploy namespace: `kubectl apply -f infrastructure/authentik-proxy/namespace.yaml`
   - Deploy Redis instance: `kubectl apply -f infrastructure/authentik-proxy/redis.yaml`
   - Deploy RBAC and ConfigMap: `kubectl apply -f infrastructure/authentik-proxy/rbac.yaml infrastructure/authentik-proxy/configmap.yaml`
   - Deploy ExternalSecret: `kubectl apply -f infrastructure/authentik-proxy/secret.yaml`
   - Deploy authentik-proxy: `kubectl apply -f infrastructure/authentik-proxy/deployment.yaml`

4. **Network and Ingress Configuration**:
   - Deploy service: `kubectl apply -f infrastructure/authentik-proxy/service.yaml`
   - Deploy ingress with BGP load balancer: `kubectl apply -f infrastructure/authentik-proxy/ingress.yaml`
   - Verify ingress gets external IP from BGP pool
   - Test DNS resolution for *.k8s.home.geoffdavis.com domains

5. **Outpost Registration and Validation**:
   - Verify external outpost appears in Authentik admin interface
   - Check outpost connectivity status (should show connected)
   - Monitor authentik-proxy pod logs for successful registration
   - Validate Redis connectivity and session storage

6. **Proxy Provider Configuration**:
   - Access Authentik admin interface
   - Create proxy providers for all services (dashboard, longhorn, hubble, grafana, prometheus, alertmanager)
   - Configure forward auth with proper internal service URLs
   - Test authentication flow for each service

**Important notes:**
- **External outpost architecture** provides better reliability and maintainability than embedded outpost
- Use correct external outpost API token, not admin user token
- Redis instance is required for session storage and caching
- Network connectivity between authentik-proxy and service namespaces is critical
- Only external outpost ingress should handle *.k8s.home.geoffdavis.com domains

**Success Criteria:**
- External outpost shows connected in Authentik admin interface
- All authentik-proxy pods are running and healthy
- Redis instance is operational and accessible
- All services redirect to Authentik for authentication
- SSO flow works correctly for all 6 services
- No conflicting ingress configurations exist

### Deploy External Authentik-Proxy URL Redirect Fixes
**Last performed:** July 2025 (successful deployment and configuration)
**Files to modify:**
- `infrastructure/authentik-proxy/secret.yaml` - Environment variable fixes for internal service URLs
- `infrastructure/authentik-proxy/configmap.yaml` - External URL configuration for user redirects
- `infrastructure/authentik-proxy/proxy-config-job-simple.yaml` - Configuration job with known outpost ID

**Context:**
This task documents the deployment of comprehensive fixes for internal cluster DNS redirect issues in the external authentik-proxy configuration. The fixes implement a hybrid URL architecture where outpost connections use internal service URLs while user redirects use external URLs.

**Steps:**
1. **Root Cause Analysis and Fix Identification**:
   - Identify three sources of internal cluster DNS redirect issues:
     - Environment variables using external URLs for outpost connections
     - ConfigMap hardcoded URLs causing internal DNS resolution conflicts
     - Configuration job needing updates for proper outpost configuration
   - Develop hybrid URL architecture solution

2. **Environment Variable Configuration Fix**:
   - Update `AUTHENTIK_HOST` in `secret.yaml` from `https://authentik.k8s.home.geoffdavis.com` to `http://authentik-server.authentik.svc.cluster.local:80`
   - Ensure outpost can connect to Authentik server using internal cluster DNS
   - Maintain external URL references for user-facing redirects in other configurations

3. **ConfigMap External URL Configuration**:
   - Update all hardcoded URLs in `configmap.yaml` to use external domains (`https://authentik.k8s.home.geoffdavis.com`)
   - Ensure user browser redirects go to external URLs instead of internal cluster DNS
   - Configure service routing for all 6 services (longhorn, grafana, prometheus, alertmanager, dashboard, hubble)

4. **Configuration Job Updates**:
   - Apply `proxy-config-job-simple.yaml` with known outpost ID `3f0970c5-d6a3-43b2-9a36-d74665c6b24e`
   - Remove problematic `fix-oauth2-redirect-urls` job that was interfering
   - Ensure configuration job updates outpost settings in Authentik database

5. **GitOps Deployment Process**:
   - Commit all configuration fixes to Git repository
   - Monitor Flux deployment and reconciliation of changes
   - Verify pods restart and pick up new environment variables and ConfigMap
   - Validate configuration job execution and completion

6. **Deployment Validation**:
   - Verify both authentik-proxy pods are running (1/1 Ready)
   - Check websocket connections established with Authentik server
   - Validate `/outpost.goauthentik.io/ping` endpoints return status 204
   - Monitor pod logs for successful connections and proper configuration

**Hybrid URL Architecture Implementation:**
- **Internal Connections**: Use `http://authentik-server.authentik.svc.cluster.local:80` for outpost-to-Authentik communication
- **External Redirects**: Use `https://authentik.k8s.home.geoffdavis.com` for user browser redirects
- **DNS Resolution**: Resolves cluster DNS conflicts by separating internal and external URL usage
- **Service Integration**: Maintains proper authentication flow while fixing connectivity issues

**Important notes:**
- **Root cause**: External outposts running inside cluster cannot resolve external DNS names through cluster DNS
- **Solution**: Hybrid approach separating outpost connections from user redirects
- **GitOps integration**: All fixes deployed via standard Git commit and Flux reconciliation process
- **Pod health**: Successful deployment results in running pods with established websocket connections
- **Token management**: May require 1Password token updates to match correct external outpost

**Success Criteria:**
- ✅ All three configuration fixes deployed and active
- ✅ Both authentik-proxy pods running with successful Authentik server connections
- ✅ Websocket connections established between outpost and Authentik server
- ✅ Health check endpoints responding correctly (status 204)
- ✅ GitOps deployment completed via Flux reconciliation
- ✅ Hybrid URL architecture implemented and functional

**Post-Deployment Tasks:**
- Verify 1Password token matches correct external outpost ID
- Test authentication flow with external URL redirects
- Validate end-to-end SSO functionality for all 6 services
- Monitor system performance with new hybrid URL configuration

**Troubleshooting:**
- **Pod connection failures**: Check internal service URL configuration in environment variables
- **User redirect issues**: Verify external URLs in ConfigMap are correct and accessible
- **Token mismatches**: Update 1Password entry with correct external outpost token
- **DNS resolution problems**: Ensure hybrid architecture properly separates internal/external URL usage

This task provides a comprehensive reference for deploying external authentik-proxy URL redirect fixes and implementing hybrid URL architecture for reliable authentication system operation.

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
- Various service ingress files - Ingress configuration cleanup

**Steps:**
1. **Diagnose Authentication Failures**:
   - Check service accessibility: `curl -I https://<service>.k8s.home.geoffdavis.com`
   - Verify ingress configuration: `kubectl get ingress -A`
   - Check Authentik outpost logs: `kubectl logs -n authentik -l app.kubernetes.io/name=authentik`

2. **Check for Conflicting Ingress Configurations**:
   - Identify individual service ingresses: `kubectl get ingress -A | grep k8s.home.geoffdavis.com`
   - Verify embedded outpost ingress exists: `kubectl get ingress -n authentik`
   - Check for duplicate domain handling between individual services and embedded outpost

3. **Remove Conflicting Individual Service Ingresses**:
   - Delete individual service ingresses that conflict with embedded outpost
   - Ensure only embedded outpost handles *.k8s.home.geoffdavis.com domains
   - Verify service endpoints are accessible: `kubectl get endpoints -A`

4. **Configure Embedded Outpost**:
   - Delete outpost config job: `kubectl delete job -n authentik outpost-config`
   - Apply outpost config: `kubectl apply -f infrastructure/authentik-outpost-config/outpost-config-job.yaml`
   - Verify outpost registration in Authentik admin interface

5. **Create Proxy Providers**:
   - Access Authentik admin interface
   - Create proxy providers for each service (dashboard, longhorn, hubble, grafana, prometheus, alertmanager)
   - Configure forward auth with proper internal service URLs
   - Verify network connectivity between authentik namespace and service namespaces

6. **Verify Resolution**:
   - Test service access: Navigate to https://<service>.k8s.home.geoffdavis.com
   - Confirm redirect to Authentik login
   - Verify successful authentication and service access
   - Check all monitored services (Longhorn, Grafana, etc.)

**Important notes:**
- **Root cause**: Conflicting ingress configurations between individual service ingresses and embedded outpost
- Embedded outpost architecture requires NO individual service ingresses for *.k8s.home.geoffdavis.com
- All services must be handled by embedded outpost ingress only
- Network connectivity must be verified between authentik namespace and service namespaces
- Manual proxy provider configuration may be required when automation fails

**Common Issues and Solutions:**
- **404/500 errors**: Usually indicates conflicting ingress configurations - remove individual service ingresses
- **Authentication loops**: Check that only embedded outpost handles *.k8s.home.geoffdavis.com domains
- **Service unreachable**: Verify service endpoints and network connectivity between namespaces
- **Configuration conflicts**: Ensure embedded outpost has exclusive domain handling

### Resolve Authentik Authentication via Ingress Configuration Cleanup
**Last performed:** January 2025 (successful resolution)
**Files to modify:**
- Individual service ingress files - Remove conflicting configurations
- `infrastructure/authentik-outpost-config/` - Embedded outpost configuration
- Various service configurations - Service endpoint validation

**Steps:**
1. **Identify Conflicting Ingress Configurations**:
   - List all ingresses handling *.k8s.home.geoffdavis.com: `kubectl get ingress -A | grep k8s.home.geoffdavis.com`
   - Identify individual service ingresses that conflict with embedded outpost
   - Check embedded outpost ingress configuration: `kubectl get ingress -n authentik`

2. **Remove Individual Service Ingresses**:
   - Delete individual service ingress resources that handle *.k8s.home.geoffdavis.com domains
   - Ensure only embedded outpost ingress handles these domains
   - Verify service endpoints remain accessible: `kubectl get endpoints -A`

3. **Configure Embedded Outpost**:
   - Apply embedded outpost configuration job
   - Verify outpost registration in Authentik admin interface
   - Check outpost connectivity and health status

4. **Create Proxy Providers**:
   - Access Authentik admin interface
   - Create proxy providers for all services (dashboard, longhorn, hubble, grafana, prometheus, alertmanager)
   - Configure forward auth with proper internal service URLs and ports
   - Verify network connectivity between authentik namespace and service namespaces

5. **Validate Service Configuration**:
   - Fix service names and port configurations (e.g., Grafana service name)
   - Ensure services are discoverable from authentik namespace
   - Test network connectivity: `kubectl exec -n authentik <pod> -- curl <service>.<namespace>:<port>`

6. **Verify Complete Resolution**:
   - Test all services: Navigate to https://<service>.k8s.home.geoffdavis.com
   - Confirm proper redirect to Authentik login
   - Verify successful authentication and service access
   - Validate all 6 services are working (dashboard, longhorn, hubble, grafana, prometheus, alertmanager)

**Important notes:**
- **Root cause confirmed**: Conflicting ingress configurations between individual services and embedded outpost
- Embedded outpost architecture requires exclusive domain handling for *.k8s.home.geoffdavis.com
- Network connectivity between authentik namespace and service namespaces is critical
- Service configuration fixes may be required (service names, ports)
- Manual proxy provider configuration is the reliable fallback when automation fails

**Resolution Summary:**
- Conflicting ingress configurations prevented proper request routing to embedded outpost
- Embedded outpost with forward auth runs within authentik-server pods
- All 6 proxy providers successfully created and operational
- Network path cleared with only embedded outpost handling authentication domains
- All services now properly authenticated and accessible via SSO

### Monitor Authentication System Health
**Last performed:** Ongoing maintenance requirement
**Files to modify:** None (monitoring task)

**Steps:**
1. **Daily Authentication Health Checks**:
   - Test key service access: `curl -I https://longhorn.k8s.home.geoffdavis.com`
   - Verify all 6 services accessible: Dashboard, Longhorn, Hubble, Grafana, Prometheus, AlertManager
   - Check for authentication response times and any 404/500 errors

2. **Weekly Ingress Configuration Validation**:
   - List all ingresses handling *.k8s.home.geoffdavis.com: `kubectl get ingress -A | grep k8s.home.geoffdavis.com`
   - Verify only embedded outpost ingress handles these domains
   - Check for any new individual service ingresses that might conflict

3. **Monthly Outpost Health Assessment**:
   - Access Authentik admin interface and check outpost status
   - Verify all proxy providers are operational
   - Review authentication logs for any recurring errors
   - Check API token expiration dates and plan rotation if needed

4. **Proactive Configuration Monitoring**:
   - Monitor for new service deployments that might create conflicting ingresses
   - Validate network connectivity between authentik namespace and service namespaces
   - Check for any changes to service names or ports that might break proxy providers

5. **Alert on Authentication Failures**:
   - Set up monitoring alerts for 404/500 responses from *.k8s.home.geoffdavis.com services
   - Monitor Authentik outpost connectivity status
   - Alert on authentication response time degradation

**Important notes:**
- Early detection of ingress configuration conflicts prevents service outages
- Regular validation ensures embedded outpost maintains exclusive domain handling
- Proactive monitoring reduces manual troubleshooting and service disruption
- Authentication system health directly impacts all cluster services

**Monitoring Checklist:**
- [ ] All 6 services respond with proper authentication redirects
- [ ] Only embedded outpost ingress handles *.k8s.home.geoffdavis.com domains
- [ ] No conflicting individual service ingresses exist
- [ ] Network connectivity between authentik and service namespaces is clear
- [ ] Authentik outpost status shows healthy in admin interface
- [ ] All proxy providers are operational and properly configured

### Prevent Authentication Configuration Conflicts
**Last performed:** Ongoing operational requirement
**Files to modify:** Various service configurations as needed

**Steps:**
1. **Service Deployment Guidelines**:
   - When adding new services to *.k8s.home.geoffdavis.com domain:
   - Do NOT create individual service ingresses for authenticated domains
   - Ensure services use proper internal service names and ports
   - Verify network connectivity from authentik namespace

2. **Configuration Validation Process**:
   - Before deploying new services, check existing ingress configurations
   - Validate that embedded outpost will have exclusive domain handling
   - Test service endpoints are accessible from authentik namespace

3. **Automated Configuration Checks**:
   - Implement pre-deployment validation scripts
   - Check for conflicting ingress configurations before Git commits
   - Validate service discovery and network connectivity

4. **Documentation and Training**:
   - Update service deployment procedures to prevent ingress conflicts
   - Document embedded outpost architecture requirements
   - Train operators on proper authentication integration patterns

**Important notes:**
- Prevention is more effective than troubleshooting after conflicts occur
- Embedded outpost architecture requires exclusive domain handling
- Service integration must follow established patterns to avoid conflicts
- Proper validation prevents authentication system disruption

### Resolve Persistent Service Connectivity Issues After Authentication Configuration
**Last performed:** January 2025 (ongoing issue)
**Files to modify:** Various infrastructure and network configuration files as needed

**Context:**
This task addresses persistent connectivity issues where services at *.k8s.home.geoffdavis.com remain inaccessible despite comprehensive authentication system restoration work. This represents a different class of issue than ingress configuration conflicts and may require network-level troubleshooting beyond Kubernetes configuration.

**Steps:**

1. **Systematic Connectivity Diagnosis**:
   - Test DNS resolution from client machines: `dig longhorn.k8s.home.geoffdavis.com`
   - Test DNS resolution from cluster: `kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup longhorn.k8s.home.geoffdavis.com`
   - Verify load balancer IP accessibility: `ping 172.29.51.200` and `telnet 172.29.51.200 443`
   - Test TLS certificate validation: `openssl s_client -connect longhorn.k8s.home.geoffdavis.com:443 -servername longhorn.k8s.home.geoffdavis.com`
   - Check ingress controller health: `kubectl get pods -n ingress-nginx-internal` and `kubectl logs -n ingress-nginx-internal -l app.kubernetes.io/name=ingress-nginx`

2. **Infrastructure Layer Validation**:
   - Verify BGP advertisement for load balancer IPs: `task bgp:verify-peering`
   - Check BGP route advertisement: `kubectl exec -n kube-system -l k8s-app=cilium -- cilium bgp routes`
   - Validate Cilium CNI health: `cilium status` and `cilium connectivity test`
   - Check external DNS record creation: `kubectl logs -n external-dns-internal -l app.kubernetes.io/name=external-dns`
   - Verify certificate manager status: `kubectl get certificates -A` and `kubectl get certificaterequests -A`
   - Test ingress controller service endpoints: `kubectl get endpoints -n ingress-nginx-internal`

3. **Authentication System Integration Testing**:
   - Test Authentik service accessibility from cluster: `kubectl exec -it -n authentik <authentik-pod> -- curl -I http://authentik-server:9000`
   - Verify embedded outpost connectivity: Check outpost status in Authentik admin interface
   - Test forward-auth endpoint: `kubectl exec -it -n authentik <authentik-pod> -- curl -I http://authentik-server:9000/outpost.goauthentik.io/auth/nginx`
   - Validate service-to-service communication: `kubectl exec -it -n authentik <authentik-pod> -- curl -I http://longhorn-frontend.longhorn-system:80`

4. **Client-Side Troubleshooting**:
   - Test DNS resolution from multiple client machines: `dig longhorn.k8s.home.geoffdavis.com @<dns-server>`
   - Check network routing to cluster IPs: `traceroute 172.29.51.200`
   - Verify certificate trust chain: Check browser certificate validation and system certificate store
   - Test with different clients: Browser, curl, mobile devices on same network
   - Check firewall rules: Verify no blocking of ports 80/443 to cluster IP range

5. **Network Infrastructure Validation**:
   - Verify UDM Pro BGP peering status: Check BGP neighbor status and route advertisement
   - Test load balancer IP reachability from router: `ping 172.29.51.200` from UDM Pro
   - Check VLAN configuration: Verify VLAN 51 routing and inter-VLAN communication
   - Validate DNS server configuration: Check if internal DNS server has proper records
   - Test network segmentation: Verify no network policies blocking traffic

6. **Kubernetes Service Discovery Validation**:
   - Check service endpoints: `kubectl get endpoints -A | grep -E "(longhorn|grafana|prometheus|alertmanager|dashboard)"`
   - Verify service port configurations: `kubectl get svc -A | grep -E "(longhorn|grafana|prometheus|alertmanager|dashboard)"`
   - Test internal service connectivity: `kubectl run -it --rm debug --image=busybox --restart=Never -- wget -O- http://longhorn-frontend.longhorn-system:80`
   - Check ingress resource configurations: `kubectl get ingress -A -o yaml | grep -A 10 -B 10 k8s.home.geoffdavis.com`

7. **Load Balancer and Ingress Deep Dive**:
   - Verify Cilium load balancer configuration: `kubectl get ciliumloadbalancerippools -o yaml`
   - Check ingress controller service type and external IP: `kubectl get svc -n ingress-nginx-internal nginx-internal-ingress-nginx-controller`
   - Test direct ingress controller access: `curl -H "Host: longhorn.k8s.home.geoffdavis.com" http://172.29.51.200`
   - Validate ingress controller logs for request processing: `kubectl logs -n ingress-nginx-internal -l app.kubernetes.io/name=ingress-nginx --tail=100`

**Important notes:**
- This represents a different class of issue than ingress configuration conflicts previously resolved
- May require network-level troubleshooting beyond Kubernetes configuration
- Could involve DNS, BGP, load balancer, certificate, or fundamental network connectivity issues
- Systematic approach needed to isolate the connectivity failure point
- Focus on validating each layer: DNS → Network → Load Balancer → Ingress → Authentication → Service

**Common Root Causes:**
- **DNS Issues**: Records not created, wrong IP addresses, DNS server not responding
- **BGP Problems**: Routes not advertised, peering down, incorrect ASN configuration
- **Load Balancer Issues**: IP pool exhaustion, service not getting external IP
- **Certificate Problems**: Invalid certificates, trust chain issues, certificate not issued
- **Network Connectivity**: Firewall blocking, VLAN misconfiguration, routing issues
- **Service Discovery**: Endpoints not ready, service port mismatches, pod not running

**Escalation Path:**
1. If DNS resolution fails → Focus on external-dns and DNS server configuration
2. If network connectivity fails → Focus on BGP, routing, and firewall configuration
3. If TLS fails → Focus on cert-manager and certificate validation
4. If ingress fails → Focus on ingress controller and load balancer configuration
5. If authentication fails → Return to authentication system troubleshooting tasks

**Success Criteria:**
- DNS resolution works from client machines
- Network connectivity established to load balancer IP
- TLS certificates validate properly
- Ingress controller processes requests correctly
- Authentication system responds to requests
- All services accessible via browser with proper SSO flow

This task documentation helps maintain consistency and reduces the learning curve for common operational procedures.

### Migrate Load Balancer from L2 Announcements to BGP-Only Architecture
**Last performed:** January 2025 (COMPLETED - BGP LoadBalancer migration successful)
**Files to modify:**
- `Taskfile.yml` - Bootstrap Cilium configuration updated to include LB-IPAM and XDP disabled
- `infrastructure/cilium/loadbalancer-pool-bgp.yaml` - BGP IP pool definitions deployed
- `infrastructure/cilium-bgp/bgp-policy-legacy.yaml` - Working BGP peering configuration using legacy schema
- Service annotations - Pool selectors updated for all LoadBalancer services
- UDM Pro BGP configuration - BGP peering established (ASN 64512 ↔ ASN 64513)

**Context:**
This migration successfully resolved L2 announcement conflicts by moving to a BGP-only load balancer architecture. **Migration Complete**: BGP peering established, route advertisement working, and all services accessible via BGP-advertised IPs. **Root Cause Resolution**: Schema compatibility issues resolved by switching to legacy CiliumBGPPeeringPolicy.

**Final Status:**
- ✅ BGP peering established and stable between cluster (ASN 64512) and UDM Pro (ASN 64513)
- ✅ Cilium v1.17.6 deployed with XDP disabled for Mac mini compatibility
- ✅ LoadBalancer IPAM working (services getting IPs from BGP pools: 172.29.52.x range)
- ✅ Network separation implemented (management VLAN 51, load balancer VLAN 52)
- ✅ **RESOLVED**: BGP routes successfully advertised using legacy CiliumBGPPeeringPolicy schema
- ✅ Schema compatibility issues resolved by switching from newer CRDs to legacy configuration
- ✅ All services accessible via BGP-advertised IPs (Longhorn: 172.29.52.100, Ingress: 172.29.52.200)

**Steps Completed:**
1. **✅ Cilium v1.17.6 Deployment**:
   - Upgraded from v1.16.1 with XDP disabled: `--set loadBalancer.acceleration=disabled`
   - LoadBalancer IPAM enabled: `--set loadBalancer.l2.enabled=false --set enable-lb-ipam=true`
   - Bootstrap configuration updated in `Taskfile.yml` for future deployments

2. **✅ BGP IP Pools Configured**:
   - Deployed BGP IP pools via GitOps: `infrastructure/cilium/loadbalancer-pool-bgp.yaml`
   - Pools: `bgp-default` (172.29.52.100-199), `bgp-ingress` (172.29.52.200-220), `bgp-reserved` (172.29.52.221-250)
   - Removed conflicting legacy pools to prevent IPAM conflicts

3. **✅ Service Annotations Updated**:
   - Ingress services annotated with `io.cilium/lb-ipam-pool=ingress`
   - Other services annotated with `io.cilium/lb-ipam-pool=default`
   - Pool selectors properly matched between pools and service annotations

4. **✅ BGP Peering Established**:
   - UDM Pro BGP configuration deployed (ASN 64513)
   - Cluster BGP configuration deployed (ASN 64512)
   - BGP peering status: **ESTABLISHED** and stable
   - All cluster nodes participating in BGP peering

5. **✅ LoadBalancer IPAM Operational**:
   - Services successfully getting external IPs from BGP pools
   - IP assignment working correctly based on pool selectors
   - Network separation implemented (VLAN 51 for management, VLAN 52 for load balancer IPs)

**Root Cause Resolution - Schema Compatibility Issues:**
- **Problem**: CiliumBGPClusterConfig/CiliumBGPAdvertisement incompatible with Cilium v1.17.6
- **Solution**: Switched to legacy CiliumBGPPeeringPolicy schema for full compatibility
- **Result**: BGP routes successfully advertised and services accessible from network
- **Configuration**: [`infrastructure/cilium-bgp/bgp-policy-legacy.yaml`](../infrastructure/cilium-bgp/bgp-policy-legacy.yaml)

**Migration Completion Steps:**
1. **✅ Schema Compatibility Resolution**:
   - Identified newer BGP CRDs incompatible with Cilium v1.17.6
   - Switched to legacy CiliumBGPPeeringPolicy schema
   - Removed problematic CiliumBGPClusterConfig/CiliumBGPAdvertisement resources

2. **✅ BGP Route Advertisement Working**:
   - Legacy schema enables proper route advertisement
   - BGP routes visible in UDM Pro routing table
   - Services accessible via BGP-advertised IPs

3. **✅ End-to-End Service Connectivity**:
   - All LoadBalancer services accessible from client machines
   - Longhorn accessible at 172.29.52.100
   - Ingress accessible at 172.29.52.200
   - Full network connectivity confirmed

**Important notes:**
- **Migration Complete**: BGP LoadBalancer migration successfully completed
- **Architecture Change**: Successfully moved from L2 announcements to BGP-only load balancer architecture
- **Cilium Compatibility**: XDP disabled configuration resolves Mac mini compatibility issues
- **Network Separation**: Management traffic (VLAN 51) and load balancer IPs (VLAN 52) properly separated
- **IPAM Success**: LoadBalancer IPAM working correctly with proper IP pool assignment
- **Schema Solution**: Legacy CiliumBGPPeeringPolicy provides full Cilium v1.17.6 compatibility

**Operational Procedures:**
- **BGP Status**: Use `task bgp-loadbalancer:status` for comprehensive BGP health check
- **Service Management**: Use `task bgp-loadbalancer:update-service-pools` to assign services to specific IP pools
- **Troubleshooting**: Use `task bgp-loadbalancer:troubleshoot` for systematic issue diagnosis
- **Monitoring**: Use `task bgp-loadbalancer:verify-bgp-peering` to check BGP peering health

**Success Criteria - ALL ACHIEVED:**
- ✅ BGP peering established between cluster nodes (ASN 64512) and UDM Pro (ASN 64513)
- ✅ All LoadBalancer services get external IPs from BGP pools (172.29.52.x range)
- ✅ Network separation implemented with proper VLAN segmentation
- ✅ **COMPLETED**: BGP routes advertised and visible in UDM Pro routing table
- ✅ **COMPLETED**: Services accessible via external IPs from client machines
- ✅ Bootstrap configuration updated for future cluster deployments

**Documentation Created:**
- **Operational Guide**: [`docs/BGP_LOADBALANCER_OPERATIONAL_GUIDE.md`](../docs/BGP_LOADBALANCER_OPERATIONAL_GUIDE.md)
- **Troubleshooting Guide**: [`docs/BGP_LOADBALANCER_TROUBLESHOOTING.md`](../docs/BGP_LOADBALANCER_TROUBLESHOOTING.md)
- **Task Commands**: [`taskfiles/bgp-loadbalancer.yml`](../taskfiles/bgp-loadbalancer.yml)

The BGP LoadBalancer system is now **production-ready** and the migration from L2 announcements is **complete**.

### Fix BGP Pool Advertisement Issues for Multiple IP Pools
**Last performed:** January 2025 (COMPLETED - BGP pool advertisement fixed)
**Files to modify:**
- `infrastructure/cilium-bgp/bgp-policy-legacy.yaml` - BGP peering policy with multiple virtual routers
- `infrastructure/ingress-nginx-internal/helmrelease.yaml` - Service pool annotations

**Context:**
This task resolves BGP route advertisement failures where only services from the `bgp-default` pool were being advertised via BGP, while services from other pools (like `bgp-ingress`) were not advertised, causing 500 errors for *.k8s.home.geoffdavis.com services.

**Root Cause:**
The legacy CiliumBGPPeeringPolicy with a single virtual router using `serviceSelector: {}` (empty selector) was not properly advertising services from all IP pools. Only services from the `bgp-default` pool were being advertised.

**Solution:**
Create dedicated virtual routers for each IP pool with explicit service selectors matching the pool labels.

**Steps:**
1. **Diagnose BGP Advertisement Issue**:
   - Check BGP routes: `kubectl exec -n kube-system <cilium-pod> -- cilium bgp routes`
   - Verify service pool assignments: `kubectl get svc -A --field-selector spec.type=LoadBalancer -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,EXTERNAL-IP:.status.loadBalancer.ingress[0].ip,POOL:.metadata.annotations.io\.cilium/lb-ipam-pool"`
   - Identify missing routes for specific pools

2. **Update BGP Policy Configuration**:
   - Replace single virtual router with multiple virtual routers
   - Create dedicated virtual router for each IP pool:
     - `bgp-default` pool: `serviceSelector.matchLabels.io.cilium/lb-ipam-pool: "bgp-default"`
     - `bgp-ingress` pool: `serviceSelector.matchLabels.io.cilium/lb-ipam-pool: "bgp-ingress"`
     - `bgp-reserved` pool: `serviceSelector.matchLabels.io.cilium/lb-ipam-pool: "bgp-reserved"`
   - Set `exportPodCIDR: true` only on first virtual router to avoid duplication
   - Each virtual router has same BGP neighbor configuration

3. **Verify Service Pool Annotations**:
   - Ensure services have correct `io.cilium/lb-ipam-pool` annotations
   - Match service annotations with IP pool names exactly
   - Update service configurations if pool names don't match

4. **Test BGP Route Advertisement**:
   - Apply BGP policy changes via GitOps
   - Monitor BGP routes: `kubectl exec -n kube-system <cilium-pod> -- cilium bgp routes`
   - Verify all LoadBalancer service IPs are advertised
   - Test service connectivity: `curl -I -k https://<service>.k8s.home.geoffdavis.com`

5. **Validate End-to-End Connectivity**:
   - Confirm BGP peering remains stable: `kubectl exec -n kube-system <cilium-pod> -- cilium bgp peers`
   - Test all services respond with proper HTTP codes (not connection timeouts)
   - Verify network routing from client machines

**BGP Policy Configuration Example:**
```yaml
spec:
  virtualRouters:
    # Virtual router for bgp-default pool services
    - localASN: 64512
      exportPodCIDR: true
      serviceSelector:
        matchLabels:
          io.cilium/lb-ipam-pool: "bgp-default"
      serviceAdvertisements:
        - LoadBalancerIP
      neighbors:
        - peerAddress: "172.29.51.1/32"
          peerASN: 64513
    # Virtual router for bgp-ingress pool services
    - localASN: 64512
      exportPodCIDR: false
      serviceSelector:
        matchLabels:
          io.cilium/lb-ipam-pool: "bgp-ingress"
      serviceAdvertisements:
        - LoadBalancerIP
      neighbors:
        - peerAddress: "172.29.51.1/32"
          peerASN: 64513
```

**Important notes:**
- **Root cause**: Single virtual router with empty serviceSelector not advertising all IP pools
- **Solution**: Multiple virtual routers with explicit pool-specific service selectors
- **Cilium v1.17.6 compatibility**: Legacy CiliumBGPPeeringPolicy schema required
- **Network impact**: Fix resolves 500 errors by ensuring ingress controller IP is advertised
- **Pool architecture**: Maintains separation between bgp-default, bgp-ingress, and bgp-reserved pools

**Success Criteria:**
- ✅ All LoadBalancer service IPs advertised via BGP regardless of pool assignment
- ✅ BGP routes include services from bgp-default, bgp-ingress, and bgp-reserved pools
- ✅ Services respond with HTTP codes instead of connection timeouts
- ✅ Network connectivity restored for *.k8s.home.geoffdavis.com services
- ✅ BGP peering remains stable with multiple virtual routers

**Troubleshooting:**
- **Missing routes**: Check service pool annotations match IP pool names exactly
- **BGP peering issues**: Verify all virtual routers have identical neighbor configuration
- **Service connectivity**: Ensure DNS records point to correct advertised IPs
- **Pool conflicts**: Verify no duplicate pool selectors between virtual routers

This fix ensures robust BGP advertisement for all IP pools and resolves service connectivity issues caused by missing route advertisements.