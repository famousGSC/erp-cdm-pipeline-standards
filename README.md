# ERP-to-CDM Pipeline Standards

Enterprise pipeline standards for professional services firms mapping ERP system extracts to a Common Data Model (CDM).

## Scope

These standards apply to all data engineering pipelines built during audit and advisory engagements where source data is extracted from ERP systems (SAP, Oracle EBS, Microsoft Dynamics, NetSuite, etc.) and loaded into a standardised Common Data Model for downstream analysis, control testing, or reporting.

## Audience

- Data engineers and pipeline developers on audit and advisory engagements
- Engagement managers responsible for data workstream sign-off
- Quality reviewers performing technical review of pipeline code

## Terminology

| Term | Definition |
|------|-----------|
| **Audited Entity** | The organisation whose financial data is being processed. Never referred to as "client" in pipeline code, comments, or logs. |
| **CDM** | Common Data Model — the target schema used across engagements for standardised analysis |
| **ERP** | Enterprise Resource Planning system — the source of financial transaction data |
| **Bronze** | Raw ingestion layer — exact copy of source, immutable after load |
| **Silver** | Conformed layer — CDM-mapped, quality-checked, audit-trailed |
| **Gold** | Analytical layer — aggregated outputs for engagement analysis and reporting |

## Standards Files

| File | Purpose |
|------|---------|
| [erp_cdm_pipeline_standards.md](standards/erp_cdm_pipeline_standards.md) | Main coding standards: naming, audit columns, DQ, CDM mapping |
| [erp_cdm_sensitive_data_policy.md](standards/erp_cdm_sensitive_data_policy.md) | Sensitive financial data handling and access control |
| [erp_cdm_sdp_template.sql](standards/erp_cdm_sdp_template.sql) | SDP SQL templates for Bronze/Silver/Gold ERP pipelines |
