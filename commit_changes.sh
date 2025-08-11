#!/bin/bash
set -e

echo "Adding files to git..."
git add charts/gitops-lifecycle-management/Chart.yaml
git add charts/gitops-lifecycle-management/templates/controllers/service-discovery-controller.yaml
git add charts/gitops-lifecycle-management/templates/controllers/service-discovery-script.yaml

echo "Committing changes..."
git commit -m "feat: Replace shell script with maintainable Python controller

- Replace complex shell script with clean Python-based service discovery controller
- Implement proper HTTP health endpoints (/healthz, /readyz) for Kubernetes probes
- Add structured logging and error handling
- Use python:3.11-alpine image with kubectl and requests dependencies
- Mount Python script via ConfigMap for better maintainability
- Chart version 0.1.8 with improved readability and debugging capabilities

This resolves HelmRelease timeout issues by providing proper readiness probes
and makes the controller much more maintainable for future development."

echo "Pushing changes..."
git push

echo "Changes committed and pushed successfully!"
