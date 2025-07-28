# Common Tasks and Workflows

This file documents repetitive tasks and operational workflows that follow established patterns in the cluster.

## Home Assistant Stack Management

### Deploy Home Assistant Stack

**Last performed:** July 2025 (successful deployment)
**Files to modify:**

- `apps/home-automation/` - Complete Home Assistant stack deployment
- `clusters/home-ops/infrastructure/apps.yaml` - Flux Kustomization for apps

**Steps:**

1. **Prerequisites Validation**:

   - Verify PostgreSQL cluster operator is operational
   - Confirm Longhorn storage is available
   - Check external Authentik outpost is working
   - Validate ingress controller and cert-manager functionality

2. **Deploy Database Infrastructure**:

   - Deploy PostgreSQL cluster: `kubectl apply -f apps/home-automation/postgresql/`
   - Verify cluster status: `kubectl get cluster homeassistant-postgresql -n home-automation`
   - Check database initialization job completion
   - Validate database credentials from 1Password integration

3. **Deploy Supporting Services**:

   - Deploy Mosquitto MQTT broker: `kubectl apply -f apps/home-automation/mosquitto/`
   - Deploy Redis cache: `kubectl apply -f apps/home-automation/redis/`
   - Verify service endpoints: `kubectl get endpoints -n home-automation`

4. **Deploy Home Assistant Core**:

   - Deploy Home Assistant: `kubectl apply -f apps/home-automation/home-assistant/`
   - Monitor deployment: `kubectl rollout status deployment home-assistant -n home-automation`
   - Check health probes: `kubectl get pods -n home-automation -l app.kubernetes.io/name=home-assistant`

5. **Configure Authentication Integration**:

   - Verify external Authentik outpost handles homeassistant.k8s.home.geoffdavis.com
   - Test SSO authentication flow
   - Validate trusted proxy configuration for Authentik integration

6. **Validate Complete Stack**:
   - Test web interface: <https://homeassistant.k8s.home.geoffdavis.com>
   - Verify database connectivity and data persistence
   - Test MQTT broker functionality
   - Check Redis cache performance
   - Validate backup strategy execution

**Important notes:**

- **Database Integration**: PostgreSQL cluster provides high availability with automated backups
- **Authentication Flow**: Full SSO integration with existing external Authentik outpost
- **Resource Management**: Production-ready resource limits and health checks
- **IoT Integration**: Mosquitto MQTT broker for secure IoT device communication
- **Performance**: Redis cache for session storage and optimization

**Success Criteria:**

- ✅ All Home Assistant stack components running and healthy
- ✅ Database cluster operational with proper backup configuration
- ✅ MQTT broker accessible for IoT device integration
- ✅ Redis cache operational and connected
- ✅ SSO authentication working via external Authentik outpost
- ✅ Web interface accessible and functional

**Troubleshooting:**

- **Database connection issues**: Check PostgreSQL cluster status and credentials
- **Authentication failures**: Verify external Authentik outpost proxy provider configuration
- **MQTT connectivity**: Check Mosquitto service endpoints and security configuration
- **Performance issues**: Monitor Redis cache utilization and Home Assistant resource usage

### Troubleshoot Home Assistant Stack Deployment Issues

**Last performed:** July 2025 (successful completion - MAJOR SUCCESS)
**Files to modify:**

- `apps/home-automation/postgresql/postgresql-backup.yaml` - Remove invalid CloudNativePG schema fields
- `apps/home-automation/postgresql/cluster.yaml` - Fix TLS certificate configuration
- `apps/home-automation/postgresql/external-secret-superuser.yaml` - Fix 1Password credential references
- `apps/home-automation/namespace.yaml` - Update PodSecurity policy for s6-overlay compatibility
- `apps/home-automation/home-assistant/deployment.yaml` - Add required security context
- `apps/home-automation/mosquitto/configmap.yaml` - Simplify MQTT listener configuration

**Context:**
This task documents the comprehensive troubleshooting and recovery of a completely non-functional Home Assistant stack deployment. Through systematic investigation and resolution of multiple critical blocking issues, the entire stack was restored to full operational status.

**Root Causes Identified:**

- **PostgreSQL Schema Validation**: CloudNativePG v1.26.1 compatibility issues with invalid `immediate: true` fields blocking all resource deployment
- **Missing 1Password Credentials**: Required credential entries missing from 1Password vault preventing external secrets synchronization
- **PostgreSQL TLS Certificate Issues**: Manual certificate configuration conflicts with CloudNativePG automatic certificate management
- **Container Security Constraints**: Namespace PodSecurity policy "restricted" incompatible with s6-overlay init system requirements
- **MQTT Port Binding Conflicts**: Mosquitto configuration causing port 1883 binding conflicts preventing service startup

**Steps:**

