# Pre-Commit Testing Guide

## Overview

This guide provides comprehensive testing scenarios to validate the pre-commit configuration for the Talos GitOps repository. It covers both enforced hooks (that block commits) and warning hooks (that allow commits but show issues).

## Testing Philosophy

- **ENFORCED hooks**: Must block commits with critical issues
- **WARNING hooks**: Should show issues but allow commits to proceed
- **Security hooks**: Must catch all credential and security violations

## Test Scenarios

### 1. Security Testing (ENFORCED - Must Block)

#### Test 1.1: Secret Detection

```bash
# Create test file with fake credentials
cat > test-secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: test-secret
data:
  password: "super-secret-password-123"  # pragma: allowlist secret
  api-key: "sk-1234567890abcdef"
EOF

# Attempt commit - should FAIL
git add test-secret.yaml
git commit -m "test: add secret file"
# Expected: Commit blocked by detect-secrets hook

# Clean up
git reset HEAD test-secret.yaml
rm test-secret.yaml
```

#### Test 1.2: Git Leaks Detection

```bash
# Create file with credential pattern
cat > test-creds.sh << EOF
#!/bin/bash
export AWS_ACCESS_KEY_ID="REDACTED"  # pragma: allowlist secret
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"  # pragma: allowlist secret
EOF

# Attempt commit - should FAIL
git add test-creds.sh
git commit -m "test: add credentials"
# Expected: Commit blocked by gitleaks hook

# Clean up
git reset HEAD test-creds.sh
rm test-creds.sh
```

#### Test 1.3: Large File Detection

```bash
# Create large file (>1MB)
dd if=/dev/zero of=large-file.bin bs=1024 count=1100

# Attempt commit - should FAIL
git add large-file.bin
git commit -m "test: add large file"
# Expected: Commit blocked by check-added-large-files hook

# Clean up
git reset HEAD large-file.bin
rm large-file.bin
```

### 2. YAML Validation Testing (ENFORCED)

#### Test 2.1: Invalid YAML Syntax

```bash
# Create invalid YAML
cat > test-invalid.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: test
data:
  key: value
    invalid-indentation: true
  - invalid list item
EOF

# Attempt commit - should FAIL
git add test-invalid.yaml
git commit -m "test: invalid yaml"
# Expected: Commit blocked by yamllint hook

# Clean up
git reset HEAD test-invalid.yaml
rm test-invalid.yaml
```

#### Test 2.2: Valid YAML with Style Issues

```bash
# Create valid YAML with style issues
cat > test-style.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: test-config-with-very-long-name-that-exceeds-normal-line-length-limits
data:
  key1: "value1"
  key2: "value2"
EOF

# Attempt commit - should SUCCEED with warnings
git add test-style.yaml
git commit -m "test: yaml with style issues"
# Expected: Commit succeeds, yamllint shows warnings about line length and trailing spaces

# Clean up
git reset HEAD~1 --soft
git reset HEAD test-style.yaml
rm test-style.yaml
```

### 3. Kubernetes Validation Testing (ENFORCED)

#### Test 3.1: Invalid Kubernetes Manifest

```bash
# Create invalid K8s manifest
mkdir -p test-k8s
cat > test-k8s/invalid-deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
spec:
  replicas: 1
  # Missing required selector field
  template:
    metadata:
      labels:
        app: test-app
    spec:
      containers:
      - name: test
        image: nginx
        # Invalid resource format
        resources:
          limits:
            memory: "invalid-format"
EOF

# Attempt commit - should FAIL
git add test-k8s/
git commit -m "test: invalid k8s manifest"
# Expected: Commit blocked by kubeval hook

# Clean up
git reset HEAD test-k8s/
rm -rf test-k8s/
```

#### Test 3.2: Invalid Kustomization

```bash
# Create invalid kustomization
mkdir -p test-kustomize
cat > test-kustomize/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- nonexistent-file.yaml  # File doesn't exist

commonLabels:
  app: test
EOF

# Attempt commit - should FAIL
git add test-kustomize/
git commit -m "test: invalid kustomization"
# Expected: Commit blocked by kustomize-validate hook

# Clean up
git reset HEAD test-kustomize/
rm -rf test-kustomize/
```

### 4. Python Validation Testing

#### Test 4.1: Python Syntax Error (ENFORCED)

```bash
# Create Python file with syntax error
cat > test-syntax.py << EOF
#!/usr/bin/env python3

def invalid_function(
    # Missing closing parenthesis
    print("This will cause a syntax error")
EOF

# Attempt commit - should FAIL
git add test-syntax.py
git commit -m "test: python syntax error"
# Expected: Commit blocked by check-ast hook

# Clean up
git reset HEAD test-syntax.py
rm test-syntax.py
```

