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
.PARAMETER ReportFormat
    Output report format(s). Valid values: CSV, Markdown, HTML, All. Defaults to CSV.

.EXAMPLE
    .\Validate-Queries.ps1
    .\Validate-Queries.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000"
    .\Validate-Queries.ps1 -ManagementGroup "my-mg-name"
    .\Validate-Queries.ps1 -UseIdentity -ManagementGroup "my-mg-name"
    .\Validate-Queries.ps1 -TenantId <tid> -ClientId <cid> -CertificatePath ./cert.pfx
    .\Validate-Queries.ps1 -ReportFormat All
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
    [Parameter(Mandatory=$false)]
    [ValidateSet('CSV','Markdown','HTML','All')]
    [string]$ReportFormat = 'CSV'
)

$ErrorActionPreference = 'Continue'

function Invoke-AzAuth {
    <#
    .SYNOPSIS
        Auth priority waterfall: explicit params > ambient context > WIF > MI > SPN > interactive > fail
    .NOTES
        Explicit params always override ambient context (Goldeneye G1 fix).
        Never caches token strings - re-acquires per batch.
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
        Write-Host "Detected WIF environment variables - authenticating with federated token"
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
        Write-Warning "Using SPN with client secret - consider switching to certificate or WIF for better security"
        $cred = [PSCredential]::new($ClientId, (ConvertTo-SecureString $ClientSecret -AsPlainText -Force))
        Connect-AzAccount -ServicePrincipal `
                          -Credential $cred `
                          -TenantId $TenantId `
                          -ErrorAction Stop | Out-Null
        Write-Host "Authenticated as SPN $ClientId (secret)"
        return
    }

    # Step 6: Interactive (adaptive - browser on GUI, device code on headless)
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

    # Step 7: Non-interactive, no auth configured - fail fast with actionable message
    throw @"
No Azure context found and non-interactive environment detected.
Authentication options:
  (a) -UseIdentity                            - Managed Identity (VM, ACI, Functions, GHA)
  (b) Set AZURE_FEDERATED_TOKEN_FILE + AZURE_CLIENT_ID + AZURE_TENANT_ID  - OIDC/WIF
  (c) -TenantId + -ClientId + -CertificatePath - SPN with certificate (recommended)
  (d) -TenantId + -ClientId + -ClientSecret   - SPN with secret (legacy)
  (e) Run Connect-AzAccount before invoking this script

See PERMISSIONS.md for setup instructions for each option.
"@
}

# --- Prerequisites ---
# ---------------------------------------------------------------------------
# Report generation functions
# ---------------------------------------------------------------------------

function Export-MarkdownReport {
    param(
        [Parameter(Mandatory)] $Results,
        [Parameter(Mandatory)] [string] $OutputPath,
        [string] $Scope = 'unknown',
        [string] $Identity = 'unknown',
        [string] $ToolVersion = '1.1.0'
    )

    $date = Get-Date -Format 'yyyy-MM-dd HH:mm UTC'
    $total = $Results.Count
    $queryable = ($Results | Where-Object { $_.checkType -ne 'None' }).Count
    $notQueryable = $total - $queryable
    $ok      = ($Results | Where-Object { $_.status -eq 'OK' }).Count
    $fail    = ($Results | Where-Object { $_.status -eq 'FAIL' }).Count
    $empty   = ($Results | Where-Object { $_.status -eq 'EMPTY' }).Count
    $errors  = ($Results | Where-Object { $_.status -eq 'ERROR' }).Count
    $skipped = ($Results | Where-Object { $_.status -eq 'SKIPPED' }).Count
    $coverage = if ($queryable -gt 0) { [math]::Round(($ok + $fail + $empty) / $queryable * 100, 1) } else { 0 }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("# ALZ Validation Report")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Field | Value |")
    [void]$sb.AppendLine("|-------|-------|")
    [void]$sb.AppendLine("| **Date** | $date |")
    [void]$sb.AppendLine("| **Identity** | $Identity |")
    [void]$sb.AppendLine("| **Scope** | $Scope |")
    [void]$sb.AppendLine("| **Tool version** | $ToolVersion |")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Executive Summary")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Metric | Count |")
    [void]$sb.AppendLine("|--------|-------|")
    [void]$sb.AppendLine("| Total items | $total |")
    [void]$sb.AppendLine("| Queryable | $queryable |")
    [void]$sb.AppendLine("| Not queryable | $notQueryable |")
    [void]$sb.AppendLine("| ├ö┬ú├á OK | $ok |")
    [void]$sb.AppendLine("| ├ö├ÿ├« FAIL | $fail |")
    [void]$sb.AppendLine("| ├ö├£┬¼ EMPTY | $empty |")
    [void]$sb.AppendLine("| ┬¡ãÆ├ÂÔöñ ERROR | $errors |")
    [void]$sb.AppendLine("| ├ö├à┬í SKIPPED | $skipped |")
    [void]$sb.AppendLine("| **Coverage** | **$coverage%** |")
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("## Results by Category")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Category | OK | FAIL | EMPTY | ERROR | SKIPPED |")
    [void]$sb.AppendLine("|----------|-----|------|-------|-------|---------|")
    $Results | Group-Object category | Sort-Object Name | ForEach-Object {
        $cat     = $_.Name
        $catOk   = ($_.Group | Where-Object { $_.status -eq 'OK' }).Count
        $catFail = ($_.Group | Where-Object { $_.status -eq 'FAIL' }).Count
        $catEmp  = ($_.Group | Where-Object { $_.status -eq 'EMPTY' }).Count
        $catErr  = ($_.Group | Where-Object { $_.status -eq 'ERROR' }).Count
        $catSkip = ($_.Group | Where-Object { $_.status -eq 'SKIPPED' }).Count
        [void]$sb.AppendLine("| $cat | $catOk | $catFail | $catEmp | $catErr | $catSkip |")
    }
    [void]$sb.AppendLine("")

    $failItems = $Results | Where-Object { $_.status -eq 'FAIL' }
    if ($failItems) {
        [void]$sb.AppendLine("## Failed Checks")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("| GUID | Category | Severity | Description | Evidence Count |")
        [void]$sb.AppendLine("|------|----------|----------|-------------|----------------|")
        foreach ($r in $failItems) {
            $desc = $r.text -replace '\|', '\|'
            [void]$sb.AppendLine("| $($r.guid) | $($r.category) | $($r.severity) | $desc | $($r.evidenceCount) |")
        }
        [void]$sb.AppendLine("")
    }

    $errorItems = $Results | Where-Object { $_.status -eq 'ERROR' }
    if ($errorItems) {
        [void]$sb.AppendLine("## Query Errors")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("| GUID | Category | Error |")
        [void]$sb.AppendLine("|------|----------|-------|")
        foreach ($r in $errorItems) {
            $err = $r.error -replace '\|', '\|'
            [void]$sb.AppendLine("| $($r.guid) | $($r.category) | $err |")
        }
        [void]$sb.AppendLine("")
    }

    $notQ = $Results | Where-Object { $_.checkType -eq 'None' }
    if ($notQ) {
        [void]$sb.AppendLine("## Not Queryable Items")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("| GUID | Category | Subcategory | Description |")
        [void]$sb.AppendLine("|------|----------|-------------|-------------|")
        foreach ($r in $notQ) {
            $desc = $r.text -replace '\|', '\|'
            [void]$sb.AppendLine("| $($r.guid) | $($r.category) | $($r.subcategory) | $desc |")
        }
    }

    $sb.ToString() | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "Markdown report: $OutputPath"
}

function Export-HtmlReport {
    param(
        [Parameter(Mandatory)] $Results,
        [Parameter(Mandatory)] [string] $OutputPath,
        [string] $Scope = 'unknown',
        [string] $Identity = 'unknown',
        [string] $ToolVersion = '1.1.0'
    )

    $date      = Get-Date -Format 'yyyy-MM-dd HH:mm UTC'
    $total     = $Results.Count
    $ok        = ($Results | Where-Object { $_.status -eq 'OK' }).Count
    $fail      = ($Results | Where-Object { $_.status -eq 'FAIL' }).Count
    $empty     = ($Results | Where-Object { $_.status -eq 'EMPTY' }).Count
    $err       = ($Results | Where-Object { $_.status -eq 'ERROR' }).Count
    $skip      = ($Results | Where-Object { $_.status -eq 'SKIPPED' }).Count
    $queryable = ($Results | Where-Object { $_.checkType -ne 'None' }).Count
    $coverage  = if ($queryable -gt 0) { [math]::Round(($ok + $fail + $empty) / $queryable * 100, 1) } else { 0 }

    $rowsJson = $Results |
        Select-Object guid, category, subcategory, severity, text, checkType, status, evidenceCount, error |
        ConvertTo-Json -Compress -Depth 3

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>ALZ Validation Report ├ö├ç├Â $date</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 0; background: #f8f9fa; color: #212529; }
  .header { background: #0078d4; color: white; padding: 24px 32px; }
  .header h1 { margin: 0 0 8px; font-size: 1.6rem; }
  .meta { opacity: 0.85; font-size: 0.9rem; }
  .content { max-width: 1200px; margin: 0 auto; padding: 24px 32px; }
  .cards { display: flex; gap: 16px; flex-wrap: wrap; margin-bottom: 28px; }
  .card { background: white; border-radius: 8px; padding: 16px 20px; min-width: 120px; box-shadow: 0 1px 4px rgba(0,0,0,.1); }
  .card .val { font-size: 2rem; font-weight: 700; }
  .card .lbl { font-size: 0.8rem; color: #6c757d; margin-top: 4px; }
  .card.ok .val { color: #107c10; } .card.fail .val { color: #d13438; }
  .card.empty .val { color: #6c757d; } .card.err .val { color: #ca5010; }
  .card.skip .val { color: #8a8886; } .card.cov .val { color: #0078d4; }
  .filters { background: white; border-radius: 8px; padding: 16px; margin-bottom: 20px; box-shadow: 0 1px 4px rgba(0,0,0,.1); display: flex; gap: 12px; flex-wrap: wrap; align-items: center; }
  .filters label { font-size: 0.85rem; font-weight: 600; }
  .filters select, .filters input { padding: 6px 10px; border: 1px solid #ced4da; border-radius: 4px; font-size: 0.85rem; }
  table { width: 100%; border-collapse: collapse; background: white; border-radius: 8px; overflow: hidden; box-shadow: 0 1px 4px rgba(0,0,0,.1); }
  th { background: #f1f3f5; padding: 10px 14px; text-align: left; font-size: 0.82rem; font-weight: 600; color: #495057; border-bottom: 2px solid #dee2e6; }
  td { padding: 8px 14px; font-size: 0.82rem; border-bottom: 1px solid #f1f3f5; vertical-align: top; }
  tr.ok td:first-child { border-left: 3px solid #107c10; }
  tr.fail td:first-child { border-left: 3px solid #d13438; }
  tr.empty td:first-child { border-left: 3px solid #6c757d; }
  tr.error td:first-child { border-left: 3px solid #ca5010; }
  tr.skipped td:first-child { border-left: 3px solid #8a8886; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 0.75rem; font-weight: 600; }
  .badge-ok { background: #dff6dd; color: #107c10; } .badge-fail { background: #fde7e9; color: #d13438; }
  .badge-empty { background: #f3f2f1; color: #6c757d; } .badge-error { background: #fff4ce; color: #ca5010; }
  .badge-skipped { background: #f3f2f1; color: #8a8886; }
  .severity-high { color: #d13438; font-weight: 600; } .severity-medium { color: #ca5010; } .severity-low { color: #107c10; }
  @media print { .filters { display: none; } body { background: white; } .card { box-shadow: none; border: 1px solid #dee2e6; } }
</style>
</head>
<body>
<div class="header">
  <h1>ALZ Validation Report</h1>
  <div class="meta">$date &nbsp;|&nbsp; Scope: $Scope &nbsp;|&nbsp; Identity: $Identity &nbsp;|&nbsp; Tool v$ToolVersion</div>
</div>
<div class="content">
  <div class="cards">
    <div class="card ok"><div class="val">$ok</div><div class="lbl">├ö┬ú├á OK</div></div>
    <div class="card fail"><div class="val">$fail</div><div class="lbl">├ö├ÿ├« FAIL</div></div>
    <div class="card empty"><div class="val">$empty</div><div class="lbl">├ö├£┬¼ EMPTY</div></div>
    <div class="card err"><div class="val">$err</div><div class="lbl">┬¡ãÆ├ÂÔöñ ERROR</div></div>
    <div class="card skip"><div class="val">$skip</div><div class="lbl">├ö├à┬í SKIPPED</div></div>
    <div class="card cov"><div class="val">${coverage}%</div><div class="lbl">Coverage</div></div>
    <div class="card"><div class="val">$total</div><div class="lbl">Total</div></div>
  </div>
  <div class="filters">
    <label>Status:</label>
    <select id="filterStatus" onchange="applyFilters()">
      <option value="">All</option>
      <option>OK</option><option>FAIL</option><option>EMPTY</option><option>ERROR</option><option>SKIPPED</option>
    </select>
    <label>Category:</label>
    <select id="filterCategory" onchange="applyFilters()">
      <option value="">All categories</option>
    </select>
    <label>Search:</label>
    <input id="filterText" type="text" placeholder="Filter description..." oninput="applyFilters()" style="width:200px">
    <span id="rowCount" style="font-size:0.82rem;color:#6c757d;margin-left:auto"></span>
  </div>
  <table id="resultsTable">
    <thead>
      <tr><th>Category</th><th>Severity</th><th>Status</th><th>Description</th><th>Count</th><th>Error</th></tr>
    </thead>
    <tbody id="resultsBody"></tbody>
  </table>
</div>
<script>
const DATA = $rowsJson;
const cats = [...new Set(DATA.map(r=>r.category))].sort();
const catSel = document.getElementById('filterCategory');
cats.forEach(c => { const o = document.createElement('option'); o.value = c; o.textContent = c; catSel.appendChild(o); });
function applyFilters() {
  const s = document.getElementById('filterStatus').value.toLowerCase();
  const c = document.getElementById('filterCategory').value.toLowerCase();
  const t = document.getElementById('filterText').value.toLowerCase();
  const filtered = DATA.filter(r =>
    (!s || r.status.toLowerCase() === s) &&
    (!c || (r.category||'').toLowerCase() === c) &&
    (!t || (r.text||'').toLowerCase().includes(t) || (r.guid||'').toLowerCase().includes(t))
  );
  renderRows(filtered);
}
function badge(s) {
  const cls = {OK:'ok',FAIL:'fail',EMPTY:'empty',ERROR:'error',SKIPPED:'skipped'}[s]||'empty';
  return '<span class="badge badge-'+cls+'">'+s+'</span>';
}
function sev(s) {
  const cls = {High:'severity-high',Medium:'severity-medium',Low:'severity-low'}[s]||'';
  return '<span class="'+cls+'">'+(s||'')+'</span>';
}
function renderRows(rows) {
  const tb = document.getElementById('resultsBody');
  tb.innerHTML = rows.map(r =>
    '<tr class="'+(r.status||'').toLowerCase()+'">' +
    '<td>'+escape(r.category)+'<br><small style="color:#6c757d">'+escape(r.subcategory)+'</small></td>' +
    '<td>'+sev(r.severity)+'</td>' +
    '<td>'+badge(r.status)+'</td>' +
    '<td>'+escape(r.text)+'</td>' +
    '<td>'+(r.evidenceCount||0)+'</td>' +
    '<td><small style="color:#ca5010">'+escape(r.error||'')+'</small></td>' +
    '</tr>'
  ).join('');
  document.getElementById('rowCount').textContent = rows.length + ' of ' + DATA.length + ' items';
}
function escape(s) { return (s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
applyFilters();
</script>
</body>
</html>
"@
    $html | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "HTML report: $OutputPath"
}

# ---------------------------------------------------------------------------
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
            Write-Error "Cannot query MG '$ManagementGroup' - ensure Reader role at MG scope. $($_.Exception.Message)"
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
        Write-Warning "Azure token expires in $([math]::Round($remainingMin,0)) min ├ö├ç├Â consider re-authenticating before a full run."
    }
} catch {
    Write-Warning "Could not check token expiry: $($_.Exception.Message)"
}

# Pre-flight token expiry check
try {
    $tok = Get-AzAccessToken -ResourceUrl 'https://management.azure.com' -ErrorAction Stop
    $remainingMin = ($tok.ExpiresOn - [DateTimeOffset]::UtcNow).TotalMinutes
    if ($remainingMin -lt 15) {
        Write-Warning "Azure token expires in $([math]::Round($remainingMin,0)) min ├ö├ç├Â consider re-authenticating before a full run."
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
$results   = [System.Collections.ArrayList]::new()
$success   = 0
$failures  = 0
$empty     = 0
$errors_ct = 0
$skipped   = 0
$total     = $queryable.Count
$i         = 0
$scopeLabel = if ($ManagementGroup) { "MG:$ManagementGroup" } elseif ($SubscriptionId) { "Sub:$SubscriptionId" } else { 'global' }

foreach ($q in $queryable) {
    $i++
    $pct = [math]::Round(($i / $total) * 100)
    Write-Progress -Activity "Validating queries" -Status "$i/$total ($pct%) - $($q.category)" -PercentComplete $pct

    $queryIntent = if ($q.queryIntent) { $q.queryIntent } else { 'findViolations' }

    $result = [PSCustomObject]@{
        guid            = $q.guid
        category        = $q.category
        subcategory     = $q.subcategory
        severity        = $q.severity
        text            = $q.text
        checkType       = 'ARG'
        queryOrEndpoint = $q.graph
        queryIntent     = $queryIntent
        status          = ""
        evidenceCount   = 0
        evidenceSample  = ""
        error           = ""
        scope           = $scopeLabel
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
        $result.evidenceCount = $n

        if ($queryIntent -eq 'findEvidence') {
            if ($n -eq 0) { $result.status = "EMPTY"; $empty++ }
            else          { $result.status = "OK";    $success++ }
        } else {
            # findViolations (default): rows > 0 means violations found = FAIL
            if ($n -eq 0) { $result.status = "OK";   $success++ }
            else          { $result.status = "FAIL";  $failures++ }
        }

        $sample = ($allData | Select-Object -First 3 | ConvertTo-Json -Compress -Depth 3)
        if ($sample -and $sample.Length -gt 500) { $sample = $sample.Substring(0, 497) + '...' }
        $result.evidenceSample = $sample
    } catch {
        if ($_.Exception.Message -match 'token|auth|401|expired|credentials|AADSTS') {
            Write-Error "FATAL: Auth failure at query $i. Token may have expired. Re-authenticate and re-run."
            $results | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
            exit 2
        }
        $result.status = "ERROR"
        $result.error  = $_.Exception.Message -replace "`n|`r", " "
        $errors_ct++
    }

    [void]$results.Add($result)
}

# --- Append non-queryable items to unified results ---
$nonQueryableItems = $allQueries | Where-Object { $_.queryable -eq $false }
foreach ($q in $nonQueryableItems) {
    $result = [PSCustomObject]@{
        guid            = $q.guid
        category        = $q.category
        subcategory     = $q.subcategory
        severity        = $q.severity
        text            = $q.text
        checkType       = 'None'
        queryOrEndpoint = ""
        queryIntent     = ""
        status          = "SKIPPED"
        evidenceCount   = 0
        evidenceSample  = ""
        error           = ""
        scope           = $scopeLabel
    }
    [void]$results.Add($result)
    $skipped++
}

Write-Progress -Activity "Validating queries" -Completed

# --- Summary ---
Write-Host ""
Write-Host "=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "  Total queryable items: $total"    -ForegroundColor White
Write-Host "  OK (no violations):    $success"  -ForegroundColor Green
Write-Host "  FAIL (violations found): $failures" -ForegroundColor Red
Write-Host "  EMPTY (valid, 0 rows): $empty"    -ForegroundColor Yellow
Write-Host "  ERROR (query failed):  $errors_ct" -ForegroundColor Red
Write-Host "  SKIPPED (not queryable): $skipped" -ForegroundColor Gray
Write-Host ""

# --- Category breakdown ---
Write-Host "=== Results by Category ===" -ForegroundColor Cyan
$results | Where-Object { $_.checkType -ne 'None' } | Group-Object -Property category | ForEach-Object {
    $catOk   = ($_.Group | Where-Object { $_.status -eq 'OK' }).Count
    $catFail = ($_.Group | Where-Object { $_.status -eq 'FAIL' }).Count
    $catEmp  = ($_.Group | Where-Object { $_.status -eq 'EMPTY' }).Count
    $catErr  = ($_.Group | Where-Object { $_.status -eq 'ERROR' }).Count
    Write-Host "  $($_.Name): OK=$catOk, FAIL=$catFail, Empty=$catEmp, Error=$catErr"
}

# --- Show errors ---
$queryErrors = $results | Where-Object { $_.status -eq 'ERROR' }
if ($queryErrors.Count -gt 0) {
    Write-Host ""
    Write-Host "=== Failed Queries ===" -ForegroundColor Red
    foreach ($e in $queryErrors) {
        Write-Host "  [$($e.guid)] $($e.text.Substring(0, [Math]::Min(80, $e.text.Length)))" -ForegroundColor Yellow
        Write-Host "    Error: $($e.error.Substring(0, [Math]::Min(200, $e.error.Length)))" -ForegroundColor Red
        Write-Host ""
    }
}

# --- Export CSV ---
$results | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
Write-Host "Results exported to: $OutputFile" -ForegroundColor Cyan

# --- Generate additional report formats ---
$identity = try { (Get-AzContext).Account.Id } catch { 'unknown' }
$scope    = $scopeLabel

$basePath = [System.IO.Path]::ChangeExtension($OutputFile, $null).TrimEnd('.')

if ($ReportFormat -in @('Markdown', 'All')) {
    $mdPath = $basePath + '.md'
    Export-MarkdownReport -Results $results -OutputPath $mdPath -Scope $scope -Identity $identity
}
if ($ReportFormat -in @('HTML', 'All')) {
    $htmlPath = $basePath + '.html'
    Export-HtmlReport -Results $results -OutputPath $htmlPath -Scope $scope -Identity $identity
}

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