1. **Root Cause Analysis and Investigation**:

   - Investigate Flux Kustomization status: `flux get kustomizations -n home-automation`
   - Check resource deployment failures: `kubectl get all -n home-automation`
   - Analyze PostgreSQL cluster status: `kubectl get cluster homeassistant-postgresql -n home-automation`
   - Review external secrets synchronization: `kubectl get externalsecrets -n home-automation`
   - Examine pod startup failures: `kubectl describe pods -n home-automation`

2. **PostgreSQL Schema Validation Fix**:

   - **Problem**: CloudNativePG v1.26.1 rejecting invalid `immediate: true` fields in Backup and ScheduledBackup resources
   - **Solution**: Remove invalid fields from `postgresql-backup.yaml`:

     ```yaml
     # Remove these invalid fields:
     # immediate: true  # Not supported in CloudNativePG v1.26.1
     ```

   - **Validation**: Verify resource deployment: `kubectl apply -f apps/home-automation/postgresql/postgresql-backup.yaml`

3. **1Password Credential Management**:

   - **Problem**: Missing credential entries in 1Password vault preventing external secrets from syncing
   - **Solution**: Create missing 1Password entries with optimized architecture:
     - PostgreSQL credentials with proper naming convention
     - Home Assistant configuration secrets
     - MQTT broker credentials
   - **Validation**: Check external secret sync: `kubectl get secrets -n home-automation`

4. **PostgreSQL TLS Certificate Resolution**:

   - **Problem**: Manual TLS certificate configuration conflicting with CloudNativePG automatic certificate management
   - **Solution**: Remove explicit certificate references from `cluster.yaml`:

     ```yaml
     # Remove manual certificate configuration (lines 106-111)
     # Enable CloudNativePG automatic certificate management
     ```

   - **Validation**: Verify cluster certificate generation: `kubectl get certificates -n home-automation`

5. **Home Assistant Security Policy Fix**:

   - **Problem**: Namespace PodSecurity policy "restricted" preventing s6-overlay init system from starting
   - **Solution**: Update namespace and deployment security configuration:

     ```yaml
     # namespace.yaml - Update PodSecurity policy
     pod-security.kubernetes.io/enforce: privileged

     # deployment.yaml - Add required security context
     securityContext:
       privileged: true
       capabilities:
         add: ["SYS_ADMIN"]
     ```

   - **Validation**: Verify pod startup: `kubectl get pods -n home-automation -l app.kubernetes.io/name=home-assistant`

6. **Mosquitto MQTT Configuration Fix**:

   - **Problem**: MQTT listener configuration causing port 1883 binding conflicts
   - **Solution**: Simplify configuration to use explicit listeners only:

     ```yaml
     # Remove conflicting port 1883 configuration
     # Use explicit listener configuration only
     ```

   - **Validation**: Check service startup: `kubectl logs -n home-automation -l app.kubernetes.io/name=mosquitto`

7. **End-to-End Stack Validation**:
   - Verify all components running: `kubectl get pods -n home-automation`
   - Test database connectivity: `kubectl exec -n home-automation <postgres-pod> -- psql -c "\l"`
   - Validate MQTT broker: `kubectl port-forward -n home-automation svc/mosquitto 1883:1883`
   - Test Home Assistant access: `curl -I https://homeassistant.k8s.home.geoffdavis.com`
   - Confirm SSO authentication via external Authentik outpost

**Critical Technical Fixes Applied:**

- **Schema Compatibility**: Fixed CloudNativePG backup resource validation preventing any deployment
- **Credential Architecture**: Implemented optimized 1Password entry structure for Home Assistant stack
- **Certificate Management**: Enabled automatic TLS certificate generation removing manual configuration conflicts
- **Container Security**: Configured proper security contexts for s6-overlay container init system requirements
- **MQTT Configuration**: Resolved listener configuration conflicts causing service startup failures
- **End-to-End Validation**: Confirmed complete stack functionality with SSO authentication via external Authentik outpost

**Important notes:**

- **Systematic Approach**: Applied fixes in dependency order (database → credentials → security → services)
- **Component Validation**: Verified each component individually before proceeding to next fix
- **CloudNativePG Compatibility**: v1.26.1 has stricter schema validation requiring removal of unsupported fields
- **s6-overlay Requirements**: Container init system requires privileged security context and specific capabilities
- **Production Ready**: Complete stack now operational with proper security, monitoring, and authentication integration

**Success Criteria:**

- ✅ All Home Assistant stack components running and healthy (Home Assistant Core v2025.7, PostgreSQL, Mosquitto MQTT, Redis)
- ✅ PostgreSQL cluster operational with proper backup configuration and automatic certificate management
- ✅ All external secrets syncing successfully from 1Password vault
- ✅ MQTT broker accessible for IoT device integration without port binding conflicts
- ✅ Home Assistant web interface accessible via <https://homeassistant.k8s.home.geoffdavis.com>
- ✅ SSO authentication working via external Authentik outpost
- ✅ Complete stack integrated with cluster monitoring and alerting systems

