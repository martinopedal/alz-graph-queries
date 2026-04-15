#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
<#
.SYNOPSIS
    Pester tests for scripts/Invoke-GraphApi.ps1
.NOTES
    All external calls are mocked via Invoke-RestMethod.
    Tests run fully offline: the script is invoked with -TenantId/-ClientId/-ClientSecret
    (SPN path) so no Az module is required.
    Every script invocation happens in BeforeAll — never inside It blocks —
    to ensure Mocks are applied reliably in Pester 5.
#>

BeforeAll {
    $script:RepoRoot    = Split-Path $PSScriptRoot -Parent
    $script:ScriptPath  = Join-Path $script:RepoRoot 'scripts' 'Invoke-GraphApi.ps1'
    $script:FakeTenant  = '00000000-0000-0000-0000-000000000000'
    $script:FakeClient  = 'aaaaaaaa-0000-0000-0000-000000000000'
    $script:FakeSecret  = 'fake-secret-for-offline-tests'

}

# ---------------------------------------------------------------------------
Describe 'Invoke-GraphApi.ps1 - result contract (all empty responses)' {
    BeforeAll {
        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $Method, $Body, $Headers, $ContentType)
            if ($Uri -match '/oauth2/v2\.0/token') { return [PSCustomObject]@{ access_token = 'fake-access-token' } }
            return [PSCustomObject]@{ value = @() }
        }
        $script:contractResults = & $script:ScriptPath `
            -TenantId $script:FakeTenant -ClientId $script:FakeClient -ClientSecret $script:FakeSecret
    }

    It 'returns a non-empty collection' {
        $script:contractResults | Should -Not -BeNullOrEmpty
        @($script:contractResults).Count | Should -BeGreaterOrEqual 1
    }

    It 'every result has required unified contract fields' {
        $requiredFields = @('guid','category','subcategory','checkType',
                            'queryOrEndpoint','queryIntent','status',
                            'evidenceCount','evidenceSample','error','scope')
        foreach ($r in $script:contractResults) {
            foreach ($field in $requiredFields) {
                $r.PSObject.Properties.Name | Should -Contain $field `
                    -Because "result $($r.guid) missing '$field'"
            }
        }
    }

    It 'checkType is always Graph' {
        foreach ($r in $script:contractResults) { $r.checkType | Should -Be 'Graph' }
    }

    It 'status is one of OK/EMPTY/FAIL/ERROR/SKIP' {
        $valid = @('OK','EMPTY','FAIL','ERROR','SKIP')
        foreach ($r in $script:contractResults) {
            $valid | Should -Contain $r.status -Because "guid=$($r.guid)"
        }
    }

    It 'returns exactly 7 checks' {
        @($script:contractResults).Count | Should -Be 7
    }
}

# ---------------------------------------------------------------------------
Describe 'Invoke-GraphApi.ps1 - token failure yields SKIP' {
    BeforeAll {
        $savedWif = $env:AZURE_FEDERATED_TOKEN_FILE
        $env:AZURE_FEDERATED_TOKEN_FILE = $null
        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri)
            if ($Uri -match '/oauth2/v2\.0/token') { throw 'Connection refused' }
            return [PSCustomObject]@{ value = @() }
        }
        $script:skipResults = & $script:ScriptPath `
            -TenantId $script:FakeTenant -ClientId $script:FakeClient -ClientSecret $script:FakeSecret
        $env:AZURE_FEDERATED_TOKEN_FILE = $savedWif
    }

    It 'all 7 checks are SKIP' {
        foreach ($r in $script:skipResults) {
            $r.status | Should -Be 'SKIP' -Because "guid=$($r.guid)"
        }
    }

    It 'error field is populated for every SKIP result' {
        foreach ($r in $script:skipResults) { $r.error | Should -Not -BeNullOrEmpty }
    }
}

# ---------------------------------------------------------------------------
Describe 'Invoke-GraphApi.ps1 - CHECK1 CA policies (disabled only)' {
    BeforeAll {
        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $Method, $Body, $Headers, $ContentType)
            if ($Uri -match '/oauth2/v2\.0/token') { return [PSCustomObject]@{ access_token = 'fake-access-token' } }
            return [PSCustomObject]@{ value = @(
                [PSCustomObject]@{ id='p1'; displayName='NoOp'; state='disabled'; grantControls=$null }
            ) }
        }
        $script:ch1Disabled = (& $script:ScriptPath `
            -TenantId $script:FakeTenant -ClientId $script:FakeClient -ClientSecret $script:FakeSecret) |
            Where-Object { $_.guid -eq '53e8908a-e28c-484c-93b6-b7808b9fe5c4' }
    }
    It 'status is EMPTY when no policies are enabled' {
        $script:ch1Disabled.status | Should -Be 'EMPTY'
    }
    It 'evidenceCount is 0' {
        $script:ch1Disabled.evidenceCount | Should -Be 0
    }
}

