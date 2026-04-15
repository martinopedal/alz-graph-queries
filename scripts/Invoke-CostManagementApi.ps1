#Requires -Version 5.1
<#
.SYNOPSIS
    Cost Management API module for ALZ budget/cost governance checks.

.DESCRIPTION
    Queries the Azure Cost Management REST API and Azure Resource Graph to assess
    budget and cost governance posture. Returns results in the unified ALZ check
    contract format, compatible with Validate-Queries.ps1 output.

    Checks performed:
      1. budgets-present           -- Budgets configured at scope (findEvidence)
      2. budget-alerts-configured  -- Budgets have notification thresholds (findEvidence)
      3. budget-threshold-exceeded -- Any scope >= 80% of budget amount (findViolations)
      4. cost-anomaly-alerts       -- Cost anomaly scheduled-action alerts present (findEvidence)
      5. orphaned-disks            -- Unattached managed disks via ARG (findViolations)
      6. orphaned-pips             -- Unused public IP addresses via ARG (findViolations)

.PARAMETER SubscriptionId
    Azure subscription ID to scope the checks.

.PARAMETER ManagementGroup
    Management group ID to scope the checks.

.PARAMETER UseIdentity
    Use system-assigned Managed Identity for authentication.

.PARAMETER UseDeviceCode
    Force interactive device code flow.

.PARAMETER TenantId
    Azure tenant ID for SPN or explicit authentication.

.PARAMETER ClientId
    Application (client) ID for SPN authentication.

.PARAMETER ClientSecret
    Client secret for SPN authentication (legacy; prefer certificate or WIF).

.PARAMETER CertificatePath
    Path to PFX certificate for SPN authentication.

.OUTPUTS
    [PSCustomObject[]]  Array of check results in the unified ALZ contract:
    @{ guid; category; subcategory; checkType; queryOrEndpoint; queryIntent;
       status; evidenceCount; evidenceSample; error; scope }

.EXAMPLE
    .\scripts\Invoke-CostManagementApi.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    .\scripts\Invoke-CostManagementApi.ps1 -ManagementGroup "alz-root" -UseIdentity

.EXAMPLE
    $results = .\scripts\Invoke-CostManagementApi.ps1 -SubscriptionId $subId
    $results | Format-Table subcategory, status, evidenceCount
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = 'Azure subscription ID to scope the checks.')]
    [string]$SubscriptionId,

    [Parameter(HelpMessage = 'Management group ID to scope the checks.')]
    [string]$ManagementGroup,

    [Parameter(HelpMessage = 'Use system-assigned Managed Identity.')]
    [switch]$UseIdentity,

    [Parameter(HelpMessage = 'Force interactive device code flow.')]
    [switch]$UseDeviceCode,

    [Parameter(HelpMessage = 'Azure tenant ID.')]
    [string]$TenantId,

    [Parameter(HelpMessage = 'Service principal client ID.')]
    [string]$ClientId,

    [Parameter(HelpMessage = 'Service principal client secret (legacy).')]
    [string]$ClientSecret,

    [Parameter(HelpMessage = 'Path to PFX certificate for SPN auth.')]
    [string]$CertificatePath
)

$ErrorActionPreference = 'Continue'

# ARM base URL ÔÇö no trailing slash
$ArmBaseUrl = 'https://management.azure.com'

# Stable check-type GUIDs (per check definition, not per resource)
$CheckGuids = @{
    'budgets-present'           = 'c4f1a5d2-3b8e-4f9a-b2c1-7e8d9f0a1b2c'
    'budget-alerts-configured'  = 'd5e2b6c3-4c9f-5a0b-c3d2-8f9e0a1b2c3d'
    'budget-threshold-exceeded' = 'e6f3c7d4-5d0a-6b1c-d4e3-9a0f1b2c3d4e'
    'cost-anomaly-alerts'       = 'f7a4d8e5-6e1b-7c2d-e5f4-0b1a2c3d4e5f'
    'orphaned-disks'            = 'a8b5e9f6-7f2c-8d3e-f6a5-1c2b3d4e5f6a'
    'orphaned-pips'             = 'b9c6f0a7-8a3d-9e4f-a7b6-2d3c4e5f6a7b'
}