**Troubleshooting:**

- **Schema validation errors**: Check CloudNativePG version compatibility and remove unsupported fields
- **External secret sync failures**: Verify 1Password credential entries exist and have correct naming
- **Certificate issues**: Enable CloudNativePG automatic certificate management, remove manual configuration
- **Pod security failures**: Update namespace PodSecurity policy and add required security contexts
- **Service startup failures**: Check configuration conflicts and port binding issues
- **Authentication failures**: Verify external Authentik outpost proxy provider configuration

This task represents a comprehensive recovery of a completely non-functional Home Assistant stack, demonstrating systematic troubleshooting methodology and the importance of understanding component dependencies and compatibility requirements.

### Maintain Home Assistant Stack

**Last performed:** Ongoing operational requirement
**Files to modify:** Various Home Assistant configuration files as needed

**Steps:**

1. **Regular Health Checks**:

   - Monitor Home Assistant pod status: `kubectl get pods -n home-automation`
   - Check database cluster health: `kubectl get cluster homeassistant-postgresql -n home-automation`
   - Verify MQTT broker connectivity and message flow
   - Monitor Redis cache performance and memory usage

2. **Configuration Updates**:

   - Update Home Assistant configuration via ConfigMap
   - Restart deployment after configuration changes: `kubectl rollout restart deployment home-assistant -n home-automation`
   - Test configuration changes in development environment first
   - Monitor logs for configuration errors: `kubectl logs -n home-automation -l app.kubernetes.io/name=home-assistant`

3. **Database Maintenance**:

   - Monitor PostgreSQL cluster backup status
   - Check database size and performance metrics
   - Validate backup restoration procedures periodically
   - Update database credentials if needed via 1Password integration

4. **Security Updates**:

   - Update Home Assistant image version in deployment.yaml
   - Update Mosquitto and Redis images as needed
   - Review and update network policies for IoT device access
   - Validate TLS certificates and authentication integration

5. **Performance Optimization**:
   - Monitor resource usage and adjust limits if needed
   - Optimize Redis cache configuration for Home Assistant workload
   - Review and tune PostgreSQL performance settings
   - Scale components if needed based on usage patterns

**Important notes:**

- **Backup Strategy**: Regular database backups with automated restoration testing
- **Security First**: Keep all components updated and properly secured
- **IoT Integration**: Monitor MQTT broker for security and performance
- **Authentication**: Maintain SSO integration with external Authentik outpost

**Monitoring Checklist:**

- [ ] Home Assistant web interface responsive and functional
- [ ] Database cluster healthy with recent backups
- [ ] MQTT broker processing messages correctly
- [ ] Redis cache operational with good performance
- [ ] SSO authentication working properly
- [ ] All pods running with healthy status

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
   - Verify NO individual service ingresses for \*.k8s.home.geoffdavis.com domains
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
- **CRITICAL**: Only external outpost ingress should handle \*.k8s.home.geoffdavis.com domains

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
   - Test DNS resolution for \*.k8s.home.geoffdavis.com domains

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
- Only external outpost ingress should handle \*.k8s.home.geoffdavis.com domains

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

### Fix Dashboard Service Configuration for External Authentik-Proxy

**Last performed:** July 2025 (successful completion - final service fix)
**Files to modify:**

- `infrastructure/authentik-proxy/fix-dashboard-service-job.yaml` - GitOps job to update Authentik database
- Authentik database - Direct database update via Python job

**Context:**
This task documents the final fix for the dashboard service configuration issue that completed the external Authentik outpost system. The dashboard proxy provider was configured to use a non-existent Kong service (Kong was disabled in the Dashboard HelmRelease), preventing proper authentication flow.

**Root Cause:**

- **Service Configuration Mismatch**: Dashboard proxy provider in Authentik was configured to forward requests to Kong service
- **Kong Service Disabled**: Kong was disabled in the Dashboard HelmRelease but proxy provider still referenced Kong service URL
- **Authentication Failure**: Requests to dashboard.k8s.home.geoffdavis.com failed because proxy provider couldn't reach the configured backend service

**Steps:**

1. **Root Cause Analysis**:

   - Identified dashboard service as the final non-working service (5/6 working)
   - Investigated Dashboard HelmRelease configuration and found Kong disabled
   - Discovered proxy provider still configured for Kong service URL
   - Confirmed authentication system working for other 5 services

2. **GitOps Database Update Solution**:

   - Created Python job to directly update Authentik database
   - Updated proxy provider configuration to use correct service URL
   - Used GitOps approach with Kubernetes Job for database modification
   - Avoided manual database intervention by using automated job

3. **Database Update Job Creation**:

   - Created `fix-dashboard-service-job.yaml` with Python script
   - Job connects to Authentik PostgreSQL database
   - Updates proxy provider external_host field to correct service URL
   - Includes proper RBAC and database connection configuration

