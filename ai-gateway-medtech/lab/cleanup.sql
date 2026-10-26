-- =============================================================================
-- Cortex AI Gateway Lab: Cleanup Script
-- =============================================================================
-- Tears down everything the module creates so you can start fresh, then re-run
-- lab/setup.sql. CORTEX_GATEWAY_MEDTECH_LAB is dedicated to this demo, so the fast path
-- drops the database (cascading the medical device tables, the knowledge corpus and
-- Cortex Search service, both semantic views, the agent, the share-loss model, its
-- monitor and predictions, MCP server, network rule, secret, the Streamlit app, the
-- eval/optimization/optimizer tables, the COST_CENTER and QUOTA_TIER tags, the
-- tier quotas, GATEWAY_BUDGET and the notebook's GATEWAY_QUOTA)
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
-- ALTER USER <your_user> UNSET TAG CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.COST_CENTER;

-- Commercial persona users and roles (setup.sql section 9b). Dropping a user
-- removes its PAT; the files under ~/.snowflake/gateway_medtech_*.pat go stale.
DROP USER IF EXISTS GATEWAY_MEDTECH_REP_NORTHEAST;
DROP USER IF EXISTS GATEWAY_MEDTECH_REP_SOUTHEAST;
DROP USER IF EXISTS GATEWAY_MEDTECH_TM_WEST;
DROP USER IF EXISTS GATEWAY_MEDTECH_TERRITORY_PLANNER;
DROP USER IF EXISTS GATEWAY_MEDTECH_SALES_OPS;
DROP USER IF EXISTS GATEWAY_MEDTECH_MARKET_ACCESS;
DROP USER IF EXISTS GATEWAY_MEDTECH_AI_PLATFORM;
DROP ROLE IF EXISTS GATEWAY_MEDTECH_FIELD_RL;
DROP ROLE IF EXISTS GATEWAY_MEDTECH_ANALYST_RL;
DROP ROLE IF EXISTS GATEWAY_MEDTECH_PLATFORM_RL;
-- Earlier versions of this lab used a single cost demo user
DROP USER IF EXISTS GATEWAY_MEDTECH_COST_DEMO;
DROP ROLE IF EXISTS GATEWAY_MEDTECH_COST_RL;

-- Cascades every schema-level object created by setup.sql, the notebook, and the app.
DROP DATABASE IF EXISTS CORTEX_GATEWAY_MEDTECH_LAB;

-- Warehouse and external access integration live at the account level.
DROP WAREHOUSE IF EXISTS GATEWAY_MEDTECH_WH;
DROP EXTERNAL ACCESS INTEGRATION IF EXISTS GATEWAY_MEDTECH_APP_EAI;

-- OAuth client for the Snowflake server entry in AI Gateway Tools (setup.sql 7b).
-- Also remove the Glean and Snowflake servers in Snowsight: AI & ML > AI Gateway >
-- MCP & Tools (Tools servers are not SQL objects).
DROP SECURITY INTEGRATION IF EXISTS GATEWAY_MEDTECH_TOOLS_OAUTH;
-- REVOKE DATABASE ROLE SNOWFLAKE$OPS.MCP$USER FROM ROLE SYSADMIN;   -- tools_setup.sql

-- Lab PAT (created in the lab notebook's Configuration step). Replace <your_user>.
-- ALTER USER <your_user> REMOVE PROGRAMMATIC ACCESS TOKEN ai_gateway_medtech;

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
-- Use instead of the fast path if CORTEX_GATEWAY_MEDTECH_LAB holds other work. Comment out
-- the DROP DATABASE / DROP WAREHOUSE lines above and run this block. Dependents
-- first: app -> quota/budget -> MCP server -> agent -> model monitor -> model ->
-- semantic views -> tables.
--
-- USE ROLE SYSADMIN;
-- USE SCHEMA CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC;
-- DROP STREAMLIT IF EXISTS AI_GATEWAY_MEDTECH_TRACE_ANALYZER;
-- DROP SNOWFLAKE.CORE.QUOTA IF EXISTS GATEWAY_QUOTA;
-- DROP SNOWFLAKE.CORE.QUOTA IF EXISTS GATEWAY_MEDTECH_FIELD_QUOTA;
-- DROP SNOWFLAKE.CORE.QUOTA IF EXISTS GATEWAY_MEDTECH_ANALYST_QUOTA;
-- DROP SNOWFLAKE.CORE.QUOTA IF EXISTS GATEWAY_MEDTECH_PLATFORM_QUOTA;
-- DROP SNOWFLAKE.CORE.BUDGET IF EXISTS GATEWAY_BUDGET;
-- DROP TAG IF EXISTS COST_CENTER;
-- DROP TAG IF EXISTS QUOTA_TIER;
-- DROP MCP SERVER IF EXISTS MEDTECH_MCP;
-- DROP AGENT IF EXISTS MEDTECH_SALES_AGENT;
-- DROP MODEL MONITOR IF EXISTS SHARE_LOSS_MODEL_MONITOR;
-- DROP MODEL IF EXISTS SHARE_LOSS_MODEL;
-- DROP CORTEX SEARCH SERVICE IF EXISTS PRODUCT_KNOWLEDGE_SEARCH;
-- DROP SEMANTIC VIEW IF EXISTS SALES_PERFORMANCE_SV;
-- DROP SEMANTIC VIEW IF EXISTS ACCOUNT_HEALTH_SV;
-- DROP VIEW IF EXISTS EVAL_PROMPTS;
-- DROP VIEW IF EXISTS SHARE_LOSS_FEATURES_V;
-- DROP TABLE IF EXISTS OPTIMIZER_CALLS;
-- DROP TABLE IF EXISTS OPTIMIZATION_RESULTS;
-- DROP TABLE IF EXISTS OPTIMIZATION_RUNS;
-- DROP TABLE IF EXISTS SHARE_LOSS_PREDICTIONS;
-- DROP TABLE IF EXISTS SHARE_LOSS_MONITOR_SOURCE;
-- DROP TABLE IF EXISTS SHARE_LOSS_MONITOR_BASELINE;
-- -- Medical device data tables
-- DROP TABLE IF EXISTS DIM_PRODUCT_FAMILY;   DROP TABLE IF EXISTS DIM_PRODUCT;
-- DROP TABLE IF EXISTS DIM_TERRITORY;        DROP TABLE IF EXISTS DIM_ACCOUNT;
-- DROP TABLE IF EXISTS DIM_HCP;              DROP TABLE IF EXISTS FACT_PROCEDURES;
-- DROP TABLE IF EXISTS FACT_SALES_ORDERS;    DROP TABLE IF EXISTS FACT_CONTRACTS;
-- DROP TABLE IF EXISTS FACT_QUOTA_ATTAINMENT; DROP TABLE IF EXISTS FACT_CONSIGNMENT_INVENTORY;
-- DROP TABLE IF EXISTS FACT_COMPETITIVE_EVENTS; DROP TABLE IF EXISTS FACT_COMPLAINTS;
-- DROP TABLE IF EXISTS ML_ACCOUNT_FEATURES;  DROP TABLE IF EXISTS PRODUCT_KNOWLEDGE_DOCS;
-- USE ROLE ACCOUNTADMIN;
-- DROP EXTERNAL ACCESS INTEGRATION IF EXISTS GATEWAY_MEDTECH_APP_EAI;
-- DROP SECRET IF EXISTS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.GATEWAY_PAT_SECRET;
-- DROP NETWORK RULE IF EXISTS CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.GATEWAY_APP_EGRESS;
-- =============================================================================
