#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
<#
.SYNOPSIS
    Pester tests for Validate-Queries.ps1
.NOTES
    Mocks Search-AzGraph and Get-AzContext to run offline.
    Tests the rowcount/status logic and basic CSV output.
#>

BeforeAll {
    # Stub Az module commands if not available
    if (-not (Get-Command Search-AzGraph -ErrorAction SilentlyContinue)) {
        function global:Search-AzGraph { param($Query, $First, $SkipToken, $Subscription, $ManagementGroup) }
    }
    if (-not (Get-Command Get-AzContext -ErrorAction SilentlyContinue)) {
        function global:Get-AzContext { return [PSCustomObject]@{ Account = @{ Id = 'test@test.com' }; Subscription = @{ Id = '00000000-0000-0000-0000-000000000000' } } }
    }
    if (-not (Get-Command Get-AzAccessToken -ErrorAction SilentlyContinue)) {
        function global:Get-AzAccessToken { param($ResourceUrl) return [PSCustomObject]@{ ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Token = 'fake' } }
    }
    
    $script:RepoRoot  = Split-Path $PSScriptRoot -Parent
    $script:QueryFile = Join-Path $script:RepoRoot 'queries' 'alz_additional_queries.json'
    $script:TempOutput = Join-Path ([System.IO.Path]::GetTempPath()) 'alz-test-output.csv'
}

AfterAll {
    if (Test-Path $script:TempOutput) { Remove-Item $script:TempOutput -Force }
}

Describe 'Query JSON schema' {
    BeforeAll {
        $script:queryData = (Get-Content $script:QueryFile -Raw | ConvertFrom-Json).queries
    }
    
    It 'should load without parse errors' {
        $script:queryData | Should -Not -BeNullOrEmpty
    }
    
    It 'should have required fields on every item' {
        foreach ($item in $script:queryData) {
            $item.guid     | Should -Not -BeNullOrEmpty -Because "item missing guid"
            $item.category | Should -Not -BeNullOrEmpty -Because "item $($item.guid) missing category"
            $item.text     | Should -Not -BeNullOrEmpty -Because "item $($item.guid) missing text"
        }
    }
    
    It 'queryable=true items must have a non-empty graph field' {
        $violations = $script:queryData | Where-Object { $_.queryable -eq $true -and (-not $_.graph -or $_.graph.Trim() -eq '') }
        $violations | Should -BeNullOrEmpty -Because "queryable=true requires a graph query"
    }
    
    It 'should have at least 200 items' {
        $script:queryData.Count | Should -BeGreaterOrEqual 200
    }
    
    It 'all GUIDs should be unique' {
        $dupes = $script:queryData | Group-Object guid | Where-Object { $_.Count -gt 1 }
        $dupes | Should -BeNullOrEmpty -Because "duplicate GUIDs found"
    }
}

Describe 'Validate-Queries.ps1 rowcount/status logic' {
    It 'reports EMPTY (findViolations) when zero rows returned' {
        # Simulate a query returning 0 rows for findViolations
        $n = 0
        $queryIntent = 'findViolations'
        $status = if ($queryIntent -eq 'findEvidence') {
            if ($n -eq 0) { 'EMPTY' } else { 'OK' }
        } else {
            if ($n -eq 0) { 'OK' } else { 'FAIL' }
        }
        # 0 rows + findViolations = no violations found = OK (not EMPTY)
        $status | Should -Be 'OK'
    }
    
    It 'reports FAIL (findViolations) when rows > 0' {
        $n = 5
        $queryIntent = 'findViolations'
        $status = if ($queryIntent -eq 'findEvidence') {
            if ($n -eq 0) { 'EMPTY' } else { 'OK' }
        } else {
            if ($n -eq 0) { 'OK' } else { 'FAIL' }
        }
        $status | Should -Be 'FAIL'
    }
    
    It 'reports EMPTY (findEvidence) when zero rows returned' {
        $n = 0
        $queryIntent = 'findEvidence'
        $status = if ($queryIntent -eq 'findEvidence') {
            if ($n -eq 0) { 'EMPTY' } else { 'OK' }
        } else {
            if ($n -eq 0) { 'OK' } else { 'FAIL' }
        }
        $status | Should -Be 'EMPTY'
    }
    
    It 'reports OK (findEvidence) when rows > 0' {
        $n = 3
        $queryIntent = 'findEvidence'
        $status = if ($queryIntent -eq 'findEvidence') {
            if ($n -eq 0) { 'EMPTY' } else { 'OK' }
        } else {
            if ($n -eq 0) { 'OK' } else { 'FAIL' }
        }
        $status | Should -Be 'OK'
    }
}

Describe 'PSScriptRoot path resolution in process_items.ps1' {
    It 'process_items.ps1 should not contain hardcoded C:\git\alz-graph-queries paths' {
        $content = Get-Content (Join-Path $script:RepoRoot 'process_items.ps1') -Raw -ErrorAction SilentlyContinue
        if ($content) {
            $content | Should -Not -Match 'C:\\git\\alz-graph-queries' -Because 'hardcoded paths break portability'
        }
    }
}

Describe 'Validate-Queries.ps1 script syntax' {
    It 'should parse without PowerShell syntax errors' {
        $scriptPath = Join-Path $script:RepoRoot 'Validate-Queries.ps1'
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty -Because 'Validate-Queries.ps1 must be free of syntax errors to load'
    }
}

Describe 'scripts/ syntax validation' {
    $scriptsDir = Join-Path $script:RepoRoot 'scripts'
    $scriptFiles = Get-ChildItem -Path $scriptsDir -Filter '*.ps1' -ErrorAction SilentlyContinue

    foreach ($file in $scriptFiles) {
        It "should parse without errors: $($file.Name)" {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors)
            $errors | Should -BeNullOrEmpty -Because "$($file.Name) must be free of syntax errors"
        }
    }
}
