# Pre-Commit Implementation Plan for Talos GitOps Repository

## Overview

This document provides a comprehensive plan for implementing pre-commit hooks in the Talos GitOps repository with a **balanced approach** - core security and syntax checks are enforced, while formatting issues generate warnings but don't block commits.

## Implementation Strategy

### Philosophy: Balanced Enforcement

- **ENFORCED (Blocks commits)**: Security issues, syntax errors, critical validation failures
- **WARNING (Allows commits)**: Formatting issues, style violations, non-critical linting

### File Types Analysis

Based on repository analysis, we need to handle:

- **YAML files**: Kubernetes manifests, Helm charts, Flux configurations
- **Python scripts**: Authentication management, token management, testing
- **Shell scripts**: Bootstrap, deployment, validation scripts
- **Markdown files**: Extensive documentation
- **Configuration files**: Taskfile, mise, gitignore, etc.

## Pre-Commit Configuration

### 1. Core Pre-Commit Config (`.pre-commit-config.yaml`)

```yaml
# Pre-commit configuration for Talos GitOps repository
# Philosophy: Balanced approach - security enforced, formatting as warnings

repos:
  # ============================================================================
  # SECURITY HOOKS (ENFORCED - CRITICAL)
  # ============================================================================

  # Secret detection - CRITICAL after security incident
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.4.0
    hooks:
      - id: detect-secrets
        name: 🔒 Detect secrets
        args: ["--baseline", ".secrets.baseline"]
        exclude: |
          (?x)^(
            \.git/.*|
            .*\.lock|
            .*\.log|
            SECURITY_INCIDENT_REPORT\.md
          )$

  # Git leaks detection
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
        name: 🔒 Git leaks scan

  # ============================================================================
  # YAML VALIDATION (ENFORCED)
  # ============================================================================

  # YAML syntax validation - ENFORCED
  - repo: https://github.com/adrienverge/yamllint
    rev: v1.32.0
    hooks:
      - id: yamllint
        name: 📋 YAML syntax check
        args: ["-c", ".yamllint.yaml"]
        types: [yaml]

  # YAML formatting - WARNING ONLY
  - repo: https://github.com/pre-commit/mirrors-prettier
    rev: v3.0.3
    hooks:
      - id: prettier
        name: 💅 YAML formatting (warning)
        types: [yaml]
        args: ["--check"]
        verbose: true
        # Allow failure but show warnings
        stages: [manual]

  # ============================================================================
  # KUBERNETES VALIDATION (ENFORCED)
  # ============================================================================

  # Kubernetes manifest validation
  - repo: https://github.com/instrumenta/kubeval
    rev: v0.16.1
    hooks:
      - id: kubeval
        name: ☸️  Kubernetes manifest validation
        files: |
          (?x)^(
            infrastructure/.*\.yaml$|
            apps/.*\.yaml$|
            clusters/.*\.yaml$
          )
        args: ["--strict", "--ignore-missing-schemas"]

  # Kustomize validation
  - repo: local
    hooks:
      - id: kustomize-validate
        name: ☸️  Kustomize validation
        entry: bash -c 'find . -name "kustomization.yaml" -execdir kustomize build . > /dev/null \;'
        language: system
        files: kustomization\.yaml$
        pass_filenames: false

  # ============================================================================
  # PYTHON VALIDATION
  # ============================================================================

  # Python syntax check - ENFORCED
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.4.0
    hooks:
      - id: check-ast
        name: 🐍 Python syntax check

  # Python import sorting - WARNING
  - repo: https://github.com/pycqa/isort
    rev: 5.12.0
    hooks:
      - id: isort
        name: 🐍 Python import sorting (warning)
        args: ["--check-only", "--diff"]
        stages: [manual]

  # Python code formatting - WARNING
  - repo: https://github.com/psf/black
    rev: 23.7.0
    hooks:
      - id: black
        name: 🐍 Python formatting (warning)
        args: ["--check", "--diff"]
        stages: [manual]

  # Python linting - WARNING
  - repo: https://github.com/pycqa/flake8
    rev: 6.0.0
    hooks:
      - id: flake8
        name: 🐍 Python linting (warning)
        args: ["--max-line-length=88", "--extend-ignore=E203,W503"]
        stages: [manual]

  # Python tests - ENFORCED for critical scripts
  - repo: local
    hooks:
      - id: pytest-critical
        name: 🧪 Python tests (critical scripts)
        entry: bash -c 'cd scripts/token-management && python -m pytest test_authentik_token_manager.py -v'
        language: system
        files: scripts/token-management/.*\.py$
        pass_filenames: false

  # ============================================================================
  # SHELL SCRIPT VALIDATION (ENFORCED)
  # ============================================================================

  # Shell script linting - ENFORCED for security
  - repo: https://github.com/shellcheck-py/shellcheck-py
    rev: v0.9.0.5
    hooks:
      - id: shellcheck
        name: 🐚 Shell script validation
        args: ["-e", "SC1091,SC2034"] # Ignore source and unused vars

  # ============================================================================
  # MARKDOWN VALIDATION
  # ============================================================================

  # Markdown linting - Basic checks ENFORCED
  - repo: https://github.com/igorshubovych/markdownlint-cli
    rev: v0.37.0
    hooks:
      - id: markdownlint
        name: 📝 Markdown basic checks
        args: ["--config", ".markdownlint.yaml"]

  # Markdown formatting - WARNING
  - repo: https://github.com/pre-commit/mirrors-prettier
    rev: v3.0.3
    hooks:
      - id: prettier
        name: 📝 Markdown formatting (warning)
        types: [markdown]
        args: ["--check"]
        stages: [manual]

  # ============================================================================
  # GENERAL FILE CHECKS (ENFORCED)
  # ============================================================================

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.4.0
    hooks:
      # File size check - ENFORCED for security
      - id: check-added-large-files
        name: 📏 Large file check
        args: ["--maxkb=1024"]

      # Encoding check - ENFORCED
      - id: check-byte-order-marker
        name: 🔤 Byte order marker check

      # Line ending consistency - ENFORCED
      - id: mixed-line-ending
        name: 📄 Line ending check
        args: ["--fix=lf"]

      # Trailing whitespace - WARNING
      - id: trailing-whitespace
        name: 🧹 Trailing whitespace (warning)
        stages: [manual]

      # End of file newline - WARNING
      - id: end-of-file-fixer
        name: 📄 End of file newline (warning)
        stages: [manual]

  # ============================================================================
  # COMMIT MESSAGE VALIDATION (WARNING)
  # ============================================================================

  # Conventional commits - WARNING
  - repo: https://github.com/compilerla/conventional-pre-commit
    rev: v2.4.0
    hooks:
      - id: conventional-pre-commit
        name: 💬 Commit message format (warning)
        stages: [commit-msg, manual]

# ============================================================================
# CONFIGURATION
# ============================================================================

# Default stages for hooks
default_stages: [commit]

# Exclude patterns
exclude: |
  (?x)^(
    \.git/.*|
    \.pre-commit-cache/.*|
    \.task/.*|
    \.bootstrap-state/.*|
    clusterconfig/.*|
    talos/generated/.*|
    .*\.backup.*|
    .*\.tmp|
    .*\.log
  )$
```

