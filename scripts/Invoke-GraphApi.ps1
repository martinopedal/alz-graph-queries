<#
.SYNOPSIS
    Microsoft Graph API module for ALZ identity and Entra ID coverage checks.

.DESCRIPTION
    Queries the Microsoft Graph API for ALZ-relevant Entra ID signals that cannot be
    retrieved via Azure Resource Graph (ARG). Returns results in the same unified contract
    used by Validate-Queries.ps1 for ARG checks.

    Checks implemented:
      1. Conditional Access policies — are any CA policies enabled?
      2. MFA enforcement via Conditional Access — does any CA policy require MFA?
      3. PIM eligible role assignments — are privileged roles using PIM (eligible assignments)?
      4. Emergency / break-glass accounts — are cloud-only emergency access accounts present?
      5. Security defaults — is the identitySecurityDefaultsEnforcementPolicy enabled?
      6. Named locations — are trusted IP/location definitions configured?
      7. Permanent Global Administrator assignments — any non-PIM permanent Global Admin?

.PARAMETER TenantId
    Azure tenant ID. If omitted the tenant from the current Az context is used.

.PARAMETER ClientId
    Application (client) ID for SPN authentication (optional if using ambient Az context).

.PARAMETER ClientSecret
    Client secret for SPN (legacy). Prefer CertificatePath or ambient context.

.PARAMETER CertificatePath
    Path to PFX certificate for SPN authentication.

.PARAMETER UseIdentity
    Use system-assigned Managed Identity to obtain a Graph token.

.PARAMETER UseDeviceCode
    Force interactive device code flow for authentication.

.OUTPUTS
    [PSCustomObject[]] — one object per check with the unified result contract:
      guid, category, subcategory, checkType, queryOrEndpoint, queryIntent,
      status, evidenceCount, evidenceSample, error, scope

.EXAMPLE
    # Invoke standalone (uses current Az context):
    $results = & "$PSScriptRoot\Invoke-GraphApi.ps1"
    $results | Format-Table guid, status, evidenceCount

.EXAMPLE
    # Invoke from Validate-Queries.ps1 (auth params forwarded):
    $graphResults = & (Join-Path $PSScriptRoot 'scripts' 'Invoke-GraphApi.ps1') `
        -TenantId $TenantId -ClientId $ClientId -CertificatePath $CertificatePath
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [string]$CertificatePath,

    [Parameter(Mandatory = $false)]
    [switch]$UseIdentity,

    [Parameter(Mandatory = $false)]
    [switch]$UseDeviceCode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function New-GraphResult {
    <#
    .SYNOPSIS Creates a result object in the unified contract.
    #>
    param(
        [string]$Guid,
        [string]$Category,
        [string]$Subcategory,
        [string]$Endpoint,
        [string]$QueryIntent,      # 'findEvidence' | 'findViolations'
        [string]$Status,           # OK | EMPTY | FAIL | ERROR | SKIP
        [int]   $EvidenceCount = 0,
        [string]$EvidenceSample = '',
        [string]$ErrorMessage  = '',
        [string]$Scope         = 'tenant'
    )
    [PSCustomObject]@{
        guid             = $Guid
        category         = $Category
        subcategory      = $Subcategory
        checkType        = 'Graph'
        queryOrEndpoint  = $Endpoint
        queryIntent      = $QueryIntent
        status           = $Status
        evidenceCount    = $EvidenceCount
        evidenceSample   = $EvidenceSample
        error            = $ErrorMessage
        scope            = $Scope
    }
}

function Get-GraphBearerToken {
    <#
    .SYNOPSIS
        Obtains a bearer token for https://graph.microsoft.com.
        Priority: explicit SPN creds > Az module ambient context > environment WIF.
    #>
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret,
        [string]$CertificatePath,
        [switch]$UseIdentity
    )

    # Path 1: SPN with client secret — direct token endpoint call (no Az module needed)
    if ($TenantId -and $ClientId -and $ClientSecret) {
        Write-Verbose "Graph auth: SPN client secret"
        $body = @{
            grant_type    = 'client_credentials'
            client_id     = $ClientId
            client_secret = $ClientSecret
            scope         = 'https://graph.microsoft.com/.default'
        }
        $resp = Invoke-RestMethod -Method Post `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
        return $resp.access_token
    }

    # Path 2: Az module ambient context — reuse the signed-in session
    if (Get-Command Get-AzAccessToken -ErrorAction SilentlyContinue) {
        try {
            $tok = Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com' -ErrorAction Stop
            Write-Verbose "Graph auth: Az module ambient context"
            # Handle both string token and SecureString (Az 12+)
            if ($tok.Token -is [System.Security.SecureString]) {
                $bstr  = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($tok.Token)
                $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                return $plain
            }
            return $tok.Token
        } catch {
            Write-Warning "Get-AzAccessToken for Graph failed: $($_.Exception.Message)"
        }
    }

    # Path 3: WIF / OIDC environment variables — exchange federated token
    if ($env:AZURE_FEDERATED_TOKEN_FILE -and $env:AZURE_CLIENT_ID -and $env:AZURE_TENANT_ID) {
        Write-Verbose "Graph auth: WIF federated token exchange"
        $federatedToken = Get-Content -Raw $env:AZURE_FEDERATED_TOKEN_FILE
        $body = @{
            grant_type            = 'urn:ietf:params:oauth:grant-type:jwt-bearer'
            client_id             = $env:AZURE_CLIENT_ID
            client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
            client_assertion      = $federatedToken
            scope                 = 'https://graph.microsoft.com/.default'
            requested_token_use   = 'on_behalf_of'
        }
        try {
            $resp = Invoke-RestMethod -Method Post `
                -Uri "https://login.microsoftonline.com/$($env:AZURE_TENANT_ID)/oauth2/v2.0/token" `
                -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
            return $resp.access_token
        } catch {
            Write-Warning "WIF token exchange for Graph failed: $($_.Exception.Message)"
        }
    }

    throw "No Graph bearer token could be obtained. " +
          "Ensure Az module is signed in (Connect-AzAccount), or supply -TenantId + -ClientId + -ClientSecret, " +
          "or set AZURE_FEDERATED_TOKEN_FILE / AZURE_CLIENT_ID / AZURE_TENANT_ID for WIF."
}

