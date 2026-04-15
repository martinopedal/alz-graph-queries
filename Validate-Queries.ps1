<#
.SYNOPSIS
    Validates Azure Resource Graph queries from the ALZ additional queries file.

.DESCRIPTION
    Runs each queryable ARG query against the current Azure subscription/tenant,
    reports success/failure/empty results, and outputs a summary report.

.PARAMETER QueriesFile
    Path to the alz_additional_queries.json file. Defaults to ./queries/alz_additional_queries.json

.PARAMETER OutputFile
    Path for the validation results CSV. Defaults to ./validation_results.csv

.PARAMETER SubscriptionId
    Optional. Scope queries to a specific subscription.

.PARAMETER ManagementGroup
    Optional. Scope queries to a management group.

.PARAMETER UseIdentity
    Use system-assigned Managed Identity for authentication.

.PARAMETER UseDeviceCode
    Force interactive device code flow for authentication.

.PARAMETER TenantId
    Azure tenant ID for SPN or explicit authentication.

.PARAMETER ClientId
    Application (client) ID for SPN authentication.

.PARAMETER ClientSecret
    Client secret for SPN authentication (legacy; prefer certificate or WIF).

.PARAMETER CertificatePath
    Path to PFX certificate for SPN authentication.

.EXAMPLE
    .\Validate-Queries.ps1
    .\Validate-Queries.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000"
    .\Validate-Queries.ps1 -ManagementGroup "my-mg-name"
    .\Validate-Queries.ps1 -UseIdentity -ManagementGroup "my-mg-name"
    .\Validate-Queries.ps1 -TenantId <tid> -ClientId <cid> -CertificatePath ./cert.pfx
#>

[CmdletBinding()]
param(
    [string]$QueriesFile = "$PSScriptRoot\queries\alz_additional_queries.json",
    [string]$OutputFile = "$PSScriptRoot\validation_results.csv",
    [string]$SubscriptionId,
    [string]$ManagementGroup,

    # --- Auth parameters ---
    [Parameter(Mandatory=$false, HelpMessage='Use system-assigned Managed Identity')]
    [switch]$UseIdentity,

    [Parameter(Mandatory=$false, HelpMessage='Force interactive device code flow')]
    [switch]$UseDeviceCode,

    [Parameter(Mandatory=$false)]
    [string]$TenantId,

    [Parameter(Mandatory=$false)]
    [string]$ClientId,

    [Parameter(Mandatory=$false)]
    [string]$ClientSecret,

    [Parameter(Mandatory=$false)]
    [string]$CertificatePath
)

$ErrorActionPreference = 'Continue'

