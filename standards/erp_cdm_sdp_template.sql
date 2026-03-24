-- ============================================================
-- ERP-to-CDM SDP SQL Template
-- Professional Services Audit Engagements
-- Version 1.0 | 2026-03-24
-- ============================================================
-- USAGE: Replace all <placeholder> values before deploying.
-- Engagement ID: replace <eng_id> with your engagement identifier
-- ERP Source:    replace <erp> with sap / oracle / dynamics / netsuite
-- Entity:        replace <entity> with gl_postings / ap_invoices / etc.
-- ============================================================

-- ============================================================
-- BRONZE TEMPLATE: Raw ERP File Extract (Auto Loader / CSV)
-- ============================================================
CREATE OR REFRESH STREAMING TABLE bronze_<erp>_<entity>
CLUSTER BY AUTO
COMMENT "Raw <entity> extract from <ERP system> — <eng_id> engagement. Immutable raw zone."
TBLPROPERTIES (
  "quality"                          = "bronze",
  "engagement.layer"                 = "raw",
  "engagement.id"                    = "<eng_id>",
  "engagement.audited_entity_id"     = "<ae_id>",
  "delta.enableChangeDataFeed"       = "true"
)
AS SELECT
  *,
  -- Audit trail columns — ALWAYS LAST
  '<erp>_<system_identifier>'                                         AS _source_system,
  current_timestamp()                                                  AS _extraction_timestamp,
  concat(current_user(), '_', monotonically_increasing_id())           AS _pipeline_run_id,
  sha2(concat_ws('|', <key_col_1>, <key_col_2>), 256)                AS _record_hash,
  current_user()                                                       AS _loaded_by
FROM STREAM read_files(
  '${volume_path}/<entity>/*.csv',
  format  => 'csv',
  header  => true
)
WHERE <primary_key_col> IS NOT NULL;  -- Minimal Bronze filtering only


-- ============================================================
-- BRONZE TEMPLATE: Raw ERP Extract from Delta Source
-- ============================================================
CREATE OR REFRESH MATERIALIZED VIEW bronze_<erp>_<entity>
COMMENT "Raw <entity> extract from <ERP system> Delta staging — <eng_id> engagement. Immutable raw zone."
TBLPROPERTIES (
  "quality"                          = "bronze",
  "engagement.layer"                 = "raw",
  "engagement.id"                    = "<eng_id>",
  "engagement.audited_entity_id"     = "<ae_id>",
  "delta.enableChangeDataFeed"       = "true"
)
AS SELECT
  *,
  '<erp>_<system_identifier>'                                         AS _source_system,
  current_timestamp()                                                  AS _extraction_timestamp,
  concat(current_user(), '_', monotonically_increasing_id())           AS _pipeline_run_id,
  sha2(concat_ws('|', <key_col_1>, <key_col_2>), 256)                AS _record_hash,
  current_user()                                                       AS _loaded_by
FROM <catalog>.<staging_schema>.<source_table>
WHERE <primary_key_col> IS NOT NULL;


