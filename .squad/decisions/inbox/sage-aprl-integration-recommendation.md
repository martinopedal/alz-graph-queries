# APRL Integration Recommendation

**Date:** 2026-05-13  
**Author:** Sage  
**Issue:** #58  
**Status:** Decision (Phase 2 item)

## TL;DR

- **Conditional-Go.** Import 150-200 high-value APRL queries in Phase 2 (Reliability + Performance categories, Azure core services only).
- APRL queries lack a `compliant` column — requires post-processing to add `compliant = 0` (all APRL queries return violations, never evidence).
- License compatible (MIT), actively maintained (last commit 2026-05-11), schema maps cleanly except for queryIntent — APRL assumes `findViolations` for all queries.

## Effort Estimate

**Size: Large (L)**

| Work Unit | Hours |
|---|---|
| Extraction script | 16-20 |
| Schema mapping | 8-10 |
| Validation pass | 12-16 |
| Integration tests | 8-10 |
| Docs | 6-8 |
| Curation | 8-12 |
| **Total** | **58-76 hours (7-10 days FTE)** |

## Go/No-Go/Conditional-Go

**Conditional-Go** — proceed with Tranche 1 (100-120 Reliability/Performance queries) if:

1. Phase 2 is confirmed (this is a Phase 2 item per `.squad/decisions.md` line 122)
2. ALZ baseline architecture review confirms service list (AKS, Storage, SQL, VMs, Networking, API Management, Cosmos DB, Key Vault, App Service)
3. Dedupe strategy confirmed (prefer our existing 132 queries where overlap exists)

**Defer Tranche 2** (Security/Governance queries) until Tranche 1 proves value.

## Rationale

APRL offers 451 production-ready ARG queries with high ALZ relevance (HA/DR/Performance). Importing 150-200 queries would triple our coverage from 132 to ~280-330 automated checks. The effort is justified if:

- Query quality meets our validation standards (offline + runtime syntax checks)
- Dedupe removes redundancy with our existing queries
- Curation filters out non-ALZ queries (niche services like AVS, Azure Large Instance)

The risk is maintenance burden (APRL evolves; quarterly re-import needed). Mitigation: document APRL snapshot date and commit SHA for traceability.

---

**Full research brief:** `.squad/aprl-extraction-research.md`
