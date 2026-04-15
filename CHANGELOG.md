# Changelog

All notable changes to this project will be documented here.

## [Unreleased]

## [1.0.0] — 2026-04-15

### Added
- 132 new Azure Resource Graph queries covering 206 previously-uncovered ALZ checklist items
- Coverage increased from 135/255 (53%) to 181/255 (71%)
- Wave 1: networking, security, management, governance, resource organisation queries
- Wave 2: hybrid/on-premises ARG-visible items converted to queries
- `Validate-Queries.ps1` — runs all queries against your Azure environment, outputs CSV results
- `auto-label-issues.yml` — auto-applies `squad` label to every new issue
- `ci-failure-analysis.yml` — opens a `bug` + `squad` issue on any workflow failure
- Squad team initialised (Lead, Atlas, Iris, Forge, Sentinel, Sage, Scribe, Ralph)
- Phase 2 roadmap issues: Microsoft Graph API (#11), Cost Management API (#12), GitHub/ADO API (#9)