Describe 'Invoke-GraphApi.ps1 - CHECK1 CA policies (one enabled)' {
    BeforeAll {
        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $Method, $Body, $Headers, $ContentType)
            if ($Uri -match '/oauth2/v2\.0/token') { return [PSCustomObject]@{ access_token = 'fake-access-token' } }
            return [PSCustomObject]@{ value = @(
                [PSCustomObject]@{ id='p1'; displayName='MFA Policy'; state='enabled'; grantControls=$null }
            ) }
        }
        $script:ch1Enabled = (& $script:ScriptPath `
            -TenantId $script:FakeTenant -ClientId $script:FakeClient -ClientSecret $script:FakeSecret) |
            Where-Object { $_.guid -eq '53e8908a-e28c-484c-93b6-b7808b9fe5c4' }
    }
    It 'status is OK when at least one policy is enabled' {
        $script:ch1Enabled.status | Should -Be 'OK'
    }
    It 'evidenceCount is > 0' {
        $script:ch1Enabled.evidenceCount | Should -BeGreaterThan 0
    }
}

# ---------------------------------------------------------------------------
Describe 'Invoke-GraphApi.ps1 - CHECK2 MFA CA (no MFA grant)' {
    BeforeAll {
        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $Method, $Body, $Headers, $ContentType)
            if ($Uri -match '/oauth2/v2\.0/token') { return [PSCustomObject]@{ access_token = 'fake-access-token' } }
            return [PSCustomObject]@{ value = @(
                [PSCustomObject]@{
                    id='p1'; displayName='Block Legacy'; state='enabled'
                    grantControls=[PSCustomObject]@{ builtInControls=@('block') }
                }
            ) }
        }
        $script:ch2NoMfa = (& $script:ScriptPath `
            -TenantId $script:FakeTenant -ClientId $script:FakeClient -ClientSecret $script:FakeSecret) |
            Where-Object { $_.guid -eq '1049d403-a923-4c34-94d0-0018ac6a9e01' }
    }
    It 'status is EMPTY when no CA policy has MFA grant' {
        $script:ch2NoMfa.status | Should -Be 'EMPTY'
    }
}

Describe 'Invoke-GraphApi.ps1 - CHECK2 MFA CA (MFA grant present)' {
    BeforeAll {
        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $Method, $Body, $Headers, $ContentType)
            if ($Uri -match '/oauth2/v2\.0/token') { return [PSCustomObject]@{ access_token = 'fake-access-token' } }
            return [PSCustomObject]@{ value = @(
                [PSCustomObject]@{
                    id='p2'; displayName='Require MFA'; state='enabled'
                    grantControls=[PSCustomObject]@{ builtInControls=@('mfa') }
                }
            ) }
        }
        $script:ch2Mfa = (& $script:ScriptPath `
            -TenantId $script:FakeTenant -ClientId $script:FakeClient -ClientSecret $script:FakeSecret) |
            Where-Object { $_.guid -eq '1049d403-a923-4c34-94d0-0018ac6a9e01' }
    }
    It 'status is OK when a CA policy requires MFA' {
        $script:ch2Mfa.status | Should -Be 'OK'
    }
    It 'evidenceCount is 1' {
        $script:ch2Mfa.evidenceCount | Should -Be 1
    }
}

# ---------------------------------------------------------------------------
Describe 'Invoke-GraphApi.ps1 - CHECK5 Security defaults enabled' {
    BeforeAll {
        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $Method, $Body, $Headers, $ContentType)
            if ($Uri -match '/oauth2/v2\.0/token') { return [PSCustomObject]@{ access_token = 'fake-access-token' } }
            return [PSCustomObject]@{ id='secdef'; isEnabled=$true }
        }
        $script:ch5Enabled = (& $script:ScriptPath `
            -TenantId $script:FakeTenant -ClientId $script:FakeClient -ClientSecret $script:FakeSecret) |
            Where-Object { $_.guid -eq 'secdefaults-00000000-0000-0000-0000-000000000001' }
    }
    It 'status is OK when isEnabled=true' {
        $script:ch5Enabled.status | Should -Be 'OK'
    }
    It 'evidenceCount is 1' {
        $script:ch5Enabled.evidenceCount | Should -Be 1
    }
}

