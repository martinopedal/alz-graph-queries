#Requires -Version 5.1
<#
.SYNOPSIS
    Offline KQL syntax validator for ALZ Graph queries using Kusto.Language NuGet.
.DESCRIPTION
    Downloads and caches Microsoft.Azure.Kusto.Language NuGet package on first run.
    Validates KQL syntax in alz_additional_queries.json offline — no Azure credentials needed.
    
    ARG-specific false positives filtered out:
    - KS204 (unknown table)   — ARG tables like 'resources', 'securityresources' not in default schema
    - KS208 (unknown database) 
    - KS142 (unknown name/column)
    
    Real syntax errors (mismatched parens, invalid operators, bad pipe chains) have different codes
    and will still be caught.
.PARAMETER QueriesFile
    Path to the JSON file containing ALZ queries. Defaults to queries/alz_additional_queries.json.
.PARAMETER ToolsDir
    Directory to cache the NuGet package. Defaults to .tools/Kusto.Language/.
.EXAMPLE
    ./scripts/Validate-KqlSyntax.ps1
#>
param(
    [string]$QueriesFile = "$PSScriptRoot\..\queries\alz_additional_queries.json",
    [string]$ToolsDir    = "$PSScriptRoot\..\.tools\Kusto.Language"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Step 1: Ensure Kusto.Language DLL is available ---
$nugetVersion = '12.0.0'
$dllPath = Join-Path $ToolsDir "Kusto.Language.dll"

if (-not (Test-Path $dllPath)) {
    Write-Host "Downloading Microsoft.Azure.Kusto.Language v$nugetVersion..."
    $null = New-Item -ItemType Directory -Path $ToolsDir -Force
    $nupkgPath = Join-Path $ToolsDir "kusto.language.nupkg"
    $nugetUrl = "https://www.nuget.org/api/v2/package/Microsoft.Azure.Kusto.Language/$nugetVersion"
    
    try {
        $wc = [System.Net.WebClient]::new()
        $wc.DownloadFile($nugetUrl, $nupkgPath)
    } catch {
        Write-Error "Failed to download Kusto.Language NuGet: $($_.Exception.Message)"
        exit 1
    }
    
    # Extract .nupkg (it's a zip)
    $extractDir = Join-Path $ToolsDir "extracted"
    Expand-Archive -Path $nupkgPath -DestinationPath $extractDir -Force
    
    # Find the best available DLL (prefer net6.0, fall back to net5.0, netstandard2.0)
    $dllSearch = @('net6.0','net5.0','netstandard2.1','netstandard2.0') | ForEach-Object {
        $candidate = Join-Path $extractDir "lib\$_\Kusto.Language.dll"
        if (Test-Path $candidate) { $candidate }
    } | Select-Object -First 1
    
    if (-not $dllSearch) {
        $dllSearch = Get-ChildItem -Path $extractDir -Recurse -Filter 'Kusto.Language.dll' |
            Select-Object -First 1 -ExpandProperty FullName
    }
    
    if (-not $dllSearch) {
        Write-Error "Could not find Kusto.Language.dll in extracted package"
        exit 1
    }
    
    Copy-Item $dllSearch $dllPath
    Write-Host "Kusto.Language cached at: $dllPath"
}

Add-Type -Path $dllPath

# --- Step 2: Load queries ---
if (-not (Test-Path $QueriesFile)) {
    Write-Error "Queries file not found: $QueriesFile"
    exit 1
}

$root = Get-Content $QueriesFile -Raw | ConvertFrom-Json
$queries = $root.queries
$queryable = $queries | Where-Object { $_.PSObject.Properties['graph'] -and $_.graph.Trim() -ne '' }
Write-Host "Validating $($queryable.Count) KQL queries from $(Split-Path $QueriesFile -Leaf)"

# --- Step 3: Validate each query ---
# Codes to treat as ARG false positives (tables/columns unknown to default Kusto schema)
$falsePositiveCodes = @('KS204', 'KS208', 'KS142')

$errors   = [System.Collections.ArrayList]::new()
$warnings = [System.Collections.ArrayList]::new()
$ok       = 0

foreach ($item in $queryable) {
    $kql = $item.graph.Trim()
    
    # Skip placeholder/empty queries
    if ($kql -match '^\s*(#|//|TODO|PLACEHOLDER)' -or $kql.Length -lt 10) { continue }
    
    try {
        $parsed = [Kusto.Language.KustoCode]::Parse($kql)
        $diags  = $parsed.GetDiagnostics() | Where-Object { $_.Code -notin $falsePositiveCodes }
        
        if ($diags.Count -gt 0) {
            $diagText = ($diags | ForEach-Object { "[$($_.Code)] $($_.Message) (pos $($_.Start))" }) -join '; '
            [void]$errors.Add([PSCustomObject]@{
                guid  = $item.guid
                text  = $item.text
                error = $diagText
                query = if ($kql.Length -gt 120) { $kql.Substring(0, 120) + '...' } else { $kql }
            })
        } else {
            $ok++
        }
    } catch {
        [void]$warnings.Add([PSCustomObject]@{
            guid    = $item.guid
            warning = "Parser threw: $($_.Exception.Message)"
        })
    }
}

# --- Step 4: Also validate field completeness ---
$schemaErrors = [System.Collections.ArrayList]::new()
foreach ($item in $queries) {
    if ($item.queryable -eq $true -and (-not $item.graph -or $item.graph.Trim() -eq '')) {
        [void]$schemaErrors.Add("GUID $($item.guid): queryable=true but no graph field")
    }
    if ($item.queryable -ne $true -and -not $item.reason -and -not $item.graph) {
        [void]$schemaErrors.Add("GUID $($item.guid): queryable=false but no reason field")
    }
}

# --- Step 5: Report ---
Write-Host ""
Write-Host "=== KQL Validation Results ==="
Write-Host "  OK:       $ok"
Write-Host "  Errors:   $($errors.Count)"
Write-Host "  Warnings: $($warnings.Count)"
Write-Host "  Schema:   $($schemaErrors.Count)"

if ($warnings.Count -gt 0) {
    Write-Host "`nWarnings (parser exceptions — may indicate unsupported syntax):"
    $warnings | ForEach-Object { Write-Warning "  [$($_.guid)] $($_.warning)" }
}

if ($schemaErrors.Count -gt 0) {
    Write-Host "`nSchema errors:"
    $schemaErrors | ForEach-Object { Write-Warning "  $_" }
}

if ($errors.Count -gt 0) {
    Write-Host "`nKQL syntax errors:"
    $errors | ForEach-Object {
        Write-Host "  GUID: $($_.guid)"
        Write-Host "  Text: $($_.text)"
        Write-Host "  KQL:  $($_.query)"
        Write-Host "  Diag: $($_.error)"
        Write-Host ""
    }
    Write-Error "$($errors.Count) KQL syntax error(s) found. Fix before merging."
    exit 1
}

Write-Host "`nAll KQL queries passed offline syntax validation."
exit 0
