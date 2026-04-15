#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
<#
.SYNOPSIS
    Pester tests for Invoke-DevOpsApi.ps1
.DESCRIPTION
    Uses mocked Invoke-RestMethod responses to validate all check logic offline.
    No real GitHub token or ADO PAT required.
#>

# File-scope variables — available in all Pester blocks without $script: prefix trick
$RepoRoot   = Split-Path $PSScriptRoot -Parent
$ScriptPath = Join-Path $RepoRoot 'scripts' 'Invoke-DevOpsApi.ps1'

BeforeAll {
    $script:RepoRoot   = Split-Path $PSScriptRoot -Parent
    $script:ScriptPath = Join-Path $script:RepoRoot 'scripts' 'Invoke-DevOpsApi.ps1'

    # Dot-source the script — the guard `if ($MyInvocation.InvocationName -eq '.')`
    # prevents the main execution block from running.
    . $script:ScriptPath
}

# ---------------------------------------------------------------------------
Describe 'Invoke-DevOpsApi.ps1 — contract shape' {

    It 'script file exists at expected path' {
        $script:ScriptPath | Should -Exist
    }

    It 'script requires PowerShell 5.1 or higher' {
        $content = Get-Content $script:ScriptPath -Raw
        $content | Should -Match '#Requires -Version 5\.1'
    }

    It 'script declares -Platform parameter' {
        $content = Get-Content $script:ScriptPath -Raw
        $content | Should -Match '\[ValidateSet\(.*GitHub.*AzureDevOps'
    }

    It 'script declares GitHub token parameter' {
        $content = Get-Content $script:ScriptPath -Raw
        $content | Should -Match 'GitHubToken'
    }

    It 'script declares ADO org URL parameter' {
        $content = Get-Content $script:ScriptPath -Raw
        $content | Should -Match 'AdoOrgUrl'
    }

    It 'result contract contains all required fields' {
        $content = Get-Content $script:ScriptPath -Raw
        $content | Should -Match "category\s*=\s*'DevOps Governance'"
        $content | Should -Match 'checkType'
        $content | Should -Match 'queryOrEndpoint'
        $content | Should -Match 'queryIntent'
        $content | Should -Match 'evidenceCount'
        $content | Should -Match 'evidenceSample'
    }

    It 'SKIP result emitted when no token provided' {
        $content = Get-Content $script:ScriptPath -Raw
        $content | Should -Match "-Status\s+'SKIP'"
    }
}

