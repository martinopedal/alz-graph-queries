# Skill: Dependabot PR Review & Merge

**Owner:** Forge  
**Created:** 2026-05-13

## Purpose

Systematic review and merge process for Dependabot dependency update PRs, ensuring security policy compliance and breaking change detection.

## Checklist

### 1. Pull PR Diff
```bash
gh pr diff {N}
```

**Verify:**
- If repo policy requires SHA-pinning: confirm diff shows SHA changes, not bare tag bumps
- Identify all affected workflows

### 2. Breaking Change Analysis

**actions/checkout v4→v6:**
- Node.js 24 runtime (verify runner compatibility - most GitHub-hosted runners support it)
- Credential persistence moved to `$RUNNER_TEMP` (requires Actions Runner v2.329.0+)

**actions/github-script v7→v9:**
- BREAKING: `require('@actions/github')` no longer works (ESM-only package)
- Check all workflows: `grep -r "require('@actions/github')" .github/workflows/`
- Alternative: use injected `getOctokit` function in script context

**actions/upload-artifact v4→v7:**
- Node.js 24 support added
- ESM migration (v7)
- Direct file uploads via `archive: false` (single files only)

**azure/login v2→v3:**
- Node.js 24 upgrade
- OIDC/WIF authentication unchanged
- User-assigned managed identity: now uses `--client-id` for Azure CLI v2.69.0+

**azure/powershell v2→v3:**
- Node.js 24 upgrade
- No breaking changes in inline script execution

### 3. SHA-Pinning Validation

**If repo policy requires SHA pins:**
- Confirm diff shows format: `uses: action@<40-char-sha> # vX.Y.Z`
- If diff shows bare tag bump (`@v4` → `@v6`), flag as policy violation

**Example violation:**
```yaml
# Before
uses: azure/powershell@v2

# Dependabot PR diff (INVALID)
-uses: azure/powershell@v2
+uses: azure/powershell@v3

# Required format
uses: azure/powershell@f5b8adcfff1904872c7b98d4012d4914d74b1a82 # v3.0.0
```

### 4. Merge or Block

**Safe to merge:**
- SHA-pinning compliant (if policy exists)
- No breaking changes affecting repo workflows
- All CI checks green

**Merge command:**
```bash
gh pr merge {N} --squash --delete-branch
```

**Block if:**
- Policy violation (leave comment explaining)
- Breaking change detected without mitigation
- CI checks failing

### 5. Post-Merge Verification

```bash
gh run list --branch main --limit 3
```

Verify next workflow run on main is healthy.

## Policy References

Check repo-specific policies:
- `.github/copilot-instructions.md`
- `SECURITY.md`
- `CONTRIBUTING.md`

Common policies:
- SHA-pinning requirement
- `persist-credentials: false` on checkout
- CodeQL only on public repos

## Common Failure Modes

1. **Base branch modified during review:** Wait 10s, retry merge
2. **PowerShell escaping in `gh pr comment`:** Use `gh api` with `-f body=` instead
3. **Missing label:** Create label first via `gh label create`

## Example Session

```bash
# 1. Get all open Dependabot PRs
gh pr list --json number,title,state,mergeable

# 2. Review each diff
gh pr diff 46
gh pr diff 47

# 3. Breaking change check (example: github-script)
grep -r "require('@actions/github')" .github/workflows/

# 4. Merge safe PRs
gh pr merge 46 --squash --delete-branch

# 5. Block problematic PR
gh api repos/{owner}/{repo}/issues/47/comments \
  -f body="Policy violation: SHA pinning required"

# 6. Verify main branch health
gh run list --branch main --limit 3
```

## Learnings from 2026-05-13 Review

- Dependabot correctly resolves SHAs when base workflow already uses SHA pins
- If base uses bare tags, Dependabot PR will also use bare tags (policy gap)
- actions/github-script v9 breaks `require()` but no repo workflows used it
- Sequential merges cause "base branch modified" errors - add 10s sleep between retries
