-- ============================================================
-- Engagement SDP SQL Template — Retail Data Pipelines
-- Version 1.0 | 2026-03-24
-- ============================================================
-- Replace <placeholders> before deploying.
-- ============================================================

-- ============================================================
-- BRONZE: File Ingestion (STREAMING TABLE)
-- ============================================================
CREATE OR REFRESH STREAMING TABLE bronze_<entity>
CLUSTER BY AUTO
COMMENT "Raw <entity> data from <source system>"
TBLPROPERTIES ("quality" = "bronze", "delta.enableChangeDataFeed" = "true")
AS SELECT
  *,
  current_timestamp() AS audit_ts,
  '<source_system>'   AS source_system
FROM STREAM read_files(
  '${volume_path}/<entity>/*.csv',
  format => 'csv', header => true
)
WHERE <primary_key> IS NOT NULL;


-- ============================================================
-- BRONZE: Delta Source (MATERIALIZED VIEW)
-- ============================================================
CREATE OR REFRESH MATERIALIZED VIEW bronze_<entity>
COMMENT "Raw <entity> data from <source catalog>"
TBLPROPERTIES ("quality" = "bronze", "delta.enableChangeDataFeed" = "true")
AS SELECT
  *,
  current_timestamp() AS audit_ts,
  '<source_system>'   AS source_system
FROM ${catalog}.${schema}.<raw_table>
WHERE <primary_key> IS NOT NULL;


-- ============================================================
-- SILVER: Validated with DQ Constraints
-- ============================================================
CREATE OR REFRESH MATERIALIZED VIEW silver_<entity> (
  CONSTRAINT valid_pk     EXPECT (<primary_key> IS NOT NULL) ON VIOLATION FAIL UPDATE,
  CONSTRAINT valid_amount EXPECT (amount >= 0)               ON VIOLATION DROP ROW
)
COMMENT "Cleaned and validated <entity> with derived metrics"
TBLPROPERTIES (
  "quality"                    = "silver",
  "delta.enableChangeDataFeed" = "true",
  "delta.enableRowTracking"    = "true"
)
AS SELECT
  TRIM(<id_col>)              AS <id_col>,
  INITCAP(TRIM(<name_col>))   AS <name_col>,
  CAST(<amount_col> AS DOUBLE) AS <amount_col>,
  ROUND(<derived_field>, 2)   AS <derived_field>,
  CASE
    WHEN <amount_col> IS NULL THEN 'MISSING_AMOUNT'
    WHEN <amount_col> < 0     THEN 'NEGATIVE_AMOUNT'
    ELSE 'CLEAN'
  END                         AS data_quality_flag,
  current_timestamp()         AS audit_ts,
  'silver_transformation'     AS source_system
FROM LIVE.bronze_<entity>;


-- ============================================================
-- GOLD: Business Aggregation
-- ============================================================
CREATE OR REFRESH MATERIALIZED VIEW gold_<aggregation>
COMMENT "<Business metric> for <use case>"
TBLPROPERTIES ("quality" = "gold", "delta.enableChangeDataFeed" = "true")
AS SELECT
  <dimension_cols>,
  COUNT(DISTINCT <id_col>)            AS record_count,
  ROUND(SUM(<amount_col>), 2)         AS total_amount,
  ROUND(AVG(<amount_col>), 2)         AS avg_amount,
  ROUND(SUM(<amount_col>) / NULLIF(COUNT(DISTINCT <id_col>), 0), 2) AS amount_per_record,
  current_timestamp()                 AS audit_ts,
  'gold_aggregation'                  AS source_system
FROM LIVE.silver_<entity> t
INNER JOIN LIVE.silver_<ref_entity> r ON t.<fk_col> = r.<pk_col>
GROUP BY <dimension_cols>;