# ---------------------------------------------------------------------------
Describe 'New-CheckResult helper' {

    It 'creates object with correct category' {
        $r = New-CheckResult -Guid 'test-001' -Subcategory 'Test' -CheckType 'GitHub' `
            -QueryOrEndpoint 'https://api.example.com' -QueryIntent 'findEvidence' -Status 'OK'
        $r.category | Should -Be 'DevOps Governance'
    }

    It 'defaults evidenceCount to 0' {
        $r = New-CheckResult -Guid 'test-002' -Subcategory 'Test' -CheckType 'GitHub' `
            -QueryOrEndpoint 'https://api.example.com' -QueryIntent 'findEvidence' -Status 'FAIL'
        $r.evidenceCount | Should -Be 0
    }

    It 'sets all mandatory fields' {
        $r = New-CheckResult -Guid 'test-003' -Subcategory 'Sub' -CheckType 'AzureDevOps' `
            -QueryOrEndpoint 'https://dev.azure.com/org' -QueryIntent 'findViolations' `
            -Status 'OK' -EvidenceCount 3 -EvidenceSample '{"x":1}' -Error '' -Scope 'org/proj'
        $r.guid            | Should -Be 'test-003'
        $r.subcategory     | Should -Be 'Sub'
        $r.checkType       | Should -Be 'AzureDevOps'
        $r.queryIntent     | Should -Be 'findViolations'
        $r.status          | Should -Be 'OK'
        $r.evidenceCount   | Should -Be 3
        $r.evidenceSample  | Should -Be '{"x":1}'
        $r.scope           | Should -Be 'org/proj'
    }

    It 'status values follow expected enum' {
        foreach ($s in @('OK','FAIL','EMPTY','SKIP','ERROR')) {
            $r = New-CheckResult -Guid 'x' -Subcategory '' -CheckType 'GitHub' `
                -QueryOrEndpoint '' -QueryIntent 'findEvidence' -Status $s
            $r.status | Should -Be $s
        }
    }
}

# ---------------------------------------------------------------------------
Describe 'Truncate-Json helper' {

    It 'returns empty string for null input' {
        Truncate-Json -Obj $null | Should -Be ''
    }

    It 'returns JSON unchanged when under MaxLen' {
        $result = Truncate-Json -Obj @{ a = 1 } -MaxLen 500
        $result | Should -Match '"a"'
        $result.Length | Should -BeLessOrEqual 500
    }

    It 'truncates and appends ellipsis when over MaxLen' {
        $large = @{ data = ('x' * 600) }
        $result = Truncate-Json -Obj $large -MaxLen 100
        $result.Length | Should -Be 100
        $result | Should -Match '\.\.\.$'
    }
}

# ---------------------------------------------------------------------------
Describe 'Invoke-RestSafe helper' {

    It 'returns ok=true and data on success' {
        Mock Invoke-RestMethod { return @{ name = 'main'; protected = $true } }
        $r = Invoke-RestSafe -Uri 'https://api.github.com/repos/o/r/branches/main' -Headers @{} -Description 'test'
        $r.ok   | Should -Be $true
        $r.data | Should -Not -BeNullOrEmpty
    }

    It 'returns ok=false on WebException' {
        Mock Invoke-RestMethod { throw [System.Net.WebException]::new('Not Found') }
        $r = Invoke-RestSafe -Uri 'https://api.github.com/no-such' -Headers @{} -Description 'test'
        $r.ok      | Should -Be $false
        $r.message | Should -Not -BeNullOrEmpty
    }

    It 'returns ok=false on generic exception' {
        Mock Invoke-RestMethod { throw 'network error' }
        $r = Invoke-RestSafe -Uri 'https://api.github.com/no-such' -Headers @{} -Description 'test'
        $r.ok | Should -Be $false
    }
}

# ---------------------------------------------------------------------------
Describe 'Resolve-GitHubToken' {

    It 'returns explicit token when provided' {
        $t = Resolve-GitHubToken -ExplicitToken 'mytoken123'
        $t | Should -Be 'mytoken123'
    }

    It 'falls back to GITHUB_TOKEN env var' {
        $old = $env:GITHUB_TOKEN
        $env:GITHUB_TOKEN = 'envtoken456'
        $t = Resolve-GitHubToken -ExplicitToken ''
        $env:GITHUB_TOKEN = $old
        $t | Should -Be 'envtoken456'
    }

    It 'returns null when no token available and gh not installed' {
        $old = $env:GITHUB_TOKEN
        Remove-Item Env:\GITHUB_TOKEN -ErrorAction SilentlyContinue
        Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'gh' }
        $t = Resolve-GitHubToken -ExplicitToken ''
        $env:GITHUB_TOKEN = $old
        $t | Should -BeNullOrEmpty
    }
}

# ---------------------------------------------------------------------------
Describe 'Invoke-GitHubChecks — branch protection logic' {

    It 'returns FAIL for gh-001 when branch.protected is false' {
        Mock Invoke-RestSafe {
            param($Uri)
            if ($Uri -like '*/repos/o/r') {
                return @{ ok = $true; data = [PSCustomObject]@{ default_branch = 'main' }; statusCode = 200 }
            }
            if ($Uri -like '*/branches/main' -and $Uri -notlike '*/protection*') {
                return @{ ok = $true; data = [PSCustomObject]@{ protected = $false }; statusCode = 200 }
            }
            # Return FAIL (404) for protection endpoints
            return @{ ok = $false; data = $null; statusCode = 404; message = 'Not Found' }
        }
        $results = Invoke-GitHubChecks -Token 'fake' -Owner 'o' -Repo 'r'
        $bp = $results | Where-Object { $_.guid -eq 'gh-001' }
        $bp.status | Should -Be 'FAIL'
    }

    It 'returns OK for gh-001 when branch.protected is true' {
        Mock Invoke-RestSafe {
            param($Uri)
            if ($Uri -like '*/repos/o/r') {
                return @{ ok = $true; data = [PSCustomObject]@{ default_branch = 'main' }; statusCode = 200 }
            }
            if ($Uri -like '*/branches/main' -and $Uri -notlike '*/protection*') {
                return @{ ok = $true; data = [PSCustomObject]@{ protected = $true }; statusCode = 200 }
            }
            return @{ ok = $false; data = $null; statusCode = 404; message = 'Not Found' }
        }
        $results = Invoke-GitHubChecks -Token 'fake' -Owner 'o' -Repo 'r'
        $bp = $results | Where-Object { $_.guid -eq 'gh-001' }
        $bp.status | Should -Be 'OK'
    }

    It 'returns FAIL for gh-002 when no required reviewers (404)' {
        Mock Invoke-RestSafe {
            param($Uri)
            if ($Uri -like '*/repos/o/r') {
                return @{ ok = $true; data = [PSCustomObject]@{ default_branch = 'main' }; statusCode = 200 }
            }
            return @{ ok = $false; data = $null; statusCode = 404; message = 'Not Found' }
        }
        $results = Invoke-GitHubChecks -Token 'fake' -Owner 'o' -Repo 'r'
        $rr = $results | Where-Object { $_.guid -eq 'gh-002' }
        $rr.status | Should -Be 'FAIL'
    }

    It 'returns OK for gh-002 when required_approving_review_count >= 1' {
        Mock Invoke-RestSafe {
            param($Uri)
            if ($Uri -like '*/repos/o/r') {
                return @{ ok = $true; data = [PSCustomObject]@{ default_branch = 'main' }; statusCode = 200 }
            }
            if ($Uri -like '*/required_pull_request_reviews') {
                return @{ ok = $true; data = [PSCustomObject]@{ required_approving_review_count = 2 }; statusCode = 200 }
            }
            return @{ ok = $false; data = $null; statusCode = 404; message = 'Not Found' }
        }
        $results = Invoke-GitHubChecks -Token 'fake' -Owner 'o' -Repo 'r'
        $rr = $results | Where-Object { $_.guid -eq 'gh-002' }
        $rr.status | Should -Be 'OK'
        $rr.evidenceCount | Should -Be 2
    }

    It 'returns FAIL for gh-003 when secret scanning returns 404' {
        Mock Invoke-RestSafe {
            param($Uri)
            if ($Uri -like '*/repos/o/r') {
                return @{ ok = $true; data = [PSCustomObject]@{ default_branch = 'main' }; statusCode = 200 }
            }
            return @{ ok = $false; data = $null; statusCode = 404; message = 'Not Found' }
        }
        $results = Invoke-GitHubChecks -Token 'fake' -Owner 'o' -Repo 'r'
        $ss = $results | Where-Object { $_.guid -eq 'gh-003' }
        $ss.status | Should -Be 'FAIL'
    }

    It 'returns OK for gh-003 when secret-scanning endpoint is accessible' {
        Mock Invoke-RestSafe {
            param($Uri)
            if ($Uri -like '*/repos/o/r') {
                return @{ ok = $true; data = [PSCustomObject]@{ default_branch = 'main' }; statusCode = 200 }
            }
            if ($Uri -like '*/secret-scanning/alerts*') {
                return @{ ok = $true; data = @(); statusCode = 200 }
            }
            return @{ ok = $false; data = $null; statusCode = 404; message = 'Not Found' }
        }
        $results = Invoke-GitHubChecks -Token 'fake' -Owner 'o' -Repo 'r'
        $ss = $results | Where-Object { $_.guid -eq 'gh-003' }
        $ss.status | Should -Be 'OK'
    }

    It 'returns OK for gh-004 when vulnerability-alerts returns 204' {
        Mock Invoke-RestSafe {
            param($Uri)
            if ($Uri -like '*/repos/o/r') {
                return @{ ok = $true; data = [PSCustomObject]@{ default_branch = 'main' }; statusCode = 200 }
            }
            if ($Uri -like '*/vulnerability-alerts') {
                return @{ ok = $false; data = $null; statusCode = 204; message = '' }
            }
            return @{ ok = $false; data = $null; statusCode = 404; message = 'Not Found' }
        }
        $results = Invoke-GitHubChecks -Token 'fake' -Owner 'o' -Repo 'r'
        $da = $results | Where-Object { $_.guid -eq 'gh-004' }
        $da.status | Should -Be 'OK'
    }

    It 'returns FAIL for gh-004 when vulnerability-alerts returns 404' {
        Mock Invoke-RestSafe {
            param($Uri)
            if ($Uri -like '*/repos/o/r') {
                return @{ ok = $true; data = [PSCustomObject]@{ default_branch = 'main' }; statusCode = 200 }
            }
            return @{ ok = $false; data = $null; statusCode = 404; message = 'Not Found' }
        }
        $results = Invoke-GitHubChecks -Token 'fake' -Owner 'o' -Repo 'r'
        $da = $results | Where-Object { $_.guid -eq 'gh-004' }
        $da.status | Should -Be 'FAIL'
    }

    It 'returns OK for gh-005 when CODEOWNERS found in .github/' {
        Mock Invoke-RestSafe {
            param($Uri)
            if ($Uri -like '*/repos/o/r') {
                return @{ ok = $true; data = [PSCustomObject]@{ default_branch = 'main' }; statusCode = 200 }
            }
            if ($Uri -like '*/.github/CODEOWNERS') {
                return @{ ok = $true; data = [PSCustomObject]@{ name = 'CODEOWNERS' }; statusCode = 200 }
            }
            return @{ ok = $false; data = $null; statusCode = 404; message = 'Not Found' }
        }
        $results = Invoke-GitHubChecks -Token 'fake' -Owner 'o' -Repo 'r'
        $co = $results | Where-Object { $_.guid -eq 'gh-005' }
        $co.status | Should -Be 'OK'
        $co.evidenceCount | Should -Be 1
    }

    It 'returns FAIL for gh-005 when no CODEOWNERS found' {
        Mock Invoke-RestSafe {
            param($Uri)
            if ($Uri -like '*/repos/o/r') {
                return @{ ok = $true; data = [PSCustomObject]@{ default_branch = 'main' }; statusCode = 200 }
            }
            return @{ ok = $false; data = $null; statusCode = 404; message = 'Not Found' }
        }
        $results = Invoke-GitHubChecks -Token 'fake' -Owner 'o' -Repo 'r'
        $co = $results | Where-Object { $_.guid -eq 'gh-005' }
        $co.status | Should -Be 'FAIL'
        $co.evidenceCount | Should -Be 0
    }

    It 'returns exactly 5 results for a full GitHub run' {
        Mock Invoke-RestSafe {
            param($Uri)
            if ($Uri -like '*/repos/o/r') {
                return @{ ok = $true; data = [PSCustomObject]@{ default_branch = 'main' }; statusCode = 200 }
            }
            return @{ ok = $false; data = $null; statusCode = 404; message = 'Not Found' }
        }
        $results = Invoke-GitHubChecks -Token 'fake' -Owner 'o' -Repo 'r'
        @($results).Count | Should -Be 5
    }

    It 'all results have checkType = GitHub' {
        Mock Invoke-RestSafe {
            param($Uri)
            if ($Uri -like '*/repos/o/r') {
                return @{ ok = $true; data = [PSCustomObject]@{ default_branch = 'main' }; statusCode = 200 }
            }
            return @{ ok = $false; data = $null; statusCode = 404; message = 'Not Found' }
        }
        $results = Invoke-GitHubChecks -Token 'fake' -Owner 'o' -Repo 'r'
        $results | ForEach-Object { $_.checkType | Should -Be 'GitHub' }
    }

    It 'all results have category = DevOps Governance' {
        Mock Invoke-RestSafe {
            param($Uri)
            if ($Uri -like '*/repos/o/r') {
                return @{ ok = $true; data = [PSCustomObject]@{ default_branch = 'main' }; statusCode = 200 }
            }
            return @{ ok = $false; data = $null; statusCode = 404; message = 'Not Found' }
        }
        $results = Invoke-GitHubChecks -Token 'fake' -Owner 'o' -Repo 'r'
        $results | ForEach-Object { $_.category | Should -Be 'DevOps Governance' }
    }
}

# ---------------------------------------------------------------------------
Describe 'Invoke-AdoChecks — ADO governance logic' {

    It 'returns exactly 3 results for a full ADO run' {
        Mock Invoke-RestSafe {
            return @{ ok = $true; data = [PSCustomObject]@{ value = @(); count = 0 }; statusCode = 200 }
        }
        $results = Invoke-AdoChecks -OrgUrl 'https://dev.azure.com/myorg' -Pat 'fakepat' -Project 'myproj'
        @($results).Count | Should -Be 3
    }

    It 'all results have checkType = AzureDevOps' {
        Mock Invoke-RestSafe {
            return @{ ok = $true; data = [PSCustomObject]@{ value = @(); count = 0 }; statusCode = 200 }
        }
        $results = Invoke-AdoChecks -OrgUrl 'https://dev.azure.com/myorg' -Pat 'fakepat' -Project 'myproj'
        $results | ForEach-Object { $_.checkType | Should -Be 'AzureDevOps' }
    }

    It 'returns FAIL for ado-001 when no main branch policies found' {
        Mock Invoke-RestSafe {
            param($Uri)
            if ($Uri -like '*/policy/configurations*') {
                return @{
                    ok = $true
                    data = [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{ settings = [PSCustomObject]@{ scope = @([PSCustomObject]@{ refName = 'refs/heads/develop' }) } }
                        )
                    }
                    statusCode = 200
                }
            }
            return @{ ok = $true; data = [PSCustomObject]@{ value = @(); count = 0 }; statusCode = 200 }
        }
        $results = Invoke-AdoChecks -OrgUrl 'https://dev.azure.com/myorg' -Pat 'fakepat' -Project 'myproj'
        $bp = $results | Where-Object { $_.guid -eq 'ado-001' }
        $bp.status | Should -Be 'FAIL'
    }

    It 'returns OK for ado-001 when main branch policies found' {
        Mock Invoke-RestSafe {
            param($Uri)
            if ($Uri -like '*/policy/configurations*') {
                return @{
                    ok = $true
                    data = [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{ settings = [PSCustomObject]@{ scope = @([PSCustomObject]@{ refName = 'refs/heads/main' }) } }
                        )
                    }
                    statusCode = 200
                }
            }
            return @{ ok = $true; data = [PSCustomObject]@{ value = @(); count = 0 }; statusCode = 200 }
        }
        $results = Invoke-AdoChecks -OrgUrl 'https://dev.azure.com/myorg' -Pat 'fakepat' -Project 'myproj'
        $bp = $results | Where-Object { $_.guid -eq 'ado-001' }
        $bp.status | Should -Be 'OK'
        $bp.evidenceCount | Should -BeGreaterOrEqual 1
    }

    It 'returns OK for ado-003 when active audit streams exist' {
        Mock Invoke-RestSafe {
            param($Uri)
            if ($Uri -like '*/audit/streams*') {
                return @{
                    ok = $true
                    data = [PSCustomObject]@{
                        value = @([PSCustomObject]@{ status = 'enabled'; displayName = 'Event Grid' })
                    }
                    statusCode = 200
                }
            }
            return @{ ok = $true; data = [PSCustomObject]@{ value = @(); count = 0 }; statusCode = 200 }
        }
        $results = Invoke-AdoChecks -OrgUrl 'https://dev.azure.com/myorg' -Pat 'fakepat' -Project 'myproj'
        $al = $results | Where-Object { $_.guid -eq 'ado-003' }
        $al.status | Should -Be 'OK'
        $al.evidenceCount | Should -BeGreaterOrEqual 1
    }

    It 'returns FAIL for ado-003 when no active audit streams' {
        Mock Invoke-RestSafe {
            param($Uri)
            if ($Uri -like '*/audit/streams*') {
                return @{
                    ok = $true
                    data = [PSCustomObject]@{ value = @() }
                    statusCode = 200
                }
            }
            return @{ ok = $true; data = [PSCustomObject]@{ value = @(); count = 0 }; statusCode = 200 }
        }
        $results = Invoke-AdoChecks -OrgUrl 'https://dev.azure.com/myorg' -Pat 'fakepat' -Project 'myproj'
        $al = $results | Where-Object { $_.guid -eq 'ado-003' }
        $al.status | Should -Be 'FAIL'
    }

    It 'returns ERROR for ado-001 on HTTP failure' {
        Mock Invoke-RestSafe {
            param($Uri)
            if ($Uri -like '*/policy/configurations*') {
                return @{ ok = $false; data = $null; statusCode = 401; message = 'Unauthorized' }
            }
            return @{ ok = $true; data = [PSCustomObject]@{ value = @(); count = 0 }; statusCode = 200 }
        }
        $results = Invoke-AdoChecks -OrgUrl 'https://dev.azure.com/myorg' -Pat 'fakepat' -Project 'myproj'
        $bp = $results | Where-Object { $_.guid -eq 'ado-001' }
        $bp.status | Should -Be 'ERROR'
        $bp.error  | Should -Match '401'
    }
}

# ---------------------------------------------------------------------------
Describe 'Script SKIP behaviour (no credentials)' {

    It 'runs without error when called with -Platform GitHub and missing -Owner/-Repo' {
        # Pipe to null to suppress table output; check no exceptions thrown
        { & $script:ScriptPath -Platform GitHub -ErrorAction SilentlyContinue 2>$null } | Should -Not -Throw
    }

    It 'runs without error when called with -Platform AzureDevOps and missing params' {
        { & $script:ScriptPath -Platform AzureDevOps -ErrorAction SilentlyContinue 2>$null } | Should -Not -Throw
    }
}