4. **Job Deployment and Execution**:

   - Deploy job via GitOps: `kubectl apply -f infrastructure/authentik-proxy/fix-dashboard-service-job.yaml`
   - Monitor job execution: `kubectl logs -n authentik-proxy job/fix-dashboard-service`
   - Verify database update completed successfully
   - Confirm job completion status

5. **Service Validation**:

   - Test dashboard service access: `curl -I https://dashboard.k8s.home.geoffdavis.com`
   - Verify proper redirect to Authentik authentication
   - Confirm successful authentication and dashboard access
   - Validate all 6 services now working (Dashboard was the final service)

6. **System Completion Verification**:
   - Confirm external outpost shows all 6 services operational
   - Verify authentication flow working for all services
   - Test end-to-end SSO functionality across all services
   - Document system as production-ready and complete

**GitOps Database Update Approach:**

- **Kubernetes Job**: Used GitOps-managed Kubernetes Job for database updates
- **Python Script**: Embedded Python script in job for database connection and updates
- **RBAC Integration**: Proper service account and permissions for database access
- **Automated Execution**: No manual intervention required, fully automated via GitOps
- **Audit Trail**: Job logs provide complete audit trail of database changes

**Important notes:**

- **Final Service Fix**: This was the last service needed to complete the external authentik-proxy system
- **GitOps Approach**: Used Kubernetes Job instead of manual database intervention
- **Root Cause**: Service configuration mismatch, not authentication system problem
- **System Completion**: All 6 services now operational, external outpost system complete
- **Production Ready**: External authentik-proxy system now fully production-ready

**Success Criteria:**

- ✅ Dashboard service accessible via <https://dashboard.k8s.home.geoffdavis.com>
- ✅ Proper authentication redirect to Authentik login
- ✅ Successful authentication and dashboard access
- ✅ All 6 services operational (Longhorn, Grafana, Prometheus, AlertManager, Hubble, Dashboard)
- ✅ External outpost system complete and production-ready
- ✅ GitOps database update job completed successfully

**Post-Fix Status:**

- **System Status**: External authentik-proxy system COMPLETE and PRODUCTION-READY
- **Service Count**: 6/6 services working correctly with authentication
- **Authentication Architecture**: External outpost architecture fully operational
- **Documentation**: Comprehensive operational procedures and troubleshooting guides complete

**Troubleshooting:**

- **Service configuration mismatches**: Check HelmRelease configuration vs proxy provider settings
- **Database connection issues**: Verify PostgreSQL connectivity and credentials
- **Job execution failures**: Check RBAC permissions and database access
- **Authentication flow problems**: Verify proxy provider configuration matches actual service endpoints

This task represents the final completion of the comprehensive external Authentik outpost system that began in July 2025, with all authentication and service connectivity issues now resolved.

### Configure Kubernetes Dashboard Bearer Token Elimination

**Last performed:** July 2025 (successful completion - COMPLETED)
**Files to modify:**

- `apps/dashboard/kong-config-override-job.yaml` - Remove problematic configuration job (DELETE FILE)
- `apps/dashboard/dashboard-service-account.yaml` - Enhance RBAC permissions for administrative access
- Browser cache - Clear cache to ensure configuration changes take effect

**Context:**
This task documents the successful elimination of manual bearer token requirements for Kubernetes Dashboard access through comprehensive authentication integration with the existing external Authentik outpost system. The project resolved conflicting Kong configuration jobs and enhanced RBAC permissions to provide seamless SSO access with full administrative capabilities.

**Root Cause:**

- **Kong Configuration Conflicts**: Multiple Kong configuration jobs were overriding each other, preventing proper Dashboard authentication integration
- **RBAC Permission Limitations**: Dashboard service account lacked sufficient permissions for full administrative access
- **Authentication Integration Gap**: Dashboard was not properly integrated with the external Authentik outpost authentication system

**Steps:**

1. **Root Cause Analysis**:

   - Identified conflicting Kong configuration jobs in Dashboard deployment
   - Discovered `kong-config-override-job.yaml` was overriding proper authentication configuration
   - Confirmed external Authentik outpost system was operational for other 5 services
   - Analyzed Dashboard service account RBAC permissions

2. **Kong Configuration Conflict Resolution**:

   - Located problematic `kong-config-override-job.yaml` file in Dashboard configuration
   - Identified that this job was overriding proper Kong service configuration
   - Removed the conflicting configuration job to allow proper authentication flow
   - Verified that Dashboard HelmRelease had Kong disabled as intended

3. **RBAC Permissions Enhancement**:

   - Updated Dashboard service account with proper cluster-admin permissions
   - Enhanced ClusterRoleBinding to provide full administrative access
   - Ensured service account has sufficient permissions for Dashboard functionality
   - Validated RBAC configuration matches administrative requirements

