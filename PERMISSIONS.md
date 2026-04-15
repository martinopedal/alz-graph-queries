# Permissions

All operations in this repository are **read-only**. No Azure resources are created, modified, or deleted.

## Azure permissions required

| Operation | Scope | Role | Notes |
|---|---|---|---|
| `Search-AzGraph` (ARG queries) | Subscription or Management Group | Reader | Required to run `Validate-Queries.ps1` |
| `Connect-AzAccount` | Tenant | None beyond Reader | Authentication only |

## Minimum role assignment

Assign **Reader** at the management group root (or at each subscription in scope) to the identity running `Validate-Queries.ps1`.

```powershell
# Example: assign Reader at management group scope
New-AzRoleAssignment `
    -ObjectId "<your-object-id>" `
    -RoleDefinitionName "Reader" `
    -Scope "/providers/Microsoft.Management/managementGroups/<mg-id>"
```

## No write permissions needed

`Validate-Queries.ps1` only calls `Search-AzGraph`. It does not use any ARM write operations, does not modify policy, and does not access secrets or credentials.

## Microsoft Graph API (Phase 2)

Phase 2 work ([#11](https://github.com/martinopedal/alz-graph-queries/issues/11)) will require additional Graph API permissions for Entra ID checks. Permissions will be documented when that work is implemented.
