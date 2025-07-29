# Documentation Maintenance Procedures

This document outlines procedures for maintaining high-quality, current documentation for the Talos GitOps home-ops cluster. Proper documentation maintenance ensures operational knowledge is preserved and accessible to all team members.

## Table of Contents

- [Documentation Philosophy](#documentation-philosophy)
- [Maintenance Schedule](#maintenance-schedule)
- [Update Procedures](#update-procedures)
- [Quality Assurance](#quality-assurance)
- [Automated Validation](#automated-validation)
- [Content Review Process](#content-review-process)
- [Community Contributions](#community-contributions)
- [Documentation Metrics](#documentation-metrics)
- [Tool and Process Maintenance](#tool-and-process-maintenance)

## Documentation Philosophy

### Core Principles

1. **Accuracy First**: Documentation must reflect current system state
2. **Actionable Content**: All procedures must be tested and workable
3. **Comprehensive Coverage**: Document both success and failure scenarios
4. **Clear Structure**: Consistent organization and formatting
5. **Accessible Language**: Technical but understandable content
6. **Version Control**: All changes tracked in Git with clear commit messages

### Documentation Types

| Type | Purpose | Update Frequency | Responsibility |
|------|---------|------------------|----------------|
| **Architecture** | System design and decisions | Quarterly | Lead Architect |
| **Operations** | Procedures and troubleshooting | Monthly | Operations Team |
| **Reference** | Technical specifications | As needed | Subject Matter Experts |
| **Getting Started** | Onboarding guides | Quarterly | Documentation Maintainer |
| **Components** | Service-specific guides | Bi-monthly | Service Owners |

## Maintenance Schedule

### Daily Tasks

- [ ] **Automated Link Checking**: Review broken link reports
- [ ] **Issue Triage**: Review documentation-related GitHub issues
- [ ] **Content Validation**: Check pre-commit validation results

### Weekly Tasks

- [ ] **Recent Changes Review**: Audit commits for documentation impact
- [ ] **User Feedback Review**: Process documentation improvement requests
- [ ] **Metric Analysis**: Review documentation usage and search metrics

### Monthly Tasks

- [ ] **Content Accuracy Audit**: Validate procedures against current system
- [ ] **Link Validation**: Comprehensive link and reference checking
- [ ] **Style Guide Compliance**: Review formatting and style consistency
- [ ] **Missing Content Identification**: Identify gaps in documentation coverage

### Quarterly Tasks

- [ ] **Comprehensive Review**: Full documentation structure and content review
- [ ] **Tool Updates**: Update documentation tools and dependencies
- [ ] **Process Improvement**: Evaluate and improve documentation processes
- [ ] **Archive Cleanup**: Remove outdated content and reorganize structure

### Annual Tasks

- [ ] **Documentation Strategy Review**: Evaluate overall documentation approach
- [ ] **Tool Migration**: Consider new documentation tools and platforms
- [ ] **Training Materials Update**: Refresh documentation training content
- [ ] **Performance Analysis**: Comprehensive analysis of documentation effectiveness

## Update Procedures

### Immediate Updates (< 24 hours)

Required for:

- Security incidents and fixes
- Critical system changes
- Emergency procedures
- Service outages and resolutions

**Process**:

```bash
# 1. Create hotfix branch
git checkout main
git pull origin main
git checkout -b docs/hotfix-critical-update

# 2. Update documentation
vim docs/path/to/file.md

# 3. Validate changes
task pre-commit:run

# 4. Commit with clear message
git add docs/
git commit -m "docs: emergency update for [issue description]"

# 5. Create pull request with urgent label
git push origin docs/hotfix-critical-update
# Use GitHub CLI or web interface to create PR with "urgent" label

# 6. Fast-track review and merge
```

### Standard Updates (< 1 week)

Required for:

- Infrastructure changes
- Application deployments
- Procedure modifications
- New features

**Process**:

```bash
# 1. Create feature branch
git checkout -b docs/update-component-guide

# 2. Update documentation
vim docs/components/component/README.md

# 3. Test procedures if applicable
# Follow documented steps to verify accuracy

# 4. Validate and commit
task pre-commit:run
git add docs/
git commit -m "docs(component): update deployment procedures"

# 5. Create pull request
git push origin docs/update-component-guide
# Create PR with standard review process
```

### Scheduled Updates (Monthly/Quarterly)

**Content Accuracy Validation**:

```bash
# 1. Create maintenance branch
git checkout -b docs/maintenance-$(date +%Y%m)

# 2. Review each document for:
# - Accuracy of commands and procedures
# - Current version numbers and references
# - Validity of links and cross-references
# - Consistency with actual system state

# 3. Test critical procedures
# Execute key operational procedures to verify accuracy

# 4. Update version-sensitive content
# Check for version updates in:
# - Kubernetes and Talos versions
# - Application versions
# - Tool versions in .mise.toml

# 5. Commit comprehensive updates
git add docs/
git commit -m "docs: monthly maintenance update - $(date +%Y-%m)"
```

### Documentation Impact Assessment

For system changes, assess documentation impact:

```bash
# 1. Identify affected documentation
grep -r "old-component" docs/
find docs/ -name "*.md" -exec grep -l "version-number" {} \;

# 2. Update affected files
# Use systematic approach to update all references

# 3. Cross-reference validation
# Ensure all cross-references remain valid

# 4. Test updated procedures
# Verify any procedural changes work correctly
```

## Quality Assurance

### Content Standards

#### Writing Guidelines

1. **Clear Headlines**: Use descriptive, hierarchical headers
2. **Active Voice**: Prefer active voice for instructions
3. **Specific Commands**: Include exact commands with proper syntax highlighting
4. **Context Provision**: Explain why, not just how
5. **Example Inclusion**: Provide real-world examples

#### Technical Accuracy

```markdown
# Good Example
## Restarting Cilium Pods

To restart Cilium pods after configuration changes:

```bash
# Delete Cilium pods to trigger restart
kubectl delete pods -n kube-system -l k8s-app=cilium

# Wait for pods to restart
kubectl wait --for=condition=Ready pods -n kube-system -l k8s-app=cilium --timeout=300s

# Verify Cilium status
cilium status
```

**Note**: This will briefly interrupt network connectivity. Plan accordingly.

### Poor Example

#### Restart Cilium

Delete the pods and they'll restart.

```text
kubectl delete pods
```

#### Code Block Standards

Always specify language for syntax highlighting:

```bash
# Shell commands
kubectl get pods -A
```

```yaml
# YAML configuration
apiVersion: v1
kind: ConfigMap
```

```python
# Python scripts
import subprocess
result = subprocess.run(['kubectl', 'get', 'pods'])
```

### Link and Reference Validation

#### Internal Links

```bash
# Check internal links
find docs/ -name "*.md" -exec grep -l "\[.*\](\..*\.md)" {} \; | \
  xargs -I {} bash -c 'echo "Checking {}"; grep -n "\[.*\](\..*\.md)" {}'

# Validate relative paths exist
find docs/ -name "*.md" -exec bash -c '
  grep -oP "\[.*?\]\(\./.*?\.md\)" "$1" | \
  sed "s/.*(\.\///;s/).*//" | \
  while read -r link; do
    if [ ! -f "$(dirname "$1")/$link" ]; then
      echo "Broken link in $1: $link"
    fi
  done
' _ {} \;
```

#### External Links

```bash
# Extract external links for validation
find docs/ -name "*.md" -exec grep -hoP 'https?://[^\s\)]+' {} \; | \
  sort -u > external-links.txt

# Check external links (requires curl)
while read -r url; do
  if ! curl -sf "$url" > /dev/null; then
    echo "Broken external link: $url"
  fi
done < external-links.txt
```

## Automated Validation

### Pre-commit Integration

The project uses pre-commit hooks for documentation quality:

```yaml
# .pre-commit-config.yaml (relevant hooks)
repos:
  - repo: https://github.com/igorshubovych/markdownlint-cli
    rev: v0.37.0
    hooks:
      - id: markdownlint
        args: ['--config', '.markdownlint.yaml']
  
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.4.0
    hooks:
      - id: check-yaml
      - id: check-merge-conflict
      - id: trailing-whitespace
        args: ['--markdown-linebreak-ext=md']
  
  - repo: https://github.com/prettier/prettier
    rev: v3.0.3
    hooks:
      - id: prettier
        types: [markdown]
```

### Continuous Integration

```bash
# GitHub Actions workflow for documentation validation
name: Documentation Validation
on:
  pull_request:
    paths:
      - 'docs/**'
  push:
    branches:
      - main
    paths:
      - 'docs/**'

jobs:
  validate-docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'
      
      - name: Install dependencies
        run: |
          npm install -g markdownlint-cli
          npm install -g markdown-link-check
      
      - name: Lint Markdown
        run: markdownlint docs/**/*.md
      
      - name: Check Links
        run: |
          find docs/ -name "*.md" -exec markdown-link-check {} \;
      
      - name: Validate YAML frontmatter
        run: |
          find docs/ -name "*.md" -exec bash -c '
            if grep -q "^---$" "$1"; then
              sed -n "1,/^---$/p" "$1" | head -n -1 | tail -n +2 | yq eval . -
            fi
          ' _ {} \;
```

### Documentation Testing

```bash
# Test documented procedures
# taskfiles/docs.yml
version: '3'

tasks:
  test-procedures:
    desc: Test documented procedures
    cmds:
      - echo "Testing cluster status procedure..."
      - task cluster:status
      - echo "Testing backup procedures..."
      - task test:backup-restore
      - echo "Testing troubleshooting commands..."
      - task test:troubleshooting-commands
  
  validate-links:
    desc: Validate all documentation links
    cmds:
      - find docs/ -name "*.md" -exec markdown-link-check {} \;
  
  lint-docs:
    desc: Lint all documentation
    cmds:
      - markdownlint docs/**/*.md
      - prettier --check docs/**/*.md
```

## Content Review Process

### Regular Review Cycle

#### Weekly Technical Review

**Scope**: Recent changes and updates
**Reviewers**: Technical leads and service owners
**Process**:

1. **Change Identification**: Review Git commits affecting documentation
2. **Accuracy Verification**: Validate technical accuracy of changes
3. **Completeness Check**: Ensure all necessary information is included
4. **Cross-Reference Update**: Update related documentation

#### Monthly Comprehensive Review

**Scope**: Full section review on rotation
**Reviewers**: Documentation team and subject matter experts
**Process**:

```bash
# Monthly review checklist
# docs/operations/review-checklist.md

## Architecture Documentation Review
- [ ] System diagrams current and accurate
- [ ] Technology versions up to date
- [ ] Design decisions documented and relevant
- [ ] Component relationships accurate

## Operations Documentation Review
- [ ] Procedures tested and working
- [ ] Troubleshooting guides comprehensive
- [ ] Emergency procedures current
- [ ] Tool references accurate

## Component Documentation Review
- [ ] Service configurations match reality
- [ ] Deployment procedures tested
- [ ] Integration guides complete
- [ ] Version information current
```

### Review Assignment

```bash
# Assign reviews based on expertise
# .github/CODEOWNERS
docs/architecture/     @lead-architect @senior-engineer
docs/operations/       @operations-team @sre-lead
docs/components/       @service-owners
docs/getting-started/  @documentation-team
docs/reference/        @technical-leads
```

### Review Quality Metrics

Track review effectiveness:

```bash
# Review metrics collection
# Weekly review report
echo "Documentation Review Report - $(date +%Y-%m-%d)"
echo "=============================================="
echo "Files reviewed: $(git log --since="1 week ago" --name-only --pretty=format: docs/ | sort -u | wc -l)"
echo "Issues found: $(grep -c "TODO\|FIXME\|XXX" docs/**/*.md)"
echo "Broken links: $(markdown-link-check docs/**/*.md 2>&1 | grep -c "✖")"
echo "Outdated references: $(grep -c "v1\.30\|old-version" docs/**/*.md)"
```

## Community Contributions

### Contribution Guidelines

For external contributors:

1. **Issue Creation**: Create issue before major documentation changes
2. **Style Compliance**: Follow established style guide
3. **Technical Accuracy**: Ensure all procedures are tested
4. **Clear Scope**: Keep changes focused and reviewable

### Review Process for Contributions

```bash
# Community contribution review process
# 1. Automated validation
#    - Pre-commit hooks run automatically
#    - CI pipeline validates content

# 2. Technical review
#    - Subject matter expert reviews accuracy
#    - Maintainer reviews for consistency

# 3. Editorial review
#    - Documentation team reviews for clarity
#    - Style and format validation

# 4. Testing validation
#    - Procedures tested in isolated environment
#    - Commands and examples verified
```

### Recognition and Attribution

```markdown
# Contributors section in relevant documents
## Contributors

This document has been improved by the following contributors:

- [@username](https://github.com/username) - Added troubleshooting section
- [@contributor](https://github.com/contributor) - Updated command examples
- [@expert](https://github.com/expert) - Technical accuracy review
```

## Documentation Metrics

### Usage Analytics

Track documentation effectiveness:

```bash
# Analytics collection (if using documentation platform)
# Track:
# - Page views and popular content
# - Search queries and results
# - User feedback and ratings
# - Time spent on pages
# - Exit points and bounce rates

# GitHub-specific metrics
# Track:
# - File edit frequency
# - Pull request documentation changes
# - Issue reports related to documentation
# - Contributor activity in docs/
```

### Quality Metrics

```bash
# Documentation quality dashboard
echo "Documentation Quality Metrics"
echo "=============================="
echo "Total documentation files: $(find docs/ -name "*.md" | wc -l)"
echo "Lines of documentation: $(cat docs/**/*.md | wc -l)"
echo "Average file size: $(find docs/ -name "*.md" -exec wc -l {} \; | awk '{sum+=$1; count++} END {print sum/count}')"
echo "Files with TODO items: $(grep -l "TODO\|FIXME" docs/**/*.md | wc -l)"
echo "External links: $(grep -ho 'https\?://[^\s\)]*' docs/**/*.md | wc -l)"
echo "Code blocks: $(grep -c '```' docs/**/*.md | awk '{sum+=$1} END {print sum}')"
```

### Improvement Tracking

```bash
# Monthly improvement tracking
# Track improvements in:
# - Reduced support requests for documented procedures
# - Faster onboarding times
# - Fewer errors in operational procedures
# - Increased self-service capability

# Document improvement initiatives
echo "Documentation Improvement Initiatives"
echo "======================================"
echo "This month's focus areas:"
echo "- Improved troubleshooting coverage"
echo "- Better cross-references between documents" 
echo "- More comprehensive examples"
echo "- Video tutorials for complex procedures"
```

## Tool and Process Maintenance

### Documentation Tools

#### Core Tools

```bash
# Required tools for documentation maintenance
tools:
  - markdownlint: "Markdown linting and style checking"
  - prettier: "Code and markdown formatting"
  - markdown-link-check: "Link validation"
  - yq: "YAML processing for frontmatter"
  - vale: "Prose linting and style checking"

# Installation and updates
npm install -g markdownlint-cli markdown-link-check prettier
pip install yq
```

#### Advanced Tools

```bash
# Advanced documentation tools
# Consider for future implementation:
# - GitBook or similar for better presentation
# - Algolia or similar for search functionality
# - Sphinx for more complex documentation needs
# - MkDocs for material design documentation
```

### Process Automation

#### Automated Updates

```bash
# Automated version updates
# .github/workflows/update-versions.yml
name: Update Documentation Versions
on:
  schedule:
    - cron: '0 6 * * 1'  # Weekly on Monday

jobs:
  update-versions:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Update Kubernetes versions
        run: |
          # Fetch latest stable Kubernetes version
          LATEST_K8S=$(curl -s https://api.github.com/repos/kubernetes/kubernetes/releases/latest | jq -r .tag_name)
          
          # Update documentation references
          find docs/ -name "*.md" -exec sed -i "s/v1\.30\.[0-9]/$(echo $LATEST_K8S | sed 's/v//')/g" {} \;
      
      - name: Update tool versions
        run: |
          # Update mise tool versions
          mise outdated --json | jq -r '.[] | "\(.name) \(.current) \(.latest)"' | \
          while read name current latest; do
            if [ "$current" != "$latest" ]; then
              echo "Updating $name from $current to $latest"
              sed -i "s/$name.*$current/$name $latest/g" docs/**/*.md
            fi
          done
      
      - name: Create pull request
        run: |
          git add docs/
          git commit -m "docs: automated version updates" || exit 0
          # Create PR with automation
```

#### Content Generation

```bash
# Automated content generation
# Generate command reference documentation
generate-command-docs() {
  echo "# Command Reference" > docs/reference/commands.md
  echo "Generated: $(date)" >> docs/reference/commands.md
  echo "" >> docs/reference/commands.md
  
  # Extract task commands
  task --list | while read line; do
    if [[ $line =~ ^[[:space:]]*([^[:space:]]+):[[:space:]]*(.+) ]]; then
      task_name="${BASH_REMATCH[1]}"
      task_desc="${BASH_REMATCH[2]}"
      echo "## $task_name" >> docs/reference/commands.md
      echo "$task_desc" >> docs/reference/commands.md
      echo '```bash' >> docs/reference/commands.md
      echo "task $task_name" >> docs/reference/commands.md
      echo '```' >> docs/reference/commands.md
      echo "" >> docs/reference/commands.md
    fi
  done
}
```

### Maintenance Calendar

#### Monthly Tasks Schedule

| Week | Focus Area | Activities |
|------|------------|------------|
| Week 1 | Content Accuracy | Test procedures, validate commands |
| Week 2 | Link Validation | Check internal and external links |
| Week 3 | Style and Format | Lint, format, style guide compliance |
| Week 4 | Structure Review | Organize content, improve navigation |

#### Quarterly Initiatives

| Quarter | Initiative | Goal |
|---------|------------|------|
| Q1 | Architecture Documentation | Update system designs and decisions |
| Q2 | Operations Procedures | Improve troubleshooting and procedures |
| Q3 | User Experience | Enhance getting started and tutorials |
| Q4 | Reference Materials | Update technical references and examples |

## Best Practices

### Documentation Maintenance Principles

1. **Proactive Updates**: Update documentation with system changes
2. **User-Centric Focus**: Prioritize user needs and common use cases
3. **Automation Where Possible**: Automate repetitive maintenance tasks
4. **Community Engagement**: Encourage and facilitate community contributions
5. **Continuous Improvement**: Regular evaluation and enhancement of processes

### Common Pitfalls to Avoid

1. **Outdated Information**: Regular validation prevents stale content
2. **Broken Links**: Automated checking catches broken references
3. **Inconsistent Style**: Style guides and linting maintain consistency
4. **Missing Context**: Always explain why, not just how
5. **Overly Complex Language**: Keep technical content accessible

### Maintenance Efficiency Tips

1. **Batch Similar Updates**: Group related changes together
2. **Use Templates**: Standardize common document types
3. **Leverage Automation**: Automate validation and basic maintenance
4. **Collaborate Effectively**: Clear ownership and review processes
5. **Measure Impact**: Track metrics to focus improvement efforts

Remember: Documentation maintenance is an investment in operational excellence. Well-maintained documentation reduces support overhead, improves system reliability, and enables team growth and knowledge transfer.