#### Test 4.2: Python Formatting Issues (WARNING)

```bash
# Create Python file with formatting issues
cat > test-format.py << EOF
#!/usr/bin/env python3

import os,sys,json
from pathlib import Path

def poorly_formatted_function( x,y,z ):
    result=x+y+z
    if result>10:
        print("Result is greater than 10")
    return result

class PoorlyFormattedClass:
    def __init__(self,value):
        self.value=value

    def get_value( self ):
        return self.value
EOF

# Attempt commit - should SUCCEED with warnings
git add test-format.py
git commit -m "test: python formatting issues"
# Expected: Commit succeeds, but shows warnings about formatting

# Test manual formatting hooks
pre-commit run black --files test-format.py --hook-stage manual
pre-commit run isort --files test-format.py --hook-stage manual
pre-commit run flake8 --files test-format.py --hook-stage manual

# Clean up
git reset HEAD~1 --soft
git reset HEAD test-format.py
rm test-format.py
```

### 5. Shell Script Validation Testing (ENFORCED)

#### Test 5.1: Shell Script Security Issues

```bash
# Create shell script with security issues
cat > test-security.sh << EOF
#!/bin/bash

# Security issue: using eval with user input
user_input="\$1"
eval "echo \$user_input"

# Security issue: unquoted variables
file_name=\$2
rm \$file_name

# Security issue: using curl without verification
curl http://example.com/script.sh | bash
EOF

chmod +x test-security.sh

# Attempt commit - should FAIL
git add test-security.sh
git commit -m "test: shell script security issues"
# Expected: Commit blocked by shellcheck hook

# Clean up
git reset HEAD test-security.sh
rm test-security.sh
```

#### Test 5.2: Shell Script Best Practices

```bash
# Create shell script with minor issues (should pass)
cat > test-minor.sh << EOF
#!/bin/bash

set -euo pipefail

# Minor issue: unused variable (ignored by config)
unused_var="not used"

# Good practices
file_name="\${1:-default.txt}"
if [[ -f "\$file_name" ]]; then
    echo "File exists: \$file_name"
fi
EOF

chmod +x test-minor.sh

# Attempt commit - should SUCCEED
git add test-minor.sh
git commit -m "test: shell script minor issues"
# Expected: Commit succeeds

# Clean up
git reset HEAD~1 --soft
git reset HEAD test-minor.sh
rm test-minor.sh
```

### 6. Markdown Validation Testing

#### Test 6.1: Markdown Structure Issues (ENFORCED)

```bash
# Create markdown with structure issues
cat > test-structure.md << EOF
### This is a level 3 heading without level 1 or 2

Some content here.

### Another level 3 heading

More content.

#### Level 4 heading

Content without proper heading hierarchy.
EOF

# Attempt commit - should FAIL
git add test-structure.md
git commit -m "test: markdown structure issues"
# Expected: Commit blocked by markdownlint hook (MD001 - heading levels)

# Clean up
git reset HEAD test-structure.md
rm test-structure.md
```

#### Test 6.2: Markdown Style Issues (WARNING)

```bash
# Create markdown with style issues
cat > test-style.md << EOF
# Test Document

This line is way too long and exceeds the typical line length limits that are recommended for markdown documents to ensure readability.

Some content here.

## Section 2
Missing blank line above heading.

- List item 1
- List item 2
Missing blank line after list.
Next paragraph.
EOF

# Attempt commit - should SUCCEED with warnings
git add test-style.md
git commit -m "test: markdown style issues"
# Expected: Commit succeeds, prettier shows formatting warnings

# Test manual formatting
pre-commit run prettier --files test-style.md --hook-stage manual

# Clean up
git reset HEAD~1 --soft
git reset HEAD test-style.md
rm test-style.md
```

### 7. Commit Message Testing (WARNING)

#### Test 7.1: Non-Conventional Commit Message

```bash
# Create a simple file
echo "test content" > test-commit-msg.txt
git add test-commit-msg.txt

# Attempt commit with non-conventional message - should SUCCEED with warning
git commit -m "added some stuff and fixed things"
# Expected: Commit succeeds, conventional-pre-commit shows warning

# Clean up
git reset HEAD~1 --soft
git reset HEAD test-commit-msg.txt
rm test-commit-msg.txt
```

#### Test 7.2: Conventional Commit Message

```bash
# Create a simple file
echo "test content" > test-commit-msg.txt
git add test-commit-msg.txt

# Commit with conventional message - should SUCCEED without warnings
git commit -m "feat: add test content file"
# Expected: Commit succeeds, no warnings

# Clean up
git reset HEAD~1 --soft
git reset HEAD test-commit-msg.txt
rm test-commit-msg.txt
```

