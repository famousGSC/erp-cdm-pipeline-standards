# ERP-to-CDM Pipeline Standards

> **For AI Agents:** This document contains complete standards for Spark Declarative Pipelines (SDP) used in professional services audit engagements. Apply these rules automatically when creating or reviewing pipeline code that maps ERP extracts to a Common Data Model (CDM). No additional instructions are needed.

---

## Quick Reference — Checklist by Layer

### Bronze Layer (Raw ERP Extract) — 8 Requirements
| Requirement | How to Apply |
|-------------|--------------|
| Table name | `bronze_` + `<erp_source>_` + `lowercase_snake_case` (e.g., `bronze_sap_gl_postings`) |
| Table type | `STREAMING TABLE` for file ingestion, `MATERIALIZED VIEW` for Delta sources |
| Immutability | No transformations beyond casting to string. Raw data must be preserved exactly. |
| Audit columns | Add `_source_system`, `_extraction_timestamp`, `_pipeline_run_id`, `_record_hash`, `_loaded_by` as LAST columns |
| Comment | `COMMENT "Raw <entity> extract from <ERP system> for <audited entity> engagement <engagement_id>"` |
| Properties | `TBLPROPERTIES ("quality" = "bronze", "engagement.layer" = "raw", "delta.enableChangeDataFeed" = "true")` |
| Constraints | Use `WHERE` clause only — no CONSTRAINT clauses on Bronze |
| Clustering | `CLUSTER BY AUTO` for STREAMING TABLEs |

### Silver Layer (CDM-Mapped Conformed) — 10 Requirements
| Requirement | How to Apply |
|-------------|--------------|
| Table name | `silver_cdm_` + `lowercase_snake_case` (e.g., `silver_cdm_journal_entry`) |
| CDM mapping | COMMENT must include source-to-target mapping reference |
| Audit columns | Same 5 audit columns, plus `_cdm_version` and `_mapping_rule_id` |
| Comment | `COMMENT "CDM-mapped <entity>. Source: <ERP>.<table>. Mapping: <mapping_doc_ref>"` |
| Properties | Add `"delta.enableRowTracking" = "true"` and `"engagement.layer" = "conformed"` |
| Constraints | CONSTRAINT clauses required for all CDM mandatory fields |
| Type coercion | All amounts must be CAST to DECIMAL(18,2), all dates to DATE |
| Null policy | CDM mandatory fields must use `ON VIOLATION FAIL UPDATE`; optional fields use `ON VIOLATION DROP ROW` |
| DQ flag | Every Silver table must include a `_data_quality_flag` column |
| Reconciliation | Row count and sum control totals must be persisted to `<schema>.reconciliation_log` |

### Gold Layer (Audit Analysis) — 8 Requirements
| Requirement | How to Apply |
|-------------|--------------|
| Table name | `gold_` + `lowercase_snake_case` (e.g., `gold_journal_entry_testing`) |
| Audit columns | Same 5 base audit columns |
| Comment | `COMMENT "Analytical view for <audit procedure> — <audited entity> engagement"` |
| Properties | `TBLPROPERTIES ("quality" = "gold", "engagement.layer" = "analytical")` |
| Aggregations | `ROUND()` for all monetary amounts (2dp), `NULLIF()` for division, `COALESCE()` for NULLs |
| Joins | Explicit `INNER JOIN` / `LEFT JOIN` with `LIVE.` prefix for pipeline tables |
| No PII | Gold tables must not contain raw PII; use aggregated or masked values only |
| Clustering | `CLUSTER BY AUTO` for STREAMING TABLEs |

---

## 1. Table Naming Convention

### Rule
All tables must use `lowercase_snake_case` with layer prefix and (for Bronze) ERP source identifier.

| Layer | Pattern | Example |
|-------|---------|---------|
| Bronze | `bronze_<erp>_<entity>` | `bronze_sap_gl_postings`, `bronze_oracle_ap_invoices` |
| Silver | `silver_cdm_<entity>` | `silver_cdm_journal_entry`, `silver_cdm_vendor` |
| Gold | `gold_<procedure>` | `gold_journal_entry_testing`, `gold_three_way_match` |

### Valid ERP Source Identifiers
`sap`, `oracle`, `dynamics`, `netsuite`, `sage`, `epicor`, `ifs`

### Invalid Examples
- `GL_POSTINGS` — uppercase
- `bronze-sap-gl` — kebab-case
- `RawGLPostings` — PascalCase
- `bronze_client_gl` — never use "client"; use audited entity ID or system name

---

## 2. Mandatory Audit Trail Columns

