# Home Assistant Stack

## Overview

The Home Assistant stack provides a comprehensive home automation platform deployed on the Talos GitOps cluster. This deployment includes Home Assistant Core, PostgreSQL database, Mosquitto MQTT broker, and Redis cache, all integrated with the cluster's authentication and monitoring systems.

## Quick Access

- **Home Assistant Web Interface**: https://homeassistant.k8s.home.geoffdavis.com
- **Authentication**: Seamless SSO via external Authentik outpost
- **Namespace**: `home-automation`

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Home Assistant Stack                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌──────────────┐ │
│  │  Home Assistant │    │   PostgreSQL    │    │  Mosquitto   │ │
│  │    (Core)       │◄──►│   (Database)    │    │   (MQTT)     │ │
│  │   Port: 8123    │    │   Port: 5432    │    │  Port: 1883  │ │
│  └─────────────────┘    └─────────────────┘    └──────────────┘ │
│           │                       │                      │      │
│           │              ┌─────────────────┐             │      │
│           └─────────────►│     Redis       │◄────────────┘      │
│                          │    (Cache)      │                    │
│                          │   Port: 6379    │                    │
│                          └─────────────────┘                    │
│                                   │                             │
│                          ┌─────────────────┐                    │
│                          │  Matter Server  │                    │
│                          │ (Thread/Matter) │                    │
│                          │   Port: 5580    │                    │
│                          └─────────────────┘                    │
│                                   │                             │
│                          ┌─────────────────┐                    │
│                          │ Matter/Thread   │                    │
│                          │    Devices      │                    │
│                          └─────────────────┘                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Components

- **Home Assistant Core (v2025.7)**: Main home automation platform and web interface
- **PostgreSQL (v16.4)**: Persistent storage with CloudNativePG operator
- **Mosquitto MQTT (v2.0.18)**: IoT device communication broker
- **Redis**: Session storage and performance caching
- **Matter Server (v8.0.0)**: Thread/Matter device support and commissioning

## Quick Commands

```bash
# Check stack status
kubectl get pods -n home-automation

# View Home Assistant logs
kubectl logs -n home-automation -l app.kubernetes.io/name=home-assistant

# View Matter Server logs
kubectl logs -n home-automation -l app.kubernetes.io/name=matter-server

# Access Home Assistant shell
kubectl exec -it -n home-automation deployment/home-assistant -- bash

# Restart Home Assistant
kubectl rollout restart deployment home-assistant -n home-automation

# Check database status
kubectl get cluster homeassistant-postgresql -n home-automation

# Check Matter Server status
kubectl get pods -n home-automation -l app.kubernetes.io/name=matter-server
```

## Key Files

- **Main Configuration**: [`home-assistant/configmap.yaml`](home-assistant/configmap.yaml)
- **Deployment**: [`home-assistant/deployment.yaml`](home-assistant/deployment.yaml)
- **Secrets**: [`home-assistant/external-secret.yaml`](home-assistant/external-secret.yaml)
- **Database**: [`postgresql/cluster.yaml`](postgresql/cluster.yaml)
- **MQTT Broker**: [`mosquitto/deployment.yaml`](mosquitto/deployment.yaml)
- **Matter Server**: [`matter-server/helmrelease.yaml`](matter-server/helmrelease.yaml)
- **Matter Documentation**: [`matter-server/README.md`](matter-server/README.md)
- **Backup Strategy**: [`BACKUP_STRATEGY.md`](BACKUP_STRATEGY.md)

## 📖 Complete Documentation

**For comprehensive documentation including architecture details, configuration management, operational procedures, security considerations, and troubleshooting guides, see:**

### [**📋 HOME_ASSISTANT_DEPLOYMENT.md**](../../docs/HOME_ASSISTANT_DEPLOYMENT.md)

The complete documentation covers:

- **Architecture & Components**: Detailed component descriptions and connections
- **Authentication & Access**: External Authentik outpost integration and SSO flow
- **Configuration Management**: YAML configuration files and update procedures
- **Operational Procedures**: Deployment, upgrades, monitoring, and health checks
- **Security Considerations**: 1Password integration, network security, and TLS encryption
- **Development & Customization**: Adding custom integrations and scaling considerations
- **Troubleshooting**: Common issues and resolution procedures

## Support Resources

- **Home Assistant Documentation**: https://www.home-assistant.io/docs/
- **CNPG Documentation**: https://cloudnative-pg.io/documentation/
- **Mosquitto Documentation**: https://mosquitto.org/documentation/
- **Cluster Documentation**: [../../docs/](../../docs/)

---

_This README provides a quick overview. For detailed information, configuration procedures, and operational guidance, refer to the [complete documentation](../../docs/HOME_ASSISTANT_DEPLOYMENT.md)._
