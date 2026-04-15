# Changelog

All notable changes to this project will be documented here.

## [Unreleased]

## [1.1.0] — 2026-04-15

### Added

- **`-ReportFormat CSV|Markdown|HTML|All`** parameter on `Validate-Queries.ps1` for flexible output;
  CSV is the default, `All` writes all three in one pass.
- **`Invoke-AzAuth`** 8-step authentication waterfall: ambient context → interactive browser →
  device code (`-UseDeviceCode`) → Managed Identity (`-UseIdentity`) → Workload Identity Federation
  (env vars) → SPN certificate → SPN secret → fail with guidance.
- **SkipToken pagination** in `Validate-Queries.ps1`: ARG queries returning > 1000 rows are
  automatically paged to completion.
- **`queryIntent` field** (`findViolations` / `findEvidence`) on all 132 ARG query items:
  `findViolations` — rows returned mean non-compliance (FAIL);
  `findEvidence` — rows returned mean the control exists (PASS).
- **`scripts/Validate-KqlSyntax.ps1`** — offline KQL validator using the Kusto.Language NuGet
  package; runs as a required CI gate (`KQL Syntax Validation` job in `squad-ci.yml`).
- **`scripts/Invoke-GraphApi.ps1`** — 7 Microsoft Graph / Entra ID compliance checks:
  conditional access policies, MFA enforcement, PIM eligible assignments, break-glass accounts,
  security defaults, named locations, and permanent Global Admin assignments. Closes #11.
- **`scripts/Invoke-CostManagementApi.ps1`** — 6 Azure Cost Management governance checks:
  budget presence, alert thresholds, threshold-exceeded detection (>= 80%), cost anomaly alerts,
  orphaned managed disks, and unused public IPs. Closes #12.
- **`scripts/Invoke-DevOpsApi.ps1`** — 8 GitHub / Azure DevOps maturity checks: branch protection,
  required reviewers, secret scanning, Dependabot alerts, CODEOWNERS file presence, ADO branch
  policies, pipeline approvals, and audit log streaming. Closes #9.
- **Pester 5 test suite** (`Tests/Validate-Queries.Tests.ps1`) for core script: auth waterfall,
  report generation, pagination, and result contract.
- Pester test suites for all three API modules:
  `Tests/Invoke-GraphApi.Tests.ps1` (25 tests),
  `Tests/Invoke-CostManagementApi.Tests.ps1` (19 tests),
  `Tests/Invoke-DevOpsApi.Tests.ps1` (42 tests).
- `validate-example.yml` — example OIDC GitHub Actions workflow.
- `PERMISSIONS.md` — comprehensive permissions reference for ARG, Graph API, Cost Management, and DevOps.

### Fixed

- `.Data.Rows.Count` wrapper bug — row count was always returning 1 regardless of actual results.
- FAIL/OK semantics inverted — non-compliant resources are now correctly flagged as FAIL.
- Hardcoded absolute paths replaced with `$PSScriptRoot`-relative paths throughout.
- `$env:TEMP` null on Linux — replaced with `[System.IO.Path]::GetTempPath()`.

### Changed

- `Validate-Queries.ps1` result objects now include `queryIntent`, `reportSection`,
  and `findingType` fields for downstream consumption by the API modules.

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
