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
- ✅ No force push, linear history enforced
- ✅ 0 required reviewers — solo repo, CI passing is the gate
- ❌ Signed commits NOT required — breaks Dependabot and GitHub API commits; remove if accidentally re-added
