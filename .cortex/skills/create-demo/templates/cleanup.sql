-- =============================================================================
-- {{DECK_TITLE}} Lab: Cleanup Script
-- =============================================================================
-- Tears down everything the module creates so you can start fresh, then re-run
-- lab/setup.sql. {{DB_NAME}} is dedicated to this demo, so the fast path simply
-- drops the database (cascading every schema, table, view, stage, semantic view,
-- Cortex Search service, function, procedure, agent, MCP server, etc. created by
-- setup.sql AND the notebook(s)) plus the account-level objects that a
-- DROP DATABASE will NOT cascade (warehouses, roles, compute pools, security
-- integrations, and any per-user session defaults you changed).
--
-- Requires a role that OWNS the objects (the role you ran setup.sql / the
-- notebooks with, e.g. SYSADMIN), plus ACCOUNTADMIN for any account-level objects
-- (roles, security integrations). All statements use IF EXISTS, so this is safe
-- to run repeatedly or against a partially-created demo.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- FAST PATH — drop the whole demo (recommended for "start fresh")
-- ─────────────────────────────────────────────────────────────────────────────

USE ROLE SYSADMIN;

-- Dropping the database cascades every schema-level object created by setup.sql
-- and the notebook(s).
DROP DATABASE IF EXISTS {{DB_NAME}};

-- Warehouse(s) live at the account level — not cascaded by DROP DATABASE.
DROP WAREHOUSE IF EXISTS {{WH_NAME}};

-- {{CLEANUP_ACCOUNT_LEVEL_STUB}}
-- Account-level objects that DROP DATABASE does NOT cascade — drop the ones this
-- module created (uncomment/fill as needed). Requires ACCOUNTADMIN for roles /
-- security integrations. Examples:
-- USE ROLE ACCOUNTADMIN;
-- DROP ROLE IF EXISTS <demo_role>;
-- DROP SECURITY INTEGRATION IF EXISTS <demo_integration>;
-- DROP COMPUTE POOL IF EXISTS <demo_pool>;
-- -- Revert any ALTER USER ... DEFAULT_ROLE/DEFAULT_WAREHOUSE the lab set.

-- ─────────────────────────────────────────────────────────────────────────────
-- Cleanup complete. Re-run lab/setup.sql, then the notebook(s), to rebuild.
-- ─────────────────────────────────────────────────────────────────────────────


-- =============================================================================
-- ALTERNATIVE — object-by-object teardown (KEEP the database/warehouse)
-- =============================================================================
-- Use this instead of the fast path if {{DB_NAME}} holds other work you want to
-- keep. Comment out the fast-path DROP DATABASE / DROP WAREHOUSE lines above and
-- run a block below. Order matters: drop dependents (agents -> tool functions/
-- procedures -> the views/tables they read; MCP servers; semantic views; search
-- services) before the objects they reference.
--
-- {{CLEANUP_OBJECT_BY_OBJECT_STUB}}
-- =============================================================================
