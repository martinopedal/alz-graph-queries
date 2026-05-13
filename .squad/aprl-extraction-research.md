# APRL v2 Query Extraction Research Brief

**Date:** 2026-05-13  
**Author:** Sage  
**Issue:** #58

## TL;DR

- **Recommendation:** Conditional-Go. Import 150-200 high-value APRL queries in Phase 2 (Reliability + Performance categories, Azure core services only).
- APRL queries lack a `compliant` column — requires post-processing to add `compliant = 0` (all APRL queries return violations, never evidence).
- License compatible (MIT), actively maintained (last commit 2026-05-11), schema maps cleanly except for queryIntent — APRL assumes `findViolations` for all queries.

## APRL Schema

APRL v2 organizes resiliency recommendations in a two-file pattern per Azure resource type:

| File | Purpose | Format |
|---|---|---|
| `recommendations.yaml` | Metadata for each recommendation | YAML array |
| `kql/*.kql` | Individual ARG queries | Plain KQL (one file per automationAvailable recommendation) |

### `recommendations.yaml` Fields

| Field | Type | Example | Maps to our schema |
|---|---|---|---|
| `aprlGuid` | string (GUID) | `4f63619f-5001-439c-bacb-8de891287727` | `guid` |
| `description` | string | "Deploy AKS cluster across availability zones" | `text` |
| `recommendationControl` | enum | `HighAvailability`, `DisasterRecovery`, `Scalability`, `Security`, `MonitoringAndAlerting`, `OtherBestPractices` | `category` (requires mapping table) |
| `recommendationImpact` | enum | `High`, `Medium`, `Low` | `severity` (direct map) |
| `recommendationResourceType` | string | `Microsoft.ContainerService/managedClusters` | Not in our schema (implicit from query) |
| `recommendationMetadataState` | enum | `Active`, `Disabled` | Ignore (filter to Active only) |
| `automationAvailable` | boolean | `true`, `false` | `queryable` (direct map) |
| `longDescription` | string | Multi-line Markdown | Not in our schema |
| `potentialBenefits` | string | "Enhanced fault tolerance for AKS" | Not in our schema |
| `learnMoreLink` | array of objects | `[{name, url}]` | Not in our schema |

### KQL Files

Query files live in `azure-resources/{Service}/{ResourceType}/kql/{aprlGuid}.kql`. Each file contains a plain KQL query with these characteristics:

- **Always returns violations** (non-compliant resources), never evidence of good posture.
- **Output columns:** `recommendationId` (GUID), `name`, `id` (resource ID), `tags`, `param1`-`param4` (violation details).
- **No `compliant` column** — our schema requires `compliant = 1` for compliant, `0` for non-compliant.

## Mapping to Our Schema

| APRL Field | Transform | Our Field | Notes |
|---|---|---|---|
| `aprlGuid` | Direct | `guid` | |
| `description` | Direct | `text` | |
| `recommendationControl` | Lookup table (see below) | `category` | APRL uses 6 controls, we have 8 categories |
| `recommendationImpact` | Direct | `severity` | Both use `High`, `Medium`, `Low` |
| `recommendationResourceType` | Ignore | — | Our queries target resource types implicitly |
| `automationAvailable` | Direct | `queryable` | `true` → `queryable: true` |
| `recommendationMetadataState` | Filter | — | Only import `Active` recommendations |
| `kql/*.kql` | Wrap with `compliant = 0` | `graph` | See "Compliant Column Transform" below |
| — | Hardcode | `queryIntent` | All APRL queries are `findViolations` |

### Recommendation Control → Category Mapping

| APRL `recommendationControl` | Our `category` | Rationale |
|---|---|---|
| `HighAvailability` | `Reliability and Resilience` | Closest fit (ALZ category for HA/DR) |
| `DisasterRecovery` | `Reliability and Resilience` | Same |
| `Scalability` | `Management & Monitoring` | No direct ALZ category for scalability; group with operational excellence |
| `Security` | `Security` | Direct map |
| `MonitoringAndAlerting` | `Management & Monitoring` | Direct map |
| `OtherBestPractices` | `Governance` | Catch-all for governance/policy/compliance items |

