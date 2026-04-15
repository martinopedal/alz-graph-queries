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

## Future: Microsoft Graph, Cost Management, GitHub/ADO

Additional modules planned in v1.1.0 will require:
- **Graph API**: `Policy.Read.All`, `RoleManagement.Read.Directory`, `Reports.Read.All`, `Directory.Read.All` (admin consent required)
- **Cost Management**: `Cost Management Reader` at subscription or MG scope
- **GitHub API**: `gh auth login` with `repo:read` scope

Documentation for these will be added when the modules ship.