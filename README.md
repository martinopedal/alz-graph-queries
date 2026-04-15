# ALZ Additional Graph Queries

Azure Resource Graph (ARG) queries for **Azure Landing Zone checklist items** that are not covered by the original [Azure/review-checklists](https://github.com/Azure/review-checklists) project.

## What's in this repo

| File | Description |
|---|---|
| `queries/alz_additional_queries.json` | 206 checklist items: **132 with new ARG queries**, 74 marked as not queryable via ARG |
| `Validate-Queries.ps1` | PowerShell script to run all ARG queries against your Azure environment and report results |
| `scripts/Invoke-GraphApi.ps1` | **[Phase 4]** Microsoft Graph API checks for Entra ID / identity posture (7 checks) |
| `scripts/Invoke-CostManagementApi.ps1` | **[Phase 4]** Azure Cost Management API checks for budget governance (6 checks) |
| `scripts/Invoke-DevOpsApi.ps1` | **[Phase 4]** GitHub / Azure DevOps governance checks (8 checks) |
| `items_no_query.json` | Source data: the 206 original items without queries |
| `alz_checklist_full.json` | Full ALZ checklist for reference |

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

**Combined coverage: 181/255 items (71%) now have automated Graph queries**, up from 135/255 (53%).

## Quick Start

### Prerequisites

**For ARG validation (`Validate-Queries.ps1`):**
- PowerShell 7+
- `Az.ResourceGraph` module (`Install-Module Az.ResourceGraph`)
- `Az.Accounts` module
- Logged into Azure (`Connect-AzAccount`)
- Reader access to subscriptions in scope

**For Phase 4 API modules (optional, additive):**
- `scripts/Invoke-GraphApi.ps1` — Microsoft Graph `Directory.Read.All` / `Policy.Read.All` (or Global Reader)
- `scripts/Invoke-CostManagementApi.ps1` — Cost Management Reader on subscription/management group
- `scripts/Invoke-DevOpsApi.ps1` — GitHub token (`repo:read`) or Azure DevOps PAT (`read` scope)

### Run validation

```powershell
# Clone and navigate
cd C:\git\alz-graph-queries

# Log in to Azure
Connect-AzAccount -TenantId "<your-tenant-id>"

# Run all queries against your environment
.\Validate-Queries.ps1

# Or scope to a specific subscription
.\Validate-Queries.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000"

# Or scope to a management group
.\Validate-Queries.ps1 -ManagementGroup "my-mg-name"
```

### Output

The script produces:
- **Console summary** - OK / Empty / Error counts per category
- **validation_results.csv** - Full results with status, row count, and error messages
- **validation_results_not_queryable.csv** - Items that cannot be validated via ARG (with reasons)

### Interpreting results

| Status | Meaning |
|---|---|
| **OK** | Query executed and returned rows. Review the `compliant` column in results. |
| **EMPTY** | Query executed but returned 0 rows. May mean the resource type doesn't exist in scope (which could itself be a finding). |
| **ERROR** | Query syntax error or permission issue. The query needs fixing. |

## Phase 4 API Modules

Three companion scripts extend coverage to checklist items that cannot be validated through ARG alone.

### `scripts/Invoke-GraphApi.ps1` — Entra ID / Microsoft Graph (7 checks)

| Check | Intent |
|---|---|
| Conditional Access policies present | findEvidence |
| MFA enforced via CA policy | findViolations |
| PIM eligible role assignments configured | findEvidence |
| Emergency / break-glass accounts present | findEvidence |
| Security defaults enforcement status | findEvidence |
| Named locations / trusted IPs defined | findEvidence |
| Permanent Global Administrator assignments | findViolations |

```powershell
# Ambient Az context (recommended)
.\scripts\Invoke-GraphApi.ps1 -TenantId "<tenant-id>"

# SPN with certificate
.\scripts\Invoke-GraphApi.ps1 -TenantId "<tid>" -ClientId "<appId>" -CertificatePath ".\cert.pfx"

# Managed Identity
.\scripts\Invoke-GraphApi.ps1 -UseIdentity
```

### `scripts/Invoke-CostManagementApi.ps1` — Budget governance (6 checks)

| Check | Intent |
|---|---|
| Budgets configured at scope | findEvidence |
| Budget alert thresholds configured | findEvidence |
| Budget threshold exceeded (≥ 80%) | findViolations |
| Cost anomaly alert actions present | findEvidence |
| Orphaned managed disks | findViolations |
| Unused public IP addresses | findViolations |

```powershell
# Scope to a subscription
.\scripts\Invoke-CostManagementApi.ps1 -SubscriptionId "<sub-id>"

# Scope to a management group
.\scripts\Invoke-CostManagementApi.ps1 -ManagementGroup "<mg-id>"

# SPN authentication
.\scripts\Invoke-CostManagementApi.ps1 -SubscriptionId "<sub-id>" `
  -TenantId "<tid>" -ClientId "<appId>" -ClientSecret "<secret>"
```

### `scripts/Invoke-DevOpsApi.ps1` — DevOps posture (8 checks)

| Check | Platform | Intent |
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
# GitHub checks (token from env GITHUB_TOKEN or gh CLI auth)
.\scripts\Invoke-DevOpsApi.ps1 -Platform GitHub -Owner "my-org" -Repo "my-repo"

# GitHub with explicit token
.\scripts\Invoke-DevOpsApi.ps1 -Platform GitHub -Owner "my-org" -Repo "my-repo" `
  -GitHubToken $env:GITHUB_TOKEN

# Azure DevOps checks
.\scripts\Invoke-DevOpsApi.ps1 -Platform AzureDevOps `
  -AdoOrgUrl "https://dev.azure.com/my-org" -AdoPat "<pat>"
```

All three modules return results in the **unified ALZ check contract** (same `status`, `evidenceCount`, `queryIntent` fields as `Validate-Queries.ps1`) so outputs can be combined into a single compliance report.

## Why 74 items are not queryable via ARG

Many ALZ checklist items are **organizational, process, or identity-related** and cannot be validated through Azure Resource Graph alone. The Phase 4 modules cover the addressable gaps:

| Gap area | Phase 4 coverage |
|---|---|
| **Entra ID configuration** (CA policies, PIM, MFA) | `Invoke-GraphApi.ps1` |
| **Billing / budget governance** | `Invoke-CostManagementApi.ps1` |
| **DevOps practices** (branch protection, CI/CD) | `Invoke-DevOpsApi.ps1` |
| **Process decisions** ("define a plan", "document escalation") | Manual review only |
| **On-premises** (ExpressRoute physical links, BFD) | Not visible to Azure APIs |

## Integration with review-checklists Excel

To use these queries with the existing Excel workflow:

1. Run `.\Validate-Queries.ps1` to get `validation_results.csv`
2. Open the ALZ checklist in the Excel workbook
3. Match results by GUID to update the Comments/Status columns
4. Or use the `checklist_graph.sh` script with a modified checklist JSON that includes these additional queries

## Automation

| Workflow | Trigger | Purpose |
|---|---|---|
| `ci-failure-analysis.yml` | Any workflow failure | Opens issue with logs, labels `bug` + `squad` |
| `squad-heartbeat.yml` | Schedule (30 min) | Ralph triage pass |

## License

MIT - these queries are provided as-is for assessment purposes.
