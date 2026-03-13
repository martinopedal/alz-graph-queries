# Copilot Instructions - alz-graph-queries

## Repository Purpose

Azure Resource Graph (ARG) queries that validate ALZ checklist items which lack automated validation.

## Code Patterns

- ✅ Queries are stored as individual `.kql` files in the `queries/` directory
- ✅ PowerShell scripts handle validation and reporting
- ✅ Results output to CSV files

## Quality Rules

- ✅ All KQL queries must be valid Azure Resource Graph syntax
- ✅ Run `Validate-Queries.ps1` before committing new queries
- ✅ Use checkmarks in documentation, no AI language or em dashes
