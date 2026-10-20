-- =============================================================================
-- cleanup.sql  (run with a role that can USE ROLE ACCOUNTADMIN; ./demo.sh teardown runs it)
-- Multi-agent orchestration over MCP: tear the whole demo down to start fresh.
--
-- Fast path: DROP DATABASE removes everything schema-level that setup.sql and
-- the lab notebook created: both MCP servers, the four agents (including
-- TOOLSET_AGENT), the bridge procedures, the semantic views, the row access
-- policy, the tables, the evaluation stage, file format, datasets and runs.
-- The warehouse, the persona users and the roles are account-level and are
-- dropped explicitly below.
--
-- Not in SQL: the host-model PAT on your own user and the local key/PAT files.
-- ./demo.sh teardown removes those after this file runs. By hand:
--   ALTER USER <your_user> REMOVE PROGRAMMATIC ACCESS TOKEN MULTI_AGENT_MCP_DEMO;
--   rm ~/.snowflake/multi_agent_mcp_demo.pat ~/.snowflake/keys/multi_agent_mcp_*.p8
--
-- If you added ORCHESTRATOR_AGENT to Snowflake CoWork, remove it first:
--   ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
--     DROP AGENT MULTI_AGENT_MCP_DEMO.APP.ORCHESTRATOR_AGENT;
--
-- Every statement uses IF EXISTS, so this file is safe to re-run.
-- =============================================================================

SET demo_db        = 'MULTI_AGENT_MCP_DEMO';
SET demo_wh        = 'MULTI_AGENT_MCP_DEMO_WH';
SET admin_role     = 'MULTI_AGENT_MCP_DEMO_ADMIN';
SET sales_global   = 'MULTI_AGENT_MCP_DEMO_SALES_GLOBAL';
SET sales_emea     = 'MULTI_AGENT_MCP_DEMO_SALES_EMEA';
SET support_role   = 'MULTI_AGENT_MCP_DEMO_SUPPORT';
SET sales_global_u = 'MULTI_AGENT_MCP_DEMO_SALES_GLOBAL_USER';
SET sales_emea_u   = 'MULTI_AGENT_MCP_DEMO_SALES_EMEA_USER';
SET support_u      = 'MULTI_AGENT_MCP_DEMO_SUPPORT_USER';

USE ROLE ACCOUNTADMIN;

-- ── Fast path ───────────────────────────────────────────────────────────────
DROP DATABASE  IF EXISTS IDENTIFIER($demo_db);
DROP WAREHOUSE IF EXISTS IDENTIFIER($demo_wh);

-- ── Account-level objects DROP DATABASE does not cascade ───────────────────
DROP USER IF EXISTS IDENTIFIER($sales_global_u);
DROP USER IF EXISTS IDENTIFIER($sales_emea_u);
DROP USER IF EXISTS IDENTIFIER($support_u);

DROP ROLE IF EXISTS IDENTIFIER($sales_global);
DROP ROLE IF EXISTS IDENTIFIER($sales_emea);
DROP ROLE IF EXISTS IDENTIFIER($support_role);
DROP ROLE IF EXISTS IDENTIFIER($admin_role);

SHOW DATABASES  LIKE 'MULTI_AGENT_MCP_DEMO%';
SHOW WAREHOUSES LIKE 'MULTI_AGENT_MCP_DEMO%';
SHOW ROLES      LIKE 'MULTI_AGENT_MCP_DEMO%';
SHOW USERS      LIKE 'MULTI_AGENT_MCP_DEMO%';

-- ── Alternative: keep the database, drop the demo objects one by one ────────
-- Comment out the fast path above and run this block (as the admin role) to
-- remove just the demo's objects in reverse-dependency order.
--
-- USE ROLE MULTI_AGENT_MCP_DEMO_ADMIN;
-- USE SCHEMA MULTI_AGENT_MCP_DEMO.APP;
-- -- Notebook objects
-- DROP MCP SERVER IF EXISTS TOOLSET_MCP;
-- DROP MCP SERVER IF EXISTS ORCHESTRATOR_MCP;
-- DROP AGENT IF EXISTS TOOLSET_AGENT;
-- DROP TABLE IF EXISTS TOOLSET_EVAL_INPUT;
-- DROP TABLE IF EXISTS ROUTING_EVAL_INPUT;
-- DROP STAGE IF EXISTS EVAL_CONFIG;
-- DROP FILE FORMAT IF EXISTS EVAL_YAML_FORMAT;
-- -- setup.sql objects
-- DROP AGENT IF EXISTS ORCHESTRATOR_AGENT;
-- DROP AGENT IF EXISTS SALES_AGENT;
-- DROP AGENT IF EXISTS SUPPORT_AGENT;
-- DROP PROCEDURE IF EXISTS ASK_SALES_SPECIALIST(VARCHAR);
-- DROP PROCEDURE IF EXISTS ASK_SUPPORT_SPECIALIST(VARCHAR);
-- DROP SEMANTIC VIEW IF EXISTS SALES_SEMANTIC_VIEW;
-- DROP SEMANTIC VIEW IF EXISTS SUPPORT_SEMANTIC_VIEW;
-- ALTER TABLE IF EXISTS SALES_BOOKINGS DROP ALL ROW ACCESS POLICIES;
-- DROP ROW ACCESS POLICY IF EXISTS SALES_THEATER_POLICY;
-- DROP TABLE IF EXISTS SALES_ENTITLEMENTS;
-- DROP TABLE IF EXISTS SALES_BOOKINGS;
-- DROP TABLE IF EXISTS SUPPORT_KB;
-- Evaluation datasets (ROUTING_EVAL_DATASET, TOOLSET_EVAL_DATASET) and runs
-- live in the schema and go with DROP SCHEMA or DROP DATABASE.
