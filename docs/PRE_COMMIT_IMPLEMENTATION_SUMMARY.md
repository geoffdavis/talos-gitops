# Pre-commit System Documentation

The pre-commit system in the Talos GitOps Home-Ops Cluster enforces code quality, security, and consistency standards across the repository. This document details its purpose, architecture, configuration, and operational aspects, highlighting its balanced enforcement approach.

## Purpose

The pre-commit system aims to:

- **Prevent Issues**: Catch security vulnerabilities, syntax errors, and formatting inconsistencies before code is committed.
- **Improve Code Quality**: Ensure adherence to coding standards and best practices.
- **Automate Checks**: Provide fast, local feedback to developers, reducing reliance on CI/CD pipelines for basic checks.
- **Maintain Consistency**: Enforce a consistent code style across the entire project.

## Architecture and Enforcement

The pre-commit system utilizes the `pre-commit` framework, which manages and runs various hooks configured in `.pre-commit-config.yaml`. A balanced enforcement approach is employed:

- **Enforced Hooks (Blocking Commits)**:
  - **Security**: `detect-secrets`, `gitleaks` (to prevent credential leaks).
  - **Syntax Validation**: `yamllint` (for YAML syntax), Kubernetes manifest validation (`kubectl dry-run`), Python syntax checks, `shellcheck` (for shell script security).
  - These hooks block commits if issues are found, ensuring critical problems are addressed immediately.

- **Warning Hooks (Non-Blocking)**:
  - **Formatting**: `prettier` (for YAML, Markdown), `black` (for Python), `isort` (for Python imports).
  - These hooks provide suggestions and automatically fix issues where possible, but do not block commits, allowing developers to address them at their convenience.

## Configuration

The core configuration is defined in the `.pre-commit-config.yaml` file. This file specifies:

- **Repositories**: URLs of hook repositories (e.g., `https://github.com/pre-commit/pre-commit-hooks`).
- **Hooks**: Individual hooks to run, along with their versions and arguments.
- **Exclusions**: Patterns to exclude certain files or directories from checks.

Additional configuration files include:

- **`.secrets.baseline`**: A baseline file for `detect-secrets` to manage legitimate secrets and reduce false positives.
- **`.yamllint.yaml`**: Custom rules for YAML linting.
- **`.markdownlint.yaml`**: Custom rules for Markdown linting.

## Operational Considerations

### Setup

1. **Install `mise`**: Ensure `mise` is installed as per the [Development Environment Setup](MISE_TOOL_MANAGEMENT.md) documentation.
2. **Install Tools**: Run `mise install` in the repository root to install all required tools, including `pre-commit`.
3. **Install Git Hooks**: Execute `task pre-commit:install` to set up the Git hooks in your local repository.

### Daily Usage

Hooks run automatically on `git commit`.

- **Fixing Enforced Issues**: If a commit is blocked, address the reported issues and attempt to commit again.
- **Addressing Warnings**: Review warnings and fix formatting issues when convenient.

### Manual Validation

- Run all enforced hooks: `task pre-commit:run`
- Check formatting issues: `task pre-commit:format`
- Run security scans only: `task pre-commit:security`

### Maintenance

- **Update Hooks**: `task pre-commit:update` to update all hooks to their latest versions.
- **Clean Cache**: `task pre-commit:clean` to clear the pre-commit cache.
- **Manage Baselines**: Regularly update `.secrets.baseline` as legitimate secrets change.

### Troubleshooting

- **Hook Fails to Run**: Verify `mise install` and `task pre-commit:install` were successful.
- **False Positives**: Update `.secrets.baseline` for legitimate secrets.
- **Bypassing Hooks**: Use `SKIP=hook-name git commit` to temporarily bypass a specific hook, or `git commit --no-verify` to bypass all hooks (use sparingly).

## Related Files

- [`.pre-commit-config.yaml`](../../.pre-commit-config.yaml) - Main pre-commit configuration.
- [`.secrets.baseline`](../../.secrets.baseline) - Secret detection baseline.
- [`.yamllint.yaml`](../../.yamllint.yaml) - YAML linting rules.
- [`.markdownlint.yaml`](../../.markdownlint.yaml) - Markdown linting rules.
- [`taskfiles/pre-commit.yml`](../../taskfiles/pre-commit.yml) - Taskfile definitions for pre-commit operations.

Please ensure this file is created with the exact content provided. After creation, use the `attempt_completion` tool to report the successful creation of the file.
