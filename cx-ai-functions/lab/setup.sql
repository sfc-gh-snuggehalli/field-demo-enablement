-- =============================================================================
-- AI Functions + Conversational BI: Customer Experience Intelligence — Lab Setup
-- =============================================================================
-- Run this script once before starting the notebooks. It provisions the whole
-- module on a single database (FIELD_CX_DEMO) and a single warehouse:
--
--   AI_FUNCTIONS schema  — structured CUSTOMERS + the app UX telemetry model
--                          (stage, raw VARIANT landing table, curated app tables).
--                          The unstructured text tables (chat threads, call
--                          transcripts, support tickets) are loaded by data_gen.py.
--   ANALYTICS schema     — business tables, one governed SEMANTIC VIEW, a Cortex
--                          Search service over the chat telemetry, and a Cortex
--                          Agent that combines them.
--
-- Two notebooks run on top of this:
--   1. cx-ai-functions-lab.ipynb        — the AI-function pipeline + app UX
--                                          telemetry ingestion + AI Function Studio.
--   2. cx-ai-functions-extensions.ipynb — semantic view / Cortex Analyst / Cortex
--                                          Search / Agent + cost & guardrails.
--
-- Prerequisites:
--   - A role with CREATE DATABASE/SCHEMA, CREATE WAREHOUSE, CREATE SEMANTIC VIEW,
--     CREATE CORTEX SEARCH SERVICE, and CREATE AGENT on this schema.
--   - The SNOWFLAKE.CORTEX_USER database role (required for all AI_* functions).
--   - Python + snowflake-snowpark-python + pandas to run data_gen.py, OR run its
--     cells from a Snowflake Notebook.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE, SCHEMAS, WAREHOUSE
-- ─────────────────────────────────────────────────────────────────────────────
-- Snowflake recommends a warehouse no larger than MEDIUM for AI functions.

CREATE DATABASE IF NOT EXISTS FIELD_CX_DEMO;
USE DATABASE FIELD_CX_DEMO;

CREATE SCHEMA IF NOT EXISTS AI_FUNCTIONS;
CREATE SCHEMA IF NOT EXISTS ANALYTICS;

CREATE WAREHOUSE IF NOT EXISTS CX_AI_FUNCTIONS_WH
  WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND = 120
  AUTO_RESUME = TRUE;

USE SCHEMA AI_FUNCTIONS;
USE WAREHOUSE CX_AI_FUNCTIONS_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. STRUCTURED SAMPLE DATA (SQL GENERATOR)
-- ─────────────────────────────────────────────────────────────────────────────
-- CUSTOMERS: a mix of B2C consumers and B2B partners for a home-valuation product.
-- 500 rows, deterministic. The unstructured tables and the app telemetry join
-- back to CUSTOMER_ID.

CREATE OR REPLACE TABLE AI_FUNCTIONS.CUSTOMERS AS
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
-- 3. UNSTRUCTURED SAMPLE DATA (loaded by lab/data_gen.py)
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
--
-- They are pre-created here as empty placeholders so downstream objects (e.g. the
-- Cortex Search service in Section 7) can be created before data_gen.py runs.
-- data_gen.py loads them with write_pandas(overwrite=True), which replaces these
-- placeholders with the populated tables.

CREATE TABLE IF NOT EXISTS AI_FUNCTIONS.CHAT_THREADS (
    thread_id      NUMBER,
    customer_id    NUMBER,
    channel        STRING,
    created_at     TIMESTAMP_NTZ,
    transcript     STRING
);

CREATE TABLE IF NOT EXISTS AI_FUNCTIONS.CALL_TRANSCRIPTS (
    call_id        NUMBER,
    customer_id    NUMBER,
    agent_id       STRING,
    call_date      DATE,
    transcript     STRING
);

