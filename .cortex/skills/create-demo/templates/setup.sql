-- =============================================================================
-- {{DECK_TITLE}} Lab: Setup Script
-- =============================================================================
-- Run this script once before starting the notebook.
-- It creates all prerequisite objects: database, schema, warehouse, sample
-- data, and any feature-specific objects the lab uses.
--
-- Prerequisites:
{{PREREQUISITES_COMMENTS}}
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE AND SCHEMA
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS {{DB_NAME}};
USE DATABASE {{DB_NAME}};
CREATE SCHEMA IF NOT EXISTS {{SCHEMA_NAME}};
USE SCHEMA {{SCHEMA_NAME}};

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WAREHOUSE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE WAREHOUSE IF NOT EXISTS {{WH_NAME}}
  WAREHOUSE_SIZE = '{{WH_SIZE}}'
  AUTO_SUSPEND = 120
  AUTO_RESUME = TRUE;

USE WAREHOUSE {{WH_NAME}};

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. SAMPLE DATA
-- ─────────────────────────────────────────────────────────────────────────────
-- Replace the stub below with tables + synthetic INSERTs (or generator SQL)
-- that fit the demo's use case. Keep volumes small enough to run interactively.

-- {{SAMPLE_DATA_STUB}}

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. FEATURE OBJECTS
-- ─────────────────────────────────────────────────────────────────────────────
-- Create the objects the lab demonstrates (UDFs, semantic views, agents,
-- tasks, streams, services, etc.) here.

-- {{FEATURE_OBJECTS_STUB}}

-- ─────────────────────────────────────────────────────────────────────────────
-- Setup complete. Open lab/{{SLUG}}-lab.ipynb in Snowflake Notebooks.
-- ─────────────────────────────────────────────────────────────────────────────