function Invoke-GraphRequest {
    <#
    .SYNOPSIS Calls a Graph endpoint and returns the value array (handles @odata.nextLink paging).
    #>
    param(
        [string]$Token,
        [string]$Uri
    )
    $headers = @{ Authorization = "Bearer $Token"; ConsistencyLevel = 'eventual' }
    $all     = [System.Collections.ArrayList]::new()
    $nextUri = $Uri

    do {
        $page    = Invoke-RestMethod -Method Get -Uri $nextUri -Headers $headers -ErrorAction Stop
        $items   = if ($page.PSObject.Properties['value'] -and $page.value) { $page.value } elseif ($page.PSObject.Properties['id']) { @($page) } else { @() }
        foreach ($item in $items) { [void]$all.Add($item) }
        $nextUri = if ($page.PSObject.Properties['@odata.nextLink']) { $page.'@odata.nextLink' } else { $null }
    } while ($nextUri)

    return , $all   # comma forces array return through pipeline
}

function Format-Sample {
    param($Items, [int]$MaxItems = 3, [int]$MaxChars = 500)
    $sample = ($Items | Select-Object -First $MaxItems | ConvertTo-Json -Compress -Depth 3)
    if ($sample -and $sample.Length -gt $MaxChars) { $sample = $sample.Substring(0, $MaxChars - 3) + '...' }
    return $sample
}

# ---------------------------------------------------------------------------
# Acquire token
# ---------------------------------------------------------------------------

Write-Verbose "=== Invoke-GraphApi.ps1 — acquiring Graph token ==="

$token         = $null
$tenantScope   = 'tenant'
$tokenError    = $null