function Invoke-AzAuth {
    <#
    .SYNOPSIS
        Auth priority waterfall: explicit params > ambient context > WIF > MI > SPN > interactive > fail
    .NOTES
        Explicit params always override ambient context (Goldeneye G1 fix).
        Never caches token strings — re-acquires per batch.
    #>
    param(
        [switch]$UseIdentity,
        [switch]$UseDeviceCode,
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret,
        [string]$CertificatePath
    )

    $hasExplicitParams = $UseIdentity -or $UseDeviceCode -or $TenantId -or $ClientId

    # Step 1: Reuse ambient context only when NO explicit auth params supplied
    if (-not $hasExplicitParams) {
        $ctx = Get-AzContext -ErrorAction SilentlyContinue
        if ($ctx) {
            Write-Host "Using existing Azure context: $($ctx.Account.Id) (tenant: $($ctx.Tenant.Id))"
            return
        }
    }

    # Step 2: WIF/federated credentials (auto-detected from environment)
    if (-not $hasExplicitParams -and
        $env:AZURE_FEDERATED_TOKEN_FILE -and
        $env:AZURE_CLIENT_ID -and
        $env:AZURE_TENANT_ID) {
        Write-Host "Detected WIF environment variables -- authenticating with federated token"
        $federatedToken = Get-Content -Raw $env:AZURE_FEDERATED_TOKEN_FILE
        Connect-AzAccount -ApplicationId $env:AZURE_CLIENT_ID `
                          -TenantId $env:AZURE_TENANT_ID `
                          -FederatedToken $federatedToken `
                          -ErrorAction Stop | Out-Null
        Write-Host "Authenticated via WIF (client: $($env:AZURE_CLIENT_ID))"
        return
    }

    # Step 3: Explicit -UseIdentity (Managed Identity)
    if ($UseIdentity) {
        Write-Host "Authenticating with Managed Identity"
        Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
        Write-Host "Authenticated via Managed Identity"
        return
    }

    # Step 4: Explicit SPN with certificate (preferred over secret)
    if ($TenantId -and $ClientId -and $CertificatePath) {
        Write-Host "Authenticating as SPN $ClientId with certificate"
        Connect-AzAccount -ServicePrincipal `
                          -ApplicationId $ClientId `
                          -TenantId $TenantId `
                          -CertificatePath $CertificatePath `
                          -ErrorAction Stop | Out-Null
        Write-Host "Authenticated as SPN $ClientId (cert)"
        return
    }

    # Step 5: Explicit SPN with secret (legacy fallback)
    if ($TenantId -and $ClientId -and $ClientSecret) {
        Write-Warning "Using SPN with client secret -- consider switching to certificate or WIF for better security"
        $cred = [PSCredential]::new($ClientId, (ConvertTo-SecureString $ClientSecret -AsPlainText -Force))
        Connect-AzAccount -ServicePrincipal `
                          -Credential $cred `
                          -TenantId $TenantId `
                          -ErrorAction Stop | Out-Null
        Write-Host "Authenticated as SPN $ClientId (secret)"
        return
    }

    # Step 6: Interactive (adaptive -- browser on GUI, device code on headless)
    # Detect non-interactive: CI env vars OR redirected stdin
    $isCI       = $env:GITHUB_ACTIONS -or $env:TF_BUILD -or $env:CI -or $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI
    $isRedirect = [Console]::IsInputRedirected

    if (-not $isCI -and -not $isRedirect) {
        if ($UseDeviceCode) {
            Write-Host "Authenticating interactively (device code forced)"
            Connect-AzAccount -UseDeviceAuthentication -ErrorAction Stop | Out-Null
        } else {
            Write-Host "Authenticating interactively (browser or device code, Az adapts)"
            Connect-AzAccount -ErrorAction Stop | Out-Null
        }
        Write-Host "Authenticated interactively: $((Get-AzContext).Account.Id)"
        return
    }

    # Step 7: Non-interactive, no auth configured -- fail fast with actionable message
    $msg = @"
No Azure context found and non-interactive environment detected.
Authentication options:
  (a) -UseIdentity                            -- Managed Identity (VM, ACI, Functions, GHA)
  (b) Set AZURE_FEDERATED_TOKEN_FILE + AZURE_CLIENT_ID + AZURE_TENANT_ID  -- OIDC/WIF
  (c) -TenantId + -ClientId + -CertificatePath -- SPN with certificate (recommended)
  (d) -TenantId + -ClientId + -ClientSecret   -- SPN with secret (legacy)
  (e) Run Connect-AzAccount before invoking this script

See PERMISSIONS.md for setup instructions for each option.
"@
    throw $msg
}

# --- Prerequisites ---
Write-Host "=== ALZ Graph Query Validator ===" -ForegroundColor Cyan
Write-Host ""

# Check Az.ResourceGraph module
if (-not (Get-Module -ListAvailable -Name Az.ResourceGraph)) {
    Write-Host "ERROR: Az.ResourceGraph module not found. Install with:" -ForegroundColor Red
    Write-Host "  Install-Module -Name Az.ResourceGraph -Scope CurrentUser" -ForegroundColor Yellow
    exit 1
}
Import-Module Az.ResourceGraph -ErrorAction Stop

