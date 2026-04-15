#Requires -Version 5.1
<#
.SYNOPSIS
    DevOps governance checks for GitHub and Azure DevOps.

.DESCRIPTION
    Performs DevOps posture checks via the GitHub REST API and Azure DevOps REST API.
    Returns a unified result array compatible with the ALZ query validator contract.

    GitHub checks (requires GITHUB_TOKEN env var, -GitHubToken param, or gh CLI auth):
      - Branch protection enabled on the default branch
      - Required reviewers configured on main/default branch
      - Secret scanning enabled on the repository
      - Dependabot alerts (vulnerability alerts) enabled
      - CODEOWNERS file present (.github/CODEOWNERS, CODEOWNERS, or docs/CODEOWNERS)

    Azure DevOps checks (requires -AdoOrgUrl and -AdoPat params):
      - Branch policies configured on main
      - Pipeline approvals required (environment approvals)
      - Audit log streaming enabled at org level

.PARAMETER Platform
    Which platform to check: GitHub (default) or AzureDevOps.

.PARAMETER GitHubToken
    GitHub personal access token (repo:read scope). Falls back to GITHUB_TOKEN env var,
    then to `gh auth token` if the gh CLI is available.

.PARAMETER Owner
    GitHub repository owner (org or user). Required for GitHub checks.

.PARAMETER Repo
    GitHub repository name. Required for GitHub checks.

.PARAMETER AdoOrgUrl
    Azure DevOps organisation URL, e.g. https://dev.azure.com/myorg. Required for ADO checks.

.PARAMETER AdoPat
    Azure DevOps Personal Access Token. Required for ADO checks.

.PARAMETER AdoProject
    Azure DevOps project name. Required for ADO branch-policy and pipeline checks.

.EXAMPLE
    # GitHub checks using GITHUB_TOKEN env var
    $env:GITHUB_TOKEN = 'ghp_...'
    .\scripts\Invoke-DevOpsApi.ps1 -Owner myorg -Repo myrepo

.EXAMPLE
    # GitHub checks with explicit token
    .\scripts\Invoke-DevOpsApi.ps1 -Owner myorg -Repo myrepo -GitHubToken 'ghp_...'

.EXAMPLE
    # Azure DevOps checks
    .\scripts\Invoke-DevOpsApi.ps1 -Platform AzureDevOps `
        -AdoOrgUrl 'https://dev.azure.com/myorg' `
        -AdoPat 'xxxx' -AdoProject 'MyProject'

.NOTES
    Result contract matches Validate-Queries.ps1:
    [PSCustomObject]@{
        guid           = <string>
        category       = 'DevOps Governance'
        subcategory    = <string>
        checkType      = 'GitHub' | 'AzureDevOps'
        queryOrEndpoint = <string>    # REST endpoint called
        queryIntent    = 'findEvidence' | 'findViolations'
        status         = 'OK' | 'FAIL' | 'EMPTY' | 'SKIP' | 'ERROR'
        evidenceCount  = <int>
        evidenceSample = <string>     # JSON-truncated sample
        error          = <string>
        scope          = <string>     # e.g. "owner/repo" or "org/project"
    }
