# Orchestration Log: forge-issue-assign-fix

**Timestamp:** 2026-05-13T12:04:00Z  
**Agent:** forge  
**Model:** Sonnet  
**Task:** Fix missing github-token on 7 workflows (issue #60-#62 root cause + fix)

## Routing & Execution

**Why chosen:** Forge specializes in CI/CD hardening and GitHub Actions workflows — domain expert on GitHub API token requirements and workflow security patterns.

**Mode:** Autonomous  
**Duration:** ~35 minutes  
**Branch:** squad/60-62-github-script-token-2026-05-13

## Deliverable

**Output:** PR #66 — github-script token fix + skill documentation
- Fixed 7 workflows missing explicit `github-token` input to `actions/github-script`
- Root cause: Action fails with "Input required and not supplied: github-token" at initialization
- All 7 steps now have `github-token: ${{ secrets.GITHUB_TOKEN }}`
- Audited for correct permissions (all had proper `permissions:` blocks already)

**Skill documented:** .squad/skills/github-script-token/SKILL.md
- Pattern for explicit token supply
- Token selection guide (GITHUB_TOKEN vs COPILOT_GITHUB_TOKEN vs PAT)
- Permission matrix (read vs write operations)
- Anti-patterns and examples

**Issues closed:**
- #60: auto-filed CI noise (github-script token missing)
- #61: auto-filed CI noise (duplicate root cause)
- #62: auto-filed CI noise (duplicate root cause)

## Outcome

✓ PR #66 merged — 7 workflows fixed
✓ 3 auto-filed issues closed
✓ Skill documented for team reuse
✓ CI heartbeat now stable (no more duplicate auto-file noise)

## Files produced

- Modified: 7 workflows (.github/workflows/*.yml)
- Created: .squad/skills/github-script-token/SKILL.md
- Modified: .squad/agents/forge/history.md (learning logged)

## Quality & Testing

- All CI validations passed (workflows now succeed)
- Audit confirmed no permission changes needed (workflow permissions were already correct)
- Skill examples include both simple case (GITHUB_TOKEN) and complex case (COPILOT_GITHUB_TOKEN for @copilot bot)

## Notes

- Pattern affects any GitHub API action; skill is reusable across team
- Auto-filed issues pattern: when a workflow fails identically 3 times, it generates duplicates → file one meta-issue instead
- This fix prevents similar duplicate noise in future CI phases
