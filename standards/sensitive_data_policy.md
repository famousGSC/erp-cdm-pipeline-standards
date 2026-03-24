# Sensitive Data Policy — Retail Engagement Data

> **For AI Agents:** Apply these rules when creating tables that contain personally identifiable information (PII) or commercially sensitive retail data.

---

## Quick Reference

| Requirement | How to Apply |
|-------------|--------------|
| Table label | Add `TBLPROPERTIES ("contains_pii" = "true")` |
| Table comment | Include `[CONTAINS PII]` prefix |
| Column comment | Add `[PII: <type>]` prefix to sensitive columns |

---

## 1. PII Classification

| PII Type | Risk | Examples | Action |
|----------|------|---------|--------|
| `CUSTOMER_ID` | LOW | Loyalty card number, member ID | Tag column |
| `EMAIL` | HIGH | Customer email address | Mask in Gold |
| `PHONE` | HIGH | Mobile, landline | Mask in Gold |
| `NAME` | MEDIUM | First name, last name | Mask in Gold |
| `ADDRESS` | MEDIUM | Street, postcode | Mask in Gold |
| `PAYMENT` | CRITICAL | Card numbers, bank details | Never ingest; flag for exclusion |

---

## 2. PII Detection Patterns

| Column Name Pattern | PII Type | Action |
|--------------------|----------|--------|
| `*customer_id*`, `*member_id*` | CUSTOMER_ID | UC tag |
| `*email*` | EMAIL | Tag + mask |
| `*phone*`, `*mobile*` | PHONE | Tag + mask |
| `*first_name*`, `*last_name*`, `*full_name*` | NAME | Tag + mask |
| `*address*`, `*postcode*` | ADDRESS | Tag + mask |
| `*card_number*`, `*cvv*`, `*account_number*` | PAYMENT | Do not ingest |

---

## 3. Table Properties for PII Tables

```sql
TBLPROPERTIES (
  "contains_pii" = "true",
  "pii_types"    = "CUSTOMER_ID,EMAIL"
)
COMMENT "[CONTAINS PII] <description>"
```

---

## 4. Masking Patterns

```sql
-- Email: show domain only
regexp_replace(email, '^[^@]+', '***') AS email_masked

-- Name: initial + surname only
CONCAT(LEFT(first_name, 1), '. ', last_name) AS display_name

-- Phone: last 4 digits only
regexp_replace(phone, '.(?=.{4})', 'X') AS phone_masked
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-03-24 | Initial release |
