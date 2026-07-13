-- =============================================================================
-- AI Functions + Conversational BI: Customer Experience Intelligence — Cleanup
-- =============================================================================
-- Tears down everything the module creates so you can start fresh, then re-run
-- lab/setup.sql. FIELD_CX_DEMO is dedicated to this demo, so the fast path simply
-- drops the database (cascading every schema, table, stage, semantic view, search
-- service, agent, UDF, and lab/notebook-created object) plus the warehouse.
--
-- Requires a role that OWNS the objects (the role you ran setup.sql with, e.g.
-- ACCOUNTADMIN or SYSADMIN). All statements use IF EXISTS, so this is safe to
-- run repeatedly or against a partially-created demo.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- FAST PATH — drop the whole demo (recommended for "start fresh")
-- ─────────────────────────────────────────────────────────────────────────────

DROP DATABASE IF EXISTS FIELD_CX_DEMO;
DROP WAREHOUSE IF EXISTS CX_AI_FUNCTIONS_WH;

-- If an older run left the pre-merge warehouse around, drop it too (harmless if absent):
DROP WAREHOUSE IF EXISTS CONVERSATIONAL_BI_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- Cleanup complete. Re-run lab/setup.sql (then lab/data_gen.py) to rebuild.
-- ─────────────────────────────────────────────────────────────────────────────


-- =============================================================================
-- ALTERNATIVE — object-by-object teardown (KEEP the database/warehouse)
-- =============================================================================
-- Use this instead of the fast path if FIELD_CX_DEMO holds other work you want to
-- keep. Comment out the DROP DATABASE / DROP WAREHOUSE lines above and run the
-- block below. Order matters: dependents (agent, search, semantic view) first.
--
-- USE DATABASE FIELD_CX_DEMO;
--
-- -- ANALYTICS: agent -> search service -> semantic view -> feature/business tables
-- DROP AGENT IF EXISTS ANALYTICS.CX_INTELLIGENCE_AGENT;
-- DROP CORTEX SEARCH SERVICE IF EXISTS ANALYTICS.CHAT_SEARCH;
-- DROP SEMANTIC VIEW IF EXISTS ANALYTICS.CX_ANALYTICS_SV;
-- DROP TABLE IF EXISTS ANALYTICS.CUSTOMER_FEEDBACK;
-- DROP TABLE IF EXISTS ANALYTICS.CHURN_LABELS;
-- DROP TABLE IF EXISTS ANALYTICS.HOME_VALUATIONS;
-- DROP TABLE IF EXISTS ANALYTICS.ENGAGEMENT_EVENTS;
-- DROP TABLE IF EXISTS ANALYTICS.SUBSCRIPTIONS;
-- DROP TABLE IF EXISTS ANALYTICS.CUSTOMERS;
-- DROP SCHEMA IF EXISTS ANALYTICS;
--
-- -- AI_FUNCTIONS: notebook/Studio-created objects
-- DROP FUNCTION IF EXISTS AI_FUNCTIONS.CLASSIFY_ESCALATION(STRING);
-- DROP FUNCTION IF EXISTS AI_FUNCTIONS.ROUTE_ESCALATION(VARCHAR);
-- DROP VIEW IF EXISTS AI_FUNCTIONS.CHAT_ESCALATION_V;
-- DROP TABLE IF EXISTS AI_FUNCTIONS.SUPPORT_TICKETS_ENRICHED;
-- DROP TABLE IF EXISTS AI_FUNCTIONS.ESCALATION_EVAL;
-- DROP TABLE IF EXISTS AI_FUNCTIONS.THREAD_SENTIMENT;
-- DROP TABLE IF EXISTS AI_FUNCTIONS.CX_TELEMETRY;
--
-- -- AI_FUNCTIONS: app UX telemetry (curated -> raw -> stage)
-- DROP TABLE IF EXISTS AI_FUNCTIONS.APP_FEEDBACK;
-- DROP TABLE IF EXISTS AI_FUNCTIONS.APP_MESSAGES;
-- DROP TABLE IF EXISTS AI_FUNCTIONS.APP_THREADS;
-- DROP TABLE IF EXISTS AI_FUNCTIONS.RAW_APP_EVENTS;
-- DROP STAGE IF EXISTS AI_FUNCTIONS.APP_EVENTS_STAGE;
--
-- -- AI_FUNCTIONS: unstructured text (data_gen.py) + structured base
-- DROP TABLE IF EXISTS AI_FUNCTIONS.CHAT_THREADS;
-- DROP TABLE IF EXISTS AI_FUNCTIONS.CALL_TRANSCRIPTS;
-- DROP TABLE IF EXISTS AI_FUNCTIONS.SUPPORT_TICKETS;
-- DROP TABLE IF EXISTS AI_FUNCTIONS.CUSTOMERS;
-- DROP SCHEMA IF EXISTS AI_FUNCTIONS;
-- =============================================================================