### Rule
Every table at every layer MUST include these columns as the **LAST** columns in the SELECT statement. These are non-negotiable for audit evidence.

| Column | Type | Description | Required At |
|--------|------|-------------|-------------|
| `_source_system` | STRING | ERP system identifier (e.g., `sap_ecc`, `oracle_ebs`) | All layers |
| `_extraction_timestamp` | TIMESTAMP | When the record was extracted from source | All layers |
| `_pipeline_run_id` | STRING | Databricks pipeline run ID — `current_user()` + run context | All layers |
| `_record_hash` | STRING | SHA2 hash of key business fields for change detection | All layers |
| `_loaded_by` | STRING | Service principal or user who ran the pipeline | All layers |
| `_cdm_version` | STRING | Version of the CDM mapping rules applied | Silver only |
| `_mapping_rule_id` | STRING | Identifier of the source-to-target mapping rule | Silver only |

### Implementation Pattern

```sql
SELECT
  -- ... all business columns first ...

  -- Audit trail columns LAST (mandatory)
  '<erp_system>' AS _source_system,
  current_timestamp() AS _extraction_timestamp,
  concat(current_user(), '_', monotonically_increasing_id()) AS _pipeline_run_id,
  sha2(concat_ws('|', <key_cols>), 256) AS _record_hash,
  current_user() AS _loaded_by
FROM source_table;
```

---

## 3. CDM Mandatory Fields

### Rule
Every Silver table mapping to CDM must include the following engagement context fields immediately after the business key:

| Column | Type | Description |
|--------|------|-------------|
| `engagement_id` | STRING | Unique engagement identifier — must never be NULL |
| `audited_entity_id` | STRING | Identifier for the audited entity — never use free-text entity name in data |
| `financial_year` | INT | Fiscal year of the record |
| `fiscal_period` | INT | Fiscal period (1–16 for SAP, 1–12 for standard) |
| `functional_currency` | STRING(3) | ISO 4217 currency code of the audited entity's functional currency |

### ERP Source Fields to Always Preserve
The following source fields must be preserved at Bronze and passed through to Silver:

| ERP Concept | SAP Field | Oracle Field | CDM Column |
|-------------|-----------|--------------|------------|
| Document number | `BELNR` | `JE_HEADER_ID` | `source_document_number` |
| Posting date | `BUDAT` | `ACCOUNTING_DATE` | `posting_date` |
| Company code | `BUKRS` | `LEDGER_ID` | `company_code` |
| GL account | `HKONT` | `CODE_COMBINATION_ID` | `gl_account_code` |
| Amount in local currency | `DMBTR` | `ACCOUNTED_DR/CR` | `amount_lc` |
| Amount in document currency | `WRBTR` | `ENTERED_DR/CR` | `amount_dc` |
| Debit/Credit indicator | `SHKZG` | (sign of amount) | `debit_credit_indicator` |
| Cost centre | `KOSTL` | `COST_CENTER_ID` | `cost_centre_code` |
| Profit centre | `PRCTR` | `SEGMENT_ID` | `profit_centre_code` |
| Posting user | `USNAM` | `CREATED_BY` | `posted_by` |

---

## 4. Data Quality Standards

### Rule
Apply DQ checks at Silver layer only. Bronze preserves raw data exactly.

### Constraint Severity

| Severity | Action | When to Use |
|----------|--------|-------------|
| CRITICAL | `ON VIOLATION FAIL UPDATE` | CDM mandatory fields, primary keys, amounts |
| NON-CRITICAL | `ON VIOLATION DROP ROW` | Optional enrichment fields, reference data lookups |

### Mandatory Silver DQ Constraints

```sql
CONSTRAINT valid_engagement_id EXPECT (engagement_id IS NOT NULL) ON VIOLATION FAIL UPDATE,
CONSTRAINT valid_audited_entity EXPECT (audited_entity_id IS NOT NULL) ON VIOLATION FAIL UPDATE,
CONSTRAINT valid_document_number EXPECT (source_document_number IS NOT NULL) ON VIOLATION FAIL UPDATE,
CONSTRAINT valid_posting_date EXPECT (posting_date IS NOT NULL AND posting_date >= '1990-01-01') ON VIOLATION FAIL UPDATE,
CONSTRAINT valid_amount EXPECT (amount_lc IS NOT NULL) ON VIOLATION FAIL UPDATE,
CONSTRAINT valid_currency EXPECT (length(functional_currency) = 3) ON VIOLATION DROP ROW,
CONSTRAINT valid_dc_indicator EXPECT (debit_credit_indicator IN ('D', 'C', 'H', 'S')) ON VIOLATION DROP ROW
```