-- ============================================================
-- SILVER TEMPLATE: CDM-Mapped GL Journal Entries
-- ============================================================
CREATE OR REFRESH MATERIALIZED VIEW silver_cdm_journal_entry (
  -- CDM mandatory fields — halt pipeline if invalid
  CONSTRAINT valid_engagement_id      EXPECT (engagement_id IS NOT NULL)          ON VIOLATION FAIL UPDATE,
  CONSTRAINT valid_audited_entity     EXPECT (audited_entity_id IS NOT NULL)       ON VIOLATION FAIL UPDATE,
  CONSTRAINT valid_document_number    EXPECT (source_document_number IS NOT NULL)  ON VIOLATION FAIL UPDATE,
  CONSTRAINT valid_posting_date       EXPECT (posting_date IS NOT NULL
                                              AND posting_date >= '1990-01-01')    ON VIOLATION FAIL UPDATE,
  CONSTRAINT valid_gl_account         EXPECT (gl_account_code IS NOT NULL)         ON VIOLATION FAIL UPDATE,
  CONSTRAINT valid_amount             EXPECT (amount_lc IS NOT NULL)               ON VIOLATION FAIL UPDATE,
  -- Non-critical fields — filter bad rows
  CONSTRAINT valid_dc_indicator       EXPECT (debit_credit_indicator IN ('D','C','H','S')) ON VIOLATION DROP ROW,
  CONSTRAINT valid_currency           EXPECT (length(functional_currency) = 3)     ON VIOLATION DROP ROW,
  CONSTRAINT valid_fiscal_period      EXPECT (fiscal_period BETWEEN 1 AND 16)      ON VIOLATION DROP ROW
)
COMMENT "CDM-mapped GL journal entries. Source: <erp>.<source_table>. Mapping: CDM-MAP-GL-v1.0. [<eng_id>]"
TBLPROPERTIES (
  "quality"                          = "silver",
  "engagement.layer"                 = "conformed",
  "engagement.id"                    = "<eng_id>",
  "engagement.audited_entity_id"     = "<ae_id>",
  "delta.enableChangeDataFeed"       = "true",
  "delta.enableRowTracking"          = "true",
  "pipelines.autoOptimize.zOrderCols"= "posting_date,gl_account_code"
)
AS SELECT
  -- Engagement context (mandatory CDM fields)
  '<eng_id>'                                                           AS engagement_id,
  '<ae_id>'                                                            AS audited_entity_id,
  CAST(<financial_year_col> AS INT)                                    AS financial_year,
  CAST(<fiscal_period_col>  AS INT)                                    AS fiscal_period,

  -- Document identifiers
  TRIM(<document_number_col>)                                          AS source_document_number,
  TRIM(<line_item_col>)                                                AS source_line_item,
  TRIM(<reference_col>)                                                AS document_reference,

  -- Dates
  CAST(<posting_date_col>   AS DATE)                                   AS posting_date,
  CAST(<document_date_col>  AS DATE)                                   AS document_date,
  CAST(<entry_date_col>     AS DATE)                                   AS entry_date,

  -- Account coding
  TRIM(<company_code_col>)                                             AS company_code,
  TRIM(<gl_account_col>)                                               AS gl_account_code,
  TRIM(<cost_centre_col>)                                              AS cost_centre_code,
  TRIM(<profit_centre_col>)                                            AS profit_centre_code,

  -- Amounts
  CAST(<amount_lc_col>      AS DECIMAL(18,2))                          AS amount_lc,
  CAST(<amount_dc_col>      AS DECIMAL(18,2))                          AS amount_dc,
  UPPER(TRIM(<currency_col>))                                          AS functional_currency,
  UPPER(TRIM(<doc_currency_col>))                                      AS document_currency,

  -- Debit/Credit
  UPPER(TRIM(<dc_indicator_col>))                                      AS debit_credit_indicator,

  -- Description
  TRIM(<description_col>)                                              AS journal_description,
  TRIM(<posting_key_col>)                                              AS posting_key,
  TRIM(<transaction_type_col>)                                         AS transaction_type,

  -- User (CONFIDENTIAL — tagged in UC)
  TRIM(<posted_by_col>)                                                AS posted_by,  -- [CONFIDENTIAL: class.employee_id]

  -- Data quality flag
  CASE
    WHEN <amount_lc_col> IS NULL                          THEN 'MISSING_AMOUNT'
    WHEN CAST(<posting_date_col> AS DATE) > CURRENT_DATE  THEN 'FUTURE_DATE'
    WHEN CAST(<amount_lc_col> AS DECIMAL(18,2)) = 0       THEN 'ZERO_AMOUNT'
    WHEN <description_col> IS NULL
      OR TRIM(<description_col>) = ''                     THEN 'MISSING_DESCRIPTION'
    ELSE 'CLEAN'
  END                                                                  AS _data_quality_flag,

  -- Audit trail (ALWAYS LAST)
  '<erp>_gl'                                                           AS _source_system,
  current_timestamp()                                                  AS _extraction_timestamp,
  concat(current_user(), '_', monotonically_increasing_id())           AS _pipeline_run_id,
  sha2(concat_ws('|', <document_number_col>, <line_item_col>), 256)   AS _record_hash,
  current_user()                                                       AS _loaded_by,
  '1.0'                                                                AS _cdm_version,
  'CDM-MAP-GL-v1.0'                                                    AS _mapping_rule_id

