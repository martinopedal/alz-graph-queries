# ALZ Graph Queries

Validates **Azure Landing Zone (ALZ) checklist items** using Azure Resource Graph KQL queries and complementary API modules. Produces CSV, Markdown, or HTML compliance reports.

## Overview

`Validate-Queries.ps1` runs 132+ ARG queries against your Azure environment and reports PASS/FAIL against the ALZ checklist. Three companion scripts extend coverage to identity, cost, and DevOps signals that ARG cannot reach:

| Module | Checks | Coverage area |
|---|---|---|
| `Validate-Queries.ps1` (core) | 132 ARG queries | Network, Security, Governance, Management |
| `scripts/Invoke-GraphApi.ps1` | 7 checks | Entra ID / identity posture |
| `scripts/Invoke-CostManagementApi.ps1` | 6 checks | Budget and cost governance |
| `scripts/Invoke-DevOpsApi.ps1` | 8 checks | GitHub / Azure DevOps maturity |

All modules share the same authentication parameters and return results in a unified contract (`status`, `evidenceCount`, `queryIntent`).

## Quick Start

```powershell
# 1. Log in
Connect-AzAccount -TenantId "<your-tenant-id>"

# 2. Run (scoped to a subscription)
.\Validate-Queries.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000"

# 3. Open the report
Start-Process .\validation_results.html   # or .csv / .md
```

## Usage

```
.\Validate-Queries.ps1 [-SubscriptionId <id>] [-ManagementGroup <id>]
                        [-ReportFormat CSV|Markdown|HTML|All]
                        [-UseDeviceCode] [-UseIdentity]
                        [-TenantId <id>] [-ClientId <id>]
                        [-ClientSecret <secret>] [-CertificatePath <path>]
```

| Parameter | Description |
|---|---|
| `-SubscriptionId` | Scope queries to a single subscription |
| `-ManagementGroup` | Scope queries to a management group (and all child subscriptions) |
| `-ReportFormat` | Output format: `CSV` (default), `Markdown`, `HTML`, or `All` |
| `-UseDeviceCode` | Force device code flow (headless / SSH sessions) |
| `-UseIdentity` | Use system-assigned Managed Identity |
| `-TenantId` | Tenant ID for SPN or explicit auth |
| `-ClientId` | Application (client) ID for SPN auth |
| `-ClientSecret` | Client secret for SPN auth |
| `-CertificatePath` | PFX path for SPN certificate auth |

## Authentication

`Invoke-AzAuth` tries methods in priority order — the first that succeeds is used:

| # | Method | When to use | How to activate |
|---|--------|-------------|-----------------|
| 1 | Existing `Az.Accounts` context | Local dev (already logged in) | Run `Connect-AzAccount` before the script |
| 2 | Interactive browser | Local dev (no existing context) | Run as-is — browser opens automatically |
| 3 | Device code | Headless / SSH sessions | `-UseDeviceCode` |
| 4 | Managed Identity | Azure VMs, Container Apps, AKS | `-UseIdentity` |
| 5 | Workload Identity Federation | GitHub Actions OIDC | Set `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_FEDERATED_TOKEN_FILE` env vars |
| 6 | Service Principal (certificate) | CI/CD pipelines | `-TenantId`, `-ClientId`, `-CertificatePath` |
| 7 | Service Principal (secret) | CI/CD pipelines (legacy) | `-TenantId`, `-ClientId`, `-ClientSecret` |
| 8 | Fail with guidance | — | All methods exhausted |

See [PERMISSIONS.md](./PERMISSIONS.md) for role assignments and setup instructions.

## Report Formats

| Format | Flag | Description |
|---|---|---|
| CSV | `-ReportFormat CSV` (default) | Raw data — `Id`, `Category`, `Status`, `RowCount`, `QueryIntent`, `Error` |
| Markdown | `-ReportFormat Markdown` | GitHub-renderable summary table with per-category breakdown |
| HTML | `-ReportFormat HTML` | Standalone offline report with summary cards and sortable findings table |
| All | `-ReportFormat All` | Writes CSV + Markdown + HTML in one pass |

## Additional API Modules

Three companion scripts in `scripts/` extend coverage beyond what ARG can see:

| Module | Checks | Permissions needed |
|---|---|---|
| `scripts/Invoke-GraphApi.ps1` | 7 Entra ID checks | `Policy.Read.All`, `RoleManagement.Read.Directory` (admin consent) |
| `scripts/Invoke-CostManagementApi.ps1` | 6 Cost Management checks | `Cost Management Reader` on subscription or MG |
| `scripts/Invoke-DevOpsApi.ps1` | 8 GitHub / ADO checks | `GITHUB_TOKEN` (`repo:read`); ADO PAT optional |

### `scripts/Invoke-GraphApi.ps1` — Entra ID (7 checks)

| Check | queryIntent |
|---|---|
| Conditional Access policies present | findEvidence |
| MFA enforced via CA policy | findEvidence |
| PIM eligible role assignments configured | findEvidence |
| Emergency / break-glass accounts present | findEvidence |
| Security defaults enforcement status | findEvidence |
| Named locations / trusted IPs defined | findEvidence |
| Permanent Global Administrator assignments | findViolations |

```powershell
.\scripts\Invoke-GraphApi.ps1 -TenantId "<tenant-id>"
.\scripts\Invoke-GraphApi.ps1 -TenantId "<tid>" -ClientId "<appId>" -CertificatePath ".\cert.pfx"
.\scripts\Invoke-GraphApi.ps1 -UseIdentity
```

### `scripts/Invoke-CostManagementApi.ps1` — Budget governance (6 checks)

