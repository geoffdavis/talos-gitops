# gitops.md

This repository uses GitOps methodology.

## Guidelines

- Avoid temporarily creating resources to clear deadlocks
- Use gitops principles to ensure repeatability
- Items in the infrastructure and apps trees might be reused by other clusters so make them as reusable as possible.
- When making changes to resources, make sure to commit and push your changes before trying to reconcile with flux.
