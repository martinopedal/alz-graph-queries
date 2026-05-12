# Copilot Instructions - alz-graph-queries

## Repository Purpose

Azure Resource Graph (ARG) queries that validate ALZ checklist items which lack automated validation.
Queries live in `queries/alz_additional_queries.json` — each item has a `queryable` flag, a KQL
`graph` field when queryable, and a `reason` field when not.

## Code Patterns

- ✅ Queries are stored as JSON in `queries/` (not `.kql` files)
- ✅ Every KQL query must return a `compliant` column (1 = compliant, 0 = non-compliant)
- ✅ PowerShell scripts handle validation and reporting
- ✅ Run `Validate-Queries.ps1` before committing new queries

## Documentation rules — ALWAYS required

Every PR that changes code, queries, or configuration MUST include a docs update in the same commit:

- ✅ `README.md` — update query counts, coverage %, and feature list if changed
- ✅ `PERMISSIONS.md` — update if new Azure/Graph/GitHub API scopes are added
- ✅ `CHANGELOG.md` — add an entry for every user-visible change (feature, fix, breaking)
- ✅ Inline comments in new PowerShell modules if the logic is non-obvious
- ✅ If a query is converted from not-queryable to queryable, update the description in `alz_additional_queries.json`

**No code PR merges without a matching docs update. This is not optional.**

## Quality Rules

- ✅ All KQL must be valid Azure Resource Graph syntax
- ✅ No AI language: no em dashes, no "leveraging/unlocking/robust/comprehensive"
- ✅ Use checkmarks in documentation

## CI / Security rules

- ✅ CodeQL only on **public** repos — this repo is public, CodeQL is appropriate here
- ✅ Private repos (news-fetcher, terraform-azapi-aks-automatic) do NOT have GHAS — never add CodeQL to them
- ✅ All GitHub Actions `uses:` must be pinned to a commit SHA, not a tag
- ✅ Add `persist-credentials: false` to every `actions/checkout` step
- ✅ Never commit secrets or credentials

## Branch protection policy (solo contributor repos)

- ✅ PRs required for all changes to main — no direct push
- ✅ Every PR description must include a docs section listing what was updated
- ✅ No force push, linear history enforced
- ✅ 0 required reviewers — solo repo, CI passing is the gate
- ❌ Signed commits NOT required — breaks Dependabot and GitHub API commits; remove if accidentally re-added

## Issue conventions

- ✅ Every new issue MUST have the `squad` label — this is how Ralph picks it up for dispatch
- ✅ The `auto-label-issues.yml` workflow adds `squad` automatically on open — never remove it
- ✅ Use `enhancement`, `bug`, `documentation` alongside `squad` for type and priority
- ✅ Issue titles must follow conventional commits prefix: `feat:`, `fix:`, `docs:`, `chore:`

## GitHub-first principle
Validate changes in GitHub Actions, not locally. Push, trigger workflow, check logs, iterate.

## Actions version policy
- Use actions/checkout@v6 and actions/setup-python@v6 (Node.js 24 compatible)

<!-- BEGIN: rubberduck-model-guide v2026-04-23 -->
## Model selection (synced — do not edit by hand)

Every task has exactly one desired model. Use it by default; only switch on rate-limit/error or to satisfy the cross-vendor rubberduck rule below.

### Vendor families

| Vendor | Models |
|---|---|
| Anthropic | `claude-opus-*`, `claude-sonnet-*`, `claude-haiku-*` |
| OpenAI | `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.3-codex`, `gpt-5.2-codex`, `gpt-5.2`, `gpt-5-mini`, `gpt-4.1` |
| Microsoft | `goldeneye` |

### Desired model per task

| Task | Desired model | Vendor | Cross-vendor fallback |
|---|---|---|---|
| Plan review (rubberduck a plan) | `claude-opus-4.7` | Anthropic | `gpt-5.4` |
| PR / code review | `gpt-5.3-codex` | OpenAI | `claude-opus-4.7` |
| Security audit | `claude-opus-4.7` | Anthropic | `goldeneye` |
| Test-coverage review | `gpt-5.3-codex` | OpenAI | `claude-opus-4.7` |
| Quant / kill-or-continue | `goldeneye` | Microsoft | `gpt-5.4` |
| Exploration (find usages, scan codebase) | `claude-haiku-4.5` | Anthropic | `gpt-5.4-mini` |
| Docs / writing | `claude-sonnet-4.6` | Anthropic | `gpt-5.4` |
| Code generation (daily driver) | `claude-sonnet-4.6` | Anthropic | `gpt-5.3-codex` |

### Cross-vendor rubberduck rule (non-negotiable)

Every rubberduck must come from a different vendor than the model that produced the work. Same-vendor models share priors and miss the same blind spots.

- Anthropic-produced work → rubberduck with `gpt-5.4` or `goldeneye`
- OpenAI-produced work → rubberduck with `claude-opus-4.7` or `goldeneye`
- Microsoft-produced work → rubberduck with panel `claude-opus-4.7` + `gpt-5.4`

If the desired model for a task would be same-vendor as the implementer, use the cross-vendor fallback in the table above.

### Escalate to dual-frontier panel when

Decision is hard to reverse: kill a project, deploy to prod, change a risk cap, sign off on research, security audit on auth/secrets/IaC. Run two independent frontier models from different vendors in parallel; adopt the union of findings.

### Fallback chain on rate-limit / errors

`claude-opus-4.7` → `claude-opus-4.6-1m` → `goldeneye` → `gpt-5.4` → `gpt-5.3-codex` → `gpt-5.2-codex`. Respect the cross-vendor rule when reviewing other models' work.
<!-- END: rubberduck-model-guide v2026-04-23 -->
