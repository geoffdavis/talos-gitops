# Development

This section contains information for developers and contributors working on the cluster.

## Quick Navigation

- [Contributing](contributing.md) - Development guidelines and contribution process
- [Testing](testing.md) - Testing procedures and validation
- [Code Quality](code-quality.md) - Pre-commit hooks and quality standards

## Development Environment

The cluster uses several tools for development and maintenance:

### Required Tools (via mise)

- **task v3.38.0+**: Task runner for automation
- **talosctl v1.10.5+**: Talos CLI tool
- **kubectl v1.31.1+**: Kubernetes CLI
- **flux v2.4.0+**: Flux CLI
- **helm v3.16.1+**: Kubernetes package manager

### Code Quality Tools

- **detect-secrets**: Secret detection and baseline management
- **yamllint**: YAML syntax and style validation
- **shellcheck**: Shell script analysis and security
- **pre-commit**: Git hook framework for code quality

## Development Workflow

### Setup Development Environment

```bash
# Install mise for tool management
curl https://mise.jdx.dev/install.sh | sh

# Install all required tools
mise install

# Configure environment
cp .env.example .env
# Edit .env to set OP_ACCOUNT
```

### Code Quality Workflow

```bash
# Pre-commit setup (one-time)
task pre-commit:setup
task pre-commit:install

# Daily development workflow
git add .
git commit -m "your changes"  # Hooks run automatically

# Manual validation
task pre-commit:run           # All enforced hooks
task pre-commit:format        # Formatting checks (warnings)
task pre-commit:security      # Security scans only
```

## Testing

### Cluster Testing

```bash
# Run comprehensive tests
task test:all

# Specific test categories
task test:config       # Configuration validation
task test:connectivity # Network connectivity
task test:extensions   # Talos extensions
task test:usb-storage  # USB SSD storage validation
```

### Component Testing

```bash
# Core idempotency test
task apps:verify-core-idempotency

# Storage validation
task storage:check-longhorn

# Network validation
task network:check-ipv6
```

For detailed development procedures, see the individual guides in this section.