| Check | queryIntent |
|---|---|
| Budgets configured at scope | findEvidence |
| Budget alert thresholds configured | findEvidence |
| Budget threshold exceeded (>= 80%) | findViolations |
| Cost anomaly alert actions present | findEvidence |
| Orphaned managed disks | findViolations |
| Unused public IP addresses | findViolations |

```powershell
.\scripts\Invoke-CostManagementApi.ps1 -SubscriptionId "<sub-id>"
.\scripts\Invoke-CostManagementApi.ps1 -ManagementGroup "<mg-id>" -UseIdentity
```

### `scripts/Invoke-DevOpsApi.ps1` — DevOps posture (8 checks)

| Check | Platform | queryIntent |
|---|---|---|
| Branch protection on default branch | GitHub | findViolations |
| Required reviewers on main branch | GitHub | findViolations |
| Secret scanning enabled | GitHub | findViolations |
| Dependabot / vulnerability alerts enabled | GitHub | findViolations |
| CODEOWNERS file present | GitHub | findEvidence |
| Branch policies on main | Azure DevOps | findViolations |
| Pipeline environment approvals required | Azure DevOps | findViolations |
| Audit log streaming enabled | Azure DevOps | findEvidence |

```powershell
.\scripts\Invoke-DevOpsApi.ps1 -Platform GitHub -Owner "my-org" -Repo "my-repo"
.\scripts\Invoke-DevOpsApi.ps1 -Platform AzureDevOps -AdoOrgUrl "https://dev.azure.com/my-org" -AdoPat "<pat>"
```

## Running in GitHub Actions

See [`.github/workflows/validate-example.yml`](./.github/workflows/validate-example.yml) for a complete OIDC workflow. Key steps:

```yaml
- uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

- name: Run ALZ validation
  run: |
    .\Validate-Queries.ps1 -ManagementGroup "${{ vars.ALZ_MGMT_GROUP }}" `
      -ReportFormat All `
      -TenantId "${{ secrets.AZURE_TENANT_ID }}" `
      -ClientId "${{ secrets.AZURE_CLIENT_ID }}"
```

## Offline KQL Validation

`scripts/Validate-KqlSyntax.ps1` validates all queries against the Kusto.Language NuGet package without an Azure connection:

```powershell
.\scripts\Validate-KqlSyntax.ps1
.\scripts\Validate-KqlSyntax.ps1 -QueriesFile ".\queries\alz_additional_queries.json"
```

This runs as a required CI gate (`KQL Syntax Validation` job in `squad-ci.yml`) on every PR.

## queryIntent Semantics

Every query declares whether rows indicate a problem or evidence of good posture:

| queryIntent | Rows returned mean | Result |
|---|---|---|
| `findViolations` | Non-compliant resources found | **FAIL** |
| `findEvidence` | Required control exists | **PASS** |

## Coverage

| Category | Original Queries | New Queries | Not Queryable | Total |
|---|---|---|---|---|
| Network Topology and Connectivity | 36 | 61 | 9 | 106 |
| Security | 2 | 23 | 7 | 32 |
| Management & Monitoring | 1 | 24 | 1 | 26 |
| Identity and Access Management | 7 | 1 | 16 | 24 |
| Resource Organization | 3 | 10 | 9 | 22 |
| Governance | 0 | 13 | 3 | 16 |
| Azure Billing & Entra ID Tenants | 0 | 0 | 15 | 15 |
| Platform Automation and DevOps | 0 | 0 | 14 | 14 |
| **Total** | **49** | **132** | **74** | **255** |

**181/255 items (71%) have automated queries**, up from 135/255 (53%).

Items not queryable via ARG are covered by the companion modules (`Invoke-GraphApi.ps1`, `Invoke-CostManagementApi.ps1`, `Invoke-DevOpsApi.ps1`) or require manual review.

## Tests

Pester 5 test suites live in `Tests/`:

| File | Coverage |
|---|---|
| `Tests/Validate-Queries.Tests.ps1` | Core script: auth waterfall, report generation, pagination |
| `Tests/Invoke-GraphApi.Tests.ps1` | Graph API module (25 tests) |
| `Tests/Invoke-CostManagementApi.Tests.ps1` | Cost Management module (19 tests) |
| `Tests/Invoke-DevOpsApi.Tests.ps1` | DevOps module (42 tests) |

Run locally:
```powershell
Invoke-Pester ./Tests/ -Output Detailed
```

The `PowerShell Tests` job in `squad-ci.yml` runs these on every PR.

## Prerequisites

- PowerShell 7+
- `Az.ResourceGraph` module — `Install-Module Az.ResourceGraph`
- `Az.Accounts` module — `Install-Module Az.Accounts`
- Reader access on subscriptions / management groups in scope

## Permissions

See [PERMISSIONS.md](./PERMISSIONS.md) for full role assignments, Graph API consent setup, and per-module requirements.

## Automation

| Workflow | Trigger | Purpose |
|---|---|---|
| `validate-example.yml` | Manual / schedule | Example OIDC run against your environment |
| `squad-ci.yml` | PR / push | KQL syntax validation + Pester tests |
| `ci-failure-analysis.yml` | Any workflow failure | Opens `bug` + `squad` issue with log excerpt |



## Data Sources & Attribution

The ALZ checklist query data in this repository is derived from the
[Azure Review Checklists](https://github.com/Azure/review-checklists) project
(© Microsoft Corporation, MIT License).

See [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md) for full attribution of all
incorporated open-source tools and data.

## License

MIT — queries provided as-is for assessment purposes.
