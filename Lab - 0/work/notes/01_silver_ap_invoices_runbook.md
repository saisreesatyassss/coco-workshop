# SILVER_AP_INVOICES – Operating Runbook

Object: `SNOWFLAKE_LEARNING_DB.SAISRISATYA_COCO_PIPELINE_LAB.SILVER_AP_INVOICES`
Role / warehouse: `SNOWFLAKE_LEARNING_ROLE` / `SNOWFLAKE_LEARNING_WH`
Refresh mode: `INCREMENTAL` (UNION ALL of simple projections, no aggregates or joins)

## 1. TARGET_LAG recommendation

| Option | When |
|---|---|
| `'1 hour'` (current) | No downstream consumer yet. Matches the slowest frequent feed (Oracle hourly batch). |
| `DOWNSTREAM` (target state, BR-009) | Once a Gold DT exists, switch Silver to `DOWNSTREAM` so it refreshes only when Gold needs it. |

A shorter lag buys nothing: SAP is real-time CDC, but Oracle/Workday are hourly and Baan is nightly,
so a combined Silver view is never fresher than its slowest hourly source.

```sql
-- When Gold is introduced:
ALTER DYNAMIC TABLE SNOWFLAKE_LEARNING_DB.SAISRISATYA_COCO_PIPELINE_LAB.SILVER_AP_INVOICES
  SET TARGET_LAG = DOWNSTREAM;
```

## 2. Inspection SQL

```sql
-- Current state, refresh mode and lag
SHOW DYNAMIC TABLES LIKE 'SILVER_AP_INVOICES'
  IN SCHEMA SNOWFLAKE_LEARNING_DB.SAISRISATYA_COCO_PIPELINE_LAB;
-- check: scheduling_state = ACTIVE, refresh_mode = INCREMENTAL, refresh_mode_reason

-- Refresh history (latest first)
SELECT name, state, state_message, refresh_action, refresh_trigger,
       data_timestamp, refresh_start_time, refresh_end_time
FROM TABLE(SNOWFLAKE_LEARNING_DB.INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
       NAME => 'SNOWFLAKE_LEARNING_DB.SAISRISATYA_COCO_PIPELINE_LAB.SILVER_AP_INVOICES'))
ORDER BY refresh_start_time DESC
LIMIT 20;

-- Failures only
SELECT name, state, state_message, refresh_start_time
FROM TABLE(SNOWFLAKE_LEARNING_DB.INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
       NAME => 'SNOWFLAKE_LEARNING_DB.SAISRISATYA_COCO_PIPELINE_LAB.SILVER_AP_INVOICES',
       ERROR_ONLY => TRUE))
ORDER BY refresh_start_time DESC;

-- Lag vs target (freshness)
SELECT name, scheduling_state, target_lag_sec,
       mean_lag_sec, maximum_lag_sec, time_within_target_lag_ratio, latest_data_timestamp
FROM TABLE(SNOWFLAKE_LEARNING_DB.INFORMATION_SCHEMA.DYNAMIC_TABLES(
       NAME => 'SNOWFLAKE_LEARNING_DB.SAISRISATYA_COCO_PIPELINE_LAB.SILVER_AP_INVOICES'));

-- Manual refresh (e.g. after a bronze backfill)
ALTER DYNAMIC TABLE SNOWFLAKE_LEARNING_DB.SAISRISATYA_COCO_PIPELINE_LAB.SILVER_AP_INVOICES REFRESH;
```

## 3. Failure / staleness patterns to watch

| Pattern | Symptom | Response |
|---|---|---|
| Bronze schema drift (column renamed/dropped) | `state = FAILED`, compilation error | Update the UNION ALL branch; explicit column lists keep this loud, not silent |
| Change tracking disabled on a bronze table | Refresh fails | `ALTER TABLE ... SET CHANGE_TRACKING = TRUE` |
| Bronze table `CREATE OR REPLACE` (e.g. reloading sample data) | Reinitialize / full refresh | Expected; prefer TRUNCATE+INSERT for reloads |
| Fallback to FULL refresh | `refresh_mode` / `refresh_action` shows FULL | Check `refresh_mode_reason`; avoid non-deterministic functions in the query |
| Auto-suspend after repeated failures | `scheduling_state = SUSPENDED` | Fix root cause, then `ALTER DYNAMIC TABLE ... RESUME` |
| Warehouse suspended/unavailable | Lag grows, `time_within_target_lag_ratio` drops | Check `SNOWFLAKE_LEARNING_WH` access |
| New status value from a source (e.g. Oracle `REJECTED`) | Passes through un-normalized | Proof query below; extend the CASE mapping |
| Duplicate invoices (Baan, BR-003) | Count by `INVOICE_NUMBER` > 1 | Dedup with QUALIFY in the Baan branch (Demo 2) |

## 4. Operating checklist

- [ ] `scheduling_state = ACTIVE` and `refresh_mode = INCREMENTAL`
- [ ] No rows from the ERROR_ONLY refresh history query in the last 24h
- [ ] `time_within_target_lag_ratio` close to 1
- [ ] Run `sql/02_silver_ap_invoices_proof.sql` after every change; row counts match bronze
- [ ] `APPROVAL_STATUS` only contains `APPROVED` / `PENDING`
- [ ] Explicit column lists only (no `SELECT *`); fully qualified names
- [ ] Switch to `TARGET_LAG = DOWNSTREAM` once a Gold consumer exists
