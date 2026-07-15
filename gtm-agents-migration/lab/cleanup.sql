-- =============================================================================
-- Migrating GTM AI: Claude Code + MCP -> Cortex Agents + CoWork — Cleanup
-- =============================================================================
-- Tears down everything the module creates so you can start fresh, then re-run
-- lab/setup.sql. GTMAGENTS is dedicated to this demo, so the fast path simply
-- drops the database (cascading every table, semantic view, Cortex Search
-- service, UDF, procedure, agent, and MCP server created by setup.sql AND the
-- four notebooks) plus the account-level objects (warehouse, role, and OAuth
-- security integration) that a DROP DATABASE will NOT cascade.
--
-- Requires a role that OWNS the objects (the role you ran setup.sql / the
-- notebooks with, e.g. SYSADMIN) and ACCOUNTADMIN for the account-level security
-- integration + role. All statements use IF EXISTS, so this is safe to run
-- repeatedly or against a partially-created demo.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- FAST PATH — drop the whole demo (recommended for "start fresh")
-- ─────────────────────────────────────────────────────────────────────────────

USE ROLE SYSADMIN;

-- Database cascades: EMAILS/REPS/OUTCOMES/EMAIL_FRAMEWORK, the log tables
-- (ROUTING_LOG/FILTER_VOLUME), the eval objects (AGENT_EVAL_QUESTIONS,
-- EVAL_SCORE_HISTORY, EVAL_STAGE, GTM_EVAL_DATASET, RUN_GTM_EVAL, GTM_EVAL_REGRESSION_CHECK),
-- EMAIL_GTM_SV, FRAMEWORK_SEARCH, GTM_TEAM_PERFORMANCE, SCORE_EMAIL_INTENT_PROC, the three
-- wrapper procs, all four agents, and the GTMAGENTS_MCP server.
DROP DATABASE IF EXISTS GTMAGENTS;

-- Warehouse lives at the account level — not cascaded by DROP DATABASE.
DROP WAREHOUSE IF EXISTS GTMAGENTS_WH;

-- Account-level security integration + role (created for Part A / least-privilege).
USE ROLE ACCOUNTADMIN;
DROP SECURITY INTEGRATION IF EXISTS GTMAGENTS_MCP_OAUTH;
DROP ROLE IF EXISTS GTMAGENTS_ROLE;

-- If you ran the opt-in cell in gtm-02 that set the MCP user's session defaults,
-- revert them (replace <your_user> and restore prior values as needed):
-- ALTER USER <your_user> UNSET DEFAULT_ROLE;
-- ALTER USER <your_user> UNSET DEFAULT_WAREHOUSE;

-- ─────────────────────────────────────────────────────────────────────────────
-- Cleanup complete. Re-run lab/setup.sql, then the notebooks, to rebuild.
-- ─────────────────────────────────────────────────────────────────────────────


-- =============================================================================
-- ALTERNATIVE — object-by-object teardown (KEEP the database/warehouse)
-- =============================================================================
-- Use this instead of the fast path if GTMAGENTS holds other work you want to
-- keep. Comment out the DROP DATABASE / DROP WAREHOUSE / DROP ROLE / DROP
-- SECURITY INTEGRATION lines above and run the block below. Order matters:
-- dependents (supervisor -> wrapper procs -> specialist agents; MCP server)
-- before the tools/tables they read.
--
-- USE ROLE SYSADMIN;
-- USE DATABASE GTMAGENTS;
--
-- -- Agents: supervisor first, then specialists
-- DROP AGENT IF EXISTS DEMO.GTM_SUPERVISOR;
-- DROP AGENT IF EXISTS DEMO.GTM_SCORING_AGENT;
-- DROP AGENT IF EXISTS DEMO.GTM_RECOMMENDATION_AGENT;
-- DROP AGENT IF EXISTS DEMO.GTM_COACHING_AGENT;
--
-- -- Agent-to-agent wrapper procedures + scoring procedure
-- DROP PROCEDURE IF EXISTS DEMO.RUN_SCORING_AGENT(STRING);
-- DROP PROCEDURE IF EXISTS DEMO.RUN_RECOMMENDATION_AGENT(STRING);
-- DROP PROCEDURE IF EXISTS DEMO.RUN_COACHING_AGENT(STRING);
-- DROP PROCEDURE IF EXISTS DEMO.SCORE_EMAIL_INTENT_PROC(NUMBER);
--
-- -- MCP server (Part A)
-- DROP MCP SERVER IF EXISTS DEMO.GTMAGENTS_MCP;
--
-- -- Tools: semantic view, Cortex Search, governed UDF
-- DROP SEMANTIC VIEW IF EXISTS DEMO.EMAIL_GTM_SV;
-- DROP CORTEX SEARCH SERVICE IF EXISTS DEMO.FRAMEWORK_SEARCH;
-- DROP FUNCTION IF EXISTS DEMO.GTM_TEAM_PERFORMANCE(STRING);
--
-- -- Logging tables
-- DROP TABLE IF EXISTS DEMO.ROUTING_LOG;
-- DROP TABLE IF EXISTS DEMO.FILTER_VOLUME;
--
-- -- Eval objects (Part C)
-- DROP TASK IF EXISTS DEMO.GTM_EVAL_REGRESSION_CHECK;
-- DROP PROCEDURE IF EXISTS DEMO.RUN_GTM_EVAL();
-- DROP DATASET IF EXISTS DEMO.GTM_EVAL_DATASET;
-- DROP TABLE IF EXISTS DEMO.EVAL_SCORE_HISTORY;
-- DROP TABLE IF EXISTS DEMO.AGENT_EVAL_QUESTIONS;
-- DROP STAGE IF EXISTS DEMO.EVAL_STAGE;
--
-- -- Source data
-- DROP TABLE IF EXISTS DEMO.OUTCOMES;
-- DROP TABLE IF EXISTS DEMO.EMAILS;
-- DROP TABLE IF EXISTS DEMO.REPS;
-- DROP TABLE IF EXISTS DEMO.EMAIL_FRAMEWORK;
--
-- -- Account-level (only if you also want these gone)
-- USE ROLE ACCOUNTADMIN;
-- DROP SECURITY INTEGRATION IF EXISTS GTMAGENTS_MCP_OAUTH;
-- =============================================================================
