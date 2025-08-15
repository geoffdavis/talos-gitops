#!/bin/bash
# Script to get Dashboard token and display it for easy login

set -e

echo "================================================"
echo "Kubernetes Dashboard Login Helper"
echo "================================================"
echo ""
echo "Dashboard URL: https://dashboard.k8s.home.geoffdavis.com"
echo ""
echo "Getting authentication token..."
echo ""

# Get the viewer service account token
TOKEN=$(kubectl get secret -n kubernetes-dashboard kubernetes-dashboard-viewer-token \
  -o jsonpath='{.data.token}' | base64 -d)

if [ -z "$TOKEN" ]; then
  echo "Error: Could not retrieve token"
  exit 1
fi

echo "Token retrieved successfully!"
echo ""
echo "Instructions:"
echo "1. Open: https://dashboard.k8s.home.geoffdavis.com"
echo "2. Select 'Token' authentication method"
echo "3. Paste the token below:"
echo ""
echo "================================================"
echo "TOKEN (copy everything below):"
echo "================================================"
echo "$TOKEN"
echo "================================================"
echo ""

# Check if pbcopy is available (macOS)
if command -v pbcopy &> /dev/null; then
  echo "$TOKEN" | pbcopy
  echo "✓ Token has been copied to your clipboard!"
  echo ""
fi

# Check if xclip is available (Linux)
if command -v xclip &> /dev/null; then
  echo "$TOKEN" | xclip -selection clipboard
  echo "✓ Token has been copied to your clipboard!"
  echo ""
fi

echo "This token provides full cluster access with read/write permissions."
echo "The token is valid for 1 year from creation."
echo ""

# Optionally open the browser
if command -v open &> /dev/null; then
  read -p "Open Dashboard in browser? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    open "https://dashboard.k8s.home.geoffdavis.com"
  fi
elif command -v xdg-open &> /dev/null; then
  read -p "Open Dashboard in browser? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    xdg-open "https://dashboard.k8s.home.geoffdavis.com"
  fi
fi