# --- Helper: Build unified result object ---
function New-CheckResult {
    [OutputType([PSCustomObject])]
    param(
        [string]$CheckKey,
        [string]$Subcategory,
        [string]$QueryOrEndpoint,
        [ValidateSet('findEvidence', 'findViolations')]
        [string]$QueryIntent,
        [ValidateSet('OK', 'EMPTY', 'FAIL', 'SKIP', 'ERROR')]
        [string]$Status,
        [int]$EvidenceCount    = 0,
        [string]$EvidenceSample = '',
        [string]$CheckError    = '',
        [string]$Scope         = ''
    )
    [PSCustomObject]@{
        guid            = $CheckGuids[$CheckKey]
        category        = 'Cost Management'
        subcategory     = $Subcategory
        checkType       = 'CostManagement'
        queryOrEndpoint = $QueryOrEndpoint
        queryIntent     = $QueryIntent
        status          = $Status
        evidenceCount   = $EvidenceCount
        evidenceSample  = $EvidenceSample
        error           = $CheckError
        scope           = $Scope
    }
}

# --- Helper: Invoke ARM REST API ---
function Invoke-ArmRest {
    param(
        [string]$Uri,
        [hashtable]$Headers,
        [string]$Method  = 'GET',
        [object]$Body    = $null
    )
    try {
        $params = @{
            Uri         = $Uri
            Headers     = $Headers
            Method      = $Method
            ContentType = 'application/json'
            ErrorAction = 'Stop'
        }
        if ($null -ne $Body) {
            $params['Body'] = ($Body | ConvertTo-Json -Depth 10 -Compress)
        }
        $response = Invoke-RestMethod @params
        return @{ Success = $true; Data = $response; Error = $null; StatusCode = 200; IsPermission = $false }
    } catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        $msg          = $_.Exception.Message -replace "`n|`r", ' '
        $isPermission = ($statusCode -in @(401, 403)) -or
                        ($msg -match 'Unauthorized|Forbidden|Authorization|Access.*Denied|403|401')
        return @{
            Success      = $false
            Data         = $null
            Error        = $msg
            StatusCode   = $statusCode
            IsPermission = $isPermission
        }
    }
}

# --- Helper: Truncate JSON evidence to safe size ---
function Get-EvidenceSample {
    param([object]$Items, [int]$MaxChars = 500, [int]$MaxItems = 3)
    if ($null -eq $Items) { return '' }
    $arr = @($Items)
    if ($arr.Count -eq 0) { return '' }
    $sample = ($arr | Select-Object -First $MaxItems | ConvertTo-Json -Compress -Depth 3)
    if ($sample.Length -gt $MaxChars) { return $sample.Substring(0, $MaxChars - 3) + '...' }
    return $sample
}

# --- Auth waterfall (mirrors Validate-Queries.ps1) ---
function Invoke-AzAuth {
    param(
        [switch]$UseIdentity,
        [switch]$UseDeviceCode,
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret,
        [string]$CertificatePath
    )

    $hasExplicitParams = $UseIdentity -or $UseDeviceCode -or $TenantId -or $ClientId

    # Reuse ambient context when no explicit params
    if (-not $hasExplicitParams) {
        $ctx = Get-AzContext -ErrorAction SilentlyContinue
        if ($ctx) {
            Write-Host "Using existing Azure context: $($ctx.Account.Id)"
            return
        }
    }

    # WIF/federated (auto-detected)
    if (-not $hasExplicitParams -and
        $env:AZURE_FEDERATED_TOKEN_FILE -and
        $env:AZURE_CLIENT_ID -and
        $env:AZURE_TENANT_ID) {
        $federatedToken = Get-Content -Raw $env:AZURE_FEDERATED_TOKEN_FILE
        Connect-AzAccount -ApplicationId $env:AZURE_CLIENT_ID `
                          -TenantId $env:AZURE_TENANT_ID `
                          -FederatedToken $federatedToken `
                          -ErrorAction Stop | Out-Null
        Write-Host "Authenticated via WIF"
        return
    }

    if ($UseIdentity) {
        Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
        Write-Host "Authenticated via Managed Identity"
        return
    }

    if ($TenantId -and $ClientId -and $CertificatePath) {
        Connect-AzAccount -ServicePrincipal -ApplicationId $ClientId `
                          -TenantId $TenantId -CertificatePath $CertificatePath `
                          -ErrorAction Stop | Out-Null
        Write-Host "Authenticated as SPN $ClientId (cert)"
        return
    }

    if ($TenantId -and $ClientId -and $ClientSecret) {
        $cred = [PSCredential]::new($ClientId, (ConvertTo-SecureString $ClientSecret -AsPlainText -Force))
        Connect-AzAccount -ServicePrincipal -Credential $cred `
                          -TenantId $TenantId -ErrorAction Stop | Out-Null
        Write-Host "Authenticated as SPN $ClientId (secret)"
        return
    }

    $isCI       = $env:GITHUB_ACTIONS -or $env:TF_BUILD -or $env:CI -or $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI
    $isRedirect = [Console]::IsInputRedirected

    if (-not $isCI -and -not $isRedirect) {
        if ($UseDeviceCode) {
            Connect-AzAccount -UseDeviceAuthentication -ErrorAction Stop | Out-Null
        } else {
            Connect-AzAccount -ErrorAction Stop | Out-Null
        }
        Write-Host "Authenticated interactively: $((Get-AzContext).Account.Id)"
        return
    }

    throw @"
No Azure context found and non-interactive environment detected.
Authentication options:
  -UseIdentity                                         Managed Identity
  -TenantId + -ClientId + -CertificatePath             SPN with certificate (recommended)
  -TenantId + -ClientId + -ClientSecret                SPN with secret (legacy)
  Set AZURE_FEDERATED_TOKEN_FILE + AZURE_CLIENT_ID + AZURE_TENANT_ID  OIDC/WIF
  Run Connect-AzAccount before invoking this script
"@
}