### Data Quality Flag Values

| Flag | Meaning |
|------|---------|
| `CLEAN` | All checks passed |
| `MISSING_AMOUNT` | Amount field is NULL |
| `INVALID_DATE` | Posting date out of expected range |
| `CURRENCY_MISMATCH` | Document currency differs from expected |
| `UNKNOWN_ACCOUNT` | GL account not found in chart of accounts |
| `DUPLICATE_DOCUMENT` | Duplicate document number detected |
| `PERIOD_MISMATCH` | Posting date does not match stated fiscal period |

---

## 5. Reconciliation Requirements

### Rule
Every Silver pipeline run must write control totals to `<schema>.reconciliation_log`. This is mandatory evidence for ISAE 3402 reporting.

### Reconciliation Log Schema

```sql
CREATE TABLE IF NOT EXISTS reconciliation_log (
  run_id          STRING,
  pipeline_name   STRING,
  layer           STRING,
  table_name      STRING,
  source_count    BIGINT,
  target_count    BIGINT,
  sum_amount_lc   DECIMAL(18,2),
  reconciled_at   TIMESTAMP,
  reconciled_by   STRING,
  status          STRING  -- 'PASS', 'BREAK', 'PENDING_REVIEW'
);
```

### Break Tolerance Policy
| Amount Range | Tolerance |
|-------------|-----------|
| < 10,000 functional currency | Zero tolerance — every unit must reconcile |
| 10,000 – 1,000,000 | 0.01% of total |
| > 1,000,000 | Must be reviewed and signed off by engagement manager |

---

## 6. Naming Convention for Non-Table Objects

| Object | Convention | Example |
|--------|-----------|---------|
| Schema | `<engagement_id>_<layer>` | `eng001_bronze`, `eng001_silver` |
| Pipeline | `<engagement_id>_erp_cdm_etl` | `eng001_erp_cdm_etl` |
| Volume (raw files) | `<engagement_id>_raw_extracts` | `eng001_raw_extracts` |
| Function | `fn_<purpose>` | `fn_hash_record`, `fn_parse_sap_date` |
| Reconciliation table | `reconciliation_log` (one per schema) | `eng001_silver.reconciliation_log` |

---

## 7. SDP Table Type Selection

| Scenario | Table Type |
|----------|------------|
| CSV/Parquet files from ERP extract | `STREAMING TABLE` |
| Reading from existing Delta staging tables | `MATERIALIZED VIEW` |
| CDC from ERP change tables | `STREAMING TABLE` with `AUTO CDC` |
| CDM-mapped output (batch) | `MATERIALIZED VIEW` |
| Aggregated audit analytical views | `MATERIALIZED VIEW` |
| Incremental journal testing (append-only) | `STREAMING TABLE` |

---

## 8. SQL Formatting Standards

| Element | Convention |
|---------|-----------|
| SQL keywords | UPPERCASE |
| Table/column names | `lowercase_snake_case` |
| Column aliases | Always explicit — no positional references |
| Monetary amounts | `CAST AS DECIMAL(18,2)` or `ROUND(..., 2)` |
| Dates | `CAST AS DATE` at Silver layer |
| String trimming | `TRIM()` on all string fields at Silver |
| Column order | Keys → Engagement context → Business fields → Derived fields → DQ flag → Audit trail |

---

## 9. Immutability Rule

### Rule
Bronze tables must NEVER be updated or deleted after initial load. They are the authoritative record of what was extracted from the source system.

- No `DELETE` or `UPDATE` operations on Bronze tables
- Re-runs must append with a new `_pipeline_run_id` or use `CREATE OR REFRESH` (which replaces)
- If source data is corrected, the correction must appear as a new record at Bronze, not an overwrite

---

## 10. Prohibited Patterns

The following are NOT permitted in any pipeline on an audit engagement:

| Prohibited | Reason |
|-----------|--------|
| Using "client" in column names, comments, or table names | Use "audited_entity" or engagement ID |
| Free-text entity name in data columns | Use `audited_entity_id` (surrogate key) |
| Hardcoded credentials or connection strings | Always use Unity Catalog secrets |
| Silent failure (no dead-letter table) | All rejected records must be logged |
| `SELECT *` at Silver or Gold layer | Explicit column list required for CDM mapping |
| In-place updates to Bronze | Bronze is immutable |
| Logging PII to pipeline logs or comments | Mask or tokenise before logging |
| Unversioned CDM mappings | `_cdm_version` column is mandatory |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-03-24 | Initial release — ERP-to-CDM audit engagement standards |