4. **Authentication System Integration**:

   - Verified Dashboard proxy provider configuration in Authentik admin interface
   - Confirmed external outpost was handling Dashboard authentication requests
   - Tested authentication flow integration with existing external Authentik outpost
   - Validated seamless SSO integration with other cluster services

5. **Configuration Deployment and Testing**:

   - Committed all configuration changes to Git repository
   - Deployed changes via GitOps using Flux reconciliation
   - Cleared browser cache to ensure configuration changes take effect (CRITICAL STEP)
   - Tested Dashboard access via <https://dashboard.k8s.home.geoffdavis.com>

6. **Production Validation**:
   - Confirmed Dashboard no longer requires manual bearer token entry
   - Verified seamless SSO authentication through Authentik
   - Tested full administrative access and Dashboard functionality
   - Validated integration with existing external outpost architecture

**Kong Configuration Cleanup Process:**

- **File Identification**: Located `kong-config-override-job.yaml` causing configuration conflicts
- **Conflict Analysis**: Determined job was overriding proper Kong service configuration
- **Safe Removal**: Deleted problematic configuration job while preserving other Dashboard components
- **Validation**: Confirmed Dashboard HelmRelease configuration remained intact with Kong disabled

**RBAC Enhancement Details:**

- **Service Account**: Updated Dashboard service account with enhanced permissions
- **ClusterRoleBinding**: Configured proper cluster-admin access for administrative functionality
- **Permission Validation**: Tested administrative access and Dashboard feature availability
- **Security Review**: Ensured permissions are appropriate for Dashboard administrative use

**Important notes:**

- **Browser Cache Clearing**: CRITICAL step for ensuring configuration changes take effect
- **Kong Configuration**: Dashboard HelmRelease has Kong disabled, conflicting jobs must be removed
- **External Outpost Integration**: Dashboard authentication fully integrated with existing external outpost system
- **Production Ready**: All changes committed to Git and deployed via GitOps for production use
- **Administrative Access**: Dashboard now provides full administrative capabilities without manual token entry

**Success Criteria:**

- ✅ Dashboard accessible via <https://dashboard.k8s.home.geoffdavis.com> without manual bearer token
- ✅ Seamless SSO authentication through Authentik external outpost
- ✅ Full administrative access and Dashboard functionality available
- ✅ Kong configuration conflicts resolved and removed
- ✅ RBAC permissions enhanced for proper administrative access
- ✅ All changes committed to Git and deployed via GitOps

**Post-Completion Status:**

- **Authentication System**: Dashboard authentication fully integrated with external Authentik outpost
- **User Experience**: Seamless SSO access without manual token requirements
- **Administrative Access**: Full cluster administrative capabilities available through Dashboard
- **Production Deployment**: All changes committed to Git and operational in production
- **System Integration**: Dashboard now part of comprehensive authentication system with other 5 services

**Troubleshooting:**

- **Authentication failures**: Clear browser cache and verify external outpost connectivity
- **Permission issues**: Check Dashboard service account RBAC configuration
- **Configuration conflicts**: Ensure no conflicting Kong configuration jobs exist
- **SSO integration problems**: Verify Dashboard proxy provider configuration in Authentik admin interface

This task represents the successful completion of the Kubernetes Dashboard bearer token elimination project, providing seamless SSO access and full administrative capabilities through integration with the existing external Authentik outpost system.

### Resolve Monitoring Stack Failures After Renovate Updates

**Last performed:** July 2025 (successful completion - MAJOR SUCCESS)
**Files to modify:**

- `apps/monitoring/` - Remove duplicate monitoring directory (DELETE ENTIRE DIRECTORY)
- `clusters/home-ops/infrastructure/apps.yaml` - Remove apps-monitoring Kustomization reference
- `infrastructure/monitoring/prometheus.yaml` - Add required service labels for LoadBalancer IPAM
- `apps/home-automation/mosquitto/service.yaml` - Add required service labels for LoadBalancer IPAM

**Context:**
This task documents the comprehensive resolution of monitoring stack failures caused by Renovate dependency updates. The failures were caused by dual issues: duplicate HelmRelease conflicts and LoadBalancer IPAM dysfunction that prevented external IP assignment and blocked Flux reconciliation.

**Root Causes Identified:**

- **Duplicate HelmRelease Conflicts**: Both `apps/monitoring/` and `infrastructure/monitoring/` contained identical kube-prometheus-stack configurations that Renovate updated simultaneously
- **Renovate Trigger**: Renovate PR #10 updated kube-prometheus-stack from v61.3.2 → v75.15.0 in both locations, causing Helm controller conflicts
- **LoadBalancer IPAM Dysfunction**: Cilium IPAM controller failure and service selector mismatch preventing external IP assignment
- **Service Configuration Issue**: IP pools expected services to have `io.cilium/lb-ipam-pool` labels, but services only had annotations