### Compliant Column Transform

APRL queries return rows where violations exist. To fit our schema, wrap each query:

**Original APRL query:**
```kql
Resources
| where type =~ "Microsoft.Storage/storageAccounts"
| where sku.name in~ ("Standard_LRS", "Premium_LRS")
| project recommendationId = "e6c7e1cc-2f47-264d-aa50-1da421314472", name, id, tags
```

**Transformed for our schema:**
```kql
Resources
| where type =~ "Microsoft.Storage/storageAccounts"
| extend compliant = case(
    sku.name in~ ("Standard_LRS", "Premium_LRS"), 0,  // Non-compliant
    1  // Compliant (default)
)
| project id, name, tags, compliant, 
    resourceType = type, 
    location,
    details = strcat("SKU: ", sku.name)
```

This pattern adds the required `compliant` column and removes APRL-specific output columns (`recommendationId`, `param1`-`param4`).

## Proof of Concept

### Sample 1: AKS Availability Zones

**APRL metadata** (`azure-resources/ContainerService/managedClusters/recommendations.yaml`):
```yaml
- description: Deploy AKS cluster across availability zones
  aprlGuid: 4f63619f-5001-439c-bacb-8de891287727
  recommendationControl: HighAvailability
  recommendationImpact: High
  recommendationResourceType: Microsoft.ContainerService/managedClusters
  recommendationMetadataState: Active
  automationAvailable: true
```

**APRL query** (truncated for brevity):
```kql
resources
| where type =~ "Microsoft.ContainerService/managedClusters"
| where location in~ ("australiaeast", "brazilsouth", ...)
| project id, name, tags, location, pools = properties.agentPoolProfiles
| mv-expand pool = pools
| extend numOfAvailabilityZones = iif(isnull(pool.availabilityZones), 0, array_length(pool.availabilityZones))
| where numOfAvailabilityZones < 2
| project
    recommendationId = "4f63619f-5001-439c-bacb-8de891287727",
    name=pool.name,
    id=strcat(id,"/agentPools/",pool.name),
    tags,
    param1 = strcat("NodePoolName: ", pool.name),
    param2 = strcat("Mode: ", pool.mode)
```

**Mapped to our schema:**
```json
{
  "guid": "4f63619f-5001-439c-bacb-8de891287727",
  "category": "Reliability and Resilience",
  "subcategory": "AKS",
  "severity": "High",
  "text": "Deploy AKS cluster across availability zones",
  "queryable": true,
  "queryIntent": "findViolations",
  "graph": "resources | where type =~ \"Microsoft.ContainerService/managedClusters\" | where location in~ (\"australiaeast\", \"brazilsouth\", \"canadacentral\", \"centralindia\", \"centralus\", \"eastasia\", \"eastus\", \"eastus2\", \"francecentral\", \"germanywestcentral\", \"israelcentral\", \"italynorth\", \"japaneast\", \"japanwest\", \"koreacentral\", \"mexicocentral\", \"newzealandnorth\", \"northeurope\", \"norwayeast\", \"polandcentral\", \"qatarcentral\", \"southafricanorth\", \"southcentralus\", \"southeastasia\", \"spaincentral\", \"swedencentral\", \"switzerlandnorth\", \"uaenorth\", \"uksouth\", \"westeurope\", \"westus2\", \"westus3\", \"usgovvirginia\", \"chinanorth3\") | project id, name, tags, location, pools = properties.agentPoolProfiles | mv-expand pool = pools | extend numOfAvailabilityZones = iif(isnull(pool.availabilityZones), 0, array_length(pool.availabilityZones)) | extend compliant = case(numOfAvailabilityZones >= 2, 1, 0) | where compliant == 0 | project id, name, tags, compliant, details = strcat(\"NodePool: \", pool.name, \"; Mode: \", pool.mode, \"; Zones: \", iif(numOfAvailabilityZones == 0, \"None\", strcat_array(pool.availabilityZones, \", \")))"
}
```

