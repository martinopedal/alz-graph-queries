# Squad Decisions

## Workflow SHA-Pinning Audit and Remediation

**Date:** 2026-05-13  
**Author:** Forge  
**Status:** Implemented in PR #55

### Context

During Dependabot PR review (#46-50), discovered inconsistent SHA-pinning across workflows:

**Policy (from `.github/copilot-instructions.md`):**
> All GitHub Actions `uses:` MUST be pinned to a commit SHA, not a tag

**Current State:**
- ✅ `validate-example.yml` - Mixed: checkout@SHA, but azure/powershell@v2 (bare tag)
- ✅ `auto-label-issues.yml` - SHA-pinned (github-script)
- ✅ `ci-failure-analysis.yml` - SHA-pinned (github-script)
- ⚠️ `squad-*.yml` (11 files) - Mix of `@v4`, `@v6`, `@v7` bare tags

**Impact:**
- PR #47 (azure/powershell v2→v3) blocked - cannot merge until SHA-pinning fixed
- Validate-example workflow failing on main due to bare tag policy violation

### Decision

Audit all workflows and pin all `uses:` to commit SHAs. Immediate upgrade of azure/powershell to v3 to unblock Dependabot PR #47.

### Implementation

**SHA mappings applied:**
- `actions/checkout@v6.0.2` → `de0fac2e4500dabe0009e67214ff5f5447ce83dd`
- `actions/upload-artifact@v4.6.2` → `ea165f8d65b6e75b540449e92b4886f43607fa02`
- `actions/github-script@v9.0.0` → `3a2844b7e9c422d3c10d287c895573f7108da1b3`
- `azure/powershell@v3.0.0` → `f5b8adcfff1904872c7b98d4012d4914d74b1a82`

**Files updated:** 13 workflows (validate-example.yml, all squad-*.yml, ci-failure-analysis.yml, auto-label-issues.yml)

## CI Failure Analysis: Handle Cancelled Jobs

**Date:** May 13, 2026  
**Author:** Lead  
**Status:** Implemented in PR #55

### Problem

The CI Failure Analysis workflow (`.github/workflows/ci-failure-analysis.yml`, line 33) filtered failed jobs only by `conclusion === 'failure'`. When jobs had `conclusion === 'cancelled'`, they were excluded from the failure report, resulting in issues filed with "Failed jobs: none" — noisy and misleading.

**Evidence:** Issues #51 and #52 both reported "Failed jobs: none" but the jobs were actually cancelled due to timeout/rate limit on May 5-6.

### Decision

Extended filter to `j.conclusion === 'failure' || j.conclusion === 'cancelled'`. Cancelled jobs are real CI failures (they blocked forward progress), even if the root cause differs.

### Implementation

Changed line 36-37 in `ci-failure-analysis.yml` from:
```javascript
const failedJobs = jobsResp.data.jobs.filter(
  j => j.conclusion === 'failure'
);
```
to:
```javascript
const failedJobs = jobsResp.data.jobs.filter(
  j => j.conclusion === 'failure' || j.conclusion === 'cancelled'
);
```

## APRL Integration Recommendation

**Date:** 2026-05-13  
**Author:** Sage  
**Issue:** #58  
**Status:** Decision (Phase 2 item)

### TL;DR

- **Conditional-Go.** Import 150-200 high-value APRL queries in Phase 2 (Reliability + Performance categories, Azure core services only).
- APRL queries lack a `compliant` column — requires post-processing to add `compliant = 0` (all APRL queries return violations, never evidence).
- License compatible (MIT), actively maintained (last commit 2026-05-11), schema maps cleanly except for queryIntent — APRL assumes `findViolations` for all queries.

### Effort Estimate

**Size: Large (L)**

| Work Unit | Hours |
|---|---|
| Extraction script | 16-20 |
| Schema mapping | 8-10 |
| Validation pass | 12-16 |
| Integration tests | 8-10 |
| Docs | 6-8 |
| Curation | 8-12 |
| **Total** | **58-76 hours (7-10 days FTE)** |

### Go/No-Go/Conditional-Go

**Conditional-Go** — proceed with Tranche 1 (100-120 Reliability/Performance queries) if:

1. Phase 2 is confirmed (this is a Phase 2 item per `.squad/decisions.md` line 122)
2. ALZ baseline architecture review confirms service list (AKS, Storage, SQL, VMs, Networking, API Management, Cosmos DB, Key Vault, App Service)
3. Dedupe strategy confirmed (prefer our existing 132 queries where overlap exists)

**Defer Tranche 2** (Security/Governance queries) until Tranche 1 proves value.

### Rationale

APRL offers 451 production-ready ARG queries with high ALZ relevance (HA/DR/Performance). Importing 150-200 queries would triple our coverage from 132 to ~280-330 automated checks. The effort is justified if:

- Query quality meets our validation standards (offline + runtime syntax checks)
- Dedupe removes redundancy with our existing queries
- Curation filters out non-ALZ queries (niche services like AVS, Azure Large Instance)

The risk is maintenance burden (APRL evolves; quarterly re-import needed). Mitigation: document APRL snapshot date and commit SHA for traceability.

---

**Full research brief:** `.squad/aprl-extraction-research.md`

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
# Squad Decisions

## Active Decisions

## Tool Registry — azure-analyzer Bundle Candidates (Sage, 2026-04-14)

Researched: 2026-04-14 by Sage

### Evaluation Criteria

Tools must pass all five gates to be included:
1. Runs locally with no cost
2. Reader permissions only (Azure, ADO, GitHub)
3. Produces structured output parseable by PowerShell (JSON or CSV)
4. Actively maintained (commit within 12 months of eval date)
5. CLI or PowerShell invocable without a GUI

---

### Approved Bundle

| Tool | Repo | What it does | Output | Runtime | License | Notes |
|------|------|-------------|--------|---------|---------|-------|
| **azqr** | [Azure/azqr](https://github.com/Azure/azqr) | Best-practice / compliance review across 60+ Azure service types | JSON, CSV, Excel | Go binary (cross-platform) | MIT | Active 2026-04-14. Single binary, no install needed. Azure Reader sufficient. |
| **PSRule for Azure** | [Azure/PSRule.Rules.Azure](https://github.com/Azure/PSRule.Rules.Azure) | Validates Azure resources + IaC against Azure Well-Architected rules | Console tables, JSON, SARIF | PowerShell module | MIT | Active 2026-04-14. `Export-AzRuleData` with Reader role only. |
| **AzGovViz** | [Azure/Azure-Governance-Visualizer](https://github.com/Azure/Azure-Governance-Visualizer) | Full Azure governance inventory: MG hierarchy, RBAC, Policy, Blueprints | CSV, JSON, HTML, Markdown | PowerShell script | MIT | Active 2025-05-27. Needs Reader + specific Graph read permissions — document in PERMISSIONS.md. |
| **checklist-graph.sh** | [Azure/review-checklists](https://github.com/Azure/review-checklists) | Runs ARG queries from the ALZ checklist JSON | JSON, text | Bash + Azure CLI + jq | MIT | Active 2026-02-25. PowerShell wrapper needed on Windows. |
| **alz-graph-queries** | [martinopedal/alz-graph-queries](https://github.com/martinopedal/alz-graph-queries) | Extended ARG queries for 135+ ALZ checklist items | JSON, CSV | PowerShell + Az.ResourceGraph | MIT | This repo — the foundation. |

---

### Rejected Tools

| Tool | Reason |
|------|--------|
| WARA-RelQ | Output is Markdown only, not structured JSON/CSV for programmatic parsing |
| Azure Proactive Resiliency Library v2 (APRL) | Query library, not a standalone runnable scanner |
| Azure Orphan Resources | Portal workbook artifact only, no CLI execution |
| AzSK / Secure DevOps Kit | Sunset / not actively maintained (last commit 2024-05) |
| CCO Insights | Power BI dashboard only, not a scriptable/CLI analyzer |

---

### APRL Note

APRL (https://github.com/Azure/Azure-Proactive-Resiliency-Library-v2) contains hundreds of ARG queries for resiliency checks. These queries can be extracted and run directly — they are not a runnable tool but the query library could be incorporated into azure-analyzer as a separate check category. **Recommendation:** Sage to research APRL query extraction as a Phase 2 item.

---

### Required Permissions Summary (for azure-analyzer PERMISSIONS.md)

| Tool | Azure Role | ADO | GitHub |
|------|-----------|-----|--------|
| azqr | Reader (subscription scope) | — | — |
| PSRule for Azure | Reader (subscription scope) | — | — |
| AzGovViz | Reader + Directory.Read.All (Graph) | — | — |
| checklist-graph.sh | Reader (subscription scope) | — | — |
| alz-graph-queries (ARG) | Reader (subscription/MG scope) | — | — |
| Iris checks (Entra/Graph) | Policy.Read.All, Directory.Read.All, RoleManagement.Read.All | — | — |
| Forge checks (ADO) | — | Code/Build/Release/Project (Read) | — |
| Forge checks (GitHub) | — | — | repo:read, security_events:read |

---

## Writing Style — All Documentation and Reports (Sage, 2026-04-14)

Source: martinopedal/news-fetcher (private) — src/drafts/voice_profile.md + .github/copilot-instructions.md
Applies to: READMEs, HTML reports, Markdown reports, PR descriptions, issue comments, all generated text

---

### Who is writing

Martin Opedal. Lead Cloud Solution Architect at Microsoft, 14 years experience. MSP background. Co-founder of a brewery. Writes from direct hands-on experience — not theory. Real examples: ALZ Terraform modules, Bicep subscription vending, Azure Policy exemptions, Karpenter node provisioning, Application Gateway for Containers.

---

### Core voice rules

- **Open directly.** Position or finding in the first sentence. No "In today's landscape", no "As we all know."
- **Conclusions before reasoning.** Answer first, explain second. Never build to a reveal.
- **Concrete over abstract.** Name the specific resource, the policy, the KQL table — not "the configuration."
- **Pragmatic over theoretical.** What works in production beats what looks good in a diagram.
- **Accountable.** If something is wrong or incomplete, say so plainly. No passive-voice deflection.

### Banned phrases and patterns

- Em dashes and en dashes (use commas, periods, or "and")
- "leveraging", "unlocking", "driving", "game-changer", "comprehensive", "robust", "cutting-edge"
- "In today's landscape", "at the end of the day", "it goes without saying"
- "I'm excited to share", "Thrilled to announce", "deep dive into"
- "journey" for career progression
- Emojis in technical writing
- 4-paragraph symmetry — vary structure

### Structure rules

- Mix long paragraphs with short punchy lines
- Sometimes skip the intro and start with the finding
- Sometimes end abruptly after the strongest statement
- Never follow intro → 3 points → conclusion every time
- End on statements at least as often as questions

### README-specific rules (from copilot-instructions)

- **Always update README.md when changing features, config, or architecture** — never let it go stale
- Keep docs concise — never over-documented
- Problem first, solution second, then usage

### HTML reports (azure-analyzer)

- Single-file, offline-capable
- One accent colour, neutral background — clean, not corporate
- Severity badges: Critical (red), High (orange), Medium (yellow), Low (grey-blue)
- Status badges: Compliant (green), Non-Compliant (red), Manual Review (grey)
- Top-of-page summary: total checked, % compliant, top 3 findings
- Per-category accordions, sortable tables
- No animations — must open without internet

### Markdown reports

- H2 for categories, H3 for subcategories
- Tables for structured compliance data
- Bold for resource names and severity labels
- Code blocks for KQL queries and remediation commands
- Fix-now / Plan-to-fix / Track groupings from Sentinel

### Quality check (before any PR)

1. Does the first sentence state the finding or purpose directly?
2. Is there at least one specific technical detail — not a generic statement?
3. Is it free of em-dashes, emojis, and AI-sounding phrases?
4. Is the README updated to reflect the change?

---

### Core Principles

- **Open directly.** State a position or finding in the first sentence. No warm-up phrases.
- **Conclusions before reasoning.** Give the answer first, then explain why.
- **Concrete over abstract.** Name specific resources, settings, and tools — not "the configuration" but "the NSG rule on subnet X".
- **Vary structure.** No uniform section lengths. Mix long paragraphs, short punchy lines, single observations.
- **End on statements, not always questions.** Especially in reports.

### Banned Phrases and Patterns

- Em dashes and en dashes (use commas, periods, or "and")
- "leveraging", "unlocking", "driving", "game-changer", "comprehensive", "robust", "cutting-edge"
- "In today's landscape", "at the end of the day", "it goes without saying"
- "I'm excited to share", "Thrilled to announce"
- "Deep dive into"
- Emojis in technical writing
- Numbered lists where every post/section follows "first this, then this, finally this" pattern

### HTML Reports (azure-analyzer)

- Clean, modern design — not corporate marketing style
- Use a single consistent color palette (one accent color, neutral background)
- Tables for compliance data — sortable where possible
- Severity badges: Critical (red), High (orange), Medium (yellow), Low (blue/grey)
- Status badges: Compliant (green), Non-Compliant (red), Manual Review (grey)
- No animations or heavy JS — reports should open offline
- Top-level summary card: total items checked, % compliant, top 3 risks
- Per-category accordion sections
- "Fix now / Plan to fix / Track" groupings from Sentinel

### Markdown Reports

- H2 for categories, H3 for subcategories
- Tables for structured data
- Bold for resource names and finding severity
- Code blocks for ARG queries or remediation snippets
- No HTML inside markdown files
- README files: problem first, solution second, then usage

### AI Governance (applies to all repo documentation)

- PRs disclose meaningful AI assistance
- No secrets or credentials in any file
- Verify non-obvious technical claims against authoritative sources before committing

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
