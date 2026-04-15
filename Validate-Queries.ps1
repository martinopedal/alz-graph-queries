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

.EXAMPLE
    .\Validate-Queries.ps1
    .\Validate-Queries.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000"
    .\Validate-Queries.ps1 -ManagementGroup "my-mg-name"
#>

[CmdletBinding()]
param(
    [string]$QueriesFile = "$PSScriptRoot\queries\alz_additional_queries.json",
    [string]$OutputFile = "$PSScriptRoot\validation_results.csv",
    [string]$SubscriptionId,
    [string]$ManagementGroup
)

$ErrorActionPreference = 'Continue'

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

# Check login
try {
    $context = Get-AzContext -ErrorAction Stop
    if (-not $context) { throw "No context" }
    Write-Host "Logged in as: $($context.Account.Id)" -ForegroundColor Green
    Write-Host "Tenant:       $($context.Tenant.Id)"
    Write-Host "Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
} catch {
    Write-Host "ERROR: Not logged into Azure. Run Connect-AzAccount first." -ForegroundColor Red
    exit 1
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