### Sample 2: Storage Account Redundancy

**APRL metadata:**
```yaml
- description: Ensure that storage accounts are zone or region redundant
  aprlGuid: e6c7e1cc-2f47-264d-aa50-1da421314472
  recommendationControl: HighAvailability
  recommendationImpact: High
  recommendationResourceType: Microsoft.Storage/storageAccounts
  recommendationMetadataState: Active
  automationAvailable: true
```

**APRL query:**
```kql
Resources
| where type =~ "Microsoft.Storage/storageAccounts"
| where sku.name in~ ("Standard_LRS", "Premium_LRS")
| project recommendationId = "e6c7e1cc-2f47-264d-aa50-1da421314472", name, id, tags
```

**Mapped to our schema:**
```json
{
  "guid": "e6c7e1cc-2f47-264d-aa50-1da421314472",
  "category": "Reliability and Resilience",
  "subcategory": "Storage",
  "severity": "High",
  "text": "Ensure that storage accounts are zone or region redundant",
  "queryable": true,
  "queryIntent": "findViolations",
  "graph": "Resources | where type =~ \"Microsoft.Storage/storageAccounts\" | extend compliant = case(sku.name in~ (\"Standard_LRS\", \"Premium_LRS\"), 0, 1) | where compliant == 0 | project id, name, tags, compliant, sku = sku.name, location"
}
```

### Sample 3: API Management Zone Redundancy

**APRL metadata:**
```yaml
- description: API Management instances should be zone redundant
  aprlGuid: 740f2c1c-8857-4648-80eb-47d2c56d5a50
  recommendationControl: HighAvailability
  recommendationImpact: High
  recommendationResourceType: Microsoft.ApiManagement/service
  recommendationMetadataState: Active
  automationAvailable: true
```

**APRL query:**
```kql
resources
| where type =~ 'Microsoft.ApiManagement/service'
| where location in~ ("australiaeast", ...)
| extend skuName = sku.name
| where tolower(skuName) == tolower('premium')
| where isnull(zones) or array_length(zones) < 2
| project recommendationId = "740f2c1c-8857-4648-80eb-47d2c56d5a50", name, id, tags, param1="Zones: No Zone or Zonal"
```

**Mapped to our schema:**
```json
{
  "guid": "740f2c1c-8857-4648-80eb-47d2c56d5a50",
  "category": "Reliability and Resilience",
  "subcategory": "API Management",
  "severity": "High",
  "text": "API Management instances should be zone redundant",
  "queryable": true,
  "queryIntent": "findViolations",
  "graph": "resources | where type =~ 'Microsoft.ApiManagement/service' | where location in~ (\"australiaeast\", \"brazilsouth\", \"canadacentral\", \"centralindia\", \"centralus\", \"eastasia\", \"eastus\", \"eastus2\", \"francecentral\", \"germanywestcentral\", \"israelcentral\", \"italynorth\", \"japaneast\", \"japanwest\", \"koreacentral\", \"mexicocentral\", \"newzealandnorth\", \"northeurope\", \"norwayeast\", \"polandcentral\", \"qatarcentral\", \"southafricanorth\", \"southcentralus\", \"southeastasia\", \"spaincentral\", \"swedencentral\", \"switzerlandnorth\", \"uaenorth\", \"uksouth\", \"westeurope\", \"westus2\", \"westus3\", \"usgovvirginia\", \"chinanorth3\") | extend skuName = sku.name | extend compliant = case(tolower(skuName) == tolower('premium') and (isnull(zones) or array_length(zones) < 2), 0, 1) | where compliant == 0 | project id, name, tags, compliant, sku = skuName, zones = iif(isnull(zones), \"None\", tostring(zones)), location"
}
```

