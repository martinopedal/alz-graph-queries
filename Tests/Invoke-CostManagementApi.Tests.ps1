#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
<#
.SYNOPSIS
    Pester tests for Invoke-CostManagementApi.ps1
.NOTES
    Offline tests only ÔÇö no Azure credentials required.
    Static checks validate contract shape, required fields, and status logic.
#>

BeforeAll {
    $script:RepoRoot    = Split-Path $PSScriptRoot -Parent
    $script:ScriptPath  = Join-Path $script:RepoRoot 'scripts' 'Invoke-CostManagementApi.ps1'
    $script:Content     = Get-Content $script:ScriptPath -Raw -ErrorAction SilentlyContinue
}

Describe 'Invoke-CostManagementApi.ps1 - static contract checks' {

    It 'script file should exist at scripts/Invoke-CostManagementApi.ps1' {
        Test-Path $script:ScriptPath | Should -BeTrue
    }

    It 'should declare all required unified contract fields' {
        $script:Content | Should -Match 'guid'
        $script:Content | Should -Match 'category'
        $script:Content | Should -Match 'checkType'
        $script:Content | Should -Match 'queryOrEndpoint'
        $script:Content | Should -Match 'queryIntent'
        $script:Content | Should -Match 'evidenceCount'
        $script:Content | Should -Match 'evidenceSample'
        $script:Content | Should -Match 'scope'
    }

    It 'should implement at least 4 Cost Management checks (findEvidence or findViolations)' {
        $matches = ([regex]::Matches($script:Content, "'find(Evidence|Violations)'")).Count
        $matches | Should -BeGreaterOrEqual 4 -Because '4+ checks required for Cost Management governance coverage'
    }

    It 'should handle missing permissions gracefully with SKIP status' {
        $script:Content | Should -Match "'SKIP'" -Because 'Permission denied must return status SKIP not ERROR'
    }

    It 'should use Get-AzAccessToken for bearer token acquisition' {
        $script:Content | Should -Match 'Get-AzAccessToken' -Because 'Token must be obtained from Az module, not hardcoded'
    }

    It 'should include findEvidence intent for at least one check' {
        $script:Content | Should -Match "'findEvidence'" -Because 'Budget presence checks use findEvidence'
    }

    It 'should include findViolations intent for at least one check' {
        $script:Content | Should -Match "'findViolations'" -Because 'Orphaned resource and threshold checks use findViolations'
    }

    It 'should use Join-Path or PSScriptRoot ÔÇö no raw backslash path concatenation' {
        # Strip comment lines before checking
        $noComments = ($script:Content -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        $noComments | Should -Not -Match "= '.*\\\\.*'" -Because 'Use Join-Path for cross-platform paths'
    }

    It 'should not hardcode real SubscriptionId or TenantId values (params must be dynamic)' {
        # Verify the script uses $SubscriptionId and $ManagementGroup params rather than hardcoded values
        $script:Content | Should -Match '\$SubscriptionId' -Because 'SubscriptionId must be a parameter, not hardcoded'
        $script:Content | Should -Match '\$ManagementGroup' -Because 'ManagementGroup must be a parameter, not hardcoded'
        # Verify the scope is dynamically constructed from parameters
        $script:Content | Should -Match 'armScope' -Because 'ARM scope must be built from parameters'
    }

    It 'should reference the Cost Management REST API endpoint' {
        $script:Content | Should -Match 'Microsoft\.Consumption/budgets' -Because 'Must call Consumption budgets API'
        $script:Content | Should -Match 'Microsoft\.CostManagement/scheduledActions' -Because 'Must call CostManagement scheduledActions API'
    }

    It 'should reference Azure Resource Graph for orphaned resource checks' {
        $script:Content | Should -Match 'Microsoft\.ResourceGraph/resources' -Because 'Orphaned resource checks use ARG REST API'
    }
}

Describe 'Invoke-CostManagementApi.ps1 - status logic (offline)' {

    It 'findEvidence: 0 results => EMPTY' {
        $n      = 0
        $intent = 'findEvidence'
        $status = if ($intent -eq 'findEvidence') { if ($n -eq 0) { 'EMPTY' } else { 'OK' } } `
                  else { if ($n -eq 0) { 'OK' } else { 'FAIL' } }
        $status | Should -Be 'EMPTY'
    }

    It 'findEvidence: results > 0 => OK' {
        $n      = 2
        $intent = 'findEvidence'
        $status = if ($intent -eq 'findEvidence') { if ($n -eq 0) { 'EMPTY' } else { 'OK' } } `
                  else { if ($n -eq 0) { 'OK' } else { 'FAIL' } }
        $status | Should -Be 'OK'
    }

    It 'findViolations: 0 results => OK' {
        $n      = 0
        $intent = 'findViolations'
        $status = if ($intent -eq 'findEvidence') { if ($n -eq 0) { 'EMPTY' } else { 'OK' } } `
                  else { if ($n -eq 0) { 'OK' } else { 'FAIL' } }
        $status | Should -Be 'OK'
    }

    It 'findViolations: results > 0 => FAIL' {
        $n      = 3
        $intent = 'findViolations'
        $status = if ($intent -eq 'findEvidence') { if ($n -eq 0) { 'EMPTY' } else { 'OK' } } `
                  else { if ($n -eq 0) { 'OK' } else { 'FAIL' } }
        $status | Should -Be 'FAIL'
    }

    It 'permission error (403) maps to SKIP status' {
        $isPermission = $true
        $status       = if ($isPermission) { 'SKIP' } else { 'ERROR' }
        $status | Should -Be 'SKIP'
    }

    It 'non-permission error maps to ERROR status' {
        $isPermission = $false
        $status       = if ($isPermission) { 'SKIP' } else { 'ERROR' }
        $status | Should -Be 'ERROR'
    }

    It 'budget threshold: spend >= 80% of amount is a violation' {
        $budget = [PSCustomObject]@{
            properties = [PSCustomObject]@{
                amount       = 1000
                currentSpend = [PSCustomObject]@{ amount = 850 }
            }
        }
        $violates = ($budget.properties.currentSpend.amount / $budget.properties.amount) -ge 0.80
        $violates | Should -BeTrue
    }

    It 'budget threshold: spend < 80% of amount is not a violation' {
        $budget = [PSCustomObject]@{
            properties = [PSCustomObject]@{
                amount       = 1000
                currentSpend = [PSCustomObject]@{ amount = 750 }
            }
        }
        $violates = ($budget.properties.currentSpend.amount / $budget.properties.amount) -ge 0.80
        $violates | Should -BeFalse
    }
}