Describe 'Invoke-GraphApi.ps1 - CHECK5 Security defaults disabled' {
    BeforeAll {
        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $Method, $Body, $Headers, $ContentType)
            if ($Uri -match '/oauth2/v2\.0/token') { return [PSCustomObject]@{ access_token = 'fake-access-token' } }
            return [PSCustomObject]@{ id='secdef'; isEnabled=$false }
        }
        $script:ch5Disabled = (& $script:ScriptPath `
            -TenantId $script:FakeTenant -ClientId $script:FakeClient -ClientSecret $script:FakeSecret) |
            Where-Object { $_.guid -eq 'secdefaults-00000000-0000-0000-0000-000000000001' }
    }
    It 'status is EMPTY when isEnabled=false' {
        $script:ch5Disabled.status | Should -Be 'EMPTY'
    }
    It 'evidenceCount is 0' {
        $script:ch5Disabled.evidenceCount | Should -Be 0
    }
}

# ---------------------------------------------------------------------------
Describe 'Invoke-GraphApi.ps1 - CHECK7 Permanent GA (none)' {
    BeforeAll {
        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $Method, $Body, $Headers, $ContentType)
            if ($Uri -match '/oauth2/v2\.0/token') { return [PSCustomObject]@{ access_token = 'fake-access-token' } }
            return [PSCustomObject]@{ value = @() }
        }
        $script:ch7Clean = (& $script:ScriptPath `
            -TenantId $script:FakeTenant -ClientId $script:FakeClient -ClientSecret $script:FakeSecret) |
            Where-Object { $_.guid -eq 'd98d954d-7d1c-4a07-92a7-cf3afe8dcbd2' }
    }
    It 'status is OK when no permanent GA assignments exist' {
        $script:ch7Clean.status | Should -Be 'OK'
    }
    It 'evidenceCount is 0' {
        $script:ch7Clean.evidenceCount | Should -Be 0
    }
}

Describe 'Invoke-GraphApi.ps1 - CHECK7 Permanent GA (violations found)' {
    BeforeAll {
        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $Method, $Body, $Headers, $ContentType)
            if ($Uri -match '/oauth2/v2\.0/token') { return [PSCustomObject]@{ access_token = 'fake-access-token' } }
            if ($Uri -match 'roleAssignments') {
                return [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{
                        id='ra1'; principalId='user-guid'
                        roleDefinitionId='62e90394-69f5-4237-9190-012177145e10'
                        directoryScopeId='/'
                    }
                ) }
            }
            return [PSCustomObject]@{ value = @() }
        }
        $script:ch7Violation = (& $script:ScriptPath `
            -TenantId $script:FakeTenant -ClientId $script:FakeClient -ClientSecret $script:FakeSecret) |
            Where-Object { $_.guid -eq 'd98d954d-7d1c-4a07-92a7-cf3afe8dcbd2' }
    }
    It 'status is FAIL when permanent GA assignments exist' {
        $script:ch7Violation.status | Should -Be 'FAIL'
    }
    It 'evidenceCount is 1' {
        $script:ch7Violation.evidenceCount | Should -Be 1
    }
}

# ---------------------------------------------------------------------------
Describe 'Invoke-GraphApi.ps1 - 403 Forbidden returns SKIP' {
    BeforeAll {
        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $Method, $Body, $Headers, $ContentType)
            if ($Uri -match '/oauth2/v2\.0/token') { return [PSCustomObject]@{ access_token = 'fake-access-token' } }
            throw [System.Net.WebException]::new('403 Forbidden - Authorization_RequestDenied')
        }
        $script:permResults = & $script:ScriptPath `
            -TenantId $script:FakeTenant -ClientId $script:FakeClient -ClientSecret $script:FakeSecret
    }

    It 'every result is SKIP or non-permission ERROR' {
        foreach ($r in $script:permResults) {
            $r.status | Should -BeIn @('SKIP','ERROR')
            if ($r.status -eq 'ERROR') {
                $r.error | Should -Not -Match '403|Forbidden|Authorization_RequestDenied'
            }
        }
    }
}

# ---------------------------------------------------------------------------
Describe 'Invoke-GraphApi.ps1 - endpoints and intent' {
    BeforeAll {
        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $Method, $Body, $Headers, $ContentType)
            if ($Uri -match '/oauth2/v2\.0/token') { return [PSCustomObject]@{ access_token = 'fake-access-token' } }
            return [PSCustomObject]@{ value = @() }
        }
        $script:endpointResults = & $script:ScriptPath `
            -TenantId $script:FakeTenant -ClientId $script:FakeClient -ClientSecret $script:FakeSecret
    }

    It 'queryOrEndpoint starts with https://graph.microsoft.com/ for every check' {
        foreach ($r in $script:endpointResults) {
            $r.queryOrEndpoint | Should -Match '^https://graph\.microsoft\.com/'
        }
    }

    It 'queryIntent is findEvidence or findViolations for every check' {
        foreach ($r in $script:endpointResults) {
            $r.queryIntent | Should -BeIn @('findEvidence','findViolations')
        }
    }
}

