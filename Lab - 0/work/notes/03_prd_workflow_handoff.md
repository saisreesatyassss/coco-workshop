# PRD Workflow Handoff – SILVER_AP_INVOICES (Baan + Workday)

Account `C2GPARTNERS` · Role `SNOWFLAKE_LEARNING_ROLE` · Warehouse `SNOWFLAKE_LEARNING_WH`
Bronze: `SNOWFLAKE_LEARNING_DB.SAISRISATYA_COCO_SOURCE_DATA` · Silver: `SNOWFLAKE_LEARNING_DB.SAISRISATYA_COCO_PIPELINE_LAB`

## Artifacts to keep

| File | Purpose |
|---|---|
| `assets/sample_business_requirements_*.csv` | The PRD inputs (source onboarding, column mapping, business rules) |
| `.cortex/skills/prd-to-silver/SKILL.md` (project root) | Reusable PRD Evaluator skill |
| `work/notes/02_prd_change_plan.md` | Skill output: 5-section change plan, open questions, assumptions |
| `work/sql/00_sample_data_adapted.sql` | Bronze load, pointed at the learning schemas |
| `work/sql/01_silver_ap_invoices.sql` | Phase 1 DT (SAP + Oracle) |
| `work/sql/03_silver_ap_invoices_prd_update.sql` | Current DT definition (4 sources) + validation V1–V5 |
| `work/sql/02_silver_ap_invoices_proof.sql` | One-shot proof query, rerun after every change |
| `work/notes/01_silver_ap_invoices_runbook.md` | Operating runbook (lag, monitoring SQL, failure patterns) |

## Review

1. Read `02_prd_change_plan.md` section 3; decisions still owed: **BR-005** (payment terms) and Workday legal sign-off (DPA-2025-0041).
2. Diff `01_...sql` vs `03_...sql`: two new UNION ALL branches, status CASE maps, Baan QUALIFY dedup.

## Rerun the checks

```sql
-- after any DDL change, force a refresh first (CREATE OR ALTER does not refresh immediately)
ALTER DYNAMIC TABLE SNOWFLAKE_LEARNING_DB.SAISRISATYA_COCO_PIPELINE_LAB.SILVER_AP_INVOICES REFRESH;
```
Then run `02_silver_ap_invoices_proof.sql` and the V1–V5 block in `03_...sql`.

Result at handoff (2026-10-23): 50 rows (SAP 15, ORACLE 15, BAAN 10, WORKDAY 10); all counts match bronze;
statuses only APPROVED/PENDING; no duplicate invoice numbers; no nulls in required columns; DT ACTIVE, INCREMENTAL, lag 1 hour.

## Reuse the skill for the next PRD

```
Run the project skill prd-to-silver
- prd_path: <new_column_mapping.csv | .xlsx>
- target_dynamic_table: SILVER_AP_INVOICES
```
The skill reads the PRD, inspects the DT and sources, returns the 5-section plan, and only applies DDL after approval.