# ============================================================
# Main
# ============================================================

Write-Host '=== ALZ Cost Management Checks ===' -ForegroundColor Cyan
Write-Host ''

Invoke-AzAuth -UseIdentity:$UseIdentity -UseDeviceCode:$UseDeviceCode `
              -TenantId $TenantId -ClientId $ClientId `
              -ClientSecret $ClientSecret -CertificatePath $CertificatePath

# Acquire bearer token
$tokenResult = Get-AzAccessToken -ResourceUrl 'https://management.azure.com/' -ErrorAction Stop
$authHeaders = @{
    Authorization  = "Bearer $($tokenResult.Token)"
    'Content-Type' = 'application/json'
}

# Resolve ARM scope
$ctx           = Get-AzContext
$resolvedSubId = if ($SubscriptionId) { $SubscriptionId } else { $null }

$armScope = if ($ManagementGroup) {
    "providers/Microsoft.Management/managementGroups/$ManagementGroup"
} elseif ($resolvedSubId) {
    "subscriptions/$resolvedSubId"
} else {
    $ctxSub = $ctx.Subscription.Id
    if (-not $ctxSub) { throw 'No subscription or management group specified and no active subscription context.' }
    $resolvedSubId = $ctxSub
    "subscriptions/$ctxSub"
}

$scopeLabel = $armScope
Write-Host "Scope: $armScope"
Write-Host ''

$results = [System.Collections.ArrayList]::new()

# ==============================================================
# Check 1 ÔÇö Budgets present
# ==============================================================
Write-Host '  [1/6] Checking for configured budgets...'
$budgetsUrl  = "$ArmBaseUrl/$armScope/providers/Microsoft.Consumption/budgets?api-version=2023-05-01"
$budgetsResp = Invoke-ArmRest -Uri $budgetsUrl -Headers $authHeaders

if (-not $budgetsResp.Success) {
    $status = if ($budgetsResp.IsPermission) { 'SKIP' } else { 'ERROR' }
    $errMsg = if ($budgetsResp.IsPermission) { "Permission denied ($(($budgetsResp.StatusCode)))): $($budgetsResp.Error)" } else { $budgetsResp.Error }
    [void]$results.Add((New-CheckResult -CheckKey 'budgets-present' `
        -Subcategory  'Budgets Present' `
        -QueryOrEndpoint $budgetsUrl `
        -QueryIntent  'findEvidence' `
        -Status       $status `
        -CheckError   $errMsg `
        -Scope        $scopeLabel))
} else {
    $budgets = @($budgetsResp.Data.value)
    $status  = if ($budgets.Count -gt 0) { 'OK' } else { 'EMPTY' }
    [void]$results.Add((New-CheckResult -CheckKey 'budgets-present' `
        -Subcategory   'Budgets Present' `
        -QueryOrEndpoint $budgetsUrl `
        -QueryIntent   'findEvidence' `
        -Status        $status `
        -EvidenceCount $budgets.Count `
        -EvidenceSample (Get-EvidenceSample $budgets) `
        -Scope         $scopeLabel))
}

# ==============================================================
# Check 2 ÔÇö Budget alert notifications configured
# ==============================================================
Write-Host '  [2/6] Checking budget alert notifications...'
if ($budgetsResp.Success) {
    $budgets = @($budgetsResp.Data.value)
    $alertedBudgets = @($budgets | Where-Object {
        $notifs = $_.properties.notifications
        ($null -ne $notifs) -and (@($notifs.PSObject.Properties).Count -gt 0)
    })
    $status = if ($alertedBudgets.Count -gt 0) { 'OK' } else { 'EMPTY' }
    [void]$results.Add((New-CheckResult -CheckKey 'budget-alerts-configured' `
        -Subcategory   'Budget Alert Notifications' `
        -QueryOrEndpoint $budgetsUrl `
        -QueryIntent   'findEvidence' `
        -Status        $status `
        -EvidenceCount $alertedBudgets.Count `
        -EvidenceSample (Get-EvidenceSample $alertedBudgets) `
        -Scope         $scopeLabel))
} else {
    # Propagate same status as check 1 (same underlying API call)
    $c1 = $results | Where-Object { $_.subcategory -eq 'Budgets Present' } | Select-Object -Last 1
    [void]$results.Add((New-CheckResult -CheckKey 'budget-alerts-configured' `
        -Subcategory   'Budget Alert Notifications' `
        -QueryOrEndpoint $budgetsUrl `
        -QueryIntent   'findEvidence' `
        -Status        $c1.status `
        -CheckError    $c1.error `
        -Scope         $scopeLabel))
}