# Authenticate
Invoke-AzAuth -UseIdentity:$UseIdentity -UseDeviceCode:$UseDeviceCode `
              -TenantId $TenantId -ClientId $ClientId `
              -ClientSecret $ClientSecret -CertificatePath $CertificatePath

# Display active context for transparency
$ctx = Get-AzContext
Write-Host "Active context: $($ctx.Account.Id) | Tenant: $($ctx.Tenant.Id) | Subscription: $($ctx.Subscription.Name)"

if ($ManagementGroup) {
    Write-Host "Validating Management Group scope visibility..."
    try {
        $visibleSubs = Search-AzGraph -Query "resourcecontainers | where type == 'microsoft.resources/subscriptions' | project subscriptionId, name" `
                                      -ManagementGroup $ManagementGroup -First 1000 -ErrorAction Stop
        $subCount = if ($visibleSubs.Data -is [System.Data.DataTable]) { $visibleSubs.Data.Rows.Count } else { @($visibleSubs.Data).Count }
        if ($subCount -eq 0) {
            Write-Warning "No subscriptions visible under MG '$ManagementGroup'. Check Reader permissions at MG scope."
        } else {
            Write-Host "Querying $subCount subscription(s) visible under MG '$ManagementGroup'"
        }
    } catch {
        if ($_.Exception.Message -match 'authorization|forbidden|403|access denied') {
            Write-Error "Cannot query MG '$ManagementGroup' -- ensure Reader role at MG scope. $($_.Exception.Message)"
            exit 1
        }
        Write-Warning "Could not enumerate subscriptions under MG: $($_.Exception.Message)"
    }
}

# Pre-flight token expiry check
try {
    $tok = Get-AzAccessToken -ResourceUrl 'https://management.azure.com' -ErrorAction Stop
    $remainingMin = ($tok.ExpiresOn - [DateTimeOffset]::UtcNow).TotalMinutes
    if ($remainingMin -lt 15) {
        Write-Warning "Azure token expires in $([math]::Round($remainingMin,0)) min — consider re-authenticating before a full run."
    }
} catch {
    Write-Warning "Could not check token expiry: $($_.Exception.Message)"
}

# --- Load queries ---
if (-not (Test-Path $QueriesFile)) {
    Write-Host "ERROR: Queries file not found at $QueriesFile" -ForegroundColor Red
    exit 1
}

$data = Get-Content $QueriesFile -Raw | ConvertFrom-Json
$allQueries = $data.queries
$queryable = $allQueries | Where-Object { $_.queryable -eq $true }

Write-Host ""
Write-Host "Loaded $($allQueries.Count) items ($($queryable.Count) queryable)" -ForegroundColor Cyan
Write-Host ""

# --- Build Search-AzGraph parameters ---
$graphParams = @{}
if ($SubscriptionId) {
    $graphParams['Subscription'] = $SubscriptionId
    Write-Host "Scoped to subscription: $SubscriptionId"
}
if ($ManagementGroup) {
    $graphParams['ManagementGroup'] = $ManagementGroup
    Write-Host "Scoped to management group: $ManagementGroup"
}

# --- Run queries ---
$results = [System.Collections.ArrayList]::new()
$success = 0
$failed = 0
$empty = 0
$total = $queryable.Count
$i = 0

foreach ($q in $queryable) {
    $i++
    $pct = [math]::Round(($i / $total) * 100)
    Write-Progress -Activity "Validating queries" -Status "$i/$total ($pct%) - $($q.category)" -PercentComplete $pct

    $result = [PSCustomObject]@{
        guid           = $q.guid
        category       = $q.category
        subcategory    = $q.subcategory
        severity       = $q.severity
        text           = $q.text
        status         = ""
        rowCount       = 0
        error          = ""
        evidenceSample = ""
        query          = $q.graph
    }

    try {
        # Paginate via SkipToken to avoid silent -First 1000 truncation
        $allData = [System.Collections.ArrayList]::new()
        $skipToken = $null
        do {
            $pageParams = @{ Query = $q.graph; First = 1000; ErrorAction = 'Stop' }
            if ($SubscriptionId)  { $pageParams['Subscription']    = @($SubscriptionId) }
            if ($ManagementGroup) { $pageParams['ManagementGroup'] = $ManagementGroup }
            if ($skipToken)       { $pageParams['SkipToken']       = $skipToken }
            $page = Search-AzGraph @pageParams
            $pageRows = if ($page.Data -is [System.Data.DataTable]) { $page.Data.Rows } else { @($page.Data) }
            foreach ($row in $pageRows) { [void]$allData.Add($row) }
            $skipToken = $page.SkipToken
        } while ($skipToken)
        $n = $allData.Count
        $result.rowCount = $n
        if ($n -eq 0) {
            $result.status = "EMPTY"
            $empty++
        } else {
            $result.status = "OK"
            $success++
        }
        # Cap evidence sample
        $sample = ($allData | Select-Object -First 3 | ConvertTo-Json -Compress -Depth 3)
        if ($sample.Length -gt 500) { $sample = $sample.Substring(0, 497) + '...' }
        $result.evidenceSample = $sample
    } catch {
        if ($_.Exception.Message -match 'token|auth|401|expired|credentials|AADSTS') {
            Write-Error "FATAL: Auth failure at query $i. Token may have expired. Re-authenticate and re-run."
            $results | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
            exit 2
        }
        $result.status = "ERROR"
        $result.error = $_.Exception.Message -replace "`n|`r", " "
        $failed++
    }

    [void]$results.Add($result)
}

Write-Progress -Activity "Validating queries" -Completed

# --- Summary ---
Write-Host ""
Write-Host "=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "  Total queryable items: $total" -ForegroundColor White
Write-Host "  OK (returned rows):    $success" -ForegroundColor Green
Write-Host "  EMPTY (valid, 0 rows): $empty" -ForegroundColor Yellow
Write-Host "  ERROR (query failed):  $failed" -ForegroundColor Red
Write-Host ""

# --- Category breakdown ---
Write-Host "=== Results by Category ===" -ForegroundColor Cyan
$results | Group-Object -Property category | ForEach-Object {
    $catOk = ($_.Group | Where-Object { $_.status -eq 'OK' }).Count
    $catEmpty = ($_.Group | Where-Object { $_.status -eq 'EMPTY' }).Count
    $catErr = ($_.Group | Where-Object { $_.status -eq 'ERROR' }).Count
    Write-Host "  $($_.Name): OK=$catOk, Empty=$catEmpty, Error=$catErr"
}

# --- Show errors ---
$errors = $results | Where-Object { $_.status -eq 'ERROR' }
if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Host "=== Failed Queries ===" -ForegroundColor Red
    foreach ($e in $errors) {
        Write-Host "  [$($e.guid)] $($e.text.Substring(0, [Math]::Min(80, $e.text.Length)))" -ForegroundColor Yellow
        Write-Host "    Error: $($e.error.Substring(0, [Math]::Min(200, $e.error.Length)))" -ForegroundColor Red
        Write-Host ""
    }
}

# --- Export CSV ---
$results | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
Write-Host "Results exported to: $OutputFile" -ForegroundColor Cyan

# --- Also export non-queryable items for reference ---
$nonQueryable = $allQueries | Where-Object { $_.queryable -eq $false }
$nonQueryable | Select-Object guid, category, subcategory, severity, text, reason |
    Export-Csv -Path ($OutputFile -replace '\.csv$', '_not_queryable.csv') -NoTypeInformation -Encoding UTF8
Write-Host "Non-queryable items exported to: $($OutputFile -replace '\.csv$', '_not_queryable.csv')" -ForegroundColor Cyan

Write-Host ""
Write-Host "Done! Review validation_results.csv for full details." -ForegroundColor Green