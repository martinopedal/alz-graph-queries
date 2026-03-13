# ALZ Additional Graph Queries

Azure Resource Graph (ARG) queries for **Azure Landing Zone checklist items** that are not covered by the original [Azure/review-checklists](https://github.com/Azure/review-checklists) project.

## What's in this repo

| File | Description |
|---|---|
| `queries/alz_additional_queries.json` | 206 checklist items: **86 with new ARG queries**, 120 marked as not queryable via ARG |
| `Validate-Queries.ps1` | PowerShell script to run all queries against your Azure environment and report results |
| `items_no_query.json` | Source data: the 206 original items without queries |
| `alz_checklist_full.json` | Full ALZ checklist for reference |

## Coverage

| Category | Original Queries | New Queries | Not Queryable | Total |
|---|---|---|---|---|
| Network Topology and Connectivity | 36 | 37 | 33 | 106 |
| Security | 2 | 17 | 13 | 32 |
| Management & Monitoring | 1 | 19 | 6 | 26 |
| Identity and Access Management | 7 | 0 | 17 | 24 |
| Resource Organization | 3 | 5 | 14 | 22 |
| Governance | 0 | 8 | 8 | 16 |
| Azure Billing & Entra ID Tenants | 0 | 0 | 15 | 15 |
| Platform Automation and DevOps | 0 | 0 | 14 | 14 |
| **Total** | **49** | **86** | **120** | **255** |

**Combined coverage: 135/255 items (53%) now have automated Graph queries**, up from 49/255 (19%).

## Quick Start

### Prerequisites

- PowerShell 7+
- `Az.ResourceGraph` module (`Install-Module Az.ResourceGraph`)
- `Az.Accounts` module
- Logged into Azure (`Connect-AzAccount`)
- Reader access to subscriptions in scope

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

## Why 120 items are not queryable

Many ALZ checklist items are **organizational, process, or identity-related** and cannot be validated through Azure Resource Graph alone:

- **Entra ID configuration** (conditional access, PIM, MFA) → requires Microsoft Graph API
- **Billing/enrollment** → requires Cost Management or EA APIs
- **Process decisions** ("define a plan", "document escalation") → manual review only
- **DevOps practices** (CI/CD, branching, IaC usage) → requires DevOps platform APIs
- **On-premises configuration** (ExpressRoute physical links, BFD) → not visible to Azure

## Integration with review-checklists Excel

To use these queries with the existing Excel workflow:

1. Run `.\Validate-Queries.ps1` to get `validation_results.csv`
2. Open the ALZ checklist in the Excel workbook
3. Match results by GUID to update the Comments/Status columns
4. Or use the `checklist_graph.sh` script with a modified checklist JSON that includes these additional queries

## License

MIT - these queries are provided as-is for assessment purposes.