**Steps:**

1. **Root Cause Analysis and Investigation**:

   - Investigate Flux reconciliation status: `flux get kustomizations`
   - Check HelmRelease status: `flux get helmreleases -A`
   - Analyze monitoring pod status: `kubectl get pods -n monitoring`
   - Review LoadBalancer service status: `kubectl get svc -A --field-selector spec.type=LoadBalancer`
   - Examine Helm release history: `helm history kube-prometheus-stack -n monitoring`

2. **Eliminate Duplicate HelmRelease Configurations**:

   - **Problem**: Two identical HelmReleases causing "missing target release for rollback" errors
   - **Solution**: Remove entire `apps/monitoring/` directory (legacy configuration):

     ```bash
     rm -rf apps/monitoring/
     ```

   - **Update Flux Configuration**: Remove `apps-monitoring` Kustomization from `clusters/home-ops/infrastructure/apps.yaml`
   - **Validation**: Verify only `infrastructure/monitoring/` remains as single source of truth

3. **Clean Corrupted Helm Release State**:

   - **Problem**: Corrupted Helm release preventing clean deployment
   - **Solution**: Delete failed Helm release:

     ```bash
     helm delete kube-prometheus-stack -n monitoring
     ```

   - **Result**: Allow Flux to redeploy cleanly from single authoritative source

4. **Fix LoadBalancer IPAM Controller Issues**:

   - **Problem**: Cilium IPAM controller stopped processing requests after monitoring stack deployment failures
   - **Solution**: Restart Cilium operator to reset IPAM controller state:

     ```bash
     kubectl delete pod -n kube-system -l io.cilium/app=operator
     ```

   - **Validation**: Monitor IPAM controller logs for resumed activity

5. **Resolve Service Selector Mismatch**:

   - **Problem**: IP pools configured to select services with `io.cilium/lb-ipam-pool` labels, but services only had annotations
   - **Solution**: Add required labels to all affected services:

     ```yaml
     # Add to service metadata
     labels:
       io.cilium/lb-ipam-pool: "bgp-default"
     ```

   - **Services Updated**: Monitoring services (Grafana, Prometheus, AlertManager) and Mosquitto service

6. **Deploy and Validate Complete Resolution**:

   - Commit all changes to Git repository
   - Monitor Flux reconciliation: `flux get kustomizations --watch`
   - Verify all monitoring services receive external IPs
   - Test external access to monitoring services
   - Validate BGP route advertisement for new IPs

**Critical Technical Fixes Applied:**

- **Configuration Deduplication**: Eliminated duplicate HelmRelease configurations causing Helm controller conflicts
- **Helm State Cleanup**: Deleted corrupted Helm release allowing clean redeployment from single authoritative source
- **IPAM Controller Recovery**: Restarted Cilium operator to reset LoadBalancer IPAM controller state after crash
- **Service Selector Fix**: Added required `io.cilium/lb-ipam-pool: "bgp-default"` labels to services
- **BGP Route Advertisement**: Verified all monitoring service IPs properly advertised via BGP and accessible from network
- **End-to-End Validation**: Confirmed complete monitoring stack functionality with external access and proper metric collection

**Important notes:**

- **Dual Root Causes**: Both duplicate HelmRelease conflicts AND LoadBalancer IPAM dysfunction required resolution
- **Renovate Impact**: Major version jump (v61.3.2 → v75.15.0) in duplicate locations caused systematic failures
- **Service Selector Requirements**: Cilium LoadBalancer IPAM requires services to have pool labels, not just annotations
- **IPAM Controller Fragility**: IPAM controller can crash during deployment failures and requires restart to resume processing
- **Single Source of Truth**: Maintaining single authoritative configuration source prevents duplicate conflicts

**Success Criteria:**

- ✅ All monitoring components running and healthy (Prometheus, Grafana, AlertManager, node-exporters, operators)
- ✅ All monitoring services have external IPs from BGP pools (Grafana: 172.29.52.101, Prometheus: 172.29.52.102, AlertManager: 172.29.52.103)
- ✅ Flux reconciliation completed successfully with no stuck loops
- ✅ BGP routes properly advertised for all monitoring service IPs
- ✅ Complete monitoring functionality validated with 29 healthy targets
- ✅ End-to-end monitoring pipeline operational with external access

**Troubleshooting:**

- **Duplicate HelmRelease errors**: Check for multiple directories containing identical HelmRelease configurations
- **IPAM controller failures**: Restart Cilium operator if LoadBalancer services stuck in pending state
- **Service selector mismatches**: Ensure services have required labels matching IP pool selectors
- **BGP advertisement issues**: Verify service labels match BGP policy service selectors
- **Helm state corruption**: Delete failed Helm releases to allow clean redeployment

