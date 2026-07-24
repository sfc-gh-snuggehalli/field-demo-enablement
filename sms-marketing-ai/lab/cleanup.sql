-- =============================================================================
-- Semantic Views & the AI-BI Stack on Snowflake — Lab: Cleanup Script
-- =============================================================================
-- Tears down everything the module creates so you can start fresh, then re-run
-- lab/setup.sql. SMS_MARKETING_DEMO is dedicated to this demo, so the fast path
-- simply drops the database (cascading every schema, table, stage, semantic
-- view, Cortex Search service, and agent created by setup.sql AND the notebook)
-- plus the warehouse, which DROP DATABASE does not cascade.
--
-- Requires a role that OWNS the objects (the role you ran setup.sql / the
-- notebook with, e.g. SYSADMIN). All statements use IF EXISTS, so this is safe
-- to run repeatedly or against a partially-created demo. This module creates no
-- dedicated roles, compute pools, security integrations, or ALTER USER session
-- defaults, so there is nothing account-level to revert beyond the warehouse.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- FAST PATH — drop the whole demo (recommended for "start fresh")
-- ─────────────────────────────────────────────────────────────────────────────

USE ROLE SYSADMIN;

-- Cascades: schema CORE, all DIM_/FACT_ tables, SMS_DOC_CHUNKS, the transcript
-- tables (CALL_MANIFEST, CALL_TRANSCRIPTS_RAW_LINES, CALL_TRANSCRIPTS_RAW,
-- TRANSCRIPT_CHUNKS), stages SMS_DOCS + CALL_TRANSCRIPTS_STAGE, file formats,
-- semantic view SMS_MARKETING_SV, both Cortex Search services (SMS_DOCS_SEARCH +
-- CALL_TRANSCRIPTS_SEARCH), and the agents SMS_MARKETING_AGENT +
-- SMS_MARKETING_AGENT_BASELINE (the latter built in the notebook).
DROP DATABASE IF EXISTS SMS_MARKETING_DEMO;

-- Warehouse lives at the account level — not cascaded by DROP DATABASE.
DROP WAREHOUSE IF EXISTS SMS_MARKETING_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- Cleanup complete. Re-run lab/setup.sql, then the notebook, to rebuild.
-- ─────────────────────────────────────────────────────────────────────────────


-- =============================================================================
-- ALTERNATIVE — object-by-object teardown (KEEP the database/warehouse)
-- =============================================================================
-- Use this instead of the fast path if SMS_MARKETING_DEMO holds other work you
-- want to keep. Comment out the fast-path DROP DATABASE / DROP WAREHOUSE lines
-- above and run the block below. Order matters: drop the agent (depends on the
-- semantic view + search service) first, then the search service and semantic
-- view, then the tables and stage.
--
-- USE ROLE SYSADMIN;
-- USE DATABASE SMS_MARKETING_DEMO;
-- USE SCHEMA CORE;
--
-- DROP AGENT IF EXISTS SMS_MARKETING_AGENT;
-- DROP AGENT IF EXISTS SMS_MARKETING_AGENT_BASELINE;   -- created in the notebook (Section 7)
-- DROP CORTEX SEARCH SERVICE IF EXISTS CALL_TRANSCRIPTS_SEARCH;
-- DROP CORTEX SEARCH SERVICE IF EXISTS SMS_DOCS_SEARCH;
-- DROP SEMANTIC VIEW IF EXISTS SMS_MARKETING_SV;
-- DROP TABLE IF EXISTS FACT_ORDER;
-- DROP TABLE IF EXISTS FACT_MESSAGE;
-- DROP TABLE IF EXISTS DIM_CAMPAIGN;
-- DROP TABLE IF EXISTS DIM_SUBSCRIBER;
-- DROP TABLE IF EXISTS DIM_BRAND;
-- DROP TABLE IF EXISTS SMS_DOC_CHUNKS;
-- DROP TABLE IF EXISTS TRANSCRIPT_CHUNKS;
-- DROP TABLE IF EXISTS CALL_TRANSCRIPTS_RAW;
-- DROP TABLE IF EXISTS CALL_TRANSCRIPTS_RAW_LINES;
-- DROP TABLE IF EXISTS CALL_MANIFEST;
-- DROP STAGE IF EXISTS SMS_DOCS;
-- DROP STAGE IF EXISTS CALL_TRANSCRIPTS_STAGE;
-- DROP FILE FORMAT IF EXISTS FF_TRANSCRIPT_LINES;
-- DROP FILE FORMAT IF EXISTS FF_MANIFEST_CSV;
-- =============================================================================
