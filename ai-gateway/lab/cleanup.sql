-- =============================================================================
-- Cortex AI Gateway Lab: Cleanup Script
-- =============================================================================
-- Tears down everything the module creates so you can start fresh, then re-run
-- lab/setup.sql. CORTEX_GATEWAY_LAB is dedicated to this demo, so the fast path
-- drops the database (cascading tables, semantic view, Cortex Search service,
-- MCP server, network rule, secret, the Streamlit app, the eval/optimization
-- tables, and the notebook's COST_CENTER tag, GATEWAY_BUDGET and GATEWAY_QUOTA)
-- plus the account-level objects DROP DATABASE does NOT cascade.
--
-- The AI Gateway itself is account-level and shared: it is NOT dropped. The last
-- block resets its specification and removes the lab's grants.
--
-- All statements use IF EXISTS / are idempotent, so this is safe to re-run.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- FAST PATH — drop the whole demo (recommended for "start fresh")
-- ─────────────────────────────────────────────────────────────────────────────

USE ROLE ACCOUNTADMIN;

-- The notebook tags the lab user with COST_CENTER; unset it before the tag is dropped.
-- Replace <your_user> with the user that ran the notebook.
-- ALTER USER <your_user> UNSET TAG CORTEX_GATEWAY_LAB.PUBLIC.COST_CENTER;

-- Cost governance demo user (setup.sql section 10b). Dropping it removes its PAT.
DROP USER IF EXISTS GATEWAY_COST_DEMO;
DROP ROLE IF EXISTS GATEWAY_COST_DEMO_RL;

-- Cascades every schema-level object created by setup.sql, the notebook, and the app.
DROP DATABASE IF EXISTS CORTEX_GATEWAY_LAB;

-- Warehouse and external access integration live at the account level.
DROP WAREHOUSE IF EXISTS GATEWAY_LAB_WH;
DROP EXTERNAL ACCESS INTEGRATION IF EXISTS GATEWAY_LAB_APP_EAI;

-- Lab PAT (created in the lab notebook's Configuration step). Replace <your_user>.
-- ALTER USER <your_user> REMOVE PROGRAMMATIC ACCESS TOKEN ai_gateway_demo;

-- ─────────────────────────────────────────────────────────────────────────────
-- AI GATEWAY — reset (shared account object; review before running)
-- ─────────────────────────────────────────────────────────────────────────────
-- setup.sql enabled client telemetry and payload capture and granted SYSADMIN
-- access. Uncomment to return the gateway to metadata-only logging and remove the
-- lab grants. Payload capture records full prompts/responses, so turn it off if
-- nothing else in the account needs it.

-- ALTER AI GATEWAY SNOWFLAKE FROM SPECIFICATION $$
-- schema_version: 1
-- models:
--   - name: '*'
-- logging:
--   enabled: true
-- $$;
-- REVOKE MONITOR ON AI GATEWAY SNOWFLAKE FROM ROLE SYSADMIN;
-- REVOKE DATABASE ROLE SNOWFLAKE.USAGE_VIEWER    FROM ROLE SYSADMIN;
-- REVOKE DATABASE ROLE SNOWFLAKE.BUDGET_CREATOR  FROM ROLE SYSADMIN;
-- REVOKE DATABASE ROLE SNOWFLAKE.SECURITY_VIEWER FROM ROLE SYSADMIN;
-- REVOKE DATABASE ROLE SNOWFLAKE.QUOTA_CREATOR   FROM ROLE SYSADMIN;
-- REVOKE APPLY TAG ON ACCOUNT FROM ROLE SYSADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Cleanup complete. Re-run lab/setup.sql, then the notebook, to rebuild.
-- ─────────────────────────────────────────────────────────────────────────────


-- =============================================================================
-- ALTERNATIVE — object-by-object teardown (KEEP the database/warehouse)
-- =============================================================================
-- Use instead of the fast path if CORTEX_GATEWAY_LAB holds other work. Comment out
-- the DROP DATABASE / DROP WAREHOUSE lines above and run this block. Dependents
-- first: app -> quota/budget -> MCP server -> search service -> semantic view -> tables.
--
-- USE ROLE SYSADMIN;
-- USE SCHEMA CORTEX_GATEWAY_LAB.PUBLIC;
-- DROP STREAMLIT IF EXISTS AI_GATEWAY_TRACE_ANALYZER;
-- DROP SNOWFLAKE.CORE.QUOTA IF EXISTS GATEWAY_QUOTA;
-- DROP SNOWFLAKE.CORE.QUOTA IF EXISTS GATEWAY_DEMO_QUOTA;
-- DROP SNOWFLAKE.CORE.BUDGET IF EXISTS GATEWAY_BUDGET;
-- DROP TAG IF EXISTS COST_CENTER;
-- DROP TAG IF EXISTS QUOTA_TIER;
-- DROP MCP SERVER IF EXISTS MARKETING_MCP;
-- DROP AGENT IF EXISTS MARKETING_AGENT;
-- DROP CORTEX SEARCH SERVICE IF EXISTS STRATEGY_SEARCH_SVC;
-- DROP SEMANTIC VIEW IF EXISTS CMO_ANALYTICS;
-- DROP TABLE IF EXISTS OPTIMIZATION_RESULTS;
-- DROP TABLE IF EXISTS OPTIMIZATION_RUNS;
-- DROP TABLE IF EXISTS EVAL_PROMPTS;
-- DROP TABLE IF EXISTS STRATEGY_DOCS;
-- DROP TABLE IF EXISTS CAMPAIGN_SPEND;
-- USE ROLE ACCOUNTADMIN;
-- DROP EXTERNAL ACCESS INTEGRATION IF EXISTS GATEWAY_LAB_APP_EAI;
-- DROP SECRET IF EXISTS CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_PAT_SECRET;
-- DROP NETWORK RULE IF EXISTS CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_APP_EGRESS;
-- =============================================================================
