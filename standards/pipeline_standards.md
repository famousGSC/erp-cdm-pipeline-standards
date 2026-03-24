# Engagement Data Engineering Standards — SDP SQL

> **For AI Agents:** This document contains complete standards for Spark Declarative Pipelines (SDP) used on data engineering engagements. Apply these rules automatically when creating or reviewing pipeline code. No additional instructions needed.

---

## Quick Reference — Checklist by Layer

### Bronze Layer Checklist
| Requirement | How to Apply |
|-------------|--------------|
| Table name | `bronze_` prefix + `lowercase_snake_case` (e.g., `bronze_transactions`) |
| Table type | `STREAMING TABLE` for file ingestion, `MATERIALIZED VIEW` for Delta sources |
| Audit columns | Add `current_timestamp() AS audit_ts` and `'source_name' AS source_system` as **LAST** columns |
| Comment | `COMMENT "Raw <entity> data from <source>"` |
| Properties | `TBLPROPERTIES ("quality" = "bronze", "delta.enableChangeDataFeed" = "true")` |
| Constraints | `WHERE` clause for NULL filtering only — no CONSTRAINT clauses |
| Clustering | `CLUSTER BY AUTO` for STREAMING TABLEs |

### Silver Layer Checklist
| Requirement | How to Apply |
|-------------|--------------|
| Table name | `silver_` prefix + `lowercase_snake_case` (e.g., `silver_transactions`) |
| Table type | `STREAMING TABLE` or `MATERIALIZED VIEW` |
| Audit columns | `audit_ts` and `source_system` as **LAST** columns |
| Comment | `COMMENT "Cleaned and validated <entity> with derived metrics"` |
| Properties | Add `"delta.enableRowTracking" = "true"` |
| Constraints | `CONSTRAINT` clauses with `ON VIOLATION FAIL UPDATE` (critical) or `ON VIOLATION DROP ROW` (non-critical) |
| Transformations | Apply `TRIM()`, `CAST()`, `INITCAP()`, add derived fields |
| Data quality flag | `data_quality_flag` column using CASE expression |

### Gold Layer Checklist
| Requirement | How to Apply |
|-------------|--------------|
| Table name | `gold_` prefix + `lowercase_snake_case` (e.g., `gold_daily_sales`) |
| Table type | `STREAMING TABLE` or `MATERIALIZED VIEW` |
| Audit columns | `audit_ts` and `source_system` as **LAST** columns |
| Comment | `COMMENT "Business aggregation for <use case>"` |
| Properties | `TBLPROPERTIES ("quality" = "gold", "delta.enableChangeDataFeed" = "true")` |
| Aggregations | `ROUND()` for financials, `NULLIF()` for division, `COALESCE()` for NULLs |
| Joins | `INNER JOIN` or `LEFT JOIN` with `LIVE.table_name` |
| Clustering | `CLUSTER BY AUTO` for STREAMING TABLEs |

---

## 1. Table Naming Convention

All table names MUST use `lowercase_snake_case` with the appropriate layer prefix.

| Layer | Prefix | Example |
|-------|--------|---------|
| Bronze | `bronze_` | `bronze_transactions` |
| Silver | `silver_` | `silver_products` |
| Gold | `gold_` | `gold_daily_sales_summary` |

**Valid:** `bronze_transactions`, `silver_products`, `gold_category_performance`
**Invalid:** `RawTransactions`, `SILVER_PRODUCTS`, `transactions` (no prefix), `gold-sales` (kebab-case)

---

## 2. Required Audit Columns

Every table MUST include these two columns as the **LAST** columns in the SELECT:

| Column | Type | Description |
|--------|------|-------------|
| `audit_ts` | TIMESTAMP | When the record was processed by the pipeline |
| `source_system` | STRING | Origin system identifier |

```sql
SELECT
  -- ... all business columns first ...

  -- Audit columns LAST
  current_timestamp() AS audit_ts,
  'source_system_name'  AS source_system
FROM source_table;
```

### `source_system` Values by Layer

| Layer | Value | Example Source |
|-------|-------|---------------|
| Bronze | `pos`, `ecommerce`, `product_catalog`, `inventory` | Point of sale, web, catalog system |
| Silver | `silver_transformation` | Silver processing layer |
| Gold | `gold_aggregation` | Gold aggregation layer |

---

## 3. SDP Table Types

| Type | When to Use |
|------|-------------|
| `STREAMING TABLE` | File ingestion (CSV/Parquet), CDC, append-only sources |
| `MATERIALIZED VIEW` | Existing Delta tables, aggregations, joins |
| `LIVE.table_name` | Referencing tables within the same pipeline |

---

## 4. Data Quality Constraints

**Bronze:** `WHERE` clause only — preserve raw data.
**Silver:** `CONSTRAINT` clauses with explicit violation handling.
**Gold:** No constraints — data already validated upstream.

| Action | Use Case |
|--------|----------|
| `ON VIOLATION DROP ROW` | Non-critical — silently filter bad rows |
| `ON VIOLATION FAIL UPDATE` | Critical — halt pipeline on failure |

```sql
-- Silver DQ example
CREATE OR REFRESH MATERIALIZED VIEW silver_transactions (
  CONSTRAINT valid_id     EXPECT (transaction_id IS NOT NULL) ON VIOLATION FAIL UPDATE,
  CONSTRAINT valid_amount EXPECT (amount >= 0)                ON VIOLATION DROP ROW
)
```

---

## 5. Table Properties