FROM LIVE.bronze_<erp>_<entity>;


-- ============================================================
-- SILVER TEMPLATE: CDM-Mapped Vendor / Supplier Master
-- ============================================================
CREATE OR REFRESH MATERIALIZED VIEW silver_cdm_vendor (
  CONSTRAINT valid_engagement_id  EXPECT (engagement_id IS NOT NULL)         ON VIOLATION FAIL UPDATE,
  CONSTRAINT valid_vendor_id      EXPECT (source_vendor_id IS NOT NULL)       ON VIOLATION FAIL UPDATE,
  CONSTRAINT valid_country        EXPECT (country_code IS NOT NULL)           ON VIOLATION DROP ROW
)
COMMENT "CDM-mapped vendor master. Source: <erp>.<vendor_table>. Mapping: CDM-MAP-VEND-v1.0. [<eng_id>]"
TBLPROPERTIES (
  "quality"                      = "silver",
  "engagement.layer"             = "conformed",
  "engagement.id"                = "<eng_id>",
  "contains_confidential_data"   = "true",
  "data_sensitivity"             = "confidential",
  "delta.enableChangeDataFeed"   = "true",
  "delta.enableRowTracking"      = "true"
)
AS SELECT
  '<eng_id>'                                                           AS engagement_id,
  '<ae_id>'                                                            AS audited_entity_id,
  TRIM(<vendor_id_col>)                                                AS source_vendor_id,
  TRIM(<vendor_name_col>)                                              AS vendor_name,  -- [CONFIDENTIAL: class.vendor_name]
  TRIM(<country_col>)                                                  AS country_code,
  TRIM(<tax_id_col>)                                                   AS tax_id_masked,  -- [RESTRICTED: class.tax_id] — masking applied below
  regexp_replace(TRIM(<tax_id_col>), '.(?=.{4})', 'X')                AS tax_id_masked,
  CAST(<payment_terms_col> AS INT)                                     AS payment_terms_days,
  TRIM(<vendor_type_col>)                                              AS vendor_type,
  CASE
    WHEN <vendor_name_col> IS NULL THEN 'MISSING_NAME'
    WHEN <tax_id_col> IS NULL      THEN 'MISSING_TAX_ID'
    ELSE 'CLEAN'
  END                                                                  AS _data_quality_flag,
  '<erp>_vendor'                                                       AS _source_system,
  current_timestamp()                                                  AS _extraction_timestamp,
  concat(current_user(), '_', monotonically_increasing_id())           AS _pipeline_run_id,
  sha2(TRIM(<vendor_id_col>), 256)                                    AS _record_hash,
  current_user()                                                       AS _loaded_by,
  '1.0'                                                                AS _cdm_version,
  'CDM-MAP-VEND-v1.0'                                                  AS _mapping_rule_id
FROM LIVE.bronze_<erp>_vendor_master;


-- ============================================================
-- GOLD TEMPLATE: Journal Entry Testing — All Journals by Period
-- ============================================================
CREATE OR REFRESH MATERIALIZED VIEW gold_journal_entry_testing
COMMENT "Analytical view for journal entry testing procedure — <ae_id> engagement. No PII."
TBLPROPERTIES (
  "quality"              = "gold",
  "engagement.layer"     = "analytical",
  "engagement.id"        = "<eng_id>",
  "delta.enableChangeDataFeed" = "true"
)
AS SELECT
  -- Dimensions
  j.engagement_id,
  j.audited_entity_id,
  j.financial_year,
  j.fiscal_period,
  j.posting_date,
  j.company_code,
  j.gl_account_code,
  a.account_description,
  a.account_type,           -- e.g., ASSET, LIABILITY, EQUITY, REVENUE, EXPENSE
  a.financial_statement_line,
  j.cost_centre_code,
  j.transaction_type,
  j.posting_key,
  j.document_currency,
  j.functional_currency,
  j.debit_credit_indicator,

  -- Risk indicators for audit testing
  CASE WHEN j.posting_date = j.entry_date  THEN 'SAME_DAY'
       WHEN j.posting_date < j.entry_date  THEN 'BACKDATED'
       WHEN j.posting_date > j.entry_date  THEN 'FORWARD_DATED'
  END                                                                  AS posting_timing_flag,
  CASE WHEN j.document_currency != j.functional_currency THEN TRUE
       ELSE FALSE
  END                                                                  AS is_foreign_currency,
  CASE WHEN CAST(ROUND(ABS(j.amount_lc), 0) AS BIGINT) % 1000 = 0
       THEN TRUE ELSE FALSE
  END                                                                  AS is_round_number,  -- Risk flag for JE testing

  -- Volume metrics
  COUNT(*)                                                             OVER w AS postings_by_account_period,
  ROUND(SUM(j.amount_lc)  OVER w, 2)                                  AS net_amount_by_account_period,

  -- Individual line amounts
  ROUND(j.amount_lc, 2)                                               AS amount_lc,
  ROUND(j.amount_dc, 2)                                               AS amount_dc,

  -- Audit trail
  j._source_system,
  j._extraction_timestamp,
  j._pipeline_run_id,
  j._cdm_version,
  current_timestamp()                                                  AS _extraction_timestamp,
  concat(current_user(), '_', monotonically_increasing_id())           AS _pipeline_run_id,
  sha2(concat_ws('|', j.source_document_number, j.source_line_item), 256) AS _record_hash,
  current_user()                                                       AS _loaded_by