# ==============================================================
# Check 3 ÔÇö Budget threshold exceeded (>= 80 %)
# ==============================================================
Write-Host '  [3/6] Checking budget consumption against thresholds...'
if ($budgetsResp.Success) {
    $budgets   = @($budgetsResp.Data.value)
    $exceeding = @($budgets | Where-Object {
        $props = $_.properties
        if ($props.amount -and $null -ne $props.currentSpend -and $props.currentSpend.amount) {
            ($props.currentSpend.amount / $props.amount) -ge 0.80
        }
    })
    $status = if ($exceeding.Count -gt 0) { 'FAIL' } else { 'OK' }
    [void]$results.Add((New-CheckResult -CheckKey 'budget-threshold-exceeded' `
        -Subcategory   'Budget Threshold Exceeded (>= 80%)' `
        -QueryOrEndpoint $budgetsUrl `
        -QueryIntent   'findViolations' `
        -Status        $status `
        -EvidenceCount $exceeding.Count `
        -EvidenceSample (Get-EvidenceSample $exceeding) `
        -Scope         $scopeLabel))
} else {
    $c1 = $results | Where-Object { $_.subcategory -eq 'Budgets Present' } | Select-Object -Last 1
    [void]$results.Add((New-CheckResult -CheckKey 'budget-threshold-exceeded' `
        -Subcategory   'Budget Threshold Exceeded (>= 80%)' `
        -QueryOrEndpoint $budgetsUrl `
        -QueryIntent   'findViolations' `
        -Status        $c1.status `
        -CheckError    $c1.error `
        -Scope         $scopeLabel))
}

# ==============================================================
# Check 4 ÔÇö Cost anomaly alerts (Scheduled Actions / InsightAlert)
# ==============================================================
Write-Host '  [4/6] Checking cost anomaly alert rules...'
$scheduledActionsUrl  = "$ArmBaseUrl/$armScope/providers/Microsoft.CostManagement/scheduledActions?api-version=2023-11-01"
$scheduledActionsResp = Invoke-ArmRest -Uri $scheduledActionsUrl -Headers $authHeaders

if (-not $scheduledActionsResp.Success) {
    $status = if ($scheduledActionsResp.IsPermission) { 'SKIP' } else { 'ERROR' }
    $errMsg = if ($scheduledActionsResp.IsPermission) {
        "Permission denied ($($scheduledActionsResp.StatusCode)): $($scheduledActionsResp.Error)"
    } else { $scheduledActionsResp.Error }
    [void]$results.Add((New-CheckResult -CheckKey 'cost-anomaly-alerts' `
        -Subcategory   'Cost Anomaly Alerts' `
        -QueryOrEndpoint $scheduledActionsUrl `
        -QueryIntent   'findEvidence' `
        -Status        $status `
        -CheckError    $errMsg `
        -Scope         $scopeLabel))
} else {
    $actions       = @($scheduledActionsResp.Data.value)
    $anomalyAlerts = @($actions | Where-Object { $_.kind -eq 'InsightAlert' })
    $status        = if ($anomalyAlerts.Count -gt 0) { 'OK' } else { 'EMPTY' }
    [void]$results.Add((New-CheckResult -CheckKey 'cost-anomaly-alerts' `
        -Subcategory   'Cost Anomaly Alerts' `
        -QueryOrEndpoint $scheduledActionsUrl `
        -QueryIntent   'findEvidence' `
        -Status        $status `
        -EvidenceCount $anomalyAlerts.Count `
        -EvidenceSample (Get-EvidenceSample $anomalyAlerts) `
        -Scope         $scopeLabel))
}

