# Project Context

- **Owner:** martinopedal
- **Project:** ALZ Additional Graph Queries — Research and tool ecosystem scouting
- **Stack:** Web research, GitHub API, Microsoft Learn, public tool evaluation
- **Created:** 2026-04-14

## Team Updates

- 2026-05-13: Writing style decision merged into .squad/decisions.md — applies to all docs, READMEs, reports, PR descriptions. See decisions.md.

## Learnings

### APRL v2 Schema and Integration Feasibility (2026-05-13)

Research completed for issue #58. APRL v2 (Azure Proactive Resiliency Library v2) contains **451 KQL queries** across 80+ Azure service types, organized in a two-file pattern per resource type:

**Schema:**
- `recommendations.yaml` — metadata (GUID, description, impact, control category, automation flag)
- `kql/{guid}.kql` — individual ARG queries (one file per automatable recommendation)

**Key findings:**
- License: MIT (compatible with our repo)
- Maintenance: Active (last commit 2026-05-11)
- Schema mapping: Clean fit to our `alz_additional_queries.json` schema EXCEPT:
  - APRL queries lack a `compliant` column — requires post-processing (all APRL queries return violations, never evidence)
  - APRL `recommendationControl` → our `category` requires a lookup table
  - All APRL queries are `findViolations` (never `findEvidence`)

**Recommendation:** Conditional-Go. Import 150-200 queries in two tranches:
1. Tranche 1 (100-120 queries): Reliability + Performance, Azure core services (AKS, Storage, SQL, VMs, Networking, API Management, Cosmos DB, Key Vault, App Service)
2. Tranche 2 (50-80 queries): Security + Governance, lower priority

**Effort:** Large (L) — 58-76 hours (7-10 days FTE). Breakdown: extraction script (16-20h), schema mapping (8-10h), validation pass (12-16h), integration tests (8-10h), docs (6-8h), curation (8-12h).

**Risks:**
- Query duplication (10-20% overlap with our existing 132 queries) — prefer our queries where overlap exists
- Maintenance burden (APRL evolves; plan quarterly re-import cycle)
- False positives (APRL checks "best practices", not ALZ-specific requirements; may be too strict)

**Open questions:**
- Subcategory assignment (extract from `recommendationResourceType` or manual curation?)
- Attribution strategy (add `queries/APRL_SOURCES.md` with commit SHA and MIT license notice)

**Sources:** All URLs cited in `.squad/aprl-extraction-research.md` (accessed 2026-05-13).

<!-- Append new learnings below. Each entry is something lasting about the project. -->
