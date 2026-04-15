# Permissions & Authentication Guide

This document explains the permissions required to run `Validate-Queries.ps1` and how to authenticate using each supported method.

## Required Azure Permissions

### Minimum (ARG queries only)
| Role | Scope | Purpose |
|------|-------|---------|
| Reader | Management Group or Subscription | Query Azure Resource Graph |

### For Management Group scope
```
az role assignment create \
  --role Reader \
  --assignee <principal-id> \
  --scope /providers/Microsoft.Management/managementGroups/<mg-id>
```

## Authentication Methods

### 1. Existing context (simplest for local use)
```powershell
Connect-AzAccount           # or: az login + Import-Module Az
./Validate-Queries.ps1 -ManagementGroup myMG
```

### 2. GitHub Actions with OIDC/WIF (recommended for CI)
1. Create an App Registration in Entra ID
2. Add a federated credential (GitHub Actions OIDC):
   - Issuer: `https://token.actions.githubusercontent.com`
   - Subject: `repo:<org>/<repo>:ref:refs/heads/main` (or use environment)
3. Assign Reader role at Management Group scope
4. Add secrets to your repo: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`

See `.github/workflows/validate-example.yml` for a complete example.

### 3. Managed Identity
```powershell
./Validate-Queries.ps1 -UseIdentity -ManagementGroup myMG
```
Assign the Reader role to the managed identity's principal ID at MG scope.

### 4. Service Principal with Certificate (recommended for non-WIF)
```powershell
./Validate-Queries.ps1 -TenantId <tid> -ClientId <cid> -CertificatePath ./cert.pfx -ManagementGroup myMG
```

### 5. Service Principal with Secret (legacy)
```powershell
./Validate-Queries.ps1 -TenantId <tid> -ClientId <cid> -ClientSecret <secret> -ManagementGroup myMG
```
Warning: Store secrets in a key vault or GitHub secret - never in plaintext.

### 6. Interactive (default for local use when no context exists)
```powershell
./Validate-Queries.ps1 -ManagementGroup myMG
# Opens browser (Windows/macOS GUI) or shows device code (Linux/SSH/headless)
```

## Microsoft Graph API (`scripts/Invoke-GraphApi.ps1`)

`Invoke-GraphApi.ps1` checks Entra ID signals that are not available through Azure Resource Graph.
It reuses the same auth parameters as `Validate-Queries.ps1` and obtains a separate Graph bearer token.

### Required Microsoft Graph permissions (application ÔÇö admin consent required)

| Permission | Type | Purpose |
|-----------|------|---------|
| `Policy.Read.All` | Application | Read Conditional Access policies |
| `RoleManagement.Read.Directory` | Application | Read PIM eligible/active role assignments |
| `Directory.Read.All` | Application | Read user accounts (break-glass detection) |

> **Note:** `Policy.Read.All` and `RoleManagement.Read.Directory` require admin consent.
> The module gracefully returns `status=SKIP` with an explanation if permissions are missing,
> so the rest of the validation run is never blocked.

## Cost Management (`scripts/Invoke-CostManagementApi.ps1`)

`Invoke-CostManagementApi.ps1` queries Azure Cost Management REST API and Azure Resource Graph
to assess budget and cost governance posture. It uses the same auth parameters as `Validate-Queries.ps1`.

### Required Azure permissions

| Role | Scope | Purpose |
|------|-------|---------|
| Cost Management Reader | Subscription or Management Group | Read budgets, budget alerts, and anomaly scheduled actions |
| Reader | Subscription or Management Group | Azure Resource Graph queries (orphaned resource checks) |

### Granting permissions

```bash
# Add required API permissions to your App Registration
az ad app permission add \
  --id <client-id> \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions \
    9e640839-a198-48fb-8b9a-013fd6f6cbcd=Role \
    9f891c37-7c93-4c2d-a929-4d25e382e0b9=Role \
    7ab1d382-f21e-4acd-a863-ba3e13f7da61=Role

# Grant admin consent
az ad app permission admin-consent --id <client-id>
```

### Token acquisition for Graph

The module uses the following priority order to obtain a Graph token:
1. **Explicit SPN with client secret** (`-TenantId` + `-ClientId` + `-ClientSecret`) ÔÇö direct `/token` call
2. **Az module ambient context** ÔÇö `Get-AzAccessToken -ResourceUrl https://graph.microsoft.com`
3. **WIF / OIDC** ÔÇö `AZURE_FEDERATED_TOKEN_FILE` + `AZURE_CLIENT_ID` + `AZURE_TENANT_ID` environment variables

If none of these succeed, all Graph checks return `status=SKIP`.

### Checks implemented

| Check | ALZ GUID | Graph endpoint | queryIntent |
|-------|----------|---------------|-------------|
| Conditional Access policies enabled | `53e8908a` | `/identity/conditionalAccess/policies` | findEvidence |
| CA policies with MFA grant | `1049d403` | `/identity/conditionalAccess/policies` | findEvidence |
| PIM eligible role schedules | `14658d35` | `/roleManagement/directory/roleEligibilitySchedules` | findEvidence |
| Break-glass / emergency accounts | `984a859c` | `/users?$filter=startswith(displayName,'break')ÔÇª` | findEvidence |
| Security defaults enforcement | *(identity hardening)* | `/policies/identitySecurityDefaultsEnforcementPolicy` | findEvidence |
| Named locations / trusted IPs | *(CA support)* | `/identity/conditionalAccess/namedLocations` | findEvidence |
| Permanent Global Admin assignments | `d98d954d` | `/roleManagement/directory/roleAssignments` | findViolations |


# Cost Management Reader at subscription scope
az role assignment create \
  --role "Cost Management Reader" \
  --assignee <principal-id> \
  --scope /subscriptions/<subscription-id>

# Cost Management Reader at Management Group scope
az role assignment create \
  --role "Cost Management Reader" \
  --assignee <principal-id> \
  --scope /providers/Microsoft.Management/managementGroups/<mg-id>
```

### Usage examples

```powershell
# Subscription scope
.\scripts\Invoke-CostManagementApi.ps1 -SubscriptionId "<subscription-id>"

# Management Group scope with Managed Identity
.\scripts\Invoke-CostManagementApi.ps1 -ManagementGroup "alz-root" -UseIdentity

# SPN with certificate
.\scripts\Invoke-CostManagementApi.ps1 -ManagementGroup "alz-root" `
    -TenantId <tid> -ClientId <cid> -CertificatePath ./cert.pfx
```

### Checks implemented

| Check | queryIntent | API endpoint |
|-------|-------------|-------------|
| Budgets present | findEvidence | `Microsoft.Consumption/budgets` |
| Budget alert notifications configured | findEvidence | `Microsoft.Consumption/budgets` |
| Budget threshold exceeded (>= 80%) | findViolations | `Microsoft.Consumption/budgets` |
| Cost anomaly alerts enabled | findEvidence | `Microsoft.CostManagement/scheduledActions` |
| Orphaned managed disks | findViolations | Azure Resource Graph |
| Orphaned public IP addresses | findViolations | Azure Resource Graph |

> **Note:** If the identity lacks Cost Management Reader, individual checks gracefully return
> `status='SKIP'` rather than failing the entire run.

## Future: Microsoft Graph, GitHub/ADO

Additional modules planned:
- **Graph API**: `Policy.Read.All`, `RoleManagement.Read.Directory`, `Reports.Read.All`, `Directory.Read.All` (admin consent required)
- **GitHub API**: `gh auth login` with `repo:read` scope