### Sample 4: SQL Database Zone Redundancy

**APRL metadata:**
```yaml
- description: Enable zone redundancy for Azure SQL Database to achieve high availability and resiliency
  aprlGuid: c0085c32-84c0-c247-bfa9-e70977cbf108
  recommendationControl: HighAvailability
  recommendationImpact: High
  recommendationResourceType: Microsoft.Sql/servers/databases
  recommendationMetadataState: Active
  automationAvailable: true
```

**APRL query:**
```kql
Resources
| where type =~ 'microsoft.sql/servers/databases'
| where location in~ ("australiaeast", ...)
| where tolower(tostring(properties.zoneRedundant))=~'false'
| project recommendationId = "c0085c32-84c0-c247-bfa9-e70977cbf108", name, id, tags
```

**Mapped to our schema:**
```json
{
  "guid": "c0085c32-84c0-c247-bfa9-e70977cbf108",
  "category": "Reliability and Resilience",
  "subcategory": "SQL Database",
  "severity": "High",
  "text": "Enable zone redundancy for Azure SQL Database to achieve high availability and resiliency",
  "queryable": true,
  "queryIntent": "findViolations",
  "graph": "Resources | where type =~ 'microsoft.sql/servers/databases' | where location in~ (\"australiaeast\", \"brazilsouth\", \"canadacentral\", \"centralindia\", \"centralus\", \"eastasia\", \"eastus\", \"eastus2\", \"francecentral\", \"germanywestcentral\", \"israelcentral\", \"italynorth\", \"japaneast\", \"japanwest\", \"koreacentral\", \"mexicocentral\", \"newzealandnorth\", \"northeurope\", \"norwayeast\", \"polandcentral\", \"qatarcentral\", \"southafricanorth\", \"southcentralus\", \"southeastasia\", \"spaincentral\", \"swedencentral\", \"switzerlandnorth\", \"uaenorth\", \"uksouth\", \"westeurope\", \"westus2\", \"westus3\", \"usgovvirginia\", \"chinanorth3\") | extend compliant = case(tolower(tostring(properties.zoneRedundant)) =~ 'false', 0, 1) | where compliant == 0 | project id, name, tags, compliant, zoneRedundant = properties.zoneRedundant, location"
}
```

### Sample 5: ExpressRoute Gateway Zone Redundancy

**APRL metadata:**
```yaml
- description: Use Zone-redundant ExpressRoute gateway SKUs
  aprlGuid: bbe668b7-eb5c-c746-8b82-70afdedf0cae
  recommendationControl: HighAvailability
  recommendationImpact: High
  recommendationResourceType: Microsoft.Network/virtualNetworkGateways
  recommendationMetadataState: Active
  automationAvailable: true
```

**APRL query** (uses Advisor join):
```kql
advisorresources
| where properties.recommendationTypeId =~ 'c9af1ef6-55bc-48af-bfe4-2c80490159f8'
| mv-expand resId = properties.resourceMetadata.resourceId
| extend resId = tostring(resId)
| project recId = properties.recommendationTypeId, resId
| join kind=leftouter (
    resources
    | extend id = tostring(id)
    | project id, name, tags, location, properties
) on $left.resId == $right.id
| project recommendationId = "bbe668b7-eb5c-c746-8b82-70afdedf0cae", name , id = resId, tags, param1 = strcat("sku-tier: ", properties.sku.tier), param2 = location
```