### 2. YAML Lint Configuration (`.yamllint.yaml`)

```yaml
# YAML Lint configuration for GitOps repository
# Balanced approach: syntax enforced, style as warnings

extends: default

rules:
  # ENFORCED RULES (syntax and security)
  document-start: disable # Not required for K8s manifests
  document-end: disable # Not required for K8s manifests

  # Line length - WARNING (common in K8s manifests)
  line-length:
    max: 120
    level: warning

  # Indentation - ENFORCED for consistency
  indentation:
    spaces: 2
    indent-sequences: true
    check-multi-line-strings: false

  # Comments - WARNING
  comments:
    min-spaces-from-content: 1
    level: warning

  # Truthy values - WARNING (K8s uses 'true'/'false')
  truthy:
    allowed-values: ["true", "false", "yes", "no"]
    level: warning

# Ignore patterns
ignore: |
  .git/
  .pre-commit-cache/
  .task/
  clusterconfig/
  talos/generated/
```

### 3. Markdown Lint Configuration (`.markdownlint.yaml`)

```yaml
# Markdown lint configuration
# Basic checks enforced, style as warnings

# Disable style-only rules (warnings handled separately)
MD013: false # Line length
MD033: false # HTML tags (needed for some docs)
MD041: false # First line heading (not always needed)

# Enforce basic structure
MD001: true # Heading levels
MD003: true # Heading style
MD022: true # Headings surrounded by blank lines
MD025: true # Single title
MD032: true # Lists surrounded by blank lines

# Enforce link validity
MD034: true # Bare URLs
MD039: true # Spaces in link text

# Code block formatting
MD040: true # Fenced code blocks language
```

