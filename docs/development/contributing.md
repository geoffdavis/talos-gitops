# Contributing Guidelines

This document provides comprehensive guidelines for contributing to the Talos GitOps home-ops cluster project. Whether you're adding new features, fixing bugs, or improving documentation, these guidelines will help ensure high-quality contributions that align with project standards.

## Table of Contents

- [Getting Started](#getting-started)
- [Development Environment Setup](#development-environment-setup)
- [Code Quality Standards](#code-quality-standards)
- [Contribution Workflow](#contribution-workflow)
- [Documentation Standards](#documentation-standards)
- [Infrastructure Changes](#infrastructure-changes)
- [Testing Requirements](#testing-requirements)
- [Review Process](#review-process)
- [Release Management](#release-management)

## Getting Started

### Prerequisites

Before contributing, ensure you have:

- **Git**: Version control system for code management
- **GitHub Account**: Access to the repository
- **mise**: Tool version management (recommended)
- **1Password CLI**: Secret management access
- **Cluster Access**: kubectl and talosctl configured

### Repository Structure

Understanding the project structure is crucial for effective contributions:

```text
├── .kilocode/                  # Kilo Code AI configuration
├── apps/                       # Application deployments
├── charts/                     # Custom Helm charts
├── clusters/                   # GitOps cluster configuration
├── docs/                       # Project documentation
├── infrastructure/             # Infrastructure service manifests
├── scripts/                    # Automation and utility scripts
├── talos/                      # Talos OS configuration
├── taskfiles/                  # Modular task definitions
├── tests/                      # Test suites
├── .pre-commit-config.yaml     # Code quality hooks
├── Taskfile.yml               # Main task automation
└── talconfig.yaml             # Talos cluster configuration
```

### Contribution Areas

We welcome contributions in these areas:

1. **Infrastructure Services**: New infrastructure components and improvements
2. **Applications**: Application deployments and configurations
3. **Documentation**: Guides, procedures, and architectural documentation
4. **Automation**: Scripts, tasks, and CI/CD improvements
5. **Testing**: Test suites and validation procedures
6. **Security**: Security hardening and best practices

## Development Environment Setup

### Initial Setup

```bash
# 1. Clone the repository
git clone https://github.com/your-username/talos-gitops.git
cd talos-gitops

# 2. Install development tools
curl https://mise.jdx.dev/install.sh | sh
mise install

# 3. Set up environment configuration
cp .env.example .env
# Edit .env with your 1Password account information

# 4. Install pre-commit hooks
task pre-commit:setup
task pre-commit:install

# 5. Verify setup
task cluster:status  # If you have cluster access
pre-commit run --all-files
```

### Tool Requirements

The project uses specific tool versions managed by mise:

```bash
# Check required tools
mise list

# Key tools and versions:
# - task v3.38.0+
# - kubectl v1.31.1+
# - helm v3.16.1+
# - flux v2.4.0+
# - talosctl v1.10.5+
# - cilium v0.16.16+
# - yq v4.44.3+
# - jq v1.7.1+
# - op v2.0.0+
```

### IDE Configuration

#### VS Code (Recommended)

Install these extensions for optimal development experience:

- **YAML**: YAML language support
- **Kubernetes**: Kubernetes resource editing
- **GitLens**: Git history and blame information
- **markdownlint**: Markdown validation
- **Prettier**: Code formatting

#### Configuration Files

The project includes configuration for:

- `.yamllint.yaml`: YAML linting rules
- `.markdownlint.yaml`: Markdown validation
- `.pre-commit-config.yaml`: Automated code quality checks

## Code Quality Standards

The project implements a balanced enforcement approach prioritizing security and syntax validation while treating formatting as warnings.

### Pre-commit System

#### Enforced Checks (Block Commits)

These issues **must** be fixed before committing:

```bash
# Security checks
detect-secrets      # Secret detection
gitleaks           # Git repository secret scanning
shellcheck         # Shell script security and best practices

# Syntax validation
yamllint           # YAML syntax validation
check-yaml         # YAML file validation
kubectl-validate   # Kubernetes manifest validation
python-syntax      # Python syntax checking
kustomize-validate # Kustomize build validation
```

#### Warning Checks (Advisory)

These issues are **recommended** to fix but don't block commits:

```bash
# Code formatting
prettier           # YAML and Markdown formatting
black              # Python code formatting
isort              # Python import sorting
markdownlint       # Markdown structure validation

# General file checks
check-merge-conflict  # Merge conflict detection
trailing-whitespace   # Whitespace cleanup
end-of-file-fixer    # File ending normalization
```

### Running Quality Checks

```bash
# Run all enforced checks
task pre-commit:run

# Run formatting checks only
task pre-commit:format

# Run security checks only
task pre-commit:security

# Clean pre-commit cache
task pre-commit:clean

# Update hook versions
task pre-commit:update
```

### Handling Quality Issues

#### Secret Detection Issues

```bash
# Update baseline for legitimate secrets
detect-secrets scan --baseline .secrets.baseline

# Review and approve new baseline entries
vim .secrets.baseline

# Commit baseline updates
git add .secrets.baseline
git commit -m "security: update secrets baseline"
```

#### YAML Validation Issues

```bash
# Check specific file
yamllint -c .yamllint.yaml path/to/file.yaml

# Common fixes:
# - Fix indentation (2 spaces)
# - Remove trailing whitespace
# - Add final newline
# - Fix line length (max 120 characters)
```

#### Kubernetes Manifest Issues

```bash
# Validate specific manifest
kubectl apply --dry-run=client -f path/to/manifest.yaml

# Validate kustomization
kustomize build path/to/kustomization/ | kubectl apply --dry-run=client -f -

# Common fixes:
# - Fix API version compatibility
# - Correct resource field names
# - Add required fields
# - Fix label selectors
```

## Contribution Workflow

### Branch Strategy

We use a feature branch workflow:

```bash
# 1. Create feature branch
git checkout main
git pull origin main
git checkout -b feature/description-of-change

# 2. Make changes
# Edit files as needed

# 3. Commit changes
git add .
git commit -m "type: descriptive commit message"

# 4. Push branch
git push origin feature/description-of-change

# 5. Create pull request
# Use GitHub web interface
```

### Commit Message Standards

Follow conventional commit format:

```text
type(scope): description

[optional body]

[optional footer]
```

#### Commit Types

- `feat`: New feature or enhancement
- `fix`: Bug fix or correction
- `docs`: Documentation changes
- `refactor`: Code refactoring without functional changes
- `test`: Test additions or updates
- `chore`: Maintenance tasks
- `security`: Security-related changes

#### Examples

```bash
# Good commit messages
git commit -m "feat(monitoring): add disk space alerting rules"
git commit -m "fix(authentik): resolve external outpost connection issues"
git commit -m "docs(operations): add BGP troubleshooting procedures"
git commit -m "security(secrets): rotate 1Password Connect credentials"

# Poor commit messages (avoid these)
git commit -m "fixed stuff"
git commit -m "WIP"
git commit -m "updates"
```

### Bootstrap vs GitOps Changes

Understand the difference between change types (see [Bootstrap vs GitOps Decision Framework](../architecture/bootstrap-vs-gitops.md)):

#### Bootstrap Changes

Require direct task execution and special handling:

```bash
# Example: Updating Talos configuration
vim talconfig.yaml
task talos:generate-config
task talos:apply-config

# Commit bootstrap changes
git add talconfig.yaml clusterconfig/
git commit -m "bootstrap: update Talos node configuration"
```

#### GitOps Changes

Managed through standard Git workflow:

```bash
# Example: Adding new application
mkdir -p apps/new-app
vim apps/new-app/deployment.yaml
vim apps/new-app/service.yaml
vim apps/new-app/kustomization.yaml

# Test locally
kubectl apply --dry-run=client -k apps/new-app/

# Commit and push
git add apps/new-app/
git commit -m "feat(apps): add new application deployment"
git push origin feature/add-new-app
```

## Documentation Standards

### Documentation Types

1. **Architecture Documentation**: High-level design and decisions
2. **Operational Procedures**: Step-by-step operational guides
3. **Reference Documentation**: Technical specifications and examples
4. **Getting Started Guides**: Beginner-friendly tutorials

### Writing Guidelines

#### Markdown Standards

````markdown
# Use ATX-style headers (# ## ###)

# Start with level 1 header for document title

# Use descriptive headers with proper hierarchy

## Code Blocks

Always specify language for syntax highlighting:

```bash
kubectl get pods -A
```
````

```yaml
apiVersion: v1
kind: ConfigMap
```

## Links

Use relative links for internal documentation:
[Bootstrap Guide](../getting-started/bootstrap.md)

Use absolute URLs for external resources:
[Kubernetes Documentation](https://kubernetes.io/docs/)

## Lists

Use consistent list formatting:

- Unordered lists with hyphens
- **Bold** for emphasis
- `code` for technical terms

```bash
# Example code block
kubectl get pods
```

### Content Guidelines

1. **Be Specific**: Include exact commands, file paths, and error messages
2. **Provide Context**: Explain why something is needed, not just how
3. **Include Examples**: Show real-world usage patterns
4. **Update Regularly**: Keep information current with cluster state
5. **Cross-Reference**: Link to related documentation

### Documentation Structure

```text
docs/
├── architecture/           # System design and decisions
│   ├── README.md          # Architecture overview
│   └── bootstrap-vs-gitops.md
├── components/            # Component-specific documentation
│   ├── applications/      # Application guides
│   ├── networking/        # Network configuration
│   └── storage/          # Storage management
├── development/          # Development and contribution guides
│   └── contributing.md   # This document
├── getting-started/      # Beginner guides
│   ├── README.md         # Quick start
│   └── bootstrap.md      # Bootstrap procedures
├── operations/          # Operational procedures
│   ├── troubleshooting.md
│   └── disaster-recovery.md
└── reference/           # Technical reference
    └── advanced-configuration.md
```

## Infrastructure Changes

### Adding New Infrastructure Services

1. **Plan the Integration**:
   - Review [Architecture Documentation](../architecture/README.md)
   - Determine Bootstrap vs GitOps placement
   - Identify dependencies and requirements

2. **Create Service Manifests**:

   ```bash
   # Create service directory
   mkdir -p infrastructure/new-service

   # Add manifests
   vim infrastructure/new-service/namespace.yaml
   vim infrastructure/new-service/helmrelease.yaml
   vim infrastructure/new-service/kustomization.yaml
   ```

3. **Configure Dependencies**:

   ```bash
   # Add to appropriate infrastructure category
   vim clusters/home-ops/infrastructure/core.yaml  # or networking.yaml, storage.yaml, etc.
   ```

4. **Test Deployment**:

   ```bash
   # Validate manifests
   kubectl apply --dry-run=client -k infrastructure/new-service/

   # Test kustomization build
   kustomize build infrastructure/new-service/

   # Deploy to test environment first
   ```

### Adding New Applications

1. **Create Application Structure**:

   ```bash
   mkdir -p apps/new-app
   vim apps/new-app/namespace.yaml
   vim apps/new-app/deployment.yaml
   vim apps/new-app/service.yaml
   vim apps/new-app/kustomization.yaml
   ```

2. **Configure GitOps Integration**:

   ```bash
   # Add to apps configuration
   vim clusters/home-ops/infrastructure/apps.yaml
   ```

3. **Authentication Integration** (if needed):
   - Add service to authentik-proxy configuration
   - Configure ingress with proper annotations
   - Test SSO integration

### Security Considerations

#### Secret Management

- **Never commit secrets**: Use 1Password Connect integration
- **Use ExternalSecrets**: Manage secrets through ExternalSecret resources
- **Rotate regularly**: Update credentials on schedule

```yaml
# Example ExternalSecret
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: app-credentials
spec:
  secretStoreRef:
    name: onepassword-connect
    kind: SecretStore
  target:
    name: app-credentials
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: "Application Credentials"
        property: password
```

#### Network Security

- **Use Network Policies**: Restrict pod-to-pod communication
- **Proper Ingress Configuration**: Use authentication annotations
- **TLS Everywhere**: Configure certificate management

#### RBAC Configuration

- **Principle of Least Privilege**: Grant minimal required permissions
- **Use Service Accounts**: Don't use default service accounts
- **Regular Audits**: Review RBAC configurations periodically

## Testing Requirements

### Local Testing

Before submitting changes:

```bash
# 1. Run pre-commit checks
task pre-commit:run

# 2. Validate Kubernetes manifests
kubectl apply --dry-run=client -k path/to/changes/

# 3. Test kustomization builds
kustomize build path/to/changes/

# 4. Run relevant test suites
pytest tests/  # If Python scripts modified

# 5. Test in isolated environment if possible
```

### Integration Testing

For significant changes:

1. **Deploy to Test Environment**: Use isolated cluster or namespace
2. **Validate Functionality**: Test all affected services
3. **Check Dependencies**: Ensure no breaking changes
4. **Performance Testing**: Monitor resource usage

### Automated Testing

The project includes test suites for critical components:

```bash
# Run all tests
task test:all

# Run specific test suites
task test:authentik-proxy
task test:token-management

# Add new tests for new functionality
```

## Review Process

### Pull Request Requirements

Before submitting a pull request:

- [ ] Pre-commit checks pass
- [ ] Documentation updated
- [ ] Tests added/updated
- [ ] Manual testing completed
- [ ] Breaking changes documented

### Review Checklist

Reviewers should verify:

- [ ] **Code Quality**: Follows project standards
- [ ] **Security**: No secrets or security issues
- [ ] **Documentation**: Changes are documented
- [ ] **Testing**: Adequate test coverage
- [ ] **Functionality**: Changes work as intended
- [ ] **Dependencies**: No breaking changes

### Review Workflow

1. **Self-Review**: Review your own changes first
2. **Automated Checks**: Ensure CI passes
3. **Peer Review**: At least one team member review
4. **Testing**: Manual testing if significant changes
5. **Approval**: Maintainer approval for merge

### Addressing Review Comments

```bash
# Make requested changes
git add .
git commit -m "review: address feedback on error handling"

# Push updates
git push origin feature/branch-name

# The pull request updates automatically
```

## Release Management

### Versioning Strategy

We use semantic versioning for releases:

- **Major**: Breaking changes or significant rewrites
- **Minor**: New features or significant improvements
- **Patch**: Bug fixes or minor improvements

### Release Process

1. **Prepare Release**:
   - Update documentation
   - Run full test suite
   - Update CHANGELOG.md

2. **Create Release**:

   ```bash
   git tag -a v1.2.3 -m "Release v1.2.3"
   git push origin v1.2.3
   ```

3. **Deploy Changes**:
   - GitOps changes deploy automatically
   - Bootstrap changes require manual execution

4. **Validate Release**:
   - Monitor cluster health
   - Test critical functionality
   - Update operational documentation

### Hotfix Process

For critical issues requiring immediate fixes:

```bash
# Create hotfix branch from main
git checkout main
git checkout -b hotfix/critical-issue

# Make minimal fix
# Test thoroughly
# Create pull request with "hotfix" label
# Fast-track review and merge
# Deploy immediately if bootstrap change
```

## Best Practices

### General Guidelines

1. **Start Small**: Make incremental changes
2. **Test Thoroughly**: Don't skip testing steps
3. **Document Everything**: Update docs with changes
4. **Ask Questions**: Use discussions for clarification
5. **Follow Standards**: Consistency is important

### Common Pitfalls to Avoid

1. **Skipping Pre-commit**: Always run quality checks
2. **Large Pull Requests**: Keep changes focused and reviewable
3. **Missing Documentation**: Update docs with code changes
4. **Ignoring Dependencies**: Consider impact on other components
5. **Bypassing Reviews**: Don't merge without proper review

### Getting Help

- **Documentation**: Check existing docs first
- **Issues**: Search GitHub issues for similar problems
- **Discussions**: Use GitHub discussions for questions
- **Code Review**: Ask for help in pull request comments

## Advanced Topics

### Custom Helm Charts

When creating custom Helm charts:

```bash
# Create chart structure
mkdir -p charts/new-chart
cd charts/new-chart
helm create .

# Follow Helm best practices
# Add to charts directory
# Document chart usage
```

### Automation Scripts

When adding automation scripts:

```bash
# Use proper script structure
#!/bin/bash
set -euo pipefail

# Add error handling
# Include usage documentation
# Add to appropriate directory
```

### Testing Infrastructure

When adding test infrastructure:

```bash
# Create test directory
mkdir -p tests/new-component

# Add test files
vim tests/new-component/test_functionality.py

# Update test runner
vim Taskfile.yml  # Add test task
```

Remember: Contributing to infrastructure is a responsibility. Your changes affect the entire cluster and its users. Take time to understand the impact and test thoroughly.