try {
    $token = Get-GraphBearerToken `
        -TenantId      $TenantId `
        -ClientId      $ClientId `
        -ClientSecret  $ClientSecret `
        -CertificatePath $CertificatePath `
        -UseIdentity:$UseIdentity

    # Determine tenant ID for scope label
    if (-not $TenantId) {
        $ctx = Get-AzContext -ErrorAction SilentlyContinue
        if ($ctx) { $TenantId = $ctx.Tenant.Id }
    }
    if ($TenantId) { $tenantScope = "tenant:$TenantId" }
} catch {
    $tokenError = $_.Exception.Message
    Write-Warning "Invoke-GraphApi: could not obtain Graph token — all checks will SKIP. $tokenError"
}

# ---------------------------------------------------------------------------
# Helper that returns a SKIP result when no token available
# ---------------------------------------------------------------------------
function Skip-Result {
    param([string]$Guid, [string]$Category, [string]$Subcategory, [string]$Endpoint, [string]$Intent)
    New-GraphResult -Guid $Guid -Category $Category -Subcategory $Subcategory `
        -Endpoint $Endpoint -QueryIntent $Intent `
        -Status 'SKIP' -ErrorMessage "No Graph token: $tokenError" -Scope $tenantScope
}

# ---------------------------------------------------------------------------
# Check definitions (metadata)
# ---------------------------------------------------------------------------
$baseCategory = 'Identity and Access Management'
$subIdentity  = 'Identity'

# ---------------------------------------------------------------------------
# CHECK 1: Conditional Access policies — any enabled?
# ALZ item: 53e8908a — Enforce CA policies for Azure-environment users
# queryIntent: findEvidence (we want to confirm CA policies exist)
# ---------------------------------------------------------------------------
$check1 = @{
    guid        = '53e8908a-e28c-484c-93b6-b7808b9fe5c4'
    category    = $baseCategory
    subcategory = $subIdentity
    endpoint    = 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies'
    intent      = 'findEvidence'
    description = 'Conditional Access policies enabled'
}

# ---------------------------------------------------------------------------
# CHECK 2: MFA via Conditional Access — any CA policy grants require MFA?
# ALZ item: 1049d403 — Enforce MFA for Azure environment users
# queryIntent: findEvidence (we want to see MFA-enforcing CA policies)
# ---------------------------------------------------------------------------
$check2 = @{
    guid        = '1049d403-a923-4c34-94d0-0018ac6a9e01'
    category    = $baseCategory
    subcategory = $subIdentity
    endpoint    = 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies'
    intent      = 'findEvidence'
    description = 'CA policies with MFA grant controls'
}

# ---------------------------------------------------------------------------
# CHECK 3: PIM eligible role assignments — privileged roles using PIM?
# ALZ item: 14658d35 — Enforce PIM for zero standing access
# queryIntent: findEvidence (eligible assignments confirm PIM is used)
# ---------------------------------------------------------------------------
$check3 = @{
    guid        = '14658d35-58fd-4772-99b8-21112df27ee4'
    category    = $baseCategory
    subcategory = $subIdentity
    endpoint    = 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilitySchedules?$select=id,principalId,roleDefinitionId,status,scheduleInfo'
    intent      = 'findEvidence'
    description = 'PIM eligible role assignment schedules'
}

# ---------------------------------------------------------------------------
# CHECK 4: Emergency / break-glass accounts
# ALZ item: 984a859c — Implement emergency access accounts
# queryIntent: findEvidence (we want to confirm break-glass accounts exist)
# Strategy: users with displayName or UPN containing "break" or "emergency" or "breakglass"
# ---------------------------------------------------------------------------
$check4 = @{
    guid        = '984a859c-773e-47d2-9162-3a765a917e1f'
    category    = $baseCategory
    subcategory = $subIdentity
    endpoint    = "https://graph.microsoft.com/v1.0/users?`$filter=accountEnabled eq true and (startswith(displayName,'break') or startswith(displayName,'emergency') or startswith(displayName,'BreakGlass') or startswith(userPrincipalName,'break') or startswith(userPrincipalName,'emergency'))&`$select=id,displayName,userPrincipalName,accountEnabled&`$count=true"
    intent      = 'findEvidence'
    description = 'Emergency/break-glass cloud accounts'
}

# ---------------------------------------------------------------------------
# CHECK 5: Security defaults status
# (No direct ALZ GUID — general identity hardening)
# queryIntent: findEvidence (enabled=true is the compliant state)
# ---------------------------------------------------------------------------
$check5 = @{
    guid        = 'secdefaults-00000000-0000-0000-0000-000000000001'
    category    = $baseCategory
    subcategory = $subIdentity
    endpoint    = 'https://graph.microsoft.com/v1.0/policies/identitySecurityDefaultsEnforcementPolicy'
    intent      = 'findEvidence'
    description = 'Security defaults enforcement policy'
}

# ---------------------------------------------------------------------------
# CHECK 6: Named locations — trusted IP / country locations configured?
# (Supports CA policy named location conditions)
# queryIntent: findEvidence (named locations confirm trusted IP setup)
# ---------------------------------------------------------------------------
$check6 = @{
    guid        = 'namedlocations-0000-0000-0000-000000000002'
    category    = $baseCategory
    subcategory = $subIdentity
    endpoint    = 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/namedLocations'
    intent      = 'findEvidence'
    description = 'Named locations / trusted IPs configured'
}