### 4. Secrets Baseline (`.secrets.baseline`)

```json
{
  "version": "1.4.0",
  "plugins_used": [
    {
      "name": "ArtifactoryDetector"
    },
    {
      "name": "AWSKeyDetector"
    },
    {
      "name": "Base64HighEntropyString",
      "limit": 4.5
    },
    {
      "name": "BasicAuthDetector"
    },
    {
      "name": "CloudantDetector"
    },
    {
      "name": "HexHighEntropyString",
      "limit": 3.0
    },
    {
      "name": "JwtTokenDetector"
    },
    {
      "name": "KeywordDetector",
      "keyword_exclude": ""
    },
    {
      "name": "MailchimpDetector"
    },
    {
      "name": "PrivateKeyDetector"
    },
    {
      "name": "SlackDetector"
    },
    {
      "name": "SoftlayerDetector"
    },
    {
      "name": "SquareOAuthDetector"
    },
    {
      "name": "StripeDetector"
    },
    {
      "name": "TwilioKeyDetector"
    }
  ],
  "filters_used": [
    {
      "path": "detect_secrets.filters.allowlist.is_line_allowlisted"
    },
    {
      "path": "detect_secrets.filters.common.is_baseline_file"
    },
    {
      "path": "detect_secrets.filters.common.is_ignored_due_to_verification_policies",
      "min_level": 2
    },
    {
      "path": "detect_secrets.filters.heuristic.is_indirect_reference"
    },
    {
      "path": "detect_secrets.filters.heuristic.is_likely_id_string"
    },
    {
      "path": "detect_secrets.filters.heuristic.is_templated_secret"
    }
  ],
  "results": {},
  "generated_at": "2025-07-26T19:21:00Z"
}
```

## Task Integration

### 5. Taskfile Tasks (`taskfiles/pre-commit.yml`)

```yaml
# Pre-commit management tasks

version: "3"

tasks:
  install:
    desc: Install pre-commit hooks
    cmds:
      - pre-commit install
      - pre-commit install --hook-type commit-msg

  update:
    desc: Update pre-commit hooks
    cmds:
      - pre-commit autoupdate
      - pre-commit install

  run:
    desc: Run pre-commit on all files
    cmds:
      - pre-commit run --all-files

  run-manual:
    desc: Run manual/warning hooks on all files
    cmds:
      - pre-commit run --all-files --hook-stage manual

  security-scan:
    desc: Run security-focused hooks only
    cmds:
      - pre-commit run detect-secrets --all-files
      - pre-commit run gitleaks --all-files

  format:
    desc: Run formatting hooks (warnings)
    cmds:
      - pre-commit run prettier --all-files --hook-stage manual || true
      - pre-commit run black --all-files --hook-stage manual || true
      - pre-commit run isort --all-files --hook-stage manual || true

  validate:
    desc: Run validation hooks only
    cmds:
      - pre-commit run yamllint --all-files
      - pre-commit run kubeval --all-files
      - pre-commit run shellcheck --all-files
      - pre-commit run check-ast --all-files

  clean:
    desc: Clean pre-commit cache
    cmds:
      - pre-commit clean

  baseline:
    desc: Update secrets baseline
    cmds:
      - detect-secrets scan --baseline .secrets.baseline
```

### 6. Mise Tool Integration (`.mise.toml` additions)

```toml
# Add to existing .mise.toml

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

## Installation and Setup

### 7. Installation Script (`scripts/setup-pre-commit.sh`)

```bash
#!/bin/bash
# Setup script for pre-commit hooks

set -euo pipefail

echo "🚀 Setting up pre-commit hooks for Talos GitOps repository..."

# Install tools via mise
echo "📦 Installing required tools..."
mise install pre-commit detect-secrets gitleaks shellcheck markdownlint-cli

# Install pre-commit hooks
echo "🔧 Installing pre-commit hooks..."
pre-commit install
pre-commit install --hook-type commit-msg

# Create initial secrets baseline
echo "🔒 Creating secrets baseline..."
detect-secrets scan --baseline .secrets.baseline

# Run initial validation
echo "✅ Running initial validation..."
pre-commit run --all-files || {
    echo "⚠️  Some hooks failed. This is normal for first run."
    echo "📝 Review the output above and fix any critical issues."
    echo "💡 Use 'task pre-commit:format' to auto-fix formatting issues."
}

