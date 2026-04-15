# Work Routing

How to decide who handles what.

## Work Type → Agent

| Work Type | Route To | Examples |
|-----------|----------|----------|
| ARG KQL queries | Atlas | New checklist item queries, query fixes, EMPTY/ERROR investigation, `alz_additional_queries.json` changes |
| ARG schema & table research | Atlas | Checking whether a resource type is queryable via ARG, supported tables |
| Query validation | Atlas | `Validate-Queries.ps1` failures, query syntax issues, scope-aware testing |
| Entra ID / Microsoft Graph checks | Iris | Conditional Access, PIM, MFA, emergency accounts, Entra Connect, identity RBAC |
| Graph API permissions | Iris | Required scopes, `PERMISSIONS.md` updates for Graph API |
| Azure DevOps API checks | Forge | Branch policies, pipelines, service connections, variable groups |
| GitHub API checks | Forge | Branch protection, secret scanning, Dependabot, CODEOWNERS, Actions workflows |
| CI/CD & workflow maintenance | Forge | Squad workflows, GitHub Actions YAML, pipeline health |
| Recommendation aggregation / scoring | Sentinel | Unified output format, severity weighting, azqr integration, report generation |
| Repository security standards | Sentinel | Secret scanning status, Dependabot alerts, branch protection validation |
| Pre-build research / tool scouting | Sage | "Does this already exist?", tool bundling candidates, API capability research, breaking-change impact |
| Issue triage & task decomposition | Lead | All `squad`-labeled issues, design reviews, PR sign-off |
| Code review | Lead | Review PRs, check quality, enforce conventions |
| Scope & priorities | Lead | What to build next, trade-offs, cross-agent decisions |

## Module Ownership

| Path | Owner | Notes |
|------|-------|-------|
| `queries/` | Atlas | ARG query JSON files — all KQL queries live here |
| `alz_checklist_full.json` | Atlas | Full ALZ checklist with query mappings |
| `items_no_query.json` | Atlas | Items without queries — routes to Iris/Forge when non-ARG |
| `items_without_queries.csv` | Atlas | CSV export of unqueried items |
| `Validate-Queries.ps1` | Atlas | Query validation script — schema + ARG execution |
| `process_items.ps1` | Atlas | Checklist item processing pipeline |
| `Tests/` | Atlas | Pester tests for query validation |
| `scripts/` | Forge | Automation and helper scripts |
| `.github/workflows/` | Forge | CI/CD workflows, squad workflows |
| `PERMISSIONS.md` | Iris | API permission documentation (Graph, ADO, GitHub) |
| `.squad/` | Lead | Team config, routing, decisions, agent charters |
| `README.md` | Lead | Project documentation |
| `CHANGELOG.md` | Lead | Release history |
| `CONTRIBUTING.md` | Lead | Contribution guidelines |

## Issue Routing

| Label | Action | Who |
|-------|--------|-----|
| `squad` | Triage: analyze issue, assign `squad:{member}` label | Lead |
| `squad:{name}` | Pick up issue and complete the work | Named member |

### How Issue Assignment Works

1. When a GitHub issue gets the `squad` label, the **Lead** triages it — analyzing content, assigning the right `squad:{member}` label, and commenting with triage notes.
2. When a `squad:{member}` label is applied, that member picks up the issue in their next session.
3. Members can reassign by removing their label and adding another member's label.
4. The `squad` label is the "inbox" — untriaged issues waiting for Lead review.

## Rules

1. **Eager by default** — spawn all agents who could usefully start work, including anticipatory downstream work.
2. **Scribe always runs** after substantial work, always as `mode: "background"`. Never blocks.
3. **Quick facts → coordinator answers directly.** Don't spawn an agent for "what port does the server run on?"
4. **When two agents could handle it**, pick the one whose domain is the primary concern.
5. **"Team, ..." → fan-out.** Spawn all relevant agents in parallel as `mode: "background"`.
6. **Anticipate downstream work.** If a feature is being built, spawn the tester to write test cases from requirements simultaneously.
7. **Issue-labeled work** — when a `squad:{member}` label is applied to an issue, route to that member. The Lead handles all `squad` (base label) triage.