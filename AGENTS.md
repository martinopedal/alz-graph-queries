# AI Agent Instructions

## Repository Purpose

Azure Resource Graph queries for validating ALZ checklist items that lack automated validation.

## Repository Structure

- ✅ `queries/` - Individual .kql files for ARG validation
- ✅ `Validate-Queries.ps1` - Runs all queries and reports results
- ✅ `process_items.ps1` - Processes checklist items
- ✅ `alz_checklist_full.json` - Full ALZ checklist data

## Code Quality

- ✅ All queries must be valid KQL / Azure Resource Graph syntax
- ✅ Run validation script before committing
- ✅ Only use checkmarks in documentation lists, no AI language or em dashes

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
