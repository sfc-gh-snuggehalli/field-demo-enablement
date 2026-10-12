-- ACME Assist — server-side conversation history (HISTORY_STORE=snowflake)
-- Run once as an admin after setup.sql.
USE ROLE SYSADMIN;
CREATE SCHEMA IF NOT EXISTS ACME_ASSIST_DEMO.APP;

CREATE TABLE IF NOT EXISTS ACME_ASSIST_DEMO.APP.CONVERSATIONS (
  conversation_id   STRING        NOT NULL,
  owner_user        STRING        NOT NULL,
  title             STRING,
  brand             STRING,
  ui_messages       VARIANT,
  wire_history      VARIANT,
  studio_session_id STRING,
  created_at        TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
  updated_at        TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT pk_conversations PRIMARY KEY (owner_user, conversation_id)
);

-- Run records for cross-instance resume (RUN_STORE=snowflake; needed for max_instances > 1).
-- Metadata only (ids, owner, sequence cursor, status); never prompts or events.
CREATE TABLE IF NOT EXISTS ACME_ASSIST_DEMO.APP.AGENT_RUNS (
  run_id           STRING        NOT NULL,
  owner_user       STRING        NOT NULL,
  conversation_id  STRING        NOT NULL,
  thread_id        STRING,
  agent            STRING,
  upstream_run_id  STRING,
  seq_base         NUMBER        DEFAULT 0,
  last_seq         NUMBER        DEFAULT 0,
  status           STRING,
  updated_at       TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT pk_agent_runs PRIMARY KEY (run_id)
);

USE ROLE ACCOUNTADMIN;
CREATE ROLE IF NOT EXISTS ACME_HISTORY_ROLE;
GRANT ROLE ACME_HISTORY_ROLE TO ROLE SYSADMIN;
GRANT USAGE ON WAREHOUSE ACME_ASSIST_WH TO ROLE ACME_HISTORY_ROLE;
GRANT USAGE ON DATABASE ACME_ASSIST_DEMO TO ROLE ACME_HISTORY_ROLE;
GRANT USAGE ON SCHEMA ACME_ASSIST_DEMO.APP TO ROLE ACME_HISTORY_ROLE;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ACME_ASSIST_DEMO.APP.CONVERSATIONS TO ROLE ACME_HISTORY_ROLE;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ACME_ASSIST_DEMO.APP.AGENT_RUNS TO ROLE ACME_HISTORY_ROLE;
-- GRANT ROLE ACME_HISTORY_ROLE TO USER <app_user>;   -- the PAT / service user
-- Caller grant so the caller's-rights App Runtime app (owner SYSADMIN) can use the table:
GRANT CALLER SELECT, INSERT, UPDATE, DELETE ON TABLE ACME_ASSIST_DEMO.APP.CONVERSATIONS TO ROLE SYSADMIN;
USE ROLE SYSADMIN;
