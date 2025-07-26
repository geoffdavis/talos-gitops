# Pre-Commit Workflow Documentation

## README.md Section Addition

Add this section to the main README.md file under a "Development Workflow" or "Contributing" section:

---

## 🔒 Pre-Commit Hooks

This repository uses pre-commit hooks to ensure code quality, security, and consistency. The hooks follow a **balanced approach**: critical security and syntax issues block commits, while formatting issues show warnings but allow commits to proceed.

### Quick Start

```bash
# Install pre-commit hooks (one-time setup)
task pre-commit:install

# Or manually:
mise install pre-commit detect-secrets gitleaks shellcheck markdownlint-cli
pre-commit install
pre-commit install --hook-type commit-msg
```

### Daily Workflow

1. **Make your changes** as normal
2. **Commit your changes** - hooks run automatically
   - 🚫 **Security/syntax issues** block the commit
   - ⚠️ **Formatting issues** show warnings but allow commit
3. **Fix critical issues** if commit is blocked
4. **Optional**: Run `task pre-commit:format` to fix formatting warnings

### Hook Categories

#### 🚫 ENFORCED (Blocks commits)

- 🔒 **Secret detection** (detect-secrets, gitleaks)
- 📋 **YAML syntax** (yamllint)
- ☸️ **Kubernetes validation** (kubeval, kustomize)
- 🐍 **Python syntax** (check-ast)
- 🐚 **Shell script security** (shellcheck)
- 📝 **Markdown structure** (markdownlint basic checks)
- 📏 **File size limits** (1MB max)
- 🔤 **File encoding** issues

#### ⚠️ WARNING (Allows commits)

- 💅 **Code formatting** (prettier, black, isort)
- 🐍 **Python linting** (flake8)
- 📝 **Markdown style** (prettier)
- 🧹 **Whitespace issues**
- 💬 **Commit message format** (conventional commits)

### Common Commands

```bash
# Run all hooks on all files
task pre-commit:run

# Run security hooks only
task pre-commit:security-scan

# Run formatting hooks (warnings)
task pre-commit:format

# Run validation hooks only
task pre-commit:validate

# Update hook versions
task pre-commit:update

# Clean cache if issues
task pre-commit:clean
```

### Bypassing Hooks (Emergency Only)

```bash
# Skip all hooks (use sparingly)
git commit --no-verify -m "emergency: bypass hooks"

# Skip specific hooks
SKIP=detect-secrets,gitleaks git commit -m "skip security hooks"
```

### Security Features

After the [security incident](SECURITY_INCIDENT_REPORT.md), these hooks provide critical protection:

- **🔒 Multi-layer secret detection** prevents credential commits
- **📏 File size limits** prevent accidental large file commits
- **🐚 Shell script security** catches dangerous patterns
- **☸️ Infrastructure validation** ensures valid Kubernetes manifests

### Troubleshooting

#### Hook Installation Issues

```bash
pre-commit uninstall && pre-commit install
pre-commit install --hook-type commit-msg
```

#### Performance Issues

```bash
# Clear cache
pre-commit clean

# Skip slow hooks for testing
SKIP=kubeval,pytest-critical pre-commit run --all-files
```

#### False Positives in Secret Detection

```bash
# Update secrets baseline
detect-secrets scan --baseline .secrets.baseline
git add .secrets.baseline
git commit -m "security: update secrets baseline"
```

### Configuration Files

- **`.pre-commit-config.yaml`** - Main hook configuration
- **`.yamllint.yaml`** - YAML linting rules
- **`.markdownlint.yaml`** - Markdown linting rules
- **`.secrets.baseline`** - Known false positives for secret detection

### Documentation

- 📋 **[Implementation Plan](docs/PRE_COMMIT_IMPLEMENTATION_PLAN.md)** - Comprehensive setup guide
- 🧪 **[Testing Guide](docs/PRE_COMMIT_TESTING_GUIDE.md)** - Validation and testing procedures

---

## Additional Files to Update

### 1. .gitignore Additions

Add these lines to the existing `.gitignore` file:

```gitignore
# Pre-commit cache
.pre-commit-cache/

# Secret scanning
.secrets.baseline.tmp
```

### 2. Taskfile.yml Additions

