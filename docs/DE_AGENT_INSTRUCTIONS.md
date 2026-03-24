# Genie Code Instructions — Retail Pipeline Standards via MCP

## GitHub Repository Details

| Setting | Value |
|---------|-------|
| **Owner** | `famousGSC` |
| **Repository** | `erp-cdm-pipeline-standards` |
| **Branch** | `main` |
| **Base Path** | `standards` |
| **UC Connection** | `lh_erp_cdm_github_mcp` |

### Available Standards Files

| File | Path | Purpose |
|------|------|---------|
| **Pipeline Standards** | `standards/pipeline_standards.md` | Naming, audit columns, DQ rules, layer checklists |
| **Sensitive Data Policy** | `standards/sensitive_data_policy.md` | Customer PII, payment data handling |
| **SDP Template** | `standards/sdp_template.sql` | Bronze/Silver/Gold code patterns |

---

## Prompt 1: Fetch Standards and Summarise

```
Fetch the engagement data engineering standards from GitHub:
- Owner: famousGSC
- Repository: erp-cdm-pipeline-standards
- Path: standards/erp_cdm_pipeline_standards.md

Summarise the Bronze and Silver layer checklists.
```

---

## Prompt 2: Review an Existing Table for Compliance

```
Fetch the standards from GitHub (famousGSC/erp-cdm-pipeline-standards,
standards/erp_cdm_pipeline_standards.md) and review bronze_transactions.

Check:
(1) naming convention
(2) audit columns present and last
(3) correct TBLPROPERTIES
(4) correct comment format

Return a PASS/FAIL for each check.
```

---

## Prompt 3: Generate a New Silver Table

```
Fetch the engagement standards and SDP template from GitHub
(famousGSC/erp-cdm-pipeline-standards, standards/).

Create a Silver MATERIALIZED VIEW called silver_stores from
LIVE.bronze_stores. Add DQ constraints for store_id and
store_name. Include a data_quality_flag. Follow the checklist.
```

---

## Prompt 4: Add a Gold Table

```
Fetch the standards from GitHub and add a new Gold table called
gold_store_performance that shows total revenue, transaction count,
and revenue per sqm by store and month. Join silver_transactions,
silver_stores and silver_products. Follow Gold layer rules.
```

---

## Prompt 5: Fix a Standards Violation

```
The table below is missing its audit columns and has the wrong
TBLPROPERTIES quality tag. Fetch the standards from GitHub and
fix it:

CREATE OR REFRESH MATERIALIZED VIEW transactions_clean AS
SELECT transaction_id, amount FROM LIVE.bronze_transactions;
```

---

## Quick Reference: Layer Checklists

### Bronze — 6 Requirements
- [ ] Name: `bronze_<entity>` (e.g., `bronze_transactions`)
- [ ] Type: `MATERIALIZED VIEW`
- [ ] `WHERE` clause for NULL primary key only — no CONSTRAINT clauses
- [ ] Comment: `"Raw <entity> from <source> source"`
- [ ] TBLPROPERTIES: `quality=bronze`, `delta.enableChangeDataFeed=true`
- [ ] 2 audit columns as LAST columns: `audit_ts`, `source_system`

### Silver — 8 Requirements
- [ ] Name: `silver_<entity>` (e.g., `silver_transactions`)
- [ ] CONSTRAINT clauses for key fields (`ON VIOLATION FAIL UPDATE` or `DROP ROW`)
- [ ] `TRIM()` on all string fields, `CAST AS DATE` for dates, `CAST AS DOUBLE` for amounts
- [ ] Derived/calculated columns (e.g., `net_amount`, `margin_pct`)
- [ ] `data_quality_flag` column using CASE expression, value `'CLEAN'` when valid
- [ ] Comment describes transformations applied
- [ ] TBLPROPERTIES: `quality=silver`, `delta.enableChangeDataFeed=true`, `delta.enableRowTracking=true`
- [ ] 2 audit columns as LAST columns: `audit_ts`, `source_system`

### Gold — 6 Requirements
- [ ] Name: `gold_<subject>` (e.g., `gold_daily_sales_summary`)
- [ ] Joins from `LIVE.silver_*` tables only
- [ ] Filter: `WHERE data_quality_flag = 'CLEAN'`
- [ ] Comment describes the business KPIs surfaced
- [ ] TBLPROPERTIES: `quality=gold`, `delta.enableChangeDataFeed=true`
- [ ] 2 audit columns as LAST columns: `audit_ts`, `source_system`

---

## Troubleshooting

### If Genie Code Cannot Access GitHub
Provide the raw URL as fallback:
- Standards: `https://github.com/famousGSC/erp-cdm-pipeline-standards/blob/main/standards/pipeline_standards.md`
- Template: `https://github.com/famousGSC/erp-cdm-pipeline-standards/blob/main/standards/sdp_template.sql`

### If Agent Ignores Standards
Be explicit about the most critical requirements:
```
IMPORTANT — enforce these rules from erp_cdm_pipeline_standards.md:
1. Audit columns MUST be the LAST 2 columns: audit_ts, source_system
2. Silver tables MUST include a data_quality_flag column
3. Gold tables MUST filter WHERE data_quality_flag = 'CLEAN'
4. Bronze tables: SELECT * + audit columns only, no transformations
5. TBLPROPERTIES quality tag must match the layer (bronze/silver/gold)
```
