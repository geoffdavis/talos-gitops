# Mise Tool Management

## Overview
This project uses [mise](https://mise.jdx.dev/) to manage development tools and their versions. Mise ensures consistent tool versions across different environments and automatically installs required tools when entering the project directory.

## Managed Tools
The following tools are managed by mise (as configured in `.mise.toml`):

- **task**: Task runner for executing project workflows
- **talhelper**: Tool for generating Talos configurations
- **talosctl**: Talos cluster management CLI
- **kubectl**: Kubernetes command-line tool
- **flux**: GitOps toolkit CLI
- **helm**: Kubernetes package manager
- **kustomize**: Kubernetes configuration management

## Usage
When working with this project:

1. **Automatic Tool Installation**: Mise will automatically install required tools when you enter the project directory
2. **Version Consistency**: All tools will be at the versions specified in `.mise.toml`
3. **Command Execution**: Use commands directly (e.g., `task bootstrap:secrets`) - mise handles the tool resolution

## Important Notes
- Always use mise-managed commands rather than globally installed versions
- Tool versions are locked to ensure reproducible builds and deployments
- If you encounter tool-related issues, run `mise install` to ensure all tools are properly installed

## Bootstrap Process
All bootstrap commands should be executed using the mise-managed tools:
- `task bootstrap:secrets`
- `task talos:generate-config`
- `task talos:apply-config`
- `task talos:bootstrap`
- `task bootstrap:1password-secrets`
- `task apps:deploy-core`
- `task flux:bootstrap`