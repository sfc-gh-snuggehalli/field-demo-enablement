-- =============================================================================
-- Cortex Search: BYO Embeddings & Cost Optimization — Cleanup Script
-- =============================================================================
-- Tears down everything the module creates so you can start fresh, then re-run
-- lab/setup.sql. CORTEX_SEARCH_COST_DEMO is dedicated to this demo, so the fast
-- path simply drops the database (cascading every schema, table, view, Cortex
-- Search service, etc. created by setup.sql, data_gen.py, AND the notebook)
-- plus the account-level objects that a DROP DATABASE will NOT cascade.
--
-- Requires a role that OWNS the objects (e.g. SYSADMIN). All statements use
-- IF EXISTS, so this is safe to run repeatedly or against a partially-created demo.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- FAST PATH -- drop the whole demo (recommended for "start fresh")
-- ---------------------------------------------------------------------------

USE ROLE SYSADMIN;

-- Dropping the database cascades every schema-level object created by setup.sql,
-- data_gen.py, and the notebook (including the Cortex Search Service).
DROP DATABASE IF EXISTS CORTEX_SEARCH_COST_DEMO;

-- Warehouse lives at the account level -- not cascaded by DROP DATABASE.
DROP WAREHOUSE IF EXISTS CORTEX_SEARCH_COST_WH;

-- No additional account-level objects (roles, security integrations, compute
-- pools) are created by this module.

-- ---------------------------------------------------------------------------
-- Cleanup complete. Re-run lab/setup.sql, then data_gen.py, then the notebook.
-- ---------------------------------------------------------------------------


-- =============================================================================
-- ALTERNATIVE -- object-by-object teardown (KEEP the database/warehouse)
-- =============================================================================
-- Use this instead of the fast path if CORTEX_SEARCH_COST_DEMO holds other work
-- you want to keep. Comment out the fast-path DROP DATABASE / DROP WAREHOUSE
-- lines above and run the block below instead.
--
-- USE DATABASE CORTEX_SEARCH_COST_DEMO;
-- USE SCHEMA DEMO;
--
-- -- 1. Drop the Cortex Search Service (depends on the table)
-- DROP CORTEX SEARCH SERVICE IF EXISTS DOCUMENT_SEARCH_SVC;
--
-- -- 2. Drop tables in reverse dependency order
-- DROP TABLE IF EXISTS DOCUMENT_CHUNKS;
-- DROP TABLE IF EXISTS DOCUMENTS;
--
-- -- 3. Drop the schema
-- DROP SCHEMA IF EXISTS DEMO;
-- =============================================================================