| Layer | Required TBLPROPERTIES |
|-------|------------------------|
| Bronze | `"quality" = "bronze"`, `"delta.enableChangeDataFeed" = "true"` |
| Silver | `"quality" = "silver"`, `"delta.enableChangeDataFeed" = "true"`, `"delta.enableRowTracking" = "true"` |
| Gold | `"quality" = "gold"`, `"delta.enableChangeDataFeed" = "true"` |

---

## 6. Comments

Every table MUST have a `COMMENT`:

| Layer | Template |
|-------|----------|
| Bronze | `COMMENT "Raw <entity> data from <source system>"` |
| Silver | `COMMENT "Cleaned and validated <entity> with derived metrics"` |
| Gold | `COMMENT "<Business metric/aggregation> for <use case>"` |

---

## 7. Complete Layer Patterns

### Bronze — STREAMING TABLE (file ingestion)
```sql
CREATE OR REFRESH STREAMING TABLE bronze_transactions
CLUSTER BY AUTO
COMMENT "Raw sales transactions from POS systems"
TBLPROPERTIES ("quality" = "bronze", "delta.enableChangeDataFeed" = "true")
AS SELECT
  *,
  current_timestamp() AS audit_ts,
  'pos'               AS source_system
FROM STREAM read_files(
  '${volume_path}/transactions/*.csv',
  format => 'csv', header => true
)
WHERE transaction_id IS NOT NULL;
```

### Bronze — MATERIALIZED VIEW (Delta source)
```sql
CREATE OR REFRESH MATERIALIZED VIEW bronze_products
COMMENT "Raw product catalog from master data system"
TBLPROPERTIES ("quality" = "bronze", "delta.enableChangeDataFeed" = "true")
AS SELECT
  *,
  current_timestamp() AS audit_ts,
  'product_catalog'   AS source_system
FROM ${catalog}.${schema}.raw_products
WHERE product_id IS NOT NULL;
```

### Silver — full validation with derived fields
```sql
CREATE OR REFRESH MATERIALIZED VIEW silver_transactions (
  CONSTRAINT valid_id       EXPECT (transaction_id IS NOT NULL)       ON VIOLATION FAIL UPDATE,
  CONSTRAINT valid_product  EXPECT (product_id IS NOT NULL)            ON VIOLATION FAIL UPDATE,
  CONSTRAINT valid_quantity EXPECT (quantity > 0)                      ON VIOLATION DROP ROW,
  CONSTRAINT valid_amount   EXPECT (amount >= 0)                       ON VIOLATION DROP ROW
)
COMMENT "Cleaned and validated sales transactions with net amount and data quality flag"
TBLPROPERTIES (
  "quality"                    = "silver",
  "delta.enableChangeDataFeed" = "true",
  "delta.enableRowTracking"    = "true"
)
AS SELECT
  TRIM(transaction_id)           AS transaction_id,
  TRIM(product_id)               AS product_id,
  CAST(quantity   AS INT)        AS quantity,
  CAST(amount     AS DOUBLE)     AS amount,
  CAST(discount   AS DOUBLE)     AS discount,
  ROUND(amount - COALESCE(discount, 0), 2)  AS net_amount,
  CASE
    WHEN quantity IS NULL THEN 'MISSING_QUANTITY'
    WHEN amount   < 0     THEN 'NEGATIVE_AMOUNT'
    ELSE 'CLEAN'
  END                            AS data_quality_flag,
  current_timestamp()            AS audit_ts,
  'silver_transformation'        AS source_system
FROM LIVE.bronze_transactions;
```

### Gold — business aggregation
```sql
CREATE OR REFRESH MATERIALIZED VIEW gold_daily_sales_summary
COMMENT "Daily sales KPIs by store and category for retail analytics"
TBLPROPERTIES ("quality" = "gold", "delta.enableChangeDataFeed" = "true")
AS SELECT
  t.sale_date,
  s.store_name,
  s.region,
  p.category,
  COUNT(DISTINCT t.transaction_id)       AS transaction_count,
  SUM(t.quantity)                         AS units_sold,
  ROUND(SUM(t.net_amount), 2)            AS net_revenue,
  ROUND(AVG(t.net_amount), 2)            AS avg_basket_value,
  ROUND(SUM(t.net_amount) / NULLIF(COUNT(DISTINCT t.transaction_id), 0), 2) AS revenue_per_transaction,
  current_timestamp()                    AS audit_ts,
  'gold_aggregation'                     AS source_system
FROM LIVE.silver_transactions t
INNER JOIN LIVE.silver_stores   s ON t.store_id   = s.store_id
INNER JOIN LIVE.silver_products p ON t.product_id = p.product_id
GROUP BY t.sale_date, s.store_name, s.region, p.category;
```

---

## 8. SQL Formatting

| Element | Convention |
|---------|-----------|
| Keywords | UPPERCASE (`SELECT`, `FROM`, `WHERE`, `AS`) |
| Names | `lowercase_snake_case` |
| Financials | `ROUND(expr, 2)` |
| Division | `NULLIF(denominator, 0)` to prevent divide-by-zero |
| NULLs | `COALESCE(col, default)` |
| Column order | Keys → Dimensions → Measures → Derived fields → DQ flag → **Audit columns last** |

---

## 9. Joins and References

```sql
-- Pipeline tables: use LIVE. prefix
FROM LIVE.silver_transactions t
INNER JOIN LIVE.silver_products p ON t.product_id = p.product_id

-- External tables: fully qualified name
FROM lh_vm_stable.advisory_demo.raw_transactions
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-03-24 | Initial release — retail advisory engagement standards |
