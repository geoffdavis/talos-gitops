# Home Assistant Stack - Home Automation Platform

## Overview

This directory contains the complete Home Assistant stack deployment for the Talos GitOps home-ops cluster. The stack provides a comprehensive home automation platform with database backend, MQTT communication, and seamless SSO integration.

## Architecture

### Current Production Stack

- **Home Assistant Core v2025.7**: Main automation platform with web interface
- **PostgreSQL Database**: CloudNativePG cluster for persistent storage with automatic certificate management
- **Mosquitto MQTT**: IoT device communication broker with resolved port binding conflicts
- **Redis Cache**: Session storage and performance optimization
- **Authentication Integration**: Full SSO via external Authentik outpost at https://homeassistant.k8s.home.geoffdavis.com

### Configuration Management Evolution

**Previous Approach (Static ConfigMap)**:

- Used static ConfigMap that overrode `configuration.yaml`
- Prevented UI-based configuration changes
- Not compatible with modern Home Assistant workflows

**New Approach (User Data Volume)**:

- Minimal bootstrap configuration for infrastructure settings only
- Full user control over configuration through Home Assistant UI
- Persistent configuration changes that survive pod restarts
- Multiple methods for advanced configuration editing

## Migration to User Data Volume Configuration

### Migration Status

🚧 **READY FOR IMPLEMENTATION** - Complete migration plan and documentation available

### Key Benefits

- **UI-First Configuration**: Configure Home Assistant through the web interface
- **Persistent Changes**: Configuration changes survive pod restarts and updates
- **GitOps Compatibility**: Essential infrastructure settings remain version-controlled
- **Flexibility**: Multiple methods for advanced configuration editing when needed
- **Backup Integration**: Configuration included in existing Longhorn backup strategy

### Implementation Documents

1. **[HOME_ASSISTANT_CONFIG_MIGRATION.md](./HOME_ASSISTANT_CONFIG_MIGRATION.md)**
   - Complete migration plan with all implementation files
   - Step-by-step migration process
   - Rollback procedures and safety measures
   - Technical implementation details

2. **[CONFIGURATION_MANAGEMENT_GUIDE.md](./CONFIGURATION_MANAGEMENT_GUIDE.md)**
   - Comprehensive guide for managing configuration post-migration
   - Multiple access methods for different user preferences
   - Common configuration tasks and examples
   - Security considerations and best practices

3. **[HOME_ASSISTANT_OPERATIONAL_PROCEDURES.md](./HOME_ASSISTANT_OPERATIONAL_PROCEDURES.md)**
   - Detailed operational procedures for migration execution
   - Pre-migration checklists and verification steps
   - Post-migration maintenance and monitoring procedures
   - Troubleshooting guide for common issues

## Quick Start - Migration Implementation

### Prerequisites

- Kubernetes cluster with Longhorn storage operational
- PostgreSQL, MQTT, and Redis services running
- Current Home Assistant deployment healthy
- Backup systems operational

### Migration Steps

1. **Backup Current Configuration**

   ```bash
   kubectl exec -n home-automation deployment/home-assistant -- tar -czf /tmp/ha-backup.tar.gz -C /config .
   kubectl cp home-automation/$(kubectl get pod -n home-automation -l app.kubernetes.io/name=home-assistant -o jsonpath='{.items[0].metadata.name}'):/tmp/ha-backup.tar.gz ./ha-backup.tar.gz
   ```

2. **Apply New Resources**

   ```bash
   # Create bootstrap ConfigMap and initialization job
   # (See HOME_ASSISTANT_OPERATIONAL_PROCEDURES.md for complete commands)
   ```

3. **Update Deployment**

   ```bash
   # Remove static ConfigMap mount and update deployment
   # (See migration documentation for detailed steps)
   ```

4. **Verify and Test**
   ```bash
   # Verify deployment health and test functionality
   # (See verification procedures in operational guide)
   ```

## Configuration Access Methods

### Method 1: Home Assistant Web Interface (Recommended)

- Navigate to https://homeassistant.k8s.home.geoffdavis.com
- Use Configuration → Settings for most options
- Perfect for integrations, automations, and user preferences

### Method 2: Direct Container Access (Advanced)

```bash
kubectl exec -it -n home-automation deployment/home-assistant -- /bin/bash
nano /config/configuration.yaml
```

### Method 3: File Manager Pod (Extended Editing)

```bash
# Deploy file manager with web interface
# (See CONFIGURATION_MANAGEMENT_GUIDE.md for setup)
```

### Method 4: VS Code Remote Development

- Use VS Code with Remote-Containers extension
- Professional development environment with syntax highlighting

## Current Deployment Structure