**Mapped to our schema:**
```json
{
  "guid": "bbe668b7-eb5c-c746-8b82-70afdedf0cae",
  "category": "Reliability and Resilience",
  "subcategory": "Networking",
  "severity": "High",
  "text": "Use Zone-redundant ExpressRoute gateway SKUs",
  "queryable": true,
  "queryIntent": "findViolations",
  "graph": "advisorresources | where properties.recommendationTypeId =~ 'c9af1ef6-55bc-48af-bfe4-2c80490159f8' | mv-expand resId = properties.resourceMetadata.resourceId | extend resId = tostring(resId) | project recId = properties.recommendationTypeId, resId | join kind=leftouter (resources | extend id = tostring(id) | project id, name, tags, location, properties) on $left.resId == $right.id | extend compliant = 0 | project id = resId, name, tags, compliant, skuTier = properties.sku.tier, location"
}
```

## Coverage Proposal

APRL contains **451 KQL queries** across 80+ Azure service types. Not all are relevant to ALZ. Propose importing **150-200 queries** in two tranches:

### Tranche 1: Reliability and Performance (100-120 queries)

Target services with high ALZ relevance:

| Service | Queries (estimate) | Rationale |
|---|---|---|
| AKS (ContainerService/managedClusters) | 15-20 | Core ALZ compute service |
| Storage Accounts | 8-10 | Core ALZ data service |
| SQL Database / Managed Instance | 10-12 | Core ALZ data service |
| Virtual Machines / VMSS | 12-15 | Core ALZ compute service |
| Virtual Network Gateways (ExpressRoute/VPN) | 8-10 | Core ALZ networking |
| Application Gateway | 6-8 | Core ALZ networking |
| API Management | 5-6 | Core ALZ app service |
| Azure Kubernetes Fleet | 3-4 | ALZ Kubernetes orchestration |
| Cosmos DB | 8-10 | Core ALZ data service |
| Service Bus | 4-6 | Core ALZ messaging |
| Event Hubs | 4-6 | Core ALZ messaging |
| Redis Cache | 3-4 | Core ALZ caching |
| Key Vault | 5-7 | Core ALZ security service |
| App Service / Function Apps | 10-12 | Core ALZ app service |

**Curation rubric for Tranche 1:**

1. `recommendationControl` = `HighAvailability` or `DisasterRecovery`
2. `recommendationImpact` = `High` or `Medium`
3. `recommendationMetadataState` = `Active`
4. `automationAvailable` = `true`
5. Service type appears in ALZ baseline architecture (networking, compute, data, messaging, security)

### Tranche 2: Security and Governance (50-80 queries)

Lower priority, import after Tranche 1 proves value:

| Service | Queries (estimate) | Rationale |
|---|---|---|
| Azure Policy (Authorization) | 5-6 | Governance |
| Azure Monitor / Log Analytics | 6-8 | Monitoring |
| Azure Front Door | 4-6 | Networking |
| Azure Firewall | 3-5 | Security |
| Private DNS Zones | 2-3 | Networking |
| Azure Backup | 6-8 | DR |
| Site Recovery | 4-5 | DR |

**Excluded services:**

- Azure VMware Solution (AVS) — niche, not ALZ baseline
- Azure Large Instance — niche
- Azure Stack HCI — edge/hybrid, not cloud-native ALZ
- Bare Metal Infrastructure — niche
- Analysis Services — legacy (superseded by Power BI Embedded)
- Bing — not ALZ-relevant
- DevTest Labs — dev-only, not production ALZ

## Validation Strategy

### Offline Syntax Validation

`scripts/Validate-KqlSyntax.ps1` will validate all imported APRL queries. Known compatibility issues:

1. **`advisorresources` table:** Used by ~10% of APRL queries (e.g., ExpressRoute Gateway zone redundancy). The Kusto.Language parser will flag this as KS204 (unknown table). Already filtered as false positive in our script (line 88: `$falsePositiveCodes = @('KS204', 'KS208', 'KS142')`). No action needed.

2. **Region filter lists:** APRL hard-codes zone-capable regions (e.g., `where location in~ ("australiaeast", "brazilsouth", ...)`). These lists are 30-40 regions long and may grow stale. Consider:
   - Keep as-is (low risk — queries will simply not match resources in new regions until we update the list)
   - OR replace with a dynamic join to a maintained region list (higher complexity, marginal benefit)

