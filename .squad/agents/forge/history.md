# Project Context

- **Owner:** martinopedal
- **Project:** ALZ Additional Graph Queries — DevOps/Platform API checks for ALZ platform items
- **Stack:** PowerShell, Azure DevOps REST API, GitHub REST API / gh CLI, JSON
- **Created:** 2026-04-14

## Learnings

### 2026-05-13: Workflow SHA-Pinning Remediation (PR #55)

**SHA-pinned 13 workflows** - Audited all `.github/workflows/*.yml` files and converted bare tag references to commit SHA pins:
- `validate-example.yml` - Upgraded `azure/powershell@v2` → `@v3` (SHA: f5b8adcfff1904872c7b98d4012d4914d74b1a82) - unblocks Dependabot PR #47
- `squad-*.yml` (11 files) - Converted `actions/checkout@v6`, `actions/upload-artifact@v7`, `actions/github-script@v9` to SHA pins
- `ci-failure-analysis.yml` - Extended filter to capture cancelled jobs: `j.conclusion === 'failure' || j.conclusion === 'cancelled'` (line 36-37)

**SHA lookup strategy** - Used `gh api repos/{owner}/{repo}/commits/{tag}` to resolve tag → commit SHA. Verified with grep that no bare tags remain.

**CI fix location** - `.github/workflows/ci-failure-analysis.yml`, line 36-37: changed job filter to include both `failure` and `cancelled` conclusions.

**PR opened** - #55 on branch `squad/workflow-remediation-2026-05-13`. Consolidated both Forge and Lead decision proposals into a single remediation PR per repo policy (all CI changes in one atomic commit).
# Project Context

- **Owner:** martinopedal
- **Project:** ALZ Additional Graph Queries — DevOps/Platform API checks for ALZ platform items
- **Stack:** PowerShell, Azure DevOps REST API, GitHub REST API / gh CLI, JSON
- **Created:** 2026-04-14

## Team Updates

- 2026-05-13: Writing style decision merged into .squad/decisions.md — applies to all docs, READMEs, reports, PR descriptions. See decisions.md.

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->
