# Demo Script — Genie Code Showcase: Retail Pipeline Standards Enforcement

**Duration:** ~20 minutes
**Persona:** Senior Data Engineer at a retail advisory firm, building a sales analytics pipeline for a UK grocery retailer

---

## Setup Before Demo

1. Open Databricks workspace: `https://adb-7405607541492599.19.azuredatabricks.net`
2. Navigate to **Workflows → Pipelines**
3. Open pipeline: `[dev] ERP-to-CDM ETL Pipeline — Genie Code Showcase`
4. Click **Edit** on any SQL file to open the pipeline editor
5. Confirm the MCP connection `lh_erp_cdm_github_mcp` is visible in the agent's tools list
6. Have the GitHub repo open in another tab: `https://github.com/famousGSC/erp-cdm-pipeline-standards`

---

## Act 1: The Problem (~3 min)

**Narrative:** "Advisory teams often build multiple pipelines across different client engagements. Without standards, every pipeline looks different — different naming conventions, missing audit columns, no consistent data quality flags. When a client asks why a number in the dashboard doesn't match their source system, it's very hard to trace without consistent lineage metadata."

**Show:**
- Open `pipelines/erp_cdm_etl.sql` to show the existing pipeline
- Point out the Bronze tables: raw source data, two audit columns at the end
- Show the Silver layer: TRIM and CAST transformations, DQ constraints, `data_quality_flag`
- Show the Gold layer: joins across silver tables, `WHERE data_quality_flag = 'CLEAN'`
- "This is what it looks like when standards are applied. Let me show you how Genie Code enforces this automatically."

---

## Act 2: Standards Stored in GitHub (~4 min)

**Narrative:** "Our team's pipeline standards live in GitHub — a single source of truth that any engineer can access. Genie Code fetches these standards at the moment it writes code. Not a static snapshot — live, versioned standards."

**Show:**
- Open `https://github.com/famousGSC/erp-cdm-pipeline-standards`
- Show `standards/erp_cdm_pipeline_standards.md` — the Bronze/Silver/Gold checklists
- Show `standards/erp_cdm_sdp_template.sql` — ready-to-use code patterns
- "The standards define exactly what a compliant pipeline looks like: naming conventions, which audit columns go where, what DQ constraints to add. The agent reads these before writing a single line of SQL."

---

## Act 3: Genie Code Fetches Standards via MCP (~5 min)

**Narrative:** "Watch what happens when I ask Genie Code to create a new Silver table. It doesn't generate generic boilerplate — it first fetches our standards from GitHub, then applies the checklist automatically."

**Prompt to type in Genie Code:**
```
Fetch the engagement standards and SDP template from GitHub
(famousGSC/erp-cdm-pipeline-standards, standards/).

Create a Silver MATERIALIZED VIEW called silver_stores from
LIVE.bronze_stores. Add DQ constraints for store_id and
store_name. Include a data_quality_flag. Follow the checklist.
```

**What to highlight:**
- The agent calls `get_file_contents` — you see it fetch the standards file in real time
- It applies the naming convention: `silver_stores` ✓
- It adds CONSTRAINT clauses with correct `ON VIOLATION` actions ✓
- It includes a `data_quality_flag` CASE expression ✓
- It adds `audit_ts` and `source_system` as the LAST two columns ✓
- It sets `quality=silver` and `delta.enableRowTracking=true` in TBLPROPERTIES ✓
- "The engineer couldn't write a non-compliant Silver table even if they wanted to."

---

## Act 4: Generate a Gold Aggregation Table (~5 min)

**Narrative:** "Now the harder part — building Gold analytics tables that join across multiple Silver sources. This is where standards enforcement really matters: filtering to clean data only, correct aggregations, consistent KPI naming."

**Prompt:**
```
Fetch the standards from GitHub and add a new Gold table called
gold_store_performance that shows total revenue, transaction count,
and revenue per sqm by store and month. Join silver_transactions,
silver_stores and silver_products. Follow Gold layer rules.
```

**Highlight:**
- Joins `LIVE.silver_transactions`, `LIVE.silver_stores`, `LIVE.silver_products` ✓
- Filters `WHERE data_quality_flag = 'CLEAN'` ✓
- `ROUND()` on all monetary amounts ✓
- `NULLIF()` for the per-sqm division ✓
- `quality=gold` in TBLPROPERTIES ✓
- `audit_ts` and `source_system` last ✓

---

## Act 5: Standards Compliance Check (~3 min)

**Narrative:** "Finally — let me show the QA review use case. Before any pipeline goes to production, a reviewer can ask the agent to check it against the standards and get a structured pass/fail report."

**Prompt:**
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

**Highlight:** The agent returns a structured compliance report — it reads the actual pipeline code and cross-references the standards checklist. This is reproducible evidence that the pipeline was reviewed against the team's published standards.

---

## Closing (~1 min)

"What we've seen: Genie Code acts as an automated senior engineer who knows your team's standards by heart. It fetches them live from GitHub, applies every checklist item, and can review any pipeline for compliance on demand. The standards are version-controlled and updated once — any engineer on any engagement automatically works to the same bar. This is how advisory data engineering scales."

---

## Appendix: Additional Prompts

**Fix a standards violation:**
```
The table below is missing its audit columns and has the wrong
TBLPROPERTIES quality tag. Fetch the standards from GitHub and fix it:

CREATE OR REFRESH MATERIALIZED VIEW transactions_clean AS
SELECT transaction_id, amount FROM LIVE.bronze_transactions;
```

**Add a channel breakdown to Gold:**
```
Fetch the standards and add a new Gold table called gold_channel_revenue
that breaks down net_revenue, transaction_count and avg_basket_value
by channel (pos / ecommerce / mobile) and month. Source from
silver_transactions. Follow Gold layer rules.
```

**Apply the sensitive data policy:**
```
Fetch the sensitive data policy from GitHub
(famousGSC/erp-cdm-pipeline-standards, standards/erp_cdm_sensitive_data_policy.md).

My silver_transactions table includes customer_id. Apply the correct
TBLPROPERTIES tags and add a comment flagging the column as containing
pseudonymised customer data.
```