#>
[CmdletBinding()]
param(
    [ValidateSet('GitHub', 'AzureDevOps')]
    [string]$Platform = 'GitHub',

    # --- GitHub params ---
    [string]$GitHubToken,
    [string]$Owner,
    [string]$Repo,

    # --- Azure DevOps params ---
    [string]$AdoOrgUrl,
    [string]$AdoPat,
    [string]$AdoProject
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function New-CheckResult {
    param(
        [string]$Guid,
        [string]$Subcategory,
        [string]$CheckType,
        [string]$QueryOrEndpoint,
        [string]$QueryIntent,
        [string]$Status,
        [int]$EvidenceCount = 0,
        [string]$EvidenceSample = '',
        [string]$Error = '',
        [string]$Scope = ''
    )
    [PSCustomObject]@{
        guid            = $Guid
        category        = 'DevOps Governance'
        subcategory     = $Subcategory
        checkType       = $CheckType
        queryOrEndpoint = $QueryOrEndpoint
        queryIntent     = $QueryIntent
        status          = $Status
        evidenceCount   = $EvidenceCount
        evidenceSample  = $EvidenceSample
        error           = $Error
        scope           = $Scope
    }
}

function Invoke-RestSafe {
    param(
        [string]$Uri,
        [hashtable]$Headers,
        [string]$Description
    )
    try {
        $resp = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get -ErrorAction Stop
        return @{ ok = $true; data = $resp; statusCode = 200 }
    }
    catch [System.Net.WebException] {
        $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        return @{ ok = $false; data = $null; statusCode = $code; message = $_.Exception.Message }
    }
    catch {
        return @{ ok = $false; data = $null; statusCode = 0; message = $_.Exception.Message }
    }
}

function Truncate-Json {
    param([object]$Obj, [int]$MaxLen = 500)
    if ($null -eq $Obj) { return '' }
    $json = $Obj | ConvertTo-Json -Compress -Depth 4
    if ($json.Length -gt $MaxLen) { return $json.Substring(0, $MaxLen - 3) + '...' }
    return $json
}

# ---------------------------------------------------------------------------
# GitHub checks
# ---------------------------------------------------------------------------

function Invoke-GitHubChecks {
    param([string]$Token, [string]$Owner, [string]$Repo)

    $results  = [System.Collections.ArrayList]::new()
    $scope    = "$Owner/$Repo"
    $apiBase  = "https://api.github.com"
    $headers  = @{
        Authorization = "Bearer $Token"
        Accept        = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }

    # ------------------------------------------------------------------
    # Check 1 — Branch protection on default branch
    # ------------------------------------------------------------------
    $endpoint1 = "$apiBase/repos/$Owner/$Repo"
    $r1 = Invoke-RestSafe -Uri $endpoint1 -Headers $headers -Description 'Get repo'
    $defaultBranch = if ($r1.ok -and $r1.data.default_branch) { $r1.data.default_branch } else { 'main' }

    $endpoint2 = "$apiBase/repos/$Owner/$Repo/branches/$defaultBranch"
    $r2 = Invoke-RestSafe -Uri $endpoint2 -Headers $headers -Description 'Branch protection'
    if (-not $r2.ok) {
        [void]$results.Add((New-CheckResult `
            -Guid 'gh-001' `
            -Subcategory 'Branch Protection' `
            -CheckType 'GitHub' `
            -QueryOrEndpoint $endpoint2 `
            -QueryIntent 'findEvidence' `
            -Status 'ERROR' `
            -Error "HTTP $($r2.statusCode): $($r2.message)" `
            -Scope $scope))
    } else {
        $protected = $r2.data.protected -eq $true
        [void]$results.Add((New-CheckResult `
            -Guid 'gh-001' `
            -Subcategory 'Branch Protection' `
            -CheckType 'GitHub' `
            -QueryOrEndpoint $endpoint2 `
            -QueryIntent 'findEvidence' `
            -Status $(if ($protected) { 'OK' } else { 'FAIL' }) `
            -EvidenceCount $(if ($protected) { 1 } else { 0 }) `
            -EvidenceSample (Truncate-Json @{ branch = $defaultBranch; protected = $r2.data.protected }) `
            -Scope $scope))
    }

    # ------------------------------------------------------------------
    # Check 2 — Required reviewers on default branch
    # ------------------------------------------------------------------
    $endpoint3 = "$apiBase/repos/$Owner/$Repo/branches/$defaultBranch/protection/required_pull_request_reviews"
    $r3 = Invoke-RestSafe -Uri $endpoint3 -Headers $headers -Description 'Required reviewers'
    if ($r3.statusCode -eq 404) {
        # 404 means no required-review rule exists
        [void]$results.Add((New-CheckResult `
            -Guid 'gh-002' `
            -Subcategory 'Required Reviewers' `
            -CheckType 'GitHub' `
            -QueryOrEndpoint $endpoint3 `
            -QueryIntent 'findEvidence' `
            -Status 'FAIL' `
            -EvidenceSample '{"required_pull_request_reviews":null}' `
            -Scope $scope))
    } elseif (-not $r3.ok) {
        [void]$results.Add((New-CheckResult `
            -Guid 'gh-002' `
            -Subcategory 'Required Reviewers' `
            -CheckType 'GitHub' `
            -QueryOrEndpoint $endpoint3 `
            -QueryIntent 'findEvidence' `
            -Status 'ERROR' `
            -Error "HTTP $($r3.statusCode): $($r3.message)" `
            -Scope $scope))
    } else {
        $minApprovals = if ($r3.data.required_approving_review_count) { [int]$r3.data.required_approving_review_count } else { 0 }
        [void]$results.Add((New-CheckResult `
            -Guid 'gh-002' `
            -Subcategory 'Required Reviewers' `
            -CheckType 'GitHub' `
            -QueryOrEndpoint $endpoint3 `
            -QueryIntent 'findEvidence' `
            -Status $(if ($minApprovals -ge 1) { 'OK' } else { 'FAIL' }) `
            -EvidenceCount $minApprovals `
            -EvidenceSample (Truncate-Json @{ required_approving_review_count = $minApprovals }) `
            -Scope $scope))
    }

    # ------------------------------------------------------------------
    # Check 3 — Secret scanning enabled
    # ------------------------------------------------------------------
    $endpoint4 = "$apiBase/repos/$Owner/$Repo/secret-scanning/alerts?per_page=1&state=open"
    $r4 = Invoke-RestSafe -Uri $endpoint4 -Headers $headers -Description 'Secret scanning'
    if ($r4.statusCode -eq 404) {
        # 404 on secret-scanning endpoint = feature not available / not enabled
        [void]$results.Add((New-CheckResult `
            -Guid 'gh-003' `
            -Subcategory 'Secret Scanning' `
            -CheckType 'GitHub' `
            -QueryOrEndpoint $endpoint4 `
            -QueryIntent 'findEvidence' `
            -Status 'FAIL' `
            -EvidenceSample '{"secret_scanning_enabled":false}' `
            -Scope $scope))
    } elseif (-not $r4.ok) {
        [void]$results.Add((New-CheckResult `
            -Guid 'gh-003' `
            -Subcategory 'Secret Scanning' `
            -CheckType 'GitHub' `
            -QueryOrEndpoint $endpoint4 `
            -QueryIntent 'findEvidence' `
            -Status 'ERROR' `
            -Error "HTTP $($r4.statusCode): $($r4.message)" `
            -Scope $scope))
    } else {
        # Endpoint accessible => secret scanning is enabled
        [void]$results.Add((New-CheckResult `
            -Guid 'gh-003' `
            -Subcategory 'Secret Scanning' `
            -CheckType 'GitHub' `
            -QueryOrEndpoint $endpoint4 `
            -QueryIntent 'findEvidence' `
            -Status 'OK' `
            -EvidenceCount 1 `
            -EvidenceSample '{"secret_scanning_enabled":true}' `
            -Scope $scope))
    }

    # ------------------------------------------------------------------
    # Check 4 — Dependabot alerts enabled
    # ------------------------------------------------------------------
    $endpoint5 = "$apiBase/repos/$Owner/$Repo/vulnerability-alerts"
    $r5 = Invoke-RestSafe -Uri $endpoint5 -Headers $headers -Description 'Dependabot alerts'
    if ($r5.statusCode -eq 204) {
        # 204 No Content = alerts enabled
        [void]$results.Add((New-CheckResult `
            -Guid 'gh-004' `
            -Subcategory 'Dependabot Alerts' `
            -CheckType 'GitHub' `
            -QueryOrEndpoint $endpoint5 `
            -QueryIntent 'findEvidence' `
            -Status 'OK' `
            -EvidenceCount 1 `
            -EvidenceSample '{"vulnerability_alerts_enabled":true}' `
            -Scope $scope))
    } elseif ($r5.statusCode -eq 404) {
        [void]$results.Add((New-CheckResult `
            -Guid 'gh-004' `
            -Subcategory 'Dependabot Alerts' `
            -CheckType 'GitHub' `
            -QueryOrEndpoint $endpoint5 `
            -QueryIntent 'findEvidence' `
            -Status 'FAIL' `
            -EvidenceSample '{"vulnerability_alerts_enabled":false}' `
            -Scope $scope))
    } elseif ($r5.ok) {
        # Some API versions return 200 with body when enabled
        [void]$results.Add((New-CheckResult `
            -Guid 'gh-004' `
            -Subcategory 'Dependabot Alerts' `
            -CheckType 'GitHub' `
            -QueryOrEndpoint $endpoint5 `
            -QueryIntent 'findEvidence' `
            -Status 'OK' `
            -EvidenceCount 1 `
            -EvidenceSample '{"vulnerability_alerts_enabled":true}' `
            -Scope $scope))
    } else {
        [void]$results.Add((New-CheckResult `
            -Guid 'gh-004' `
            -Subcategory 'Dependabot Alerts' `
            -CheckType 'GitHub' `
            -QueryOrEndpoint $endpoint5 `
            -QueryIntent 'findEvidence' `
            -Status 'ERROR' `
            -Error "HTTP $($r5.statusCode): $($r5.message)" `
            -Scope $scope))
    }

    # ------------------------------------------------------------------
    # Check 5 — CODEOWNERS file present
    # ------------------------------------------------------------------
    $codeownersEndpoints = @(
        "$apiBase/repos/$Owner/$Repo/contents/.github/CODEOWNERS",
        "$apiBase/repos/$Owner/$Repo/contents/CODEOWNERS",
        "$apiBase/repos/$Owner/$Repo/contents/docs/CODEOWNERS"
    )
    $codeownersFound  = $false
    $codeownersPath   = ''
    foreach ($coEp in $codeownersEndpoints) {
        $rCo = Invoke-RestSafe -Uri $coEp -Headers $headers -Description 'CODEOWNERS'
        if ($rCo.ok) {
            $codeownersFound = $true
            $codeownersPath  = $coEp
            break
        }
    }
    [void]$results.Add((New-CheckResult `
        -Guid 'gh-005' `
        -Subcategory 'CODEOWNERS Present' `
        -CheckType 'GitHub' `
        -QueryOrEndpoint ($codeownersPath -or $codeownersEndpoints[0]) `
        -QueryIntent 'findEvidence' `
        -Status $(if ($codeownersFound) { 'OK' } else { 'FAIL' }) `
        -EvidenceCount $(if ($codeownersFound) { 1 } else { 0 }) `
        -EvidenceSample (Truncate-Json @{ codeowners_present = $codeownersFound; path = $codeownersPath }) `
        -Scope $scope))

    return $results
}

# ---------------------------------------------------------------------------
# Azure DevOps checks
# ---------------------------------------------------------------------------

function Invoke-AdoChecks {
    param([string]$OrgUrl, [string]$Pat, [string]$Project)

    $results = [System.Collections.ArrayList]::new()
    $orgName = ($OrgUrl.TrimEnd('/') -split '/')[-1]
    $scope   = "$orgName/$Project"
    $b64Pat  = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))
    $headers = @{
        Authorization = "Basic $b64Pat"
        'Content-Type' = 'application/json'
    }

    # ------------------------------------------------------------------
    # Check 1 — Branch policies on main
    # ------------------------------------------------------------------
    $endpoint1 = "$($OrgUrl.TrimEnd('/'))/$Project/_apis/policy/configurations?api-version=7.1"
    $r1 = Invoke-RestSafe -Uri $endpoint1 -Headers $headers -Description 'ADO branch policies'
    if (-not $r1.ok) {
        [void]$results.Add((New-CheckResult `
            -Guid 'ado-001' `
            -Subcategory 'Branch Policies' `
            -CheckType 'AzureDevOps' `
            -QueryOrEndpoint $endpoint1 `
            -QueryIntent 'findEvidence' `
            -Status 'ERROR' `
            -Error "HTTP $($r1.statusCode): $($r1.message)" `
            -Scope $scope))
    } else {
        $policies = @($r1.data.value)
        $mainPolicies = $policies | Where-Object {
            $_.settings.scope | Where-Object { $_.refName -like '*main*' -or $_.refName -like '*master*' }
        }
        $count = @($mainPolicies).Count
        [void]$results.Add((New-CheckResult `
            -Guid 'ado-001' `
            -Subcategory 'Branch Policies' `
            -CheckType 'AzureDevOps' `
            -QueryOrEndpoint $endpoint1 `
            -QueryIntent 'findEvidence' `
            -Status $(if ($count -gt 0) { 'OK' } else { 'FAIL' }) `
            -EvidenceCount $count `
            -EvidenceSample (Truncate-Json ($mainPolicies | Select-Object -First 3)) `
            -Scope $scope))
    }

    # ------------------------------------------------------------------
    # Check 2 — Pipeline environment approvals
    # ------------------------------------------------------------------
    $endpoint2 = "$($OrgUrl.TrimEnd('/'))/$Project/_apis/pipelines/approvals?api-version=7.1-preview.1"
    $r2 = Invoke-RestSafe -Uri $endpoint2 -Headers $headers -Description 'ADO pipeline approvals'

    if ($r2.statusCode -eq 404) {
        # Try environments endpoint as alternative signal
        $envEndpoint = "$($OrgUrl.TrimEnd('/'))/$Project/_apis/distributedtask/environments?api-version=7.1"
        $rEnv = Invoke-RestSafe -Uri $envEndpoint -Headers $headers -Description 'ADO environments'
        if ($rEnv.ok) {
            $envCount = if ($rEnv.data.count) { [int]$rEnv.data.count } else { @($rEnv.data.value).Count }
            [void]$results.Add((New-CheckResult `
                -Guid 'ado-002' `
                -Subcategory 'Pipeline Approvals' `
                -CheckType 'AzureDevOps' `
                -QueryOrEndpoint $envEndpoint `
                -QueryIntent 'findEvidence' `
                -Status $(if ($envCount -gt 0) { 'OK' } else { 'FAIL' }) `
                -EvidenceCount $envCount `
                -EvidenceSample (Truncate-Json @{ environments = $envCount; note = 'Environments found; check each for approval gates' }) `
                -Scope $scope))
        } else {
            [void]$results.Add((New-CheckResult `
                -Guid 'ado-002' `
                -Subcategory 'Pipeline Approvals' `
                -CheckType 'AzureDevOps' `
                -QueryOrEndpoint $endpoint2 `
                -QueryIntent 'findEvidence' `
                -Status 'ERROR' `
                -Error "HTTP $($r2.statusCode): $($r2.message)" `
                -Scope $scope))
        }
    } elseif (-not $r2.ok) {
        [void]$results.Add((New-CheckResult `
            -Guid 'ado-002' `
            -Subcategory 'Pipeline Approvals' `
            -CheckType 'AzureDevOps' `
            -QueryOrEndpoint $endpoint2 `
            -QueryIntent 'findEvidence' `
            -Status 'ERROR' `
            -Error "HTTP $($r2.statusCode): $($r2.message)" `
            -Scope $scope))
    } else {
        $approvalCount = if ($r2.data.count) { [int]$r2.data.count } else { @($r2.data.value).Count }
        [void]$results.Add((New-CheckResult `
            -Guid 'ado-002' `
            -Subcategory 'Pipeline Approvals' `
            -CheckType 'AzureDevOps' `
            -QueryOrEndpoint $endpoint2 `
            -QueryIntent 'findEvidence' `
            -Status $(if ($approvalCount -gt 0) { 'OK' } else { 'FAIL' }) `
            -EvidenceCount $approvalCount `
            -EvidenceSample (Truncate-Json ($r2.data.value | Select-Object -First 3)) `
            -Scope $scope))
    }

    # ------------------------------------------------------------------
    # Check 3 — Audit log streaming enabled at org level
    # ------------------------------------------------------------------
    $endpoint3 = "$($OrgUrl.TrimEnd('/'))/_apis/audit/streams?api-version=7.1-preview.1"
    $r3 = Invoke-RestSafe -Uri $endpoint3 -Headers $headers -Description 'ADO audit streams'
    if (-not $r3.ok) {
        [void]$results.Add((New-CheckResult `
            -Guid 'ado-003' `
            -Subcategory 'Audit Log Streaming' `
            -CheckType 'AzureDevOps' `
            -QueryOrEndpoint $endpoint3 `
            -QueryIntent 'findEvidence' `
            -Status 'ERROR' `
            -Error "HTTP $($r3.statusCode): $($r3.message)" `
            -Scope $orgName))
    } else {
        $streams = @($r3.data.value)
        $activeStreams = $streams | Where-Object { $_.status -eq 'enabled' -or $_.isEnabled -eq $true }
        $count = @($activeStreams).Count
        [void]$results.Add((New-CheckResult `
            -Guid 'ado-003' `
            -Subcategory 'Audit Log Streaming' `
            -CheckType 'AzureDevOps' `
            -QueryOrEndpoint $endpoint3 `
            -QueryIntent 'findEvidence' `
            -Status $(if ($count -gt 0) { 'OK' } else { 'FAIL' }) `
            -EvidenceCount $count `
            -EvidenceSample (Truncate-Json ($activeStreams | Select-Object -First 3)) `
            -Scope $orgName))
    }

    return $results
}