```
apps/home-automation/
├── README.md                                    # This file
├── HOME_ASSISTANT_CONFIG_MIGRATION.md          # Migration implementation guide
├── CONFIGURATION_MANAGEMENT_GUIDE.md           # Post-migration configuration guide
├── HOME_ASSISTANT_OPERATIONAL_PROCEDURES.md    # Operational procedures
├── namespace.yaml                               # Namespace with privileged security policy
├── kustomization.yaml                           # Kustomization configuration
├── home-assistant/
│   ├── deployment.yaml                          # Home Assistant deployment
│   ├── service.yaml                             # Service definition
│   ├── pvc.yaml                                 # Persistent volume claim (10Gi)
│   ├── configmap.yaml                           # Current static configuration (to be replaced)
│   ├── external-secret.yaml                    # 1Password secret integration
│   └── kustomization.yaml                       # Home Assistant component kustomization
├── postgresql/                                  # PostgreSQL database cluster
├── mosquitto/                                   # MQTT broker
├── redis/                                       # Redis cache
└── matter-server/                               # Matter/Thread support
```

## Post-Migration Structure

```
apps/home-automation/home-assistant/
├── deployment.yaml                              # Updated deployment (no ConfigMap mount)
├── service.yaml                                 # Service definition (unchanged)
├── pvc.yaml                                     # Persistent volume claim (unchanged)
├── bootstrap-configmap.yaml                    # Minimal bootstrap configuration
├── config-init-job.yaml                        # Configuration initialization job
├── external-secret.yaml                        # 1Password secret integration (unchanged)
└── kustomization.yaml                           # Updated kustomization
```

## Security Considerations

### Current Security Context

- **Namespace**: `pod-security.kubernetes.io/enforce: privileged` (required for s6-overlay)
- **Container Security**: Privileged mode with specific capabilities for Home Assistant init system
- **File Permissions**: Configuration owned by user 1000 (Home Assistant user)
- **Network Security**: Protected by external Authentik outpost with proper proxy headers

### Secret Management

- Database credentials managed via 1Password Connect
- MQTT credentials stored in Kubernetes secrets
- Location data (latitude/longitude) stored securely
- No secrets stored in configuration files

## Backup and Recovery

### Automatic Backups

- **Longhorn Integration**: Configuration directory included in regular volume snapshots
- **Database Backups**: PostgreSQL cluster has automated backup strategy
- **Backup Labels**: PVC labeled for critical backup tier

### Manual Backup Procedures

```bash
# Create configuration backup
kubectl exec -n home-automation deployment/home-assistant -- tar -czf /tmp/config-backup.tar.gz -C /config .
kubectl cp home-automation/$(kubectl get pod -n home-automation -l app.kubernetes.io/name=home-assistant -o jsonpath='{.items[0].metadata.name}'):/tmp/config-backup.tar.gz ./config-backup.tar.gz
```

### Recovery Procedures

- Full recovery procedures documented in operational guide
- Rollback procedures available if migration issues occur
- Database recovery handled by PostgreSQL cluster operator

## Monitoring and Observability

### Health Checks

- **Liveness Probe**: HTTP check on port 8123
- **Readiness Probe**: Ensures service is ready to accept traffic
- **Startup Probe**: Extended startup time for Home Assistant initialization

### Metrics Integration

- Home Assistant metrics available via Prometheus integration
- Grafana dashboards for system health monitoring
- Alerts configured for critical failures

### Log Management

- Structured logging with configurable levels
- Integration with cluster logging infrastructure
- Debug logging available for troubleshooting

## Troubleshooting

### Common Issues

1. **Configuration Not Loading**: Check file permissions and YAML syntax
2. **Database Connection Issues**: Verify PostgreSQL cluster status and credentials
3. **MQTT Integration Problems**: Check Mosquitto broker connectivity
4. **Authentication Failures**: Verify external Authentik outpost configuration

### Diagnostic Commands

```bash
# Check deployment status
kubectl get pods -n home-automation -l app.kubernetes.io/name=home-assistant

# View logs
kubectl logs -n home-automation deployment/home-assistant --tail=50

# Validate configuration
kubectl exec -n home-automation deployment/home-assistant -- python -m homeassistant --script check_config --config /config
```

## Support and Documentation

### Internal Documentation

- Complete migration and operational procedures included
- Configuration management guide for different user scenarios
- Troubleshooting procedures for common issues

### External Resources

- [Home Assistant Documentation](https://www.home-assistant.io/docs/)
- [Home Assistant Community](https://community.home-assistant.io/)
- [CloudNativePG Documentation](https://cloudnative-pg.io/documentation/)

## Next Steps

1. **Review Migration Documentation**: Read through all migration documents
2. **Plan Migration Window**: Schedule migration during low-usage period
3. **Execute Migration**: Follow operational procedures step-by-step
4. **Validate Functionality**: Test all integrations and configurations
5. **Update GitOps Repository**: Commit changes to version control
6. **Monitor and Maintain**: Follow ongoing maintenance procedures

This migration enables modern Home Assistant configuration management while maintaining the infrastructure-level control that GitOps provides. The result is a flexible, maintainable, and user-friendly home automation platform.
