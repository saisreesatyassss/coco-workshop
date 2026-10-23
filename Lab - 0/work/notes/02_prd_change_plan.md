# PRD Change Plan – SILVER_AP_INVOICES

Skill: `prd-to-silver` · Target: `SNOWFLAKE_LEARNING_DB.SAISRISATYA_COCO_PIPELINE_LAB.SILVER_AP_INVOICES`
PRD files: `sample_business_requirements_column_mapping.csv` (primary), `..._business_rules.csv`, `..._source_onboarding.csv`
DDL: `sql/03_silver_ap_invoices_prd_update.sql` (compiled OK)

## 1. Summary of requested changes

| PRD ID | Change |
|---|---|
| SRC-2025-003 | Add **Baan IV** (EMEA, nightly batch ~02:00 UTC) – `BRONZE_BAAN_AP_INVOICES` |
| SRC-2025-004 | Add **Workday** (Americas + London tenant, hourly) – `BRONZE_WORKDAY_AP_INVOICES` |
| BR-001 | Status → `APPROVED`/`PENDING`: Baan POSTED→APPROVED; Workday Approved→APPROVED, In Review→PENDING |
| BR-003 | Dedup Baan on `INVOICE_NUMBER`, latest `CREATED_AT` wins |
| BR-007 | `SOURCE_SYSTEM` literal `'BAAN'` / `'WORKDAY'` |
| BR-008 | Drop `BAN_COMPANY`, `WD_TENANT_ID` |
| BR-002 / BR-006 | No change: keep original currency and GL codes |

No new Silver columns – both sources map onto the existing 16-column schema.

## 2. Source-to-Silver mapping summary

| Silver column | Baan | Workday | Transform |
|---|---|---|---|
| INVOICE_ID | BAN_INVOICE_ID | WD_INVOICE_ID | direct |
| INVOICE_NUMBER | BAN_INVOICE_REF | WD_INVOICE_NUM | direct (Baan dedup key) |
| VENDOR_ID | BAN_VENDOR_CODE | WD_SUPPLIER_ID | direct |
| VENDOR_NAME | BAN_VENDOR_DESC | WD_SUPPLIER_NAME | direct (UTF-8) |
| INVOICE_DATE | BAN_INV_DATE | WD_INVOICE_DATE | direct |
| DUE_DATE | BAN_PAY_DATE | WD_DUE_DATE | direct |
| INVOICE_AMOUNT | BAN_AMOUNT | WD_AMOUNT | direct, original currency |
| CURRENCY_CODE | BAN_CURR | WD_CURRENCY | direct |
| PAYMENT_TERMS | BAN_PAY_TERMS | WD_PAY_TERMS | **as-is** (open, BR-005) |
| PO_NUMBER | BAN_PO_REF | WD_PO_NUMBER | direct, optional |
| LINE_DESCRIPTION | BAN_LINE_DESC | WD_MEMO | direct, optional |
| GL_ACCOUNT | BAN_GL_CODE | WD_LEDGER_ACCOUNT | direct, no cross-map |
| COST_CENTER | BAN_COST_CTR | WD_COST_CENTER | direct |
| APPROVAL_STATUS | BAN_STATUS | WD_APPROVAL_STATUS | CASE map (BR-001) |
| CREATED_AT | BAN_CREATED | WD_CREATED_DATE | direct (UTC) |
| SOURCE_SYSTEM | 'BAAN' | 'WORKDAY' | literal |
| *dropped* | BAN_COMPANY | WD_TENANT_ID | BR-008 |

## 3. Open questions and assumptions

**Open questions (PRD says needs decision)**
- BR-005 payment terms: 4 formats now in Silver (`NET30`, `N30`, `Net 30`). Default: leave as-is, normalize in Gold. Owner: Sarah Chen / David Kim (due 2025-06-20).
- SRC-2025-004 Workday go-live is pending legal (DPA-2025-0041). Loading it into Silver assumes the data is cleared for use.

**Assumptions made**
- Baan dedup tie-break: if two rows share `BAN_INVOICE_REF` and `BAN_CREATED`, keep highest `BAN_INVOICE_ID` (PRD gives no tie-break).
- Dedup applied to Baan only; the PRD reports the issue for Baan only. Current data has no duplicates in any source.
- Unknown future statuses pass through upper-cased (not silently mapped), so validation V2 catches them.
- Baan cost center has two formats (`BC-XX`/`BC-XXX`); kept as-is, not a Silver concern.
- `TARGET_LAG` stays `'1 hour'` until a Gold DT exists (then `DOWNSTREAM`, BR-009).

**Out of scope for this DT**
- BR-004 high-value flag → DMF in the Guardrails Pack. BR-002 FX → Gold. BR-006 CoA mapping → Phase 2. BR-010 history → Bronze.

## 4. DDL delta plan

- Add two `UNION ALL` branches (Baan, Workday) with CASE status maps.
- Add `QUALIFY ROW_NUMBER() OVER (PARTITION BY BAN_INVOICE_REF ORDER BY BAN_CREATED DESC, BAN_INVOICE_ID DESC) = 1` to the Baan branch.
- SAP/Oracle branches and lag/warehouse/refresh mode unchanged; comment updated.
- Applied with `CREATE OR ALTER` → query change **reinitializes** the DT (acceptable at 50 rows).

## 5. Validation queries

In `sql/03_silver_ap_invoices_prd_update.sql`: V1 counts vs bronze per source, V2 allowed statuses, V3 duplicate keys, V4 required-column nulls, V5 DT health.
