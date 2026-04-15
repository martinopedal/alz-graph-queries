# Changelog

All notable changes to this project will be documented here.

## [Unreleased]

## [1.1.0] — 2026-04-15

### Added

- **`scripts/Invoke-GraphApi.ps1`** — 7 Microsoft Graph API checks for Entra ID / identity posture:
  conditional access policies, MFA enforcement, PIM eligible assignments, break-glass accounts,
  security defaults, named locations, and permanent Global Admin assignments.
  Returns results in the unified ALZ check contract. Closes #11.
- **`scripts/Invoke-CostManagementApi.ps1`** — 6 Azure Cost Management API checks for budget
  governance: budget presence, alert thresholds, threshold-exceeded detection (≥ 80%), cost anomaly
  alerts, orphaned managed disks, and unused public IPs. Closes #12.
- **`scripts/Invoke-DevOpsApi.ps1`** — 8 GitHub / Azure DevOps governance checks: branch protection,
  required reviewers, secret scanning, Dependabot alerts, CODEOWNERS file presence, ADO branch
  policies, pipeline approvals, and audit log streaming. Closes #9.
- Pester test suites for all three new modules
  (`Tests/Invoke-GraphApi.Tests.ps1`, `Tests/Invoke-CostManagementApi.Tests.ps1`,
  `Tests/Invoke-DevOpsApi.Tests.ps1`) — 86 additional unit tests (25 + 19 + 42).
- `queryIntent` field (`findViolations` / `findEvidence`) on all 132 ARG query items in
  `queries/alz_additional_queries.json` for unified result contract semantics.
- Markdown (`-ReportFormat Markdown`) and HTML (`-ReportFormat HTML`) report output from
  `Validate-Queries.ps1` via new `Export-MarkdownReport` and `Export-HtmlReport` functions.
- Authentication waterfall in `Validate-Queries.ps1`: SPN (cert → secret → WIF), Managed Identity,
  device code, and ambient `Az.Accounts` context via `Invoke-AzAuth`; management-group scope support.
- `validate-example.yml` — example OIDC workflow showing how to run `Validate-Queries.ps1` in CI.
- Pester test scaffold and KQL offline validator in `squad-ci.yml` (`PowerShell Tests` +
  `KQL Syntax Validation` required CI jobs).
- `PERMISSIONS.md` expanded with Microsoft Graph API, Cost Management, and Azure DevOps
  permission requirements for all Phase 4 modules.

### Fixed

- Removed stray `>>>>>>>` conflict-marker lines from `process_items.ps1`.
- Encoding artefacts (`ÔÇö` → `-`) and double-dash (`--` → `-`) style issues in
  `Validate-Queries.ps1` comments and help text.
- `throw @"` here-string refactored for cross-platform PowerShell compatibility.
- Cross-platform path fixes in Pester tests for Linux CI runners.
- Safe property access in KQL validator (`?.` null-conditional guards).

### Changed

- `Validate-Queries.ps1` result objects now include `queryIntent`, `reportSection`,
  and `findingType` fields for downstream consumption by the Phase 4 modules.

## [1.0.0] — 2026-04-15

### Added
- 132 new Azure Resource Graph queries covering 206 previously-uncovered ALZ checklist items
- Coverage increased from 135/255 (53%) to 181/255 (71%)
- Wave 1: networking, security, management, governance, resource organisation queries
- Wave 2: hybrid/on-premises ARG-visible items converted to queries
- `Validate-Queries.ps1` — runs all queries against your Azure environment, outputs CSV results
- `auto-label-issues.yml` — auto-applies `squad` label to every new issue
- `ci-failure-analysis.yml` — opens a `bug` + `squad` issue on any workflow failure
- Squad team initialised (Lead, Atlas, Iris, Forge, Sentinel, Sage, Scribe, Ralph)
- Phase 2 roadmap issues: Microsoft Graph API (#11), Cost Management API (#12), GitHub/ADO API (#9)
