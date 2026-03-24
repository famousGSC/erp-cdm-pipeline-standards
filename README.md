# Retail Advisory Pipeline Standards

Data engineering pipeline standards for advisory engagements working with UK retail data. These standards ensure consistent, auditable, and maintainable Spark Declarative Pipelines (SDP) across all engagement teams.

## Scope

These standards apply to all Bronze/Silver/Gold pipelines built on Databricks using the Spark Declarative Pipelines framework. They cover naming conventions, audit columns, data quality constraints, table properties, and SQL formatting.

## Audience

- Data engineers building pipelines for retail analytics engagements
- Technical leads reviewing pipeline code before deployment
- AI agents (Genie Code) generating pipeline code in Pipeline Authoring mode

## Standards Files

| File | Purpose |
|------|---------|
| [pipeline_standards.md](standards/pipeline_standards.md) | Main coding standards: naming, audit columns, DQ constraints, layer checklists |
| [sensitive_data_policy.md](standards/sensitive_data_policy.md) | Customer PII handling and masking patterns |
| [sdp_template.sql](standards/sdp_template.sql) | Ready-to-use Bronze/Silver/Gold SDP SQL templates |

## Demo Usage Docs

| File | Purpose |
|------|---------|
| [DE_AGENT_INSTRUCTIONS.md](docs/DE_AGENT_INSTRUCTIONS.md) | Copy-paste prompts for Genie Code in Pipeline Authoring mode |
| [DEMO_SCRIPT.md](docs/DEMO_SCRIPT.md) | 20-minute demo walkthrough script |

## Key Principles

| Layer | Purpose |
|-------|---------|
| **Bronze** | Raw ingestion — exact copy of source, `WHERE` filter on primary key only |
| **Silver** | Validated and transformed — DQ constraints, derived fields, `data_quality_flag` |
| **Gold** | Business aggregations — joins across silver tables, `WHERE data_quality_flag = 'CLEAN'` |

Every table requires two audit columns as the **last** columns: `audit_ts` and `source_system`.