## Automated Test Suite

### Test Script (`scripts/test-pre-commit.sh`)

```bash
#!/bin/bash
# Automated pre-commit testing script

set -euo pipefail

echo "🧪 Running pre-commit test suite..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test function
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"  # "pass" or "fail"

    echo -n "Testing $test_name... "
    TESTS_RUN=$((TESTS_RUN + 1))

    if eval "$test_command" >/dev/null 2>&1; then
        actual_result="pass"
    else
        actual_result="fail"
    fi

    if [[ "$actual_result" == "$expected_result" ]]; then
        echo -e "${GREEN}✓${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} (expected $expected_result, got $actual_result)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Security tests
echo "🔒 Testing security hooks..."
run_test "detect-secrets baseline" "detect-secrets scan --baseline .secrets.baseline" "pass"
run_test "gitleaks scan" "gitleaks detect --no-git" "pass"

# YAML tests
echo "📋 Testing YAML validation..."
run_test "yamllint config" "yamllint .yamllint.yaml" "pass"
run_test "yamllint infrastructure" "yamllint infrastructure/" "pass"

# Python tests
echo "🐍 Testing Python validation..."
run_test "python syntax check" "python -m py_compile scripts/authentik-proxy-config/*.py" "pass"
run_test "pytest token management" "cd scripts/token-management && python -m pytest test_authentik_token_manager.py -v" "pass"

# Shell script tests
echo "🐚 Testing shell script validation..."
run_test "shellcheck bootstrap scripts" "shellcheck scripts/bootstrap-*.sh" "pass"

# Kubernetes tests
echo "☸️ Testing Kubernetes validation..."
run_test "kustomize build clusters" "kustomize build clusters/home-ops/" "pass"

# Summary
echo ""
echo "📊 Test Results:"
echo "  Tests run: $TESTS_RUN"
echo -e "  Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "  Failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}🎉 All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed.${NC}"
    exit 1
fi
```

## Manual Testing Checklist

### Pre-Implementation Testing

- [ ] Install pre-commit framework
- [ ] Install all required tools (detect-secrets, gitleaks, etc.)
- [ ] Create initial secrets baseline
- [ ] Run pre-commit on existing codebase

### Security Hook Testing

- [ ] Test secret detection with fake credentials
- [ ] Test git leaks detection with credential patterns
- [ ] Test large file detection
- [ ] Verify secrets baseline excludes known false positives

### Validation Hook Testing

- [ ] Test YAML syntax validation with invalid files
- [ ] Test Kubernetes manifest validation
- [ ] Test Python syntax checking
- [ ] Test shell script security scanning
- [ ] Test markdown structure validation

### Warning Hook Testing

- [ ] Test YAML formatting (should warn, not block)
- [ ] Test Python formatting (should warn, not block)
- [ ] Test markdown style issues (should warn, not block)
- [ ] Test commit message format (should warn, not block)

### Integration Testing

- [ ] Test with existing repository files
- [ ] Test performance with large changesets
- [ ] Test hook bypass mechanisms
- [ ] Test manual hook execution

### Edge Case Testing

- [ ] Test with binary files
- [ ] Test with symlinks
- [ ] Test with submodules
- [ ] Test with merge commits
- [ ] Test with empty commits

## Performance Testing

### Benchmark Commands

```bash
# Time full pre-commit run
time pre-commit run --all-files

# Time individual hooks
time pre-commit run detect-secrets --all-files
time pre-commit run yamllint --all-files
time pre-commit run kubeval --all-files

# Profile hook performance
pre-commit run --all-files --verbose
```

### Performance Expectations

- **Full run**: < 60 seconds for entire repository
- **Security hooks**: < 30 seconds
- **YAML validation**: < 15 seconds
- **Python validation**: < 10 seconds
- **Individual commits**: < 10 seconds

## Troubleshooting Common Issues

### Hook Installation Issues

```bash
# Reinstall hooks
pre-commit uninstall
pre-commit install
pre-commit install --hook-type commit-msg
```

### Cache Issues

```bash
# Clear pre-commit cache
pre-commit clean
pre-commit install
```

### Baseline Issues

```bash
# Regenerate secrets baseline
detect-secrets scan --baseline .secrets.baseline --force-use-all-plugins
```

### Performance Issues

```bash
# Run hooks in parallel (if supported)
pre-commit run --all-files --show-diff-on-failure

# Skip slow hooks for quick testing
SKIP=kubeval,pytest-critical pre-commit run --all-files
```

This testing guide ensures comprehensive validation of the pre-commit configuration and helps maintain the security and quality standards of the GitOps repository.