CREATE TABLE IF NOT EXISTS AI_FUNCTIONS.SUPPORT_TICKETS (
    ticket_id      NUMBER,
    customer_id    NUMBER,
    created_at     TIMESTAMP_NTZ,
    subject        STRING,
    body           STRING
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. APP UX TELEMETRY MODEL (how a customer's own app data flows into Snowflake)
-- ─────────────────────────────────────────────────────────────────────────────
-- This section models what a real conversational app emits: message-level turns
-- and explicit feedback (thumbs up / down). It demonstrates BOTH ingestion paths:
--
--   (a) RAW / semi-structured landing — an internal stage receives JSON files the
--       app drops; COPY INTO loads them verbatim into a VARIANT column. This is the
--       immutable landing zone: schema-on-read, captures everything the app sends
--       with no schema coordination. (In production the continuous path is Snowpipe
--       or Snowpipe Streaming; the notebook narrates that.)
--
--   (b) CURATED / structured — LATERAL FLATTEN turns the VARIANT into typed tables
--       (APP_THREADS / APP_MESSAGES / APP_FEEDBACK) that are governed, joinable to
--       CUSTOMERS, performant, and feed the AI functions + semantic view.
--
-- The stage + raw table are created here; the notebook (Section: "App UX
-- telemetry") generates sample JSON, lands it in the stage, COPYs it in, and
-- flattens it — so attendees watch the whole flow run.

-- 4a. Internal stage that simulates where the app drops event files.
CREATE STAGE IF NOT EXISTS AI_FUNCTIONS.APP_EVENTS_STAGE
  FILE_FORMAT = (TYPE = JSON)
  COMMENT = 'Landing zone for raw app UX telemetry (one JSON doc per chat thread)';

-- 4b. Raw landing table — one VARIANT payload per file/record, loaded as-is.
CREATE TABLE IF NOT EXISTS AI_FUNCTIONS.RAW_APP_EVENTS (
    payload        VARIANT,
    source_file    STRING,
    loaded_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Raw app telemetry exactly as the app emitted it (schema-on-read).';

-- 4c. Curated structured tables (populated in the notebook by flattening RAW_APP_EVENTS).
--     Defined here so the semantic view / search / agent can reference them, and so
--     the shapes are documented even before the notebook runs.
CREATE TABLE IF NOT EXISTS AI_FUNCTIONS.APP_THREADS (
    thread_id      STRING,
    customer_id    NUMBER,
    channel        STRING,
    app_version    STRING,
    started_at     TIMESTAMP_NTZ
);

CREATE TABLE IF NOT EXISTS AI_FUNCTIONS.APP_MESSAGES (
    message_id     STRING,
    thread_id      STRING,
    turn_no        NUMBER,
    role           STRING,          -- 'user' or 'assistant'
    content        STRING,
    model          STRING,
    created_at     TIMESTAMP_NTZ
);

CREATE TABLE IF NOT EXISTS AI_FUNCTIONS.APP_FEEDBACK (
    message_id     STRING,
    thread_id      STRING,
    rating         NUMBER,          -- +1 thumbs up, -1 thumbs down
    comment        STRING,
    created_at     TIMESTAMP_NTZ
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. ANALYTICS: business tables (structured GENERATOR data)
-- ─────────────────────────────────────────────────────────────────────────────

USE SCHEMA ANALYTICS;

-- Customers of the home-valuation product (mirrors AI_FUNCTIONS.CUSTOMERS shape
-- with the extra columns the semantic view needs).
CREATE OR REPLACE TABLE ANALYTICS.CUSTOMERS AS
SELECT
    seq4() + 1                                                        AS customer_id,
    CASE WHEN UNIFORM(1, 100, RANDOM()) <= 70 THEN 'B2C' ELSE 'B2B' END
                                                                      AS customer_type,
    ['Denver','Boulder','Fort Collins','Colorado Springs','Aurora','Remote']
        [UNIFORM(0, 5, RANDOM())]::STRING                             AS region,
    ['Free','Starter','Pro','Enterprise']
        [UNIFORM(0, 3, RANDOM())]::STRING                             AS plan,
    DATEADD('day', -UNIFORM(30, 900, RANDOM()), CURRENT_DATE())       AS signup_date
FROM TABLE(GENERATOR(ROWCOUNT => 500));

-- One active subscription row per customer with plan-based MRR.
CREATE OR REPLACE TABLE ANALYTICS.SUBSCRIPTIONS AS
SELECT
    customer_id                                                       AS subscription_id,
    customer_id,
    plan,
    CASE plan
        WHEN 'Free'       THEN 0
        WHEN 'Starter'    THEN 29
        WHEN 'Pro'        THEN 99
        WHEN 'Enterprise' THEN 499
    END                                                               AS mrr,
    ['active','active','active','paused','cancelled']
        [UNIFORM(0, 4, RANDOM())]::STRING                             AS status,
    signup_date                                                       AS start_date
FROM ANALYTICS.CUSTOMERS;

-- Engagement events (logins, valuation runs, API calls) drive "highly engaged".
CREATE OR REPLACE TABLE ANALYTICS.ENGAGEMENT_EVENTS AS
SELECT
    seq4() + 1                                                        AS event_id,
    UNIFORM(1, 500, RANDOM())                                         AS customer_id,
    ['login','valuation_run','report_export','api_call']
        [UNIFORM(0, 3, RANDOM())]::STRING                             AS event_type,
    DATEADD('hour', -UNIFORM(1, 4320, RANDOM()), CURRENT_TIMESTAMP()) AS event_ts
FROM TABLE(GENERATOR(ROWCOUNT => 8000));

-- Home valuation requests per customer.
CREATE OR REPLACE TABLE ANALYTICS.HOME_VALUATIONS AS
SELECT
    seq4() + 1                                                        AS valuation_id,
    UNIFORM(1, 500, RANDOM())                                         AS customer_id,
    UNIFORM(250000, 1500000, RANDOM())                                AS estimated_value,
    DATEADD('day', -UNIFORM(1, 700, RANDOM()), CURRENT_DATE())        AS valuation_date
FROM TABLE(GENERATOR(ROWCOUNT => 3000));

-- Churn labels — one per customer (~25% churned).
CREATE OR REPLACE TABLE ANALYTICS.CHURN_LABELS AS
SELECT
    customer_id,
    (UNIFORM(1, 100, RANDOM()) <= 25)                                 AS is_churned,
    CASE WHEN (UNIFORM(1, 100, RANDOM()) <= 25)
         THEN DATEADD('day', -UNIFORM(1, 180, RANDOM()), CURRENT_DATE())
    END                                                               AS churn_date
FROM ANALYTICS.CUSTOMERS;

-- Thumbs feedback rolled up to the customer level so the semantic view can expose a
-- governed "thumbs-down rate". Sourced from the app telemetry curated in the
-- notebook; COALESCE keeps a row per customer even before the notebook has run.
CREATE OR REPLACE TABLE ANALYTICS.CUSTOMER_FEEDBACK AS
SELECT
    c.customer_id,
    COALESCE(f.thumbs_up,   0) AS thumbs_up,
    COALESCE(f.thumbs_down, 0) AS thumbs_down
FROM ANALYTICS.CUSTOMERS c
LEFT JOIN (
    SELECT
        t.customer_id,
        SUM(IFF(fb.rating > 0, 1, 0)) AS thumbs_up,
        SUM(IFF(fb.rating < 0, 1, 0)) AS thumbs_down
    FROM FIELD_CX_DEMO.AI_FUNCTIONS.APP_FEEDBACK fb
    JOIN FIELD_CX_DEMO.AI_FUNCTIONS.APP_THREADS  t ON fb.thread_id = t.thread_id
    GROUP BY t.customer_id
) f ON c.customer_id = f.customer_id;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. ANALYTICS: governed semantic view (one definition of the business)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE SEMANTIC VIEW ANALYTICS.CX_ANALYTICS_SV
  TABLES (
    customers AS ANALYTICS.CUSTOMERS
      PRIMARY KEY (customer_id)
      COMMENT = 'Customers of the home-valuation product (B2C and B2B)',
    subscriptions AS ANALYTICS.SUBSCRIPTIONS
      PRIMARY KEY (subscription_id)
      COMMENT = 'One subscription per customer',
    engagement AS ANALYTICS.ENGAGEMENT_EVENTS
      PRIMARY KEY (event_id)
      COMMENT = 'Product engagement events',
    valuations AS ANALYTICS.HOME_VALUATIONS
      PRIMARY KEY (valuation_id)
      COMMENT = 'Home valuation requests',
    churn AS ANALYTICS.CHURN_LABELS
      PRIMARY KEY (customer_id)
      COMMENT = 'Per-customer churn label',
    feedback AS ANALYTICS.CUSTOMER_FEEDBACK
      PRIMARY KEY (customer_id)
      COMMENT = 'Per-customer thumbs up / down from the app UX telemetry'
  )
  RELATIONSHIPS (
    subs_to_customers AS subscriptions (customer_id) REFERENCES customers,
    events_to_customers AS engagement (customer_id) REFERENCES customers,
    valuations_to_customers AS valuations (customer_id) REFERENCES customers,
    churn_to_customers AS churn (customer_id) REFERENCES customers,
    feedback_to_customers AS feedback (customer_id) REFERENCES customers
  )
  FACTS (
    subscriptions.mrr_fact AS mrr,
    valuations.value_fact AS estimated_value,
    churn.churned_flag AS IFF(is_churned, 1, 0),
    feedback.thumbs_up_fact AS thumbs_up,
    feedback.thumbs_down_fact AS thumbs_down
  )
  DIMENSIONS (
    customers.customer_type AS customer_type
      WITH SYNONYMS = ('segment')
      COMMENT = 'B2C or B2B',
    customers.region AS region
      COMMENT = 'Customer region',
    customers.plan AS plan
      WITH SYNONYMS = ('tier')
      COMMENT = 'Subscription plan',
    customers.signup_month AS DATE_TRUNC('month', signup_date)
      COMMENT = 'Month the customer signed up',
    subscriptions.status AS status
      COMMENT = 'Subscription status',
    engagement.event_type AS event_type
      COMMENT = 'Type of engagement event',
    churn.is_churned AS is_churned
      COMMENT = 'Whether the customer has churned'
  )
  METRICS (
    customers.customer_count AS COUNT(customers.customer_id)
      COMMENT = 'Number of customers',
    subscriptions.total_mrr AS SUM(subscriptions.mrr_fact)
      COMMENT = 'Total monthly recurring revenue',
    subscriptions.avg_mrr AS AVG(subscriptions.mrr_fact)
      COMMENT = 'Average monthly recurring revenue per customer',
    engagement.total_events AS COUNT(engagement.event_id)
      COMMENT = 'Total engagement events',
    valuations.avg_home_value AS AVG(valuations.value_fact)
      COMMENT = 'Average estimated home value',
    churn.churned_customers AS SUM(churn.churned_flag)
      COMMENT = 'Number of churned customers',
    churn_rate AS DIV0(churn.churned_customers, customers.customer_count)
      COMMENT = 'Share of customers that have churned',
    feedback.total_thumbs_up AS SUM(feedback.thumbs_up_fact)
      COMMENT = 'Total thumbs-up on assistant responses',
    feedback.total_thumbs_down AS SUM(feedback.thumbs_down_fact)
      COMMENT = 'Total thumbs-down on assistant responses',
    thumbs_down_rate AS DIV0(SUM(feedback.thumbs_down_fact),
                             SUM(feedback.thumbs_up_fact) + SUM(feedback.thumbs_down_fact))
      COMMENT = 'Share of rated assistant responses that got a thumbs-down'
  )
  COMMENT = 'Centralized customer, revenue, engagement, churn, and app-feedback definitions'
  AI_VERIFIED_QUERIES (
    churn_by_plan AS (
      QUESTION 'What is the churn rate by plan?'
      SQL 'SELECT * FROM SEMANTIC_VIEW(ANALYTICS.CX_ANALYTICS_SV METRICS churn_rate DIMENSIONS customers.plan)'
    ),
    thumbs_down_by_plan AS (
      QUESTION 'What is the thumbs-down rate by plan?'
      SQL 'SELECT * FROM SEMANTIC_VIEW(ANALYTICS.CX_ANALYTICS_SV METRICS thumbs_down_rate DIMENSIONS customers.plan)'
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. ANALYTICS: Cortex Search over the unstructured CX telemetry
-- ─────────────────────────────────────────────────────────────────────────────
-- Reads FIELD_CX_DEMO.AI_FUNCTIONS.CHAT_THREADS (loaded by data_gen.py). If you
-- have not run data_gen.py yet, run it before this statement (or re-run this
-- statement afterward).

CREATE OR REPLACE CORTEX SEARCH SERVICE ANALYTICS.CHAT_SEARCH
  ON transcript
  ATTRIBUTES customer_id, channel
  WAREHOUSE = CX_AI_FUNCTIONS_WH
  TARGET_LAG = '1 hour'
AS (
  SELECT
      thread_id,
      transcript,
      customer_id,
      channel
  FROM FIELD_CX_DEMO.AI_FUNCTIONS.CHAT_THREADS
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. ANALYTICS: Cortex Agent (structured metrics + unstructured chat)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE AGENT ANALYTICS.CX_INTELLIGENCE_AGENT
  COMMENT = 'Conversational BI over churn/revenue/feedback metrics plus CX chat telemetry'
  PROFILE = '{"display_name": "CX Intelligence", "color": "blue"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  instructions:
    response: "Answer concisely and cite whether the answer came from metrics or chat transcripts."
    orchestration: "Use Analyst for churn, revenue, engagement, feedback (thumbs up/down), and customer-count questions. Use Search for questions about what customers said or how they feel. Combine both when a question links metrics to conversations."
    sample_questions:
      - question: "What is the churn rate by plan?"
      - question: "What is the thumbs-down rate by plan?"
      - question: "Which churn-risk customers had negative support chats?"

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "CX_Metrics"
        description: "Churn, revenue (MRR), engagement, home value, thumbs up/down feedback, and customer counts from the governed semantic view."
    - tool_spec:
        type: "cortex_search"
        name: "Chat_Telemetry"
        description: "Customer chat transcripts. Use for what customers asked about or how they felt."
    - tool_spec:
        type: "data_to_chart"
        name: "data_to_chart"
        description: "Generates visualizations from returned data."

  tool_resources:
    CX_Metrics:
      semantic_view: "FIELD_CX_DEMO.ANALYTICS.CX_ANALYTICS_SV"
      execution_environment:
        type: "warehouse"
        warehouse: "CX_AI_FUNCTIONS_WH"
    Chat_Telemetry:
      name: "FIELD_CX_DEMO.ANALYTICS.CHAT_SEARCH"
      max_results: "5"
      id_column: "THREAD_ID"
      columns_and_descriptions:
        TRANSCRIPT:
          description: "Full customer chat transcript."
          type: "string"
          searchable: true
          filterable: false
        CUSTOMER_ID:
          description: "Customer identifier, joins to the semantic view."
          type: "string"
          searchable: false
          filterable: true
  $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Setup complete.
--   1) You just ran this script (schemas, warehouse, structured + app-telemetry
--      objects, semantic view, search service, agent).
--   2) Run: python lab/data_gen.py   (loads CHAT_THREADS, CALL_TRANSCRIPTS, SUPPORT_TICKETS)
--      then re-run Section 7 (CHAT_SEARCH) if it ran before the data was present.
--   3) Open lab/cx-ai-functions-lab.ipynb (AI-function pipeline + app UX telemetry),
--      then lab/cx-ai-functions-extensions.ipynb (semantic view / Analyst / Search /
--      Agent + cost & guardrails), or chat with CX_INTELLIGENCE_AGENT in Snowsight.
-- ─────────────────────────────────────────────────────────────────────────────
