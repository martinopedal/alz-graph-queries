# Project Context

- **Owner:** martinopedal
- **Project:** ALZ Additional Graph Queries — Microsoft Graph/Entra ID checks for ALZ identity items
- **Stack:** PowerShell (Microsoft.Graph module), Microsoft Graph REST API, JSON
- **Created:** 2026-04-14

## Team Updates

- 2026-05-13: Writing style decision merged into .squad/decisions.md — applies to all docs, READMEs, reports, PR descriptions. See decisions.md.

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

### Graph API SPN Certificate Authentication (Issue #59)

**Date:** 2026-05-13

**Scopes confirmed for Invoke-GraphApi.ps1:**
- `Policy.Read.All` (API ID: 332a536c-c7ef-4017-ab91-336970924f0d) — Conditional Access policies
- `RoleManagement.Read.Directory` (API ID: 0e263e50-5827-48a4-b97c-d940288653c7) — PIM eligible role assignments
- `Directory.Read.All` (API ID: 06da0dbc-49e3-46ad-b81d-440d94be40a5) — User accounts (break-glass detection)

**SHAs used in GitHub Actions example workflow:**
- `actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2`
- `actions/setup-python@0b93645e9e0d6c8c991ae992102c6ab17ad27139 # v5.0.2`
- `actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2`

All SHAs verified from existing workflows in this repo (validate-example.yml, squad-ci.yml).

**Actual parameter names for Invoke-GraphApi.ps1:**
- `-TenantId` (optional; defaults to current Az context)
- `-ClientId` (optional; SPN application ID)
- `-ClientSecret` (legacy; SPN secret)
- `-CertificatePath` (path to PFX file)
- `-UseIdentity` (switch for Managed Identity)
- `-UseDeviceCode` (switch for interactive device code)

**Note:** Invoke-GraphApi.ps1 is called from within Validate-Queries.ps1 (not standalone in workflows). Auth params are forwarded automatically.
