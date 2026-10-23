# Demo 3 – Agent on the AP Data Product

## 3.1 Agent use case
- **Audience:** AP / Finance operations analysts and the Finance Controller.
- **Top questions:** total spend by vendor (last 12 months) · invoice count by month and business unit · top vendors by unpaid (pending) amount · invoices by source system · average invoice by currency.
- **Guardrails:** answer only from `SV_AP_ANALYTICS`; never convert currencies (BR-002); "unpaid" = `PENDING` is a stated proxy; ask a clarifying question for ambiguous metric or time grain; say so when data doesn't cover a question (payments, FX, budgets).
- **Semantic descriptions that help:** business unit = COST_CENTER; PENDING = open/unpaid proxy; vendor IDs not harmonized across ERPs; payment terms not normalized.

## 3.2 Semantic view – `SNOWFLAKE_LEARNING_DB.SAISRISATYA_COCO_PIPELINE_LAB.SV_AP_ANALYTICS`
YAML: `work/cortex_project/SV_AP_ANALYTICS.sv.yaml`
- Grain: one row per invoice; primary key (INVOICE_ID, SOURCE_SYSTEM).
- Metrics: TOTAL_SPEND, INVOICE_COUNT, AVG_INVOICE_AMOUNT, PENDING_AMOUNT. Filters: PENDING_INVOICES, OVERDUE_INVOICES.
- Time dimensions: INVOICE_DATE (default), DUE_DATE, CREATED_AT. 8 verified queries.
- Assumptions: "last 12 months" is relative to the latest INVOICE_DATE (data is Jan–Jun 2025); vendor identity = VENDOR_NAME.
- Check: SV totals by source match Silver V1 exactly (SAP 334,601.25 · ORACLE 589,900 · BAAN 257,600 · WORKDAY 265,300).

## 3.3 Agent – `SNOWFLAKE_LEARNING_DB.SAISRISATYA_COCO_PIPELINE_LAB.AP_ANALYTICS_ASSISTANT`
Spec: `work/cortex_project/AP_ANALYTICS_ASSISTANT.agent.yaml` · tool `ap_invoices_analyst` → SV_AP_ANALYTICS on SNOWFLAKE_LEARNING_WH.
Tests:
- "Top 10 vendors by unpaid invoice amount" → 3-part answer (Answer / SQL / Assumptions), grouped by currency, pending = proxy. ✅
- "Which vendors are problematic?" → asked a clarifying question (overdue vs pending vs high spend, currency, window). ✅ matches AGENT_EVAL_SET expectation.

## 3.4 Best-practices audit of SV_AP_ANALYTICS

```
Quality Score: 4.66/6 (78%) [Good]
  Has keys          pass (INVOICE_ID, SOURCE_SYSTEM)
  Relationships: N/A (single-table view, not scored)
  Has metrics       pass (4)
  VQRs: 8           pass (1.68/2 – saturates at ~10)
  Descriptions      pass (avg 80 chars across 21 elements)
```

**Warnings**
1. **Mixed-currency sums** – TOTAL_SPEND / PENDING_AMOUNT add USD+EUR+GBP. → Keep currency in every grouped answer (done via instructions) and add an FX-converted metric once the Gold FX table exists (BR-002).
2. **OVERDUE_INVOICES uses CURRENT_DATE** – all sample invoices are from 2025, so every invoice is "overdue" today, and there is no paid flag. → Document it in answers or add a paid/payment-status column upstream.

**Recommendations**
3. **Duplicate guidance** – custom instructions repeat what synonyms already encode ("business unit = COST_CENTER", "unpaid = PENDING"). → Trim the instructions to the currency rule and the "last N months" rule.
4. **More VQRs** – add 2–4 from AGENT_EVAL_SET (spend with a single vendor, 2025 monthly spend trend, invoices over $100k, total spend) to reach ~10.
5. **PAYMENT_TERMS not normalized** (NET30 / N30 / Net 30) – add sample values, or a derived TERMS_DAYS dimension, once BR-005 is decided.
6. **VENDOR_ID not harmonized across ERPs** – keep VENDOR_NAME as the vendor key; revisit with a vendor master.

**Passed:** descriptions on all elements, consistent UPPER_SNAKE naming, data types defined, enum sample values on status/source/currency, metrics vs facts classified correctly, no relationship descriptions.
