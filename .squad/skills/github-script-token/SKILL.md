# Skill: GitHub Script Token Input

**Owner:** Forge  
**Created:** 2026-05-14

## Purpose

Always supply explicit `github-token` input to `actions/github-script` steps, even though the action's documentation suggests it defaults to `${{ github.token }}`. The implementation requires it to be explicitly provided.

## Pattern

**Required syntax:**

```yaml
- uses: actions/github-script@<sha> # vX.Y.Z
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    script: |
      # Your script here
```

**When to use different tokens:**

- `${{ secrets.GITHUB_TOKEN }}` — Default for in-repo operations (issues, PRs, labels in the same repo)
- `${{ secrets.COPILOT_GITHUB_TOKEN }}` — For @copilot bot assignment (requires PAT with `read:org` and `workflow` scopes)
- Custom PAT — For cross-repo operations or elevated permissions

## Root Cause

The action fails with this error when `github-token` is missing:

```
Error: Input required and not supplied: github-token
at Object.getInput (/home/runner/work/_actions/actions/github-script/.../dist/index.js:212:15)
```

This happens during the action's initialization, before the script runs. The action's documentation implies `github-token` defaults to `${{ github.token }}`, but the implementation requires explicit supply via `with:`.

## Audit Pattern

When reviewing workflows, search for all `actions/github-script` uses:

```bash
grep -r "actions/github-script" .github/workflows/
```

For each occurrence, verify the step has:
1. `github-token:` input under `with:`
2. Appropriate permissions at job or workflow level (e.g., `issues: write` for issue operations)

## Permissions Requirements

Match `github-token` choice with required permissions:

| Operation | Token | Workflow Permission Required |
|-----------|-------|------------------------------|
| Read issues/PRs | `GITHUB_TOKEN` | `issues: read` or `pull-requests: read` |
| Write issues (create, comment, label) | `GITHUB_TOKEN` | `issues: write` |
| Write PRs | `GITHUB_TOKEN` | `pull-requests: write` |
| Assign @copilot bot | Custom PAT | `issues: write` + PAT with `workflow` scope |
| Cross-repo operations | Custom PAT | Depends on operation |

## Examples

### Issue labeling (most common)

```yaml
permissions:
  issues: write
  contents: read

jobs:
  label:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/github-script@3a2844b7e9c422d3c10d287c895573f7108da1b3 # v7.0.1
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            await github.rest.issues.addLabels({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              labels: ['squad']
            });
```

### @copilot bot assignment (requires PAT)

```yaml
permissions:
  issues: write
  contents: read

jobs:
  assign:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/github-script@3a2844b7e9c422d3c10d287c895573f7108da1b3 # v7.0.1
        with:
          github-token: ${{ secrets.COPILOT_GITHUB_TOKEN }}
          script: |
            await github.request('POST /repos/{owner}/{repo}/issues/{issue_number}/assignees', {
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              assignees: ['copilot-swe-agent[bot]'],
              agent_assignment: {
                target_repo: `${context.repo.owner}/${context.repo.repo}`,
                base_branch: 'main'
              }
            });
```

## Anti-Patterns

❌ **Missing token input:**

```yaml
- uses: actions/github-script@<sha>
  with:
    script: |
      # Will fail with "Input required and not supplied: github-token"
      await github.rest.issues.addLabels(...)
```

❌ **Using PAT when default token is sufficient:**

```yaml
# Unnecessary — GITHUB_TOKEN is enough for in-repo issue operations
- uses: actions/github-script@<sha>
  with:
    github-token: ${{ secrets.MY_PAT }}
    script: |
      await github.rest.issues.addLabels(...)
```

❌ **Missing workflow permissions:**

```yaml
# No permissions block — step will fail with 403
jobs:
  label:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/github-script@<sha>
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            await github.rest.issues.addLabels(...)  # 403: Resource not accessible by integration
```

## Learnings from PR #66

- 7 workflows in this repo used `actions/github-script` without explicit `github-token`
- All failed with the same error when triggered by issue creation events
- Auto-filed issues #60, #61, #62 all had identical root cause
- The second step in `squad-issue-assign.yml` already had `github-token` (using `COPILOT_GITHUB_TOKEN`) — it was the only one that worked correctly
- Adding explicit `github-token: ${{ secrets.GITHUB_TOKEN }}` to all 7 steps resolved the issue
- No permission changes were needed — workflows already had correct `permissions:` blocks

## References

- PR #66: https://github.com/martinopedal/alz-graph-queries/pull/66
- Issues closed: #60, #61, #62
- Actions documentation: https://github.com/actions/github-script#readme