This task represents a comprehensive recovery of a completely non-functional monitoring stack, demonstrating systematic troubleshooting methodology for complex GitOps and LoadBalancer IPAM issues.

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
   - Ensure only embedded outpost handles \*.k8s.home.geoffdavis.com domains
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
- Embedded outpost architecture requires NO individual service ingresses for \*.k8s.home.geoffdavis.com
- All services must be handled by embedded outpost ingress only
- Network connectivity must be verified between authentik namespace and service namespaces
- Manual proxy provider configuration may be required when automation fails

**Common Issues and Solutions:**

- **404/500 errors**: Usually indicates conflicting ingress configurations - remove individual service ingresses
- **Authentication loops**: Check that only embedded outpost handles \*.k8s.home.geoffdavis.com domains
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

   - List all ingresses handling \*.k8s.home.geoffdavis.com: `kubectl get ingress -A | grep k8s.home.geoffdavis.com`
   - Identify individual service ingresses that conflict with embedded outpost
   - Check embedded outpost ingress configuration: `kubectl get ingress -n authentik`

2. **Remove Individual Service Ingresses**:

   - Delete individual service ingress resources that handle \*.k8s.home.geoffdavis.com domains
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
- Embedded outpost architecture requires exclusive domain handling for \*.k8s.home.geoffdavis.com
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

   - List all ingresses handling \*.k8s.home.geoffdavis.com: `kubectl get ingress -A | grep k8s.home.geoffdavis.com`
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
   - Set up monitoring alerts for 404/500 responses from \*.k8s.home.geoffdavis.com services
   - Monitor Authentik outpost connectivity status
   - Alert on authentication response time degradation

**Important notes:**

- Early detection of ingress configuration conflicts prevents service outages
- Regular validation ensures embedded outpost maintains exclusive domain handling
- Proactive monitoring reduces manual troubleshooting and service disruption
- Authentication system health directly impacts all cluster services

**Monitoring Checklist:**

- [ ] All 6 services respond with proper authentication redirects
- [ ] Only embedded outpost ingress handles \*.k8s.home.geoffdavis.com domains
- [ ] No conflicting individual service ingresses exist
- [ ] Network connectivity between authentik and service namespaces is clear
- [ ] Authentik outpost status shows healthy in admin interface
- [ ] All proxy providers are operational and properly configured

### Prevent Authentication Configuration Conflicts

**Last performed:** Ongoing operational requirement
**Files to modify:** Various service configurations as needed

**Steps:**

1. **Service Deployment Guidelines**:

   - When adding new services to \*.k8s.home.geoffdavis.com domain:
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
This task addresses persistent connectivity issues where services at \*.k8s.home.geoffdavis.com remain inaccessible despite comprehensive authentication system restoration work. This represents a different class of issue than ingress configuration conflicts and may require network-level troubleshooting beyond Kubernetes configuration.

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
This task resolves BGP route advertisement failures where only services from the `bgp-default` pool were being advertised via BGP, while services from other pools (like `bgp-ingress`) were not advertised, causing 500 errors for \*.k8s.home.geoffdavis.com services.

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
- ✅ Network connectivity restored for \*.k8s.home.geoffdavis.com services
- ✅ BGP peering remains stable with multiple virtual routers

**Troubleshooting:**

- **Missing routes**: Check service pool annotations match IP pool names exactly
- **BGP peering issues**: Verify all virtual routers have identical neighbor configuration
- **Service connectivity**: Ensure DNS records point to correct advertised IPs
- **Pool conflicts**: Verify no duplicate pool selectors between virtual routers

This fix ensures robust BGP advertisement for all IP pools and resolves service connectivity issues caused by missing route advertisements.

## Development Quality and Security

### Setup Pre-commit Hooks

**Last performed:** July 2025 (successful implementation)
**Files to modify:**

- `.pre-commit-config.yaml` - Main pre-commit configuration
- `.yamllint.yaml` - YAML linting rules optimized for Kubernetes
- `.markdownlint.yaml` - Markdown validation focusing on structure
- `.secrets.baseline` - Secret detection baseline for false positives

**Steps:**

1. **One-time Setup**:

   - Install pre-commit tools: `mise install` (includes pre-commit in `.mise.toml`)
   - Setup pre-commit environment: `task pre-commit:setup`
   - Install git hooks: `task pre-commit:install`

2. **Verify Installation**:

   - Test all hooks: `task pre-commit:run`
   - Test security hooks only: `task pre-commit:security`
   - Test formatting hooks: `task pre-commit:format`

3. **Configure Baseline**:
   - Update secrets baseline: `detect-secrets scan --baseline .secrets.baseline`
   - Review and approve legitimate secrets in baseline
   - Commit baseline updates to repository

**Important notes:**

- **Balanced Enforcement**: Security and syntax issues block commits, formatting issues show warnings
- **Security Priority**: Secret detection and shell script security are enforced after security incident
- **Developer Friendly**: Formatting warnings don't block development workflow
- **Comprehensive Coverage**: Validates YAML, Python, Shell, Markdown, and Kubernetes manifests