# ---------------------------------------------------------------------------
# Resolve GitHub token
# ---------------------------------------------------------------------------

function Resolve-GitHubToken {
    param([string]$ExplicitToken)

    if ($ExplicitToken) { return $ExplicitToken }

    if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN }

    # Fallback: gh CLI
    $ghCmd = Get-Command 'gh' -ErrorAction SilentlyContinue
    if ($ghCmd) {
        try {
            $ghToken = gh auth token 2>$null
            if ($ghToken) { return $ghToken.Trim() }
        } catch { }
    }

    return $null
}

# ---------------------------------------------------------------------------
# Main  (guard allows dot-sourcing in Pester tests without side effects)
# ---------------------------------------------------------------------------

# When this script is dot-sourced (e.g. by Pester), only function definitions
# are loaded.  The main execution block runs only when called as a script.
if ($MyInvocation.InvocationName -eq '.') { return }

$allResults = [System.Collections.ArrayList]::new()

if ($Platform -eq 'GitHub') {
    if (-not $Owner -or -not $Repo) {
        Write-Warning "GitHub checks require -Owner and -Repo parameters. Skipping."
        [void]$allResults.Add((New-CheckResult `
            -Guid 'gh-000' -Subcategory 'Configuration' -CheckType 'GitHub' `
            -QueryOrEndpoint 'N/A' -QueryIntent 'findEvidence' -Status 'SKIP' `
            -Error 'Missing -Owner or -Repo'))
        $allResults | Format-Table -AutoSize
        return $allResults
    }

    $token = Resolve-GitHubToken -ExplicitToken $GitHubToken
    if (-not $token) {
        Write-Warning "No GitHub token found. Set GITHUB_TOKEN env var, pass -GitHubToken, or run 'gh auth login'. Skipping."
        foreach ($guid in @('gh-001','gh-002','gh-003','gh-004','gh-005')) {
            [void]$allResults.Add((New-CheckResult `
                -Guid $guid -Subcategory 'Token Required' -CheckType 'GitHub' `
                -QueryOrEndpoint 'N/A' -QueryIntent 'findEvidence' -Status 'SKIP' `
                -Error 'No GitHub token available' -Scope "$Owner/$Repo"))
        }
    } else {
        Write-Host "Running GitHub DevOps governance checks for $Owner/$Repo..." -ForegroundColor Cyan
        $ghResults = Invoke-GitHubChecks -Token $token -Owner $Owner -Repo $Repo
        foreach ($r in $ghResults) { [void]$allResults.Add($r) }
    }
}
elseif ($Platform -eq 'AzureDevOps') {
    if (-not $AdoOrgUrl -or -not $AdoPat) {
        Write-Warning "ADO checks require -AdoOrgUrl and -AdoPat parameters. Skipping."
        foreach ($guid in @('ado-001','ado-002','ado-003')) {
            [void]$allResults.Add((New-CheckResult `
                -Guid $guid -Subcategory 'Token Required' -CheckType 'AzureDevOps' `
                -QueryOrEndpoint 'N/A' -QueryIntent 'findEvidence' -Status 'SKIP' `
                -Error 'Missing -AdoOrgUrl or -AdoPat'))
        }
    } elseif (-not $AdoProject) {
        Write-Warning "ADO project checks require -AdoProject. Skipping branch policy and pipeline checks."
        [void]$allResults.Add((New-CheckResult `
            -Guid 'ado-000' -Subcategory 'Configuration' -CheckType 'AzureDevOps' `
            -QueryOrEndpoint 'N/A' -QueryIntent 'findEvidence' -Status 'SKIP' `
            -Error 'Missing -AdoProject'))
    } else {
        Write-Host "Running Azure DevOps governance checks for $AdoOrgUrl / $AdoProject..." -ForegroundColor Cyan
        $adoResults = Invoke-AdoChecks -OrgUrl $AdoOrgUrl -Pat $AdoPat -Project $AdoProject
        foreach ($r in $adoResults) { [void]$allResults.Add($r) }
    }
}

# --- Print summary table ---
Write-Host ""
Write-Host "=== DevOps Governance Check Results ===" -ForegroundColor Cyan
$allResults | Format-Table guid, subcategory, checkType, status, evidenceCount, scope -AutoSize

$ok   = @($allResults | Where-Object { $_.status -eq 'OK'   }).Count
$fail = @($allResults | Where-Object { $_.status -eq 'FAIL'  }).Count
$skip = @($allResults | Where-Object { $_.status -eq 'SKIP'  }).Count
$err  = @($allResults | Where-Object { $_.status -eq 'ERROR' }).Count

Write-Host "Summary: OK=$ok  FAIL=$fail  SKIP=$skip  ERROR=$err" -ForegroundColor $(if ($fail -gt 0 -or $err -gt 0) { 'Yellow' } else { 'Green' })

return $allResults