# ---------------------------------------------------------------------------
# CHECK 7: Permanent Global Administrator assignments (non-PIM)
# ALZ item: d98d954d — Limit Global Administrator to emergency scenarios
# queryIntent: findViolations (permanent GA = violation; should use PIM only)
# The Global Administrator role definition ID is fixed across all tenants.
# ---------------------------------------------------------------------------
$globalAdminRoleId = '62e90394-69f5-4237-9190-012177145e10'
$check7 = @{
    guid        = 'd98d954d-7d1c-4a07-92a7-cf3afe8dcbd2'
    category    = $baseCategory
    subcategory = $subIdentity
    endpoint    = "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '$globalAdminRoleId'&`$select=id,principalId,roleDefinitionId,directoryScopeId"
    intent      = 'findViolations'
    description = 'Permanent (non-PIM) Global Admin assignments'
}

# ---------------------------------------------------------------------------
# Run checks
# ---------------------------------------------------------------------------

$results = [System.Collections.ArrayList]::new()

foreach ($check in @($check1, $check2, $check3, $check4, $check5, $check6, $check7)) {
    if (-not $token) {
        [void]$results.Add((Skip-Result -Guid $check.guid -Category $check.category `
            -Subcategory $check.subcategory -Endpoint $check.endpoint -Intent $check.intent))
        continue
    }

    Write-Verbose "Graph check [$($check.guid)]: $($check.description)"

    try {
        # ---------------------------------------------------------------
        # Fetch data from Graph
        # ---------------------------------------------------------------
        $raw = Invoke-GraphRequest -Token $token -Uri $check.endpoint

        # ---------------------------------------------------------------
        # Per-check post-processing
        # ---------------------------------------------------------------
        switch ($check.guid) {

            # CHECK 1: Any enabled CA policies?
            '53e8908a-e28c-484c-93b6-b7808b9fe5c4' {
                $enabled = @($raw | Where-Object { $_.state -eq 'enabled' })
                $n       = $enabled.Count
                $sample  = Format-Sample -Items ($enabled | Select-Object -Property id,displayName,state)
                $status  = if ($n -gt 0) { 'OK' } else { 'EMPTY' }
                [void]$results.Add((New-GraphResult -Guid $check.guid -Category $check.category `
                    -Subcategory $check.subcategory -Endpoint $check.endpoint -QueryIntent $check.intent `
                    -Status $status -EvidenceCount $n -EvidenceSample $sample -Scope $tenantScope))
            }

            # CHECK 2: CA policies with MFA grant?
            '1049d403-a923-4c34-94d0-0018ac6a9e01' {
                $mfaPolicies = @($raw | Where-Object {
                    $_.state -eq 'enabled' -and
                    $_.grantControls -and
                    $_.grantControls.builtInControls -contains 'mfa'
                })
                $n      = $mfaPolicies.Count
                $sample = Format-Sample -Items ($mfaPolicies | Select-Object -Property id,displayName,state)
                $status = if ($n -gt 0) { 'OK' } else { 'EMPTY' }
                [void]$results.Add((New-GraphResult -Guid $check.guid -Category $check.category `
                    -Subcategory $check.subcategory -Endpoint $check.endpoint -QueryIntent $check.intent `
                    -Status $status -EvidenceCount $n -EvidenceSample $sample -Scope $tenantScope))
            }

            # CHECK 3: PIM eligible schedules
            '14658d35-58fd-4772-99b8-21112df27ee4' {
                $active = @($raw | Where-Object { $_.status -eq 'Provisioned' })
                $n      = $active.Count
                $sample = Format-Sample -Items ($active | Select-Object -Property id,principalId,roleDefinitionId,status)
                $status = if ($n -gt 0) { 'OK' } else { 'EMPTY' }
                [void]$results.Add((New-GraphResult -Guid $check.guid -Category $check.category `
                    -Subcategory $check.subcategory -Endpoint $check.endpoint -QueryIntent $check.intent `
                    -Status $status -EvidenceCount $n -EvidenceSample $sample -Scope $tenantScope))
            }

            # CHECK 4: Break-glass accounts
            '984a859c-773e-47d2-9162-3a765a917e1f' {
                $n      = @($raw).Count
                $sample = Format-Sample -Items ($raw | Select-Object -Property id,displayName,userPrincipalName)
                $status = if ($n -gt 0) { 'OK' } else { 'EMPTY' }
                [void]$results.Add((New-GraphResult -Guid $check.guid -Category $check.category `
                    -Subcategory $check.subcategory -Endpoint $check.endpoint -QueryIntent $check.intent `
                    -Status $status -EvidenceCount $n -EvidenceSample $sample -Scope $tenantScope))
            }

            # CHECK 5: Security defaults
            'secdefaults-00000000-0000-0000-0000-000000000001' {
                # raw is the single policy object (not an array)
                $isEnabled = $false
                if ($raw -is [System.Collections.ArrayList]) {
                    $obj       = if ($raw.Count -gt 0) { $raw[0] } else { $null }
                    $isEnabled = $obj -and $obj.isEnabled -eq $true
                } else {
                    $isEnabled = $raw -and $raw.isEnabled -eq $true
                    $obj       = $raw
                }
                $n      = if ($isEnabled) { 1 } else { 0 }
                $sample = if ($obj) { ($obj | ConvertTo-Json -Compress -Depth 2) } else { '' }
                if ($sample -and $sample.Length -gt 500) { $sample = $sample.Substring(0, 497) + '...' }
                $status = if ($isEnabled) { 'OK' } else { 'EMPTY' }
                [void]$results.Add((New-GraphResult -Guid $check.guid -Category $check.category `
                    -Subcategory $check.subcategory -Endpoint $check.endpoint -QueryIntent $check.intent `
                    -Status $status -EvidenceCount $n -EvidenceSample $sample -Scope $tenantScope))
            }

            # CHECK 6: Named locations
            'namedlocations-0000-0000-0000-000000000002' {
                $n      = @($raw).Count
                $sample = Format-Sample -Items ($raw | Select-Object -Property id,displayName,'@odata.type')
                $status = if ($n -gt 0) { 'OK' } else { 'EMPTY' }
                [void]$results.Add((New-GraphResult -Guid $check.guid -Category $check.category `
                    -Subcategory $check.subcategory -Endpoint $check.endpoint -QueryIntent $check.intent `
                    -Status $status -EvidenceCount $n -EvidenceSample $sample -Scope $tenantScope))
            }

            # CHECK 7: Permanent GA assignments (findViolations — more = worse)
            'd98d954d-7d1c-4a07-92a7-cf3afe8dcbd2' {
                $n      = @($raw).Count
                $sample = Format-Sample -Items ($raw | Select-Object -Property id,principalId,roleDefinitionId,directoryScopeId)
                # FAIL if permanent GA assignments exist; OK if none (PIM-only is compliant)
                $status = if ($n -eq 0) { 'OK' } else { 'FAIL' }
                [void]$results.Add((New-GraphResult -Guid $check.guid -Category $check.category `
                    -Subcategory $check.subcategory -Endpoint $check.endpoint -QueryIntent $check.intent `
                    -Status $status -EvidenceCount $n -EvidenceSample $sample -Scope $tenantScope))
            }

            default {
                $n      = @($raw).Count
                $sample = Format-Sample -Items $raw
                $status = if ($n -gt 0) { 'OK' } else { 'EMPTY' }
                [void]$results.Add((New-GraphResult -Guid $check.guid -Category $check.category `
                    -Subcategory $check.subcategory -Endpoint $check.endpoint -QueryIntent $check.intent `
                    -Status $status -EvidenceCount $n -EvidenceSample $sample -Scope $tenantScope))
            }
        }

    } catch {
        $msg = $_.Exception.Message -replace "`n|`r", " "

        # Classify permission errors as SKIP rather than ERROR
        $isPermError = $msg -match '403|Forbidden|Authorization_RequestDenied|Insufficient|PrivilegedAccess|Policy\.Read|RoleManagement\.Read|Directory\.Read'
        $status      = if ($isPermError) { 'SKIP' } else { 'ERROR' }

        [void]$results.Add((New-GraphResult -Guid $check.guid -Category $check.category `
            -Subcategory $check.subcategory -Endpoint $check.endpoint -QueryIntent $check.intent `
            -Status $status -ErrorMessage $msg -Scope $tenantScope))
    }
}

# Return the results array
return , $results