### Daily Pre-commit Usage

**Last performed:** Ongoing development workflow
**Files to modify:** Various files during development

**Steps:**

1. **Automatic Validation**:

   - Make changes to files as normal
   - Commit changes: `git commit -m "your message"`
   - Pre-commit hooks run automatically
   - Fix any enforced issues (security, syntax) and commit again
   - Address formatting warnings when convenient

2. **Manual Validation**:

   - Run all enforced hooks: `task pre-commit:run`
   - Check formatting issues: `task pre-commit:format`
   - Security scan only: `task pre-commit:security`
   - Update hook versions: `task pre-commit:update`

3. **Maintenance Tasks**:
   - Clean pre-commit cache: `task pre-commit:clean`
   - Uninstall hooks: `task pre-commit:uninstall`
   - Emergency bypass: `SKIP=hook-name git commit`

**Important notes:**

- **Enforced Hooks**: Secret detection, YAML syntax, Kubernetes validation, Python syntax, shell script security
- **Warning Hooks**: Code formatting (prettier, black, isort), whitespace cleanup, commit message format
- **Real Issue Detection**: System identifies actual problems, not just style preferences
- **Fast Feedback**: Issues caught locally before reaching CI/CD pipeline

### Maintain Pre-commit System

**Last performed:** July 2025 (initial implementation)
**Files to modify:**

- `.pre-commit-config.yaml` - Hook versions and configuration
- `.secrets.baseline` - Secret detection baseline management
- `.yamllint.yaml` - YAML validation rules
- `.markdownlint.yaml` - Markdown validation rules

**Steps:**

1. **Regular Maintenance**:

   - Update hook versions: `task pre-commit:update`
   - Review and update `.secrets.baseline` when legitimate secrets change
   - Adjust validation rules based on false positives
   - Monitor hook effectiveness and performance

2. **Handle False Positives**:

   - Update `.secrets.baseline` for legitimate secrets
   - Adjust `.yamllint.yaml` for new Kubernetes patterns
   - Update exclusion patterns for generated files
   - Document any permanent exceptions

3. **Configuration Tuning**:

   - Review enforcement vs warning balance based on team feedback
   - Add new hooks for additional file types as needed
   - Optimize hook performance for large repositories
   - Update task commands for improved workflow

4. **Team Adoption**:
   - Train team members on pre-commit workflow
   - Document troubleshooting procedures
   - Monitor adoption and address resistance
   - Collect feedback for continuous improvement

**Important notes:**

- **Baseline Management**: Keep `.secrets.baseline` current with legitimate secrets
- **Performance Monitoring**: Ensure hooks don't slow down development workflow significantly
- **Team Communication**: Changes to enforcement levels should be communicated to team
- **Documentation**: Keep task commands and troubleshooting guides updated

### Troubleshoot Pre-commit Issues

**Last performed:** As needed during development
**Files to modify:** Various configuration files as needed

**Steps:**

1. **Common Issues and Solutions**:

   - **Hook fails to run**: Check tool installation with `mise install`
   - **False positive secrets**: Update `.secrets.baseline` with `detect-secrets scan --baseline .secrets.baseline`
   - **YAML validation errors**: Check syntax with `yamllint -c .yamllint.yaml <file>`
   - **Kubernetes validation fails**: Verify manifest syntax with `kubectl apply --dry-run=client -f <file>`
   - **Python syntax errors**: Check with `python -m py_compile <file>`

2. **Performance Issues**:

   - Clean pre-commit cache: `task pre-commit:clean`
   - Skip slow hooks temporarily: `SKIP=hook-name git commit`
   - Update to latest hook versions: `task pre-commit:update`
   - Review file exclusion patterns in `.pre-commit-config.yaml`

3. **Emergency Procedures**:

   - Bypass all hooks: `git commit --no-verify`
   - Skip specific hook: `SKIP=hook-name git commit`
   - Uninstall hooks temporarily: `task pre-commit:uninstall`
   - Reinstall after fixes: `task pre-commit:install`

4. **Configuration Debugging**:
   - Test specific hook: `pre-commit run <hook-name> --all-files`
   - Verbose output: `pre-commit run --verbose`
   - Check hook configuration: `pre-commit run --show-diff-on-failure`
   - Validate configuration: `pre-commit validate-config`

**Important notes:**

- **Emergency Bypasses**: Use `--no-verify` sparingly and fix issues promptly
- **Team Communication**: Notify team of any temporary hook disabling
- **Root Cause Analysis**: Address underlying issues rather than just bypassing hooks
- **Documentation**: Update troubleshooting procedures based on new issues encountered

This task documentation helps maintain consistency and provides clear procedures for the comprehensive pre-commit system implementation.
