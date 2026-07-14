-- =============================================================================
-- Donor Lapse/Churn Intelligence: Snowflake ML -> Agent — Cleanup
-- =============================================================================
-- Tears down everything the module creates so you can start fresh, then re-run
-- lab/setup.sql. DONOR_CHURN_ML_DEMO is dedicated to this demo, so the fast path
-- simply drops the database (cascading every schema, table, view, stage, feature
-- store, ML function, model, model monitor, semantic view, tool function, and
-- agent created by setup.sql AND the three notebooks) plus the account-level
-- objects (two warehouses + the compute pool) that a DROP DATABASE will NOT
-- cascade.
--
-- Requires a role that OWNS the objects (the role you ran setup.sql / the
-- notebooks with, e.g. ACCOUNTADMIN or SYSADMIN). All statements use IF EXISTS,
-- so this is safe to run repeatedly or against a partially-created demo.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- FAST PATH — drop the whole demo (recommended for "start fresh")
-- ─────────────────────────────────────────────────────────────────────────────

-- Optional task graph (notebook Section 14). Dropping the database removes the
-- task objects, but suspend first if it is actively scheduled to stop future runs.
-- ALTER TASK IF EXISTS DONOR_CHURN_ML_DEMO.MODELS."DONOR_LAPSE_TRAINING_DAG$PREP_TRAINING_DATA" SUSPEND;

DROP DATABASE IF EXISTS DONOR_CHURN_ML_DEMO;

-- Warehouses live at the account level — not cascaded by DROP DATABASE.
DROP WAREHOUSE IF EXISTS DONOR_CHURN_ML_WH;
DROP WAREHOUSE IF EXISTS DONOR_CHURN_ML_SOWH;

-- Compute pool (notebook ML Jobs / task DAG) also lives at the account level.
-- It keeps billing while RUNNING, so drop it (safe if it was never created).
DROP COMPUTE POOL IF EXISTS DONOR_CHURN_ML_POOL;

-- ─────────────────────────────────────────────────────────────────────────────
-- Cleanup complete. Re-run lab/setup.sql, then the notebooks, to rebuild.
-- ─────────────────────────────────────────────────────────────────────────────


-- =============================================================================
-- ALTERNATIVE — object-by-object teardown (KEEP the database/warehouse)
-- =============================================================================
-- Use this instead of the fast path if DONOR_CHURN_ML_DEMO holds other work you
-- want to keep. Comment out the DROP DATABASE / DROP WAREHOUSE / DROP COMPUTE
-- POOL lines above and run the block below. Order matters: dependents (agent,
-- tool functions, monitor, model) before the tables/views they read.
--
-- USE DATABASE DONOR_CHURN_ML_DEMO;
--
-- -- MODELS: agent -> tool functions -> monitor -> registry model -> ML functions
-- DROP AGENT IF EXISTS MODELS.DONOR_RETENTION_AGENT;
-- DROP FUNCTION IF EXISTS MODELS.TOP_CHURN_RISK(STRING, NUMBER);
-- DROP FUNCTION IF EXISTS MODELS.PREDICT_DONOR_CHURN(NUMBER);
-- DROP MODEL MONITOR IF EXISTS MODELS.DONOR_LAPSE_MONITOR;
-- DROP MODEL IF EXISTS MODELS.DONOR_LAPSE_MODEL;
-- DROP TABLE IF EXISTS MODELS.LAPSE_BASELINE_SNAPSHOT;
-- DROP TABLE IF EXISTS MODELS.LAPSE_SCORING_LOG;
-- DROP TABLE IF EXISTS MODELS.DONOR_LAPSE_SCORES;
-- DROP SNOWFLAKE.ML.CLASSIFICATION IF EXISTS MODELS.LAPSE_BASELINE_MODEL;
-- DROP SNOWFLAKE.ML.ANOMALY_DETECTION IF EXISTS MODELS.DONATION_VOLUME_ANOMALY;
-- DROP SNOWFLAKE.ML.FORECAST IF EXISTS MODELS.DONATION_VOLUME_FORECAST;
-- DROP VIEW IF EXISTS MODELS.LAPSE_CLASSIFY_INPUT;
-- DROP STAGE IF EXISTS MODELS.PAYLOAD_STAGE;
-- DROP SCHEMA IF EXISTS MODELS;
--
-- -- ANALYTICS: semantic view
-- DROP SEMANTIC VIEW IF EXISTS ANALYTICS.DONOR_CHURN_SV;
-- DROP SCHEMA IF EXISTS ANALYTICS;
--
-- -- FEATURES: Feature Store views + snapshot calendar + dataset (notebook 01)
-- --   Feature views / entities / datasets are managed by the Feature Store API;
-- --   dropping the schema removes the underlying objects.
-- DROP TABLE IF EXISTS FEATURES.LAPSE_TRAINING_CURRENT;
-- DROP TABLE IF EXISTS FEATURES.SNAPSHOT_CALENDAR;
-- DROP SCHEMA IF EXISTS FEATURES;
--
-- -- RAW: training views + synthetic source tables
-- DROP VIEW IF EXISTS RAW.DONATION_VOLUME_TS;
-- DROP VIEW IF EXISTS RAW.DONOR_TRAINING_BASE;
-- DROP TABLE IF EXISTS RAW.ENGAGEMENTS;
-- DROP TABLE IF EXISTS RAW.DONATIONS;
-- DROP TABLE IF EXISTS RAW.DONORS;
-- DROP SCHEMA IF EXISTS RAW;
-- =============================================================================
