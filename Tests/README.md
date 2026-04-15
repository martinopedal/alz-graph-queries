# Tests

Pester 5 test suite for alz-graph-queries.

## Running locally

```powershell
# Install Pester 5 if needed
Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force

# Run all tests
Invoke-Pester -Path ./Tests/ -Output Detailed
```

## What's tested

- `Validate-Queries.Tests.ps1` — JSON schema validation, rowcount/status logic (queryIntent semantics)
- `process_items.Tests.ps1` — path resolution (no hardcoded paths)