**Recommendation:** Keep APRL region lists as-is for Phase 2. Document in `queries/README.md` that zone-redundancy checks are scoped to known zone-capable regions as of the APRL snapshot date.

3. **`compliant` column transform:** All imported queries require the `compliant = 0` wrapper. Validate that each query produces valid output after transform by running a sample against a test subscription.

### Runtime Validation

After import, run `Validate-Queries.ps1` against a test ALZ subscription to confirm:

1. No KQL runtime errors (syntax errors not caught by offline validation)
2. SkipToken pagination works for large result sets (APRL queries often return 100+ resources)
3. CSV/Markdown/HTML reports render correctly with new queries

## Effort Estimate

**Size: Large (L)**

| Work Unit | Hours | Notes |
|---|---|---|
| **Extraction script** | 16-20 | Parse APRL YAML + KQL, apply transforms, output JSON |
| **Schema mapping** | 8-10 | Implement `recommendationControl` → `category` lookup, wrap queries with `compliant = 0` |
| **Validation pass** | 12-16 | Run offline syntax + runtime validation, fix edge cases |
| **Integration tests** | 8-10 | Extend Pester tests to cover APRL-sourced queries (verify `queryIntent`, pagination) |
| **Docs** | 6-8 | Update README (query count, coverage %), CHANGELOG, add `queries/APRL_SOURCES.md` for attribution |
| **Curation** | 8-12 | Manual review of 150-200 queries to confirm ALZ relevance, filter out duplicates |
| **Total** | **58-76 hours** | 7-10 days FTE |

**Dependencies:**

- Phase 2 kickoff (this is a Phase 2 item per `.squad/decisions.md` line 122)
- Decision on Tranche 1 service list (requires ALZ baseline architecture review)

## Risks and Open Questions

### Risks

1. **Query duplication:** Our repo has 132 existing queries. APRL has 451. Expect 10-20% overlap (e.g., storage redundancy, AKS zone redundancy). Mitigation: Deduplicate by comparing `text` field and resource type before import. Prefer our existing queries where overlap exists (already validated against ALZ).

2. **Maintenance burden:** APRL is actively maintained (last commit 2026-05-11). If we import 150-200 queries, we inherit responsibility for keeping them current. Upstream changes (new regions, deprecated SKUs, API changes) will require periodic re-imports. Mitigation: Document APRL snapshot date in `queries/APRL_SOURCES.md`. Plan a quarterly re-import cycle.

3. **Schema drift:** APRL uses `param1`-`param4` for violation details (unstructured strings). Our schema has no equivalent. Mitigation: Extract key details into the `graph` query output (e.g., `details = strcat("SKU: ", sku.name)`) instead of relying on APRL's `param` fields.

4. **False positives:** APRL queries check for "best practices" (e.g., zone redundancy), not ALZ-specific requirements. Some APRL recommendations may be too strict for ALZ baseline (e.g., requiring Premium SKUs where Standard is sufficient). Mitigation: Tag imported queries with `source = "APRL"` and allow users to filter by source in reports.

### Open Questions

1. **Subcategory assignment:** Our schema has a `subcategory` field (e.g., "AKS", "Storage"). APRL does not. How do we assign subcategories? Options:
   - Extract from `recommendationResourceType` (e.g., `Microsoft.ContainerService/managedClusters` → "AKS")
   - Manual assignment during curation (higher quality, more effort)
   - Leave blank for imported queries (breaks report grouping)

   **Recommendation:** Extract from `recommendationResourceType` with a lookup table. Add manual overrides for ambiguous cases (e.g., `Microsoft.Network/*` spans multiple subcategories).

