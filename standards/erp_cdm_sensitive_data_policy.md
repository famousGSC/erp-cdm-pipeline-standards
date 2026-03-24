# ERP-to-CDM Sensitive Data Policy

> **For AI Agents:** Apply these rules whenever creating or reviewing tables that contain financial, personal, or commercially sensitive data from audited entity ERP systems. These standards ensure compliance with engagement confidentiality obligations and data protection regulations (GDPR, CCPA, local equivalents).

---

## Quick Reference — Sensitivity Classification

| Classification | Examples | Required Action |
|---------------|---------|-----------------|
| RESTRICTED | TINs, bank accounts, payroll amounts, board-level compensation | Masking mandatory; no Gold exposure |
| CONFIDENTIAL | GL account codes, vendor names, employee IDs, contract values | Column tagging mandatory |
| INTERNAL | Cost centres, profit centres, GL descriptions | Standard access control sufficient |
| PUBLIC | Currency codes, date dimensions, standardised CDM codes | No special handling |

---

## 1. Financial Data Sensitivity Types

### Tier 1 — RESTRICTED (Highest Sensitivity)

| Data Type | UC Tag | ERP Source Fields | Handling |
|-----------|--------|-------------------|---------|
| Tax Identification Number (TIN/VAT) | `class.tax_id` | SAP: `STCEG`, Oracle: `TAX_REGISTRATION_NUMBER` | Mask to last 4 digits only |
| Bank account number | `class.bank_account` | SAP: `BANKN`, Oracle: `BANK_ACCOUNT_NUM` | Tokenise; never expose in Gold |
| Sort code / routing number | `class.bank_routing` | SAP: `BANKL`, Oracle: `ROUTING_NUM` | Tokenise |
| Payroll amount | `class.compensation` | SAP: `LGART`/`BETRG`, Oracle: `PAY_VALUE` | Aggregate only in Gold; no individual rows |
| Senior executive compensation | `class.executive_comp` | HR tables | Exclude from pipeline entirely; manual process |
| Audited entity board minutes references | `class.board_data` | Any source | Do not ingest; flag for manual review |

### Tier 2 — CONFIDENTIAL

| Data Type | UC Tag | Handling |
|-----------|--------|---------|
| Vendor / supplier name | `class.vendor_name` | Tag column; restrict Gold access by role |
| Employee name | `class.employee_name` | Tag column; mask in Gold aggregations |
| Employee ID | `class.employee_id` | Tag column; hash in Gold |
| Contract / PO value | `class.contract_value` | Tag column; aggregate only in Gold |
| GL account description | `class.gl_description` | Tag column; include in Silver, aggregate in Gold |
| Profit centre description | `class.cost_centre_desc` | Tag column |

---

## 2. PII Detection Patterns

**For AI Agents:** When reviewing column names in ERP extract schemas, automatically classify the following patterns:

| Column Name Pattern | Sensitivity | Action |
|--------------------|-------------|--------|
| `*tin*`, `*vat*`, `*tax_reg*` | RESTRICTED | Apply masking + UC tag |
| `*bank_account*`, `*iban*`, `*sort_code*` | RESTRICTED | Tokenise + UC tag |
| `*salary*`, `*wage*`, `*compensation*`, `*payroll*` | RESTRICTED | Aggregate only; no row-level Gold |
| `*employee_name*`, `*emp_name*`, `*staff_name*` | CONFIDENTIAL | UC tag + mask in Gold |
| `*employee_id*`, `*emp_id*`, `*staff_id*` | CONFIDENTIAL | UC tag + hash in Gold |
| `*vendor_name*`, `*supplier_name*` | CONFIDENTIAL | UC tag |
| `*email*` | CONFIDENTIAL | UC tag + mask |
| `*phone*`, `*mobile*`, `*tel*` | CONFIDENTIAL | UC tag + mask |
| `*posted_by*`, `*created_by*`, `*changed_by*` | CONFIDENTIAL | UC tag (user tracking) |
| `*ip_address*` | CONFIDENTIAL | UC tag |

---

## 3. Required Table-Level Properties for Sensitive Data

### If a table contains RESTRICTED data:

```sql
TBLPROPERTIES (
  "contains_restricted_data" = "true",
  "data_sensitivity" = "restricted",
  "masking_applied" = "true",
  "engagement.data_classification" = "restricted"
)
COMMENT "[RESTRICTED DATA] <description> — Masking applied per ERP-CDM Sensitive Data Policy v1.0"
```

### If a table contains CONFIDENTIAL data:

```sql
TBLPROPERTIES (
  "contains_confidential_data" = "true",
  "data_sensitivity" = "confidential",
  "engagement.data_classification" = "confidential"
)
COMMENT "[CONFIDENTIAL] <description> — Column-level tagging applied"
```

---

## 4. Masking and Tokenisation Patterns

### Tax Identification Numbers
```sql
-- Show last 4 characters only, mask remainder
regexp_replace(tin, '.(?=.{4})', 'X') AS tin_masked
```

### Bank Account Numbers
```sql
-- Replace with SHA2 token — never expose in analytics layer
sha2(bank_account_number, 256) AS bank_account_token
```

### Employee Names
```sql
-- Gold layer: replace with role/department
CASE WHEN _data_sensitivity = 'restricted' THEN 'REDACTED'
     ELSE CONCAT(LEFT(first_name, 1), '. ', last_name)
END AS employee_display_name
```

### Monetary Amounts for Senior Executives
```sql
-- Do not produce row-level records; aggregate only
-- Gold analytical view must use SUM/AVG with minimum group size of 5
CASE WHEN COUNT(*) OVER (PARTITION BY cost_centre_code) < 5
     THEN NULL  -- suppress small groups
     ELSE ROUND(SUM(amount_lc), -3)  -- round to nearest 1000
END AS payroll_amount_banded
```

---

## 5. Audited Entity Data Isolation

### Rule
Data from different audited entities MUST be physically isolated into separate schemas. Shared tables are not permitted.

```
<engagement_id>_bronze   -- One schema per engagement
<engagement_id>_silver
<engagement_id>_gold
```

Sharing data across engagement schemas is a confidentiality breach. Unity Catalog row filters must enforce `engagement_id = current_engagement_id()` on any cross-engagement views.

---

## 6. Engagement Data Retention

### Rule
Pipeline data must not be retained beyond the engagement retention period defined in the engagement letter. Tables must include:

```sql
TBLPROPERTIES (
  "engagement.retention_date" = "<yyyy-mm-dd>",
  "engagement.id" = "<engagement_id>",
  "engagement.audited_entity_id" = "<ae_id>"
)
```

At retention date, the entire engagement schema must be dropped. No manual selective deletion is permitted.

---

## 7. Access Control Requirements

| Layer | Who Can Access | How |
|-------|---------------|-----|
| Bronze | Pipeline service principal only | Unity Catalog grants |
| Silver (full) | Engagement data lead + QA reviewer | Role-based UC grant |
| Silver (masked) | All engagement team members | Dynamic view with masking |
| Gold | All engagement team members | Standard UC grant |
| Gold (restricted fields) | Data lead only | Column-level masking policy |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-03-24 | Initial release |
