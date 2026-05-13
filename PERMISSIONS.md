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

### Setting up `scripts/Invoke-GraphApi.ps1` for CI with Certificate Authentication

This section walks through configuring a service principal with certificate authentication for running Graph API checks in GitHub Actions or Azure Pipelines.

#### Step 1 — Create App Registration

Create an Entra ID application with the required Graph permissions:

```bash
# Create the application
az ad app create --display-name "alz-graph-queries-ci"
# Note the appId from the output

# Store it for later steps
export APP_ID="<appId-from-previous-output>"
```

Add the required Microsoft Graph application permissions:

```bash
# Policy.Read.All — for Conditional Access policies
az ad app permission add --id $APP_ID --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 332a536c-c7ef-4017-ab91-336970924f0d=Role

# RoleManagement.Read.Directory — for PIM eligible role assignments
az ad app permission add --id $APP_ID --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 0e263e50-5827-48a4-b97c-d940288653c7=Role

# Directory.Read.All — for user accounts (break-glass detection)
az ad app permission add --id $APP_ID --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 06da0dbc-49e3-46ad-b81d-440d94be40a5=Role
```

#### Step 2 — Generate and Upload Certificate

**Option A: PowerShell (Windows)**

```powershell
$cert = New-SelfSignedCertificate `
  -CertStoreLocation "cert:\CurrentUser\My" `
  -Subject "CN=alz-graph-queries-ci" `
  -KeySpec KeyExchange `
  -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider v1.0" `
  -NotAfter (Get-Date).AddYears(2)

# Export to PFX (with password)
$pwd = ConvertTo-SecureString -String "YourSecurePassword" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath "./alz-graph-queries-ci.pfx" -Password $pwd

# For GitHub Actions, base64-encode the cert
$certBytes = [System.IO.File]::ReadAllBytes("./alz-graph-queries-ci.pfx")
$certBase64 = [System.Convert]::ToBase64String($certBytes)
Write-Host $certBase64
```

**Option B: OpenSSL (cross-platform)**

```bash
# Generate private key and self-signed certificate (2-year validity)
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 730 \
  -subj "/CN=alz-graph-queries-ci"

# Convert to PFX
openssl pkcs12 -export -in cert.pem -inkey key.pem -out alz-graph-queries-ci.pfx \
  -name "alz-graph-queries-ci" -passout pass:"YourSecurePassword"

# For GitHub Actions, base64-encode the cert
cat alz-graph-queries-ci.pfx | base64 -w 0 > alz-graph-queries-ci.pfx.b64
cat alz-graph-queries-ci.pfx.b64
```

#### Step 3 — Upload Certificate to App Registration

```bash
az ad app credential create --id $APP_ID \
  --cert @alz-graph-queries-ci.cer \
  --display-name "CI certificate"
```

Or via Azure Portal: App Registration → Certificates & secrets → Certificates → Upload certificate.

#### Step 4 — Grant Admin Consent

```bash
az ad app permission admin-consent --id $APP_ID
```

Verify in Azure Portal: App Registration → API permissions → All permissions are showing "Granted for <TenantName>".

#### Step 5 — GitHub Actions Workflow with SPN Certificate

Store these secrets in your GitHub repository:

| Secret | Value |
|--------|-------|
| `AZURE_TENANT_ID` | Your Entra ID tenant ID |
| `AZURE_CLIENT_ID` | The app registration's client ID |
| `AZURE_CERT_PFX_BASE64` | Base64-encoded PFX certificate (from Step 2) |
| `AZURE_CERT_PASSWORD` | Certificate password (from Step 2) |

Add this job to your `.github/workflows/alz-validation.yml`:

```yaml
name: ALZ Validation with Graph API (SPN Certificate)

on:
  workflow_dispatch:
    inputs:
      management_group:
        description: Management Group ID to scan
        required: false

permissions:
  contents: read

jobs:
  validate:
    name: ALZ Checklist + Graph API
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
        with:
          persist-credentials: false

      - uses: actions/setup-python@0b93645e9e0d6c8c991ae992102c6ab17ad27139 # v5.0.2
        with:
          python-version: '3.11'

      - name: Decode and stage certificate
        shell: bash
        run: |
          echo "${{ secrets.AZURE_CERT_PFX_BASE64 }}" | base64 -d > /tmp/cert.pfx

      - name: Run ALZ validation + Graph API checks
        shell: pwsh
        run: |
          $params = @{
            TenantId       = '${{ secrets.AZURE_TENANT_ID }}'
            ClientId       = '${{ secrets.AZURE_CLIENT_ID }}'
            CertificatePath = '/tmp/cert.pfx'
            ManagementGroup = '${{ github.event.inputs.management_group || ''alz-root'' }}'
            ReportFormat   = 'All'
          }
          
          ./Validate-Queries.ps1 @params
          
          # Graph API checks are integrated into Validate-Queries.ps1
          # Results appear in validation_results.* with all other compliance data

      - name: Upload reports
        if: always()
        uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2
        with:
          name: alz-validation-reports
          path: |
            validation_results.csv
            validation_results.md
            validation_results.html
          retention-days: 30
```

**Key points:**

- The certificate password is passed inline; use a key vault secret (`${{ secrets.AZURE_CERT_PASSWORD }}`) in production
- `Invoke-GraphApi.ps1` is automatically invoked by `Validate-Queries.ps1` when Graph credentials are available
- Graph results are merged into the unified report (CSV, Markdown, HTML)
- No extra API calls needed; Graph checks run alongside ARG queries

#### Step 6 — Azure Pipelines with Managed Identity (simpler alternative)

If running in Azure Pipelines on an Azure Hosted Agent or self-hosted agent in Azure, use Managed Identity instead:

```yaml
trigger:
  - main

pool:
  vmImage: 'ubuntu-latest'

stages:
  - stage: Validate
    displayName: ALZ Validation
    jobs:
      - job: GraphAndArg
        displayName: ALZ Checklist + Graph API
        steps:
          - checkout: self
            fetchDepth: 1

          - task: AzureCLI@2
            inputs:
              azureSubscription: '<service-connection-name>'
              scriptType: 'pscore'
              scriptLocation: 'inlineScript'
              inlineScript: |
                $params = @{
                  UseIdentity     = $true
                  ManagementGroup = 'alz-root'
                  ReportFormat    = 'All'
                }
                ./Validate-Queries.ps1 @params

          - task: PublishBuildArtifacts@1
            inputs:
              pathToPublish: '$(System.DefaultWorkingDirectory)'
              artifactName: 'alz-validation-reports'
              publishLocation: 'Container'
            condition: always()
```

Managed Identity is simpler because Azure Pipelines handles credential injection automatically — no certificate upload needed.

#### Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| `AADSTS65001: User or admin has not consented` | Graph permissions lack admin consent | Run Step 4 (`az ad app permission admin-consent`) |
| `Certificate thumbprint not found` | Cert not imported into the app registration | Re-upload cert via Azure Portal or Step 3 |
| `AZUREPS_GHACTIONLOGIN_TOKEN_EXPIRED` | Certificate expired (> 2 years old) | Generate a new cert and re-upload |
| `EAUTH: Certificate verification failed` | Invalid base64 encoding in GitHub secret | Regenerate: `cat cert.pfx \| base64 -w 0` (no newlines) |

## Future: Microsoft Graph, GitHub/ADO

Additional modules planned:
- **GitHub API**: `gh auth login` with `repo:read` scope
