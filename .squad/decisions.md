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
