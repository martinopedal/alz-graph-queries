# Third-Party Notices

This project incorporates content from the following open-source projects.

---

## Azure Review Checklists
- **Source:** https://github.com/Azure/review-checklists
- **Copyright:** Copyright (c) Microsoft Corporation
- **License:** MIT License

The following files contain checklist data (GUIDs, categories, text, severity ratings)
derived from the Azure Review Checklists project:

- `alz_checklist_full.json` — full ALZ checklist, used for mapping and reference
- `items_no_query.json` — checklist items not yet covered by ARG queries
- `items_without_queries.csv` — same data in CSV format
- `queries/alz_additional_queries.json` — checklist metadata fields; KQL queries in the
  `graph` field are original work by this project's contributors

---

## Azure Quick Review (azqr)
- **Source:** https://github.com/Azure/azqr
- **Copyright:** Copyright (c) Microsoft Corporation
- **License:** MIT License
- **Usage:** Referenced in documentation. Install separately from https://azure.github.io/azqr

---

## AzGovViz — Azure Governance Visualizer
- **Source:** https://github.com/JulianHayward/Azure-MG-Sub-Governance-Reporting
- **Copyright:** Copyright (c) 2020 Julian Hayward
- **License:** MIT License
- **Usage:** Referenced in documentation. Install separately.

---

## PSRule for Azure
- **Source:** https://github.com/Azure/PSRule.Rules.Azure
- **Copyright:** Copyright (c) Microsoft Corporation and contributors
- **License:** MIT License
- **Usage:** Dev/CI dependency. `Install-Module PSRule.Rules.Azure`

---

## WARA — Well-Architected Reliability Assessment
- **Source:** https://github.com/Azure/Azure-Proactive-Resiliency-Library-v2
- **Copyright:** Copyright (c) Microsoft Corporation
- **License:** MIT License
- **Usage:** Referenced in documentation. `Install-Module WARA`

---

## Pester
- **Source:** https://github.com/pester/Pester
- **Copyright:** Copyright (c) 2012 Jakub Jares and contributors
- **License:** Apache License 2.0
- **Usage:** Test runner for CI. `Install-Module Pester`

---

## Az PowerShell Modules
- **Source:** https://github.com/Azure/azure-powershell
- **Copyright:** Copyright (c) Microsoft Corporation
- **License:** MIT License
- **Usage:** Required dependency. `Install-Module Az`