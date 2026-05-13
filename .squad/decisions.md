# Squad Decisions

## Workflow SHA-Pinning Audit and Remediation

**Date:** 2026-05-13  
**Author:** Forge  
**Status:** Implemented in PR #55

### Context

During Dependabot PR review (#46-50), discovered inconsistent SHA-pinning across workflows:

**Policy (from `.github/copilot-instructions.md`):**
> All GitHub Actions `uses:` MUST be pinned to a commit SHA, not a tag

**Current State:**
- ✅ `validate-example.yml` - Mixed: checkout@SHA, but azure/powershell@v2 (bare tag)
- ✅ `auto-label-issues.yml` - SHA-pinned (github-script)
- ✅ `ci-failure-analysis.yml` - SHA-pinned (github-script)
- ⚠️ `squad-*.yml` (11 files) - Mix of `@v4`, `@v6`, `@v7` bare tags

**Impact:**
- PR #47 (azure/powershell v2→v3) blocked - cannot merge until SHA-pinning fixed
- Validate-example workflow failing on main due to bare tag policy violation

### Decision

Audit all workflows and pin all `uses:` to commit SHAs. Immediate upgrade of azure/powershell to v3 to unblock Dependabot PR #47.

### Implementation

**SHA mappings applied:**
- `actions/checkout@v6.0.2` → `de0fac2e4500dabe0009e67214ff5f5447ce83dd`
- `actions/upload-artifact@v4.6.2` → `ea165f8d65b6e75b540449e92b4886f43607fa02`
- `actions/github-script@v9.0.0` → `3a2844b7e9c422d3c10d287c895573f7108da1b3`
- `azure/powershell@v3.0.0` → `f5b8adcfff1904872c7b98d4012d4914d74b1a82`

**Files updated:** 13 workflows (validate-example.yml, all squad-*.yml, ci-failure-analysis.yml, auto-label-issues.yml)

## CI Failure Analysis: Handle Cancelled Jobs

**Date:** May 13, 2026  
**Author:** Lead  
**Status:** Implemented in PR #55

### Problem

The CI Failure Analysis workflow (`.github/workflows/ci-failure-analysis.yml`, line 33) filtered failed jobs only by `conclusion === 'failure'`. When jobs had `conclusion === 'cancelled'`, they were excluded from the failure report, resulting in issues filed with "Failed jobs: none" — noisy and misleading.

**Evidence:** Issues #51 and #52 both reported "Failed jobs: none" but the jobs were actually cancelled due to timeout/rate limit on May 5-6.

### Decision

Extended filter to `j.conclusion === 'failure' || j.conclusion === 'cancelled'`. Cancelled jobs are real CI failures (they blocked forward progress), even if the root cause differs.

### Implementation

Changed line 36-37 in `ci-failure-analysis.yml` from:
```javascript
const failedJobs = jobsResp.data.jobs.filter(
  j => j.conclusion === 'failure'
);
```
to:
```javascript
const failedJobs = jobsResp.data.jobs.filter(
  j => j.conclusion === 'failure' || j.conclusion === 'cancelled'
);
```

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
