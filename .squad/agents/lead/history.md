# Project Context

- **Owner:** martinopedal
- **Project:** ALZ Additional Graph Queries — Azure Landing Zone checklist automation
- **Stack:** PowerShell, KQL (Azure Resource Graph), JSON
- **Created:** 2026-04-14

## Team Updates

- 2026-05-13: Writing style decision merged into .squad/decisions.md — applies to all docs, READMEs, reports, PR descriptions. See decisions.md.

## Learnings

### CI Failure Analysis: Incomplete Job Filtering (May 13)
**Root Cause:** Issues #51 and #52 fired when Squad Heartbeat jobs were **cancelled** (not failed) on May 5-6. The CI Failure Analysis workflow triggered on the run's failure conclusion but filtered jobs only by `conclusion === 'failure'`, missing cancelled jobs. This created noise: issues with "Failed jobs: none" when jobs were actually cancelled due to timeout/rate limit.

**Resolution:** Both issues closed as stale — heartbeat workflow has been green since May 12. Recommend Forge review whether the CI Failure Analysis script should also report `cancelled` jobs or filter differently.

**Triage Pattern:** When CI auto-files issues with "Failed jobs: none", check job conclusions in raw API response — may be `cancelled` rather than `failure`.
