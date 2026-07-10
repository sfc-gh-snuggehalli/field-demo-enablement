-- =============================================================================
-- AI Functions: Customer Experience Telemetry — Lab Setup
-- =============================================================================
-- Run this script once before starting the notebook.
-- It creates the shared demo database, the AI_FUNCTIONS schema, a warehouse, and
-- a small structured CUSTOMERS table. The UNSTRUCTURED text tables (chat threads,
-- call transcripts, support tickets) are loaded by lab/data_gen.py.
--
-- Prerequisites:
--   - A role with CREATE DATABASE (or access to an existing DB) and CREATE WAREHOUSE.
--   - The SNOWFLAKE.CORTEX_USER database role (required for all AI_* functions).
--   - Python + snowflake-snowpark-python + pandas installed locally to run data_gen.py,
--     OR run data_gen.py cells from a Snowflake Notebook.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE AND SCHEMA  (shared across both CX modules)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS FIELD_CX_DEMO;
USE DATABASE FIELD_CX_DEMO;
CREATE SCHEMA IF NOT EXISTS AI_FUNCTIONS;
USE SCHEMA AI_FUNCTIONS;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WAREHOUSE
-- ─────────────────────────────────────────────────────────────────────────────
-- Snowflake recommends a warehouse no larger than MEDIUM for AI functions.

CREATE WAREHOUSE IF NOT EXISTS CX_AI_FUNCTIONS_WH
  WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND = 120
  AUTO_RESUME = TRUE;

USE WAREHOUSE CX_AI_FUNCTIONS_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. STRUCTURED SAMPLE DATA (SQL GENERATOR)
-- ─────────────────────────────────────────────────────────────────────────────
-- CUSTOMERS: a mix of B2C consumers and B2B partners for a home-valuation product.
-- 500 rows, deterministic. The unstructured tables join back to CUSTOMER_ID.

CREATE OR REPLACE TABLE CUSTOMERS AS
SELECT
    seq4() + 1                                                        AS customer_id,
    CASE WHEN UNIFORM(1, 100, RANDOM()) <= 70 THEN 'B2C' ELSE 'B2B' END
                                                                      AS customer_type,
    ['Denver','Boulder','Fort Collins','Colorado Springs','Aurora','Remote']
        [UNIFORM(0, 5, RANDOM())]::STRING                             AS region,
    ['Free','Starter','Pro','Enterprise']
        [UNIFORM(0, 3, RANDOM())]::STRING                             AS plan,
    DATEADD('day', -UNIFORM(1, 900, RANDOM()), CURRENT_DATE())        AS signup_date
FROM TABLE(GENERATOR(ROWCOUNT => 500));

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. UNSTRUCTURED SAMPLE DATA (loaded by lab/data_gen.py)
-- ─────────────────────────────────────────────────────────────────────────────
-- The following text tables are CREATED and loaded by the companion Python script
-- via session.write_pandas(..., auto_create_table=True). Run it after this script:
--
--     python lab/data_gen.py            # local (named connection), or
--     %run from a Snowflake Notebook cell using get_active_session()
--
-- Tables created by data_gen.py (all join to CUSTOMERS.CUSTOMER_ID):
--   CHAT_THREADS(thread_id, customer_id, channel, created_at, transcript)
--   CALL_TRANSCRIPTS(call_id, customer_id, agent_id, call_date, transcript)
--   SUPPORT_TICKETS(ticket_id, customer_id, created_at, subject, body)

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. FEATURE OBJECTS
-- ─────────────────────────────────────────────────────────────────────────────
-- The AI-function pipeline (sentiment, topic classification, extraction,
-- summarization, filtering) is demonstrated live in the notebook so attendees see
-- each function run. Those views read CHAT_THREADS / CALL_TRANSCRIPTS / SUPPORT_TICKETS,
-- so create them AFTER data_gen.py has loaded the unstructured tables.

-- ─────────────────────────────────────────────────────────────────────────────
-- Setup complete.
--   1) You just ran this script (database, schema, warehouse, CUSTOMERS).
--   2) Run: python lab/data_gen.py   (loads CHAT_THREADS, CALL_TRANSCRIPTS, SUPPORT_TICKETS)
--   3) Open lab/cx-ai-functions-lab.ipynb in Snowflake Notebooks.
-- ─────────────────────────────────────────────────────────────────────────────
