#!/bin/bash
# Setup script for pre-commit hooks

set -euo pipefail

echo "🚀 Setting up pre-commit hooks for Talos GitOps repository..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Install tools via mise and other package managers
echo "📦 Installing required tools..."
mise install pre-commit shellcheck

# Install Python-based tools
echo "📦 Installing Python-based tools..."
mise exec -- python -m pip install detect-secrets

# Install gitleaks via brew (Go binary)
echo "📦 Installing gitleaks..."
if command -v brew >/dev/null 2>&1; then
    brew install gitleaks
else
    echo "⚠️  Homebrew not found. Please install gitleaks manually or via your package manager"
fi

# Install markdownlint-cli via npm
echo "📦 Installing markdownlint-cli..."
if command -v npm >/dev/null 2>&1; then
    npm install -g markdownlint-cli
else
    echo "⚠️  npm not found. Please install markdownlint-cli manually"
fi

# Install pre-commit hooks
echo "🔧 Installing pre-commit hooks..."
pre-commit install
pre-commit install --hook-type commit-msg

# Create initial secrets baseline
echo "🔒 Creating secrets baseline..."
mise exec -- python -m detect_secrets scan --baseline .secrets.baseline

# Run initial validation
echo "✅ Running initial validation..."
if pre-commit run --all-files; then
    echo -e "${GREEN}🎉 All hooks passed!${NC}"
else
    echo -e "${YELLOW}⚠️  Some hooks failed. This is normal for first run.${NC}"
    echo "📝 Review the output above and fix any critical issues."
    echo "💡 Use 'task pre-commit:format' to auto-fix formatting issues."
fi

echo ""
echo "🎉 Pre-commit setup complete!"
echo ""
echo "📋 Next steps:"
echo "  • Review any hook failures above"
echo "  • Run 'task pre-commit:format' to fix formatting"
echo "  • Run 'task pre-commit:run' to validate all files"
echo "  • Commit your changes to test the hooks"