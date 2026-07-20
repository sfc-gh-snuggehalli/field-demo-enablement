-- =============================================================================
-- Proactive Retail Intelligence with Snowflake Cortex — Lab: Cleanup Script
-- =============================================================================
-- Tears down everything the module creates so you can start fresh, then re-run
-- lab/setup.sql. PROACTIVE_RETAIL_DEMO is dedicated to this demo, so the fast
-- path simply drops the database (cascading every schema, table, view, semantic
-- view, Cortex Search service, ML model, task, function, and agent created by
-- setup.sql AND the notebook) plus the warehouse, which DROP DATABASE does not
-- cascade.
--
-- Requires a role that OWNS the objects (e.g. SYSADMIN). All statements use
-- IF EXISTS, so this is safe to run repeatedly or against a partial demo.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- FAST PATH — drop the whole demo (recommended for "start fresh")
-- ─────────────────────────────────────────────────────────────────────────────

USE ROLE SYSADMIN;

-- Dropping the database cascades every schema-level object created by setup.sql
-- AND the notebook (ML models, findings/drivers tables, semantic view, search
-- service, the GET_PROACTIVE_BRIEFING function, and both agents).
DROP DATABASE IF EXISTS PROACTIVE_RETAIL_DEMO;

-- The warehouse lives at the account level — not cascaded by DROP DATABASE.
DROP WAREHOUSE IF EXISTS PROACTIVE_RETAIL_WH;

-- This module creates no dedicated roles, security integrations, compute pools,
-- or ALTER USER session defaults, so there is nothing else at the account level
-- to revert.

-- ─────────────────────────────────────────────────────────────────────────────
-- Cleanup complete. Re-run lab/setup.sql, then the notebook, to rebuild.
-- ─────────────────────────────────────────────────────────────────────────────


-- =============================================================================
-- ALTERNATIVE — object-by-object teardown (KEEP the database/warehouse)
-- =============================================================================
-- Use this instead of the fast path if PROACTIVE_RETAIL_DEMO holds other work
-- you want to keep. Comment out the fast-path DROP DATABASE / DROP WAREHOUSE
-- lines above and run the block below. Order matters: drop dependents (agents ->
-- the custom tool function -> semantic view / search service -> ML models ->
-- task -> views -> tables) before the objects they reference.
--
-- USE ROLE SYSADMIN;
-- USE DATABASE PROACTIVE_RETAIL_DEMO;
--
-- -- Agents (created in the notebook)
-- DROP AGENT IF EXISTS ANALYTICS.PROACTIVE_RETAIL_AGENT;
-- DROP AGENT IF EXISTS ANALYTICS.PROACTIVE_RETAIL_AGENT_BASELINE;
--
-- -- Custom tool function (created in the notebook)
-- DROP FUNCTION IF EXISTS ANALYTICS.GET_PROACTIVE_BRIEFING();
--
-- -- Serving objects
-- DROP CORTEX SEARCH SERVICE IF EXISTS ANALYTICS.RETURN_REASONS_SEARCH;
-- DROP SEMANTIC VIEW IF EXISTS ANALYTICS.RETAIL_RETURNS_SV;
--
-- -- Scheduled monitoring task
-- DROP TASK IF EXISTS ANALYTICS.REFRESH_ANOMALY_FINDINGS_TASK;
--
-- -- Cortex ML Function models
-- DROP SNOWFLAKE.ML.TOP_INSIGHTS IF EXISTS ANALYTICS.RETURN_DRIVERS_MODEL;
-- DROP SNOWFLAKE.ML.ANOMALY_DETECTION IF EXISTS ANALYTICS.RETURN_RATE_DETECTOR;
--
-- -- Derived tables and views
-- DROP TABLE IF EXISTS ANALYTICS.RETURN_DRIVERS;
-- DROP VIEW  IF EXISTS ANALYTICS.RETURN_DRIVERS_INPUT;
-- DROP VIEW  IF EXISTS ANALYTICS.STORE_ANOMALIES_ENRICHED;
-- DROP TABLE IF EXISTS ANALYTICS.STORE_ANOMALY_FINDINGS;
-- DROP VIEW  IF EXISTS ANALYTICS.RETURN_RATE_RECENT;
-- DROP VIEW  IF EXISTS ANALYTICS.RETURN_RATE_TRAIN;
--
-- -- Raw data
-- DROP TABLE IF EXISTS RAW.RETURN_REASONS;
-- DROP TABLE IF EXISTS RAW.RETURNS_FACT;
-- DROP TABLE IF EXISTS RAW.STORE_DAY_METRICS;
-- DROP TABLE IF EXISTS RAW.STORES;
-- DROP TABLE IF EXISTS RAW.RETAILERS;
-- =============================================================================