FROM LIVE.silver_cdm_journal_entry j
LEFT JOIN LIVE.silver_cdm_chart_of_accounts a
  ON j.gl_account_code = a.gl_account_code
 AND j.engagement_id   = a.engagement_id

WINDOW w AS (
  PARTITION BY j.engagement_id, j.gl_account_code, j.fiscal_period
);


-- ============================================================
-- GOLD TEMPLATE: Three-Way Match for AP Invoice Testing
-- ============================================================
CREATE OR REFRESH MATERIALIZED VIEW gold_three_way_match
COMMENT "AP three-way match (invoice / PO / GR) for accounts payable testing — <ae_id> engagement."
TBLPROPERTIES (
  "quality"              = "gold",
  "engagement.layer"     = "analytical",
  "engagement.id"        = "<eng_id>",
  "delta.enableChangeDataFeed" = "true"
)
AS SELECT
  i.engagement_id,
  i.audited_entity_id,
  i.financial_year,
  i.source_document_number                                             AS invoice_number,
  i.posting_date                                                       AS invoice_date,
  ROUND(i.amount_lc, 2)                                               AS invoice_amount_lc,
  v.vendor_name,
  p.po_number,
  ROUND(p.po_amount_lc, 2)                                            AS po_amount_lc,
  g.gr_number,
  ROUND(g.gr_amount_lc, 2)                                            AS gr_amount_lc,

  -- Match status
  CASE
    WHEN p.po_number IS NULL AND g.gr_number IS NULL THEN 'NO_MATCH'
    WHEN p.po_number IS NULL                          THEN 'INVOICE_ONLY_NO_PO'
    WHEN g.gr_number IS NULL                          THEN 'NO_GOODS_RECEIPT'
    WHEN ABS(i.amount_lc - p.po_amount_lc) > 0.01   THEN 'AMOUNT_VARIANCE'
    ELSE 'THREE_WAY_MATCH'
  END                                                                  AS match_status,

  -- Variance
  ROUND(i.amount_lc - COALESCE(p.po_amount_lc, 0), 2)                AS invoice_po_variance,

  current_timestamp()                                                  AS _extraction_timestamp,
  concat(current_user(), '_', monotonically_increasing_id())           AS _pipeline_run_id,
  sha2(i.source_document_number, 256)                                  AS _record_hash,
  current_user()                                                       AS _loaded_by

FROM LIVE.silver_cdm_journal_entry i
LEFT JOIN LIVE.silver_cdm_vendor v
  ON i.audited_entity_id = v.audited_entity_id
 AND i.engagement_id     = v.engagement_id
LEFT JOIN LIVE.silver_cdm_purchase_order p
  ON i.source_document_number = p.invoice_reference
 AND i.engagement_id          = p.engagement_id
LEFT JOIN LIVE.silver_cdm_goods_receipt g
  ON p.po_number       = g.po_number
 AND i.engagement_id   = g.engagement_id
WHERE i.transaction_type = 'VENDOR_INVOICE';