# ==============================================================
# ARG REST helper ÔÇö shared for checks 5 & 6
# ==============================================================
$argUrl    = "$ArmBaseUrl/providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01"
$argScoping = @{}
if ($resolvedSubId)   { $argScoping['subscriptions']    = @($resolvedSubId) }
if ($ManagementGroup) { $argScoping['managementGroups'] = @($ManagementGroup) }
if ($argScoping.Count -eq 0 -and $ctx.Subscription.Id) {
    $argScoping['subscriptions'] = @($ctx.Subscription.Id)
}

# ==============================================================
# Check 5 ÔÇö Orphaned managed disks
# ==============================================================
Write-Host '  [5/6] Checking for unattached managed disks...'
$diskQuery = @"
resources
| where type == 'microsoft.compute/disks'
| where properties.diskState == 'Unattached'
| project id, name, subscriptionId, resourceGroup, sku = sku.name, sizeGB = properties.diskSizeGB
"@
$diskBody = $argScoping + @{ query = $diskQuery.Trim() }
$diskResp = Invoke-ArmRest -Uri $argUrl -Headers $authHeaders -Method 'POST' -Body $diskBody

if (-not $diskResp.Success) {
    $status = if ($diskResp.IsPermission) { 'SKIP' } else { 'ERROR' }
    $errMsg = if ($diskResp.IsPermission) { "Permission denied ($($diskResp.StatusCode)): $($diskResp.Error)" } else { $diskResp.Error }
    [void]$results.Add((New-CheckResult -CheckKey 'orphaned-disks' `
        -Subcategory   'Orphaned Managed Disks' `
        -QueryOrEndpoint $argUrl `
        -QueryIntent   'findViolations' `
        -Status        $status `
        -CheckError    $errMsg `
        -Scope         $scopeLabel))
} else {
    $disks  = @($diskResp.Data.data)
    $status = if ($disks.Count -gt 0) { 'FAIL' } else { 'OK' }
    [void]$results.Add((New-CheckResult -CheckKey 'orphaned-disks' `
        -Subcategory   'Orphaned Managed Disks' `
        -QueryOrEndpoint $argUrl `
        -QueryIntent   'findViolations' `
        -Status        $status `
        -EvidenceCount $disks.Count `
        -EvidenceSample (Get-EvidenceSample $disks) `
        -Scope         $scopeLabel))
}

# ==============================================================
# Check 6 ÔÇö Orphaned public IP addresses
# ==============================================================
Write-Host '  [6/6] Checking for unused public IP addresses...'
$pipQuery = @"
resources
| where type == 'microsoft.network/publicipaddresses'
| where isnull(properties.ipConfiguration)
| project id, name, subscriptionId, resourceGroup, sku = sku.name, allocationMethod = properties.publicIPAllocationMethod
"@
$pipBody = $argScoping + @{ query = $pipQuery.Trim() }
$pipResp = Invoke-ArmRest -Uri $argUrl -Headers $authHeaders -Method 'POST' -Body $pipBody

if (-not $pipResp.Success) {
    $status = if ($pipResp.IsPermission) { 'SKIP' } else { 'ERROR' }
    $errMsg = if ($pipResp.IsPermission) { "Permission denied ($($pipResp.StatusCode)): $($pipResp.Error)" } else { $pipResp.Error }
    [void]$results.Add((New-CheckResult -CheckKey 'orphaned-pips' `
        -Subcategory   'Orphaned Public IP Addresses' `
        -QueryOrEndpoint $argUrl `
        -QueryIntent   'findViolations' `
        -Status        $status `
        -CheckError    $errMsg `
        -Scope         $scopeLabel))
} else {
    $pips   = @($pipResp.Data.data)
    $status = if ($pips.Count -gt 0) { 'FAIL' } else { 'OK' }
    [void]$results.Add((New-CheckResult -CheckKey 'orphaned-pips' `
        -Subcategory   'Orphaned Public IP Addresses' `
        -QueryOrEndpoint $argUrl `
        -QueryIntent   'findViolations' `
        -Status        $status `
        -EvidenceCount $pips.Count `
        -EvidenceSample (Get-EvidenceSample $pips) `
        -Scope         $scopeLabel))
}

# ==============================================================
# Summary
# ==============================================================
Write-Host ''
Write-Host '=== Cost Management Check Summary ===' -ForegroundColor Cyan
foreach ($r in $results) {
    $color = switch ($r.status) {
        'OK'    { 'Green' }
        'EMPTY' { 'Yellow' }
        'FAIL'  { 'Red' }
        'SKIP'  { 'DarkYellow' }
        default { 'Red' }
    }
    Write-Host "  [$($r.status.PadRight(5))] $($r.subcategory)" -ForegroundColor $color
}
Write-Host ''

return $results.ToArray()
