-- =============================================================================
-- Conversational BI: Semantic Views + Cortex Analyst + Agent — Lab Setup
-- =============================================================================
-- Run this script once before starting the notebook.
-- It creates the ANALYTICS schema in the shared FIELD_CX_DEMO database, the
-- structured business tables, one governed SEMANTIC VIEW (centralized churn /
-- revenue / engagement definitions), a Cortex Search service over the CX
-- telemetry from the AI Functions module, and a Cortex Agent that combines them.
--
-- Prerequisites:
--   - A role with CREATE DATABASE / SCHEMA, CREATE WAREHOUSE, CREATE SEMANTIC VIEW,
--     CREATE CORTEX SEARCH SERVICE, and CREATE AGENT on this schema.
--   - The SNOWFLAKE.CORTEX_USER database role.
--   - Recommended: run the "AI Functions: Customer Experience Telemetry" module first
--     (cx-ai-functions/lab) so FIELD_CX_DEMO.AI_FUNCTIONS.CHAT_THREADS exists for the
--     Cortex Search service and the agent's unstructured tool.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE AND SCHEMA  (shared across both CX modules)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS FIELD_CX_DEMO;
USE DATABASE FIELD_CX_DEMO;
CREATE SCHEMA IF NOT EXISTS ANALYTICS;
USE SCHEMA ANALYTICS;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WAREHOUSE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE WAREHOUSE IF NOT EXISTS CONVERSATIONAL_BI_WH
  WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND = 120
  AUTO_RESUME = TRUE;

USE WAREHOUSE CONVERSATIONAL_BI_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. STRUCTURED SAMPLE DATA (SQL GENERATOR)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE CUSTOMERS AS
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
CREATE OR REPLACE TABLE SUBSCRIPTIONS AS
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
FROM CUSTOMERS;

-- Engagement events (logins, valuation runs, API calls) drive "highly engaged".
CREATE OR REPLACE TABLE ENGAGEMENT_EVENTS AS
SELECT
    seq4() + 1                                                        AS event_id,
    UNIFORM(1, 500, RANDOM())                                         AS customer_id,
    ['login','valuation_run','report_export','api_call']
        [UNIFORM(0, 3, RANDOM())]::STRING                             AS event_type,
    DATEADD('hour', -UNIFORM(1, 4320, RANDOM()), CURRENT_TIMESTAMP()) AS event_ts
FROM TABLE(GENERATOR(ROWCOUNT => 8000));

-- Home valuation requests per customer.
CREATE OR REPLACE TABLE HOME_VALUATIONS AS
SELECT
    seq4() + 1                                                        AS valuation_id,
    UNIFORM(1, 500, RANDOM())                                         AS customer_id,
    UNIFORM(250000, 1500000, RANDOM())                                AS estimated_value,
    DATEADD('day', -UNIFORM(1, 700, RANDOM()), CURRENT_DATE())        AS valuation_date
FROM TABLE(GENERATOR(ROWCOUNT => 3000));

-- Churn labels — one per customer (~25% churned).
CREATE OR REPLACE TABLE CHURN_LABELS AS
SELECT
    customer_id,
    (UNIFORM(1, 100, RANDOM()) <= 25)                                 AS is_churned,
    CASE WHEN (UNIFORM(1, 100, RANDOM()) <= 25)
         THEN DATEADD('day', -UNIFORM(1, 180, RANDOM()), CURRENT_DATE())
    END                                                               AS churn_date
FROM CUSTOMERS;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. UNSTRUCTURED DATA (from the AI Functions module)
-- ─────────────────────────────────────────────────────────────────────────────
-- The Cortex Search service and agent below read
-- FIELD_CX_DEMO.AI_FUNCTIONS.CHAT_THREADS, created by cx-ai-functions/lab/data_gen.py.
-- Run that module first. (If you only want the semantic view + Analyst, you can skip
-- the search service and the agent's Search tool.)

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. FEATURE OBJECTS
-- ─────────────────────────────────────────────────────────────────────────────

-- 5a. Semantic view — one governed definition of churn / revenue / engagement.
CREATE OR REPLACE SEMANTIC VIEW CX_ANALYTICS_SV
  TABLES (
    customers AS CUSTOMERS
      PRIMARY KEY (customer_id)
      COMMENT = 'Customers of the home-valuation product (B2C and B2B)',
    subscriptions AS SUBSCRIPTIONS
      PRIMARY KEY (subscription_id)
      COMMENT = 'One subscription per customer',
    engagement AS ENGAGEMENT_EVENTS
      PRIMARY KEY (event_id)
      COMMENT = 'Product engagement events',
    valuations AS HOME_VALUATIONS
      PRIMARY KEY (valuation_id)
      COMMENT = 'Home valuation requests',
    churn AS CHURN_LABELS
      PRIMARY KEY (customer_id)
      COMMENT = 'Per-customer churn label'
  )
  RELATIONSHIPS (
    subs_to_customers AS subscriptions (customer_id) REFERENCES customers,
    events_to_customers AS engagement (customer_id) REFERENCES customers,
    valuations_to_customers AS valuations (customer_id) REFERENCES customers,
    churn_to_customers AS churn (customer_id) REFERENCES customers
  )
  FACTS (
    subscriptions.mrr_fact AS mrr,
    valuations.value_fact AS estimated_value,
    churn.churned_flag AS IFF(is_churned, 1, 0)
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
      COMMENT = 'Share of customers that have churned'
  )
  COMMENT = 'Centralized customer, revenue, engagement, and churn definitions'
  AI_VERIFIED_QUERIES (
    churn_by_plan AS (
      QUESTION 'What is the churn rate by plan?'
      SQL 'SELECT * FROM SEMANTIC_VIEW(CX_ANALYTICS_SV METRICS churn_rate DIMENSIONS customers.plan)'
    )
  );

-- 5b. Cortex Search service over the unstructured CX telemetry (needs Module A).
CREATE OR REPLACE CORTEX SEARCH SERVICE CHAT_SEARCH
  ON transcript
  ATTRIBUTES customer_id, channel
  WAREHOUSE = CONVERSATIONAL_BI_WH
  TARGET_LAG = '1 hour'
AS (
  SELECT
      thread_id,
      transcript,
      customer_id,
      channel
  FROM FIELD_CX_DEMO.AI_FUNCTIONS.CHAT_THREADS
);

-- 5c. Cortex Agent combining structured (Analyst over the semantic view) and
--     unstructured (Cortex Search over chat telemetry) tools, plus charting.
CREATE OR REPLACE AGENT CX_INTELLIGENCE_AGENT
  COMMENT = 'Conversational BI over churn/revenue metrics plus CX chat telemetry'
  PROFILE = '{"display_name": "CX Intelligence", "color": "blue"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  instructions:
    response: "Answer concisely and cite whether the answer came from metrics or chat transcripts."
    orchestration: "Use Analyst for churn, revenue, engagement, and customer-count questions. Use Search for questions about what customers said or how they feel. Combine both when a question links metrics to conversations."
    sample_questions:
      - question: "What is the churn rate by plan?"
      - question: "Which churn-risk customers had negative support chats?"

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "CX_Metrics"
        description: "Churn, revenue (MRR), engagement, home value, and customer counts from the governed semantic view."
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
        warehouse: "CONVERSATIONAL_BI_WH"
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
--   1) You just ran this script (structured tables, semantic view, search, agent).
--   2) Open lab/conversational-bi-lab.ipynb in Snowflake Notebooks, or chat with
--      CX_INTELLIGENCE_AGENT in Snowsight (AI & ML -> Agents).
-- ─────────────────────────────────────────────────────────────────────────────