2. **queryIntent edge cases:** All APRL queries are `findViolations`. But some APRL recommendations are informational (e.g., "Monitor health for ExpressRoute gateway" — `automationAvailable: false`). These lack ARG queries. Do we import the metadata-only recommendations? **Recommendation:** No. Only import `automationAvailable: true` recommendations with KQL queries.

3. **License compatibility:** APRL is MIT (verified 2026-05-13 at https://raw.githubusercontent.com/Azure/Azure-Proactive-Resiliency-Library-v2/refs/heads/main/LICENSE). Our repo is also MIT. No conflict. But we must attribute APRL per MIT terms. **Action:** Add `queries/APRL_SOURCES.md` with full attribution text and APRL commit SHA.

## Sources

- APRL v2 repository: https://github.com/Azure/Azure-Proactive-Resiliency-Library-v2 (accessed 2026-05-13)
- APRL LICENSE: https://raw.githubusercontent.com/Azure/Azure-Proactive-Resiliency-Library-v2/refs/heads/main/LICENSE (accessed 2026-05-13)
- APRL README: https://github.com/Azure/Azure-Proactive-Resiliency-Library-v2#readme (accessed 2026-05-13)
- Sample APRL queries:
  - AKS zone redundancy: https://raw.githubusercontent.com/Azure/Azure-Proactive-Resiliency-Library-v2/refs/heads/main/azure-resources/ContainerService/managedClusters/kql/4f63619f-5001-439c-bacb-8de891287727.kql (accessed 2026-05-13)
  - Storage redundancy: https://raw.githubusercontent.com/Azure/Azure-Proactive-Resiliency-Library-v2/refs/heads/main/azure-resources/Storage/storageAccounts/kql/e6c7e1cc-2f47-264d-aa50-1da421314472.kql (accessed 2026-05-13)
  - API Management zone redundancy: https://raw.githubusercontent.com/Azure/Azure-Proactive-Resiliency-Library-v2/refs/heads/main/azure-resources/ApiManagement/service/kql/740f2c1c-8857-4648-80eb-47d2c56d5a50.kql (accessed 2026-05-13)
  - SQL Database zone redundancy: https://raw.githubusercontent.com/Azure/Azure-Proactive-Resiliency-Library-v2/refs/heads/main/azure-resources/Sql/servers/kql/c0085c32-84c0-c247-bfa9-e70977cbf108.kql (accessed 2026-05-13)
  - ExpressRoute Gateway zone redundancy: https://raw.githubusercontent.com/Azure/Azure-Proactive-Resiliency-Library-v2/refs/heads/main/azure-resources/Network/virtualNetworkGateways/kql/bbe668b7-eb5c-c746-8b82-70afdedf0cae.kql (accessed 2026-05-13)
- APRL metadata samples:
  - AKS recommendations: https://raw.githubusercontent.com/Azure/Azure-Proactive-Resiliency-Library-v2/refs/heads/main/azure-resources/ContainerService/managedClusters/recommendations.yaml (accessed 2026-05-13)
  - Storage recommendations: https://raw.githubusercontent.com/Azure/Azure-Proactive-Resiliency-Library-v2/refs/heads/main/azure-resources/Storage/storageAccounts/recommendations.yaml (accessed 2026-05-13)
  - SQL recommendations: https://raw.githubusercontent.com/Azure/Azure-Proactive-Resiliency-Library-v2/refs/heads/main/azure-resources/Sql/servers/recommendations.yaml (accessed 2026-05-13)
  - VPN Gateway recommendations: https://raw.githubusercontent.com/Azure/Azure-Proactive-Resiliency-Library-v2/refs/heads/main/azure-resources/Network/virtualNetworkGateways/recommendations.yaml (accessed 2026-05-13)
- APRL commit activity: https://github.com/Azure/Azure-Proactive-Resiliency-Library-v2/commits/main (accessed 2026-05-13)
- GitHub API (APRL repo structure): `gh api repos/Azure/Azure-Proactive-Resiliency-Library-v2/*` (accessed 2026-05-13)
