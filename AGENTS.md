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