echo "🎉 Pre-commit setup complete!"
echo ""
echo "📋 Next steps:"
echo "  • Review any hook failures above"
echo "  • Run 'task pre-commit:format' to fix formatting"
echo "  • Run 'task pre-commit:run' to validate all files"
echo "  • Commit your changes to test the hooks"
```

### 8. GitIgnore Updates

```gitignore
# Add to existing .gitignore

# Pre-commit cache
.pre-commit-cache/

# Secret scanning
.secrets.baseline.tmp
```

## Usage Workflow

### Daily Development Workflow

1. **Make changes** to files as normal
2. **Commit changes** - hooks run automatically
   - Security and syntax issues **block** the commit
   - Formatting issues show **warnings** but allow commit
3. **Fix critical issues** if commit is blocked
4. **Optional**: Run `task pre-commit:format` to fix formatting warnings

### Periodic Maintenance

1. **Weekly**: `task pre-commit:update` - Update hook versions
2. **Monthly**: `task pre-commit:run-manual` - Check all warnings
3. **As needed**: `task pre-commit:security-scan` - Security audit

### Hook Categories

#### ENFORCED (Blocks commits)

- 🔒 Secret detection (detect-secrets, gitleaks)
- 📋 YAML syntax (yamllint)
- ☸️ Kubernetes validation (kubeval, kustomize)
- 🐍 Python syntax (check-ast)
- 🐚 Shell script security (shellcheck)
- 📝 Markdown basic structure
- 📏 File size limits
- 🔤 File encoding issues

#### WARNING (Allows commits)

- 💅 Code formatting (prettier, black, isort)
- 🐍 Python linting (flake8)
- 📝 Markdown style
- 🧹 Whitespace issues
- 💬 Commit message format

## Security Considerations

### Critical Security Features

1. **Secret Detection**: Multiple layers (detect-secrets + gitleaks)
2. **Baseline Management**: Tracks known false positives
3. **File Size Limits**: Prevents accidental large file commits
4. **Shell Script Security**: Shellcheck catches security issues

### Post-Security-Incident Improvements

- Addresses all items from `SECURITY_INCIDENT_REPORT.md`
- Prevents future credential commits
- Automated scanning in development workflow
- Regular security audits via tasks

## Testing Strategy

### Test Scenarios

1. **Secret detection**: Try committing fake credentials
2. **YAML validation**: Commit invalid YAML syntax
3. **Python syntax**: Commit Python with syntax errors
4. **Shell security**: Commit shell script with security issues
5. **Large files**: Try committing files > 1MB
6. **Formatting**: Commit unformatted code (should warn, not block)

### Validation Commands

```bash
# Test all enforced hooks
task pre-commit:validate

# Test security scanning
task pre-commit:security-scan

# Test formatting (warnings)
task pre-commit:format

# Full test run
task pre-commit:run
```

## Implementation Priority

### Phase 1: Critical Security (Immediate)

1. Install pre-commit framework
2. Configure secret detection (detect-secrets, gitleaks)
3. Set up basic YAML and Python syntax validation
4. Create secrets baseline

### Phase 2: Core Validation (Week 1)

1. Add Kubernetes manifest validation
2. Configure shell script security checking
3. Set up basic markdown validation
4. Add file size and encoding checks

### Phase 3: Quality Improvements (Week 2)

1. Add formatting hooks as warnings
2. Configure Python linting
3. Set up commit message validation
4. Create comprehensive task integration

### Phase 4: Optimization (Ongoing)

1. Fine-tune hook performance
2. Add custom validation rules
3. Integrate with CI/CD pipeline
4. Regular maintenance and updates

## Benefits

### Security Benefits

- **Prevents credential commits** (addresses security incident)
- **Validates infrastructure code** before deployment
- **Catches security issues** in shell scripts
- **Enforces file safety** (size, encoding)

### Quality Benefits

- **Consistent YAML formatting** across manifests
- **Python code quality** in automation scripts
- **Documentation standards** in markdown files
- **Shell script reliability** in deployment scripts

### Developer Experience

- **Fast feedback** on issues before push
- **Balanced enforcement** - security strict, style flexible
- **Clear error messages** for quick fixes
- **Optional formatting** doesn't block productivity

This implementation provides comprehensive protection while maintaining developer productivity, directly addressing the security concerns raised in the incident report while supporting the sophisticated GitOps workflow of the Talos cluster.