Add this include to the main `Taskfile.yml`:

```yaml
includes:
  pre-commit: ./taskfiles/pre-commit.yml
```

### 3. .mise.toml Additions

Add these tools and tasks to the existing `.mise.toml`:

```toml
# Pre-commit tools
pre-commit = "latest"
detect-secrets = "latest"  # pragma: allowlist secret
gitleaks = "latest"
shellcheck = "latest"
markdownlint-cli = "latest"

[tasks.setup-pre-commit]
description = "Setup pre-commit hooks"
run = """
  mise install pre-commit detect-secrets gitleaks shellcheck markdownlint-cli
  pre-commit install
  pre-commit install --hook-type commit-msg
  detect-secrets scan --baseline .secrets.baseline
"""

[tasks.pre-commit-all]
description = "Run all pre-commit hooks"
run = "pre-commit run --all-files"

[tasks.pre-commit-security]
description = "Run security pre-commit hooks"
run = """
  pre-commit run detect-secrets --all-files
  pre-commit run gitleaks --all-files
"""
```

## Implementation Checklist

### Phase 1: Core Setup (Immediate)

- [ ] Create `.pre-commit-config.yaml` from implementation plan
- [ ] Create `.yamllint.yaml` configuration
- [ ] Create `.markdownlint.yaml` configuration
- [ ] Create `.secrets.baseline` file
- [ ] Update `.gitignore` with pre-commit cache
- [ ] Install pre-commit framework: `mise install pre-commit`

### Phase 2: Security Focus (Day 1)

- [ ] Install security tools: `mise install detect-secrets gitleaks`
- [ ] Create initial secrets baseline: `detect-secrets scan --baseline .secrets.baseline`
- [ ] Test secret detection with fake credentials
- [ ] Run security scan on entire repository
- [ ] Fix any detected issues

### Phase 3: Validation Setup (Day 2)

- [ ] Install validation tools: `mise install shellcheck markdownlint-cli`
- [ ] Create `taskfiles/pre-commit.yml` with management tasks
- [ ] Update main `Taskfile.yml` to include pre-commit tasks
- [ ] Test YAML and Kubernetes validation
- [ ] Test shell script and Python validation

### Phase 4: Integration (Day 3)

- [ ] Install hooks: `pre-commit install && pre-commit install --hook-type commit-msg`
- [ ] Run full validation: `pre-commit run --all-files`
- [ ] Fix any validation failures
- [ ] Test commit workflow with sample changes
- [ ] Update README.md with workflow documentation

### Phase 5: Team Rollout (Week 1)

- [ ] Document troubleshooting procedures
- [ ] Create team training materials
- [ ] Test performance with large changesets
- [ ] Set up automated testing of hook configuration
- [ ] Monitor and adjust hook sensitivity

## Success Metrics

### Security Improvements

- ✅ Zero credential commits after implementation
- ✅ All shell scripts pass security validation
- ✅ No large files accidentally committed
- ✅ All team members using hooks consistently

### Quality Improvements

- ✅ Consistent YAML formatting across manifests
- ✅ Valid Kubernetes manifests in all commits
- ✅ Python code meets basic quality standards
- ✅ Documentation follows markdown standards

### Developer Experience

- ✅ Commit process remains fast (< 10 seconds typical)
- ✅ Clear error messages for blocked commits
- ✅ Easy bypass for emergency situations
- ✅ Formatting warnings don't block productivity

## Maintenance

### Weekly Tasks

- [ ] Review any new false positives in secret detection
- [ ] Check for pre-commit hook updates: `task pre-commit:update`
- [ ] Monitor hook performance and adjust if needed

### Monthly Tasks

- [ ] Review and update `.secrets.baseline` if needed
- [ ] Audit bypassed commits for patterns
- [ ] Update hook configurations based on team feedback
- [ ] Review security scan results and trends

### Quarterly Tasks

- [ ] Full security audit of hook effectiveness
- [ ] Performance optimization review
- [ ] Team feedback collection and process improvements
- [ ] Update documentation based on lessons learned

This comprehensive pre-commit strategy provides robust protection while maintaining developer productivity, directly addressing the security concerns from the incident report while supporting the sophisticated GitOps workflow of the Talos cluster.
