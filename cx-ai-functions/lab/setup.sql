-- =============================================================================
-- AI Functions + Conversational BI: Customer Experience Intelligence — Lab Setup
-- =============================================================================
-- Run this ONE script before the notebooks. It provisions AND fully populates the
-- whole module on a single database (FIELD_CX_DEMO) and a single warehouse, so
-- every downstream object is valid the moment this script finishes — no Python,
-- no second data-loading step, and no re-creating the search service.
--
--   AI_FUNCTIONS schema  — structured CUSTOMERS, the unstructured text tables
--                          (chat threads, call transcripts, support tickets), and
--                          the app UX telemetry model (stage, raw VARIANT landing
--                          table, curated APP_* tables). All loaded here in SQL.
--   ANALYTICS schema     — business tables, one governed SEMANTIC VIEW, a Cortex
--                          Search service over the chat telemetry, and a Cortex
--                          Agent that combines them. Created LAST, over data that
--                          already exists.
--
-- Two notebooks run on top of this (neither generates data — they demonstrate):
--   1. cx-ai-functions-lab.ipynb        — run the AI-function pipeline + a read-only
--                                          tour of the app-telemetry setup loaded,
--                                          plus AI Function Studio and cost.
--   2. cx-ai-functions-extensions.ipynb — integrate: semantic view / Cortex Analyst /
--                                          Cortex Search / Agent + cost & guardrails.
--
-- Prerequisites:
--   - A role with CREATE DATABASE/SCHEMA, CREATE WAREHOUSE, CREATE SEMANTIC VIEW,
--     CREATE CORTEX SEARCH SERVICE, and CREATE AGENT on this schema.
--   - The SNOWFLAKE.CORTEX_USER database role (required for all AI_* functions).
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
-- 3. UNSTRUCTURED SAMPLE DATA (SQL GENERATOR)
-- ─────────────────────────────────────────────────────────────────────────────
-- The three text tables the AI functions run against are generated here in pure
-- SQL. Each row draws a topic and a
-- sentiment; ARRAY_CONSTRUCT + GET pick a realistic snippet for that combination,
-- and the transcript is assembled with string concatenation. Sentiment is skewed
-- toward negative/mixed so AI_SENTIMENT, AI_CLASSIFY, AI_AGG, and AI_FILTER return
-- interesting, non-uniform results.
--
-- Topic taxonomy (index -> topic):
--   0 valuation_accuracy  1 pricing_billing  2 onboarding
--   3 bug_report          4 cancellation     5 feature_request
-- Sentiment (index): 0 negative  1 positive  2 neutral   (weighted ~45/35/20)

-- 3a. CHAT_THREADS — multi-turn customer <-> assistant conversations.
CREATE OR REPLACE TABLE AI_FUNCTIONS.CHAT_THREADS AS
WITH base AS (
    SELECT
        seq4() + 1                                                    AS thread_id,
        UNIFORM(1, 500, RANDOM())                                     AS customer_id,
        ['web_chat','in_app','mobile'][UNIFORM(0, 2, RANDOM())]::STRING AS channel,
        DATEADD('minute', -UNIFORM(1, 260000, RANDOM()), CURRENT_TIMESTAMP()) AS created_at,
        UNIFORM(0, 5, RANDOM())                                       AS topic_idx,
        CASE WHEN UNIFORM(1, 100, RANDOM()) <= 45 THEN 0
             WHEN UNIFORM(1, 100, RANDOM()) <= 64 THEN 2
             ELSE 1 END                                               AS sentiment_idx
    FROM TABLE(GENERATOR(ROWCOUNT => 1200))
),
snippet AS (
    SELECT base.*,
        GET(CASE topic_idx
            WHEN 0 THEN ARRAY_CONSTRUCT(
                'Your valuation is way off. It says my house is worth 80k less than three appraisers told me.',
                'The home value estimate was spot on - matched my recent appraisal within a couple percent.',
                'How often does the estimated home value get refreshed after I update the square footage?')
            WHEN 1 THEN ARRAY_CONSTRUCT(
                'I was charged twice this month and the Pro plan price jumped without any notice.',
                'Upgrading to Pro was worth it, the comps report alone pays for the subscription.',
                'Can you explain the difference between the Starter and Pro plans for billing?')
            WHEN 2 THEN ARRAY_CONSTRUCT(
                'I have been stuck on the onboarding step for an hour, the address import keeps failing.',
                'Setup was painless, I connected my listings and had a dashboard in ten minutes.',
                'Where do I find the guide for importing my B2B partner property portfolio?')
            WHEN 3 THEN ARRAY_CONSTRUCT(
                'The valuation chart is completely broken, it throws an error every time I open it.',
                'Thanks for the quick fix - the map view loads correctly now.',
                'Is the mobile app supposed to show the same comps as the web version?')
            WHEN 4 THEN ARRAY_CONSTRUCT(
                'I want to cancel immediately and get a refund, this product is not working for me.',
                'I was going to cancel but the new market-trends feature convinced me to stay.',
                'If I cancel mid-cycle, do I keep access until the end of the billing period?')
            ELSE ARRAY_CONSTRUCT(
                'Every competitor has API access and you still do not. This is a dealbreaker for our team.',
                'Love the product - it would be perfect if you added rental yield estimates too.',
                'Are there plans to support commercial property valuations for B2B accounts?')
        END, sentiment_idx)::STRING                                   AS user_snippet
    FROM base
)
SELECT
    thread_id,
    customer_id,
    channel,
    created_at,
    'Customer: Hi, I need help with my account.\n' ||
    'Assistant: Happy to help - what''s going on?\n' ||
    'Customer: ' || user_snippet || '\n' ||
    'Assistant: Thanks for the detail, let me look into that for you.\n' ||
    'Customer: ' || GET(ARRAY_CONSTRUCT(
        'Please hurry, this is frustrating.',
        'Appreciate it.',
        'Okay, thanks.'), sentiment_idx)::STRING                      AS transcript
FROM snippet;

-- 3b. CALL_TRANSCRIPTS — text stand-ins for support call recordings.
CREATE OR REPLACE TABLE AI_FUNCTIONS.CALL_TRANSCRIPTS AS
WITH base AS (
    SELECT
        seq4() + 1                                                    AS call_id,
        UNIFORM(1, 500, RANDOM())                                     AS customer_id,
        'agent_' || LPAD(UNIFORM(1, 10, RANDOM()), 2, '0')            AS agent_id,
        DATEADD('day', -UNIFORM(0, 180, RANDOM()), CURRENT_DATE())    AS call_date,
        UNIFORM(0, 5, RANDOM())                                       AS topic_idx,
        CASE WHEN UNIFORM(1, 100, RANDOM()) <= 45 THEN 0
             WHEN UNIFORM(1, 100, RANDOM()) <= 64 THEN 2
             ELSE 1 END                                               AS sentiment_idx
    FROM TABLE(GENERATOR(ROWCOUNT => 400))
),
snippet AS (
    SELECT base.*,
        GET(CASE topic_idx
            WHEN 0 THEN ARRAY_CONSTRUCT(
                'Your valuation is way off. It says my house is worth 80k less than three appraisers told me.',
                'The home value estimate was spot on - matched my recent appraisal within a couple percent.',
                'How often does the estimated home value get refreshed after I update the square footage?')
            WHEN 1 THEN ARRAY_CONSTRUCT(
                'I was charged twice this month and the Pro plan price jumped without any notice.',
                'Upgrading to Pro was worth it, the comps report alone pays for the subscription.',
                'Can you explain the difference between the Starter and Pro plans for billing?')
            WHEN 2 THEN ARRAY_CONSTRUCT(
                'I have been stuck on the onboarding step for an hour, the address import keeps failing.',
                'Setup was painless, I connected my listings and had a dashboard in ten minutes.',
                'Where do I find the guide for importing my B2B partner property portfolio?')
            WHEN 3 THEN ARRAY_CONSTRUCT(
                'The valuation chart is completely broken, it throws an error every time I open it.',
                'Thanks for the quick fix - the map view loads correctly now.',
                'Is the mobile app supposed to show the same comps as the web version?')
            WHEN 4 THEN ARRAY_CONSTRUCT(
                'I want to cancel immediately and get a refund, this product is not working for me.',
                'I was going to cancel but the new market-trends feature convinced me to stay.',
                'If I cancel mid-cycle, do I keep access until the end of the billing period?')
            ELSE ARRAY_CONSTRUCT(
                'Every competitor has API access and you still do not. This is a dealbreaker for our team.',
                'Love the product - it would be perfect if you added rental yield estimates too.',
                'Are there plans to support commercial property valuations for B2B accounts?')
        END, sentiment_idx)::STRING                                   AS caller_snippet
    FROM base
)
SELECT
    call_id,
    customer_id,
    agent_id,
    call_date,
    'Agent: Thank you for calling home valuation support, this is ' || agent_id || '.\n' ||
    'Caller: ' || caller_snippet || '\n' ||
    'Agent: I understand. Let me pull up your account and take a look.\n' ||
    'Caller: ' || GET(ARRAY_CONSTRUCT(
        'I have called about this three times now.',
        'Great, thank you so much.',
        'Sure, take your time.'), sentiment_idx)::STRING              AS transcript
FROM snippet;

-- 3c. SUPPORT_TICKETS — free-text tickets with a topic-derived subject.
CREATE OR REPLACE TABLE AI_FUNCTIONS.SUPPORT_TICKETS AS
WITH base AS (
    SELECT
        seq4() + 1                                                    AS ticket_id,
        UNIFORM(1, 500, RANDOM())                                     AS customer_id,
        DATEADD('hour', -UNIFORM(0, 4320, RANDOM()), CURRENT_TIMESTAMP()) AS created_at,
        UNIFORM(0, 5, RANDOM())                                       AS topic_idx,
        CASE WHEN UNIFORM(1, 100, RANDOM()) <= 45 THEN 0
             WHEN UNIFORM(1, 100, RANDOM()) <= 64 THEN 2
             ELSE 1 END                                               AS sentiment_idx
    FROM TABLE(GENERATOR(ROWCOUNT => 600))
)
SELECT
    ticket_id,
    customer_id,
    created_at,
    GET(ARRAY_CONSTRUCT(
        'Estimated value looks wrong',
        'Billing question',
        'Trouble getting started',
        'Something is broken',
        'Cancellation request',
        'Feature suggestion'), topic_idx)::STRING                     AS subject,
    GET(CASE topic_idx
        WHEN 0 THEN ARRAY_CONSTRUCT(
            'Your valuation is way off. It says my house is worth 80k less than three appraisers told me.',
            'The home value estimate was spot on - matched my recent appraisal within a couple percent.',
            'How often does the estimated home value get refreshed after I update the square footage?')
        WHEN 1 THEN ARRAY_CONSTRUCT(
            'I was charged twice this month and the Pro plan price jumped without any notice.',
            'Upgrading to Pro was worth it, the comps report alone pays for the subscription.',
            'Can you explain the difference between the Starter and Pro plans for billing?')
        WHEN 2 THEN ARRAY_CONSTRUCT(
            'I have been stuck on the onboarding step for an hour, the address import keeps failing.',
            'Setup was painless, I connected my listings and had a dashboard in ten minutes.',
            'Where do I find the guide for importing my B2B partner property portfolio?')
        WHEN 3 THEN ARRAY_CONSTRUCT(
            'The valuation chart is completely broken, it throws an error every time I open it.',
            'Thanks for the quick fix - the map view loads correctly now.',
            'Is the mobile app supposed to show the same comps as the web version?')
        WHEN 4 THEN ARRAY_CONSTRUCT(
            'I want to cancel immediately and get a refund, this product is not working for me.',
            'I was going to cancel but the new market-trends feature convinced me to stay.',
            'If I cancel mid-cycle, do I keep access until the end of the billing period?')
        ELSE ARRAY_CONSTRUCT(
            'Every competitor has API access and you still do not. This is a dealbreaker for our team.',
            'Love the product - it would be perfect if you added rental yield estimates too.',
            'Are there plans to support commercial property valuations for B2B accounts?')
    END, sentiment_idx)::STRING                                       AS body
FROM base;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. APP UX TELEMETRY MODEL + INGESTION (how a customer's app data flows into Snowflake)
-- ─────────────────────────────────────────────────────────────────────────────
-- This section models what a real conversational app emits: message-level turns
-- and explicit feedback (thumbs up / down). It demonstrates BOTH ingestion paths
-- and RUNS the full flow here, so the curated tables and the thumbs_down_rate
-- metric are populated before any consumer is created:
--
--   (a) RAW / semi-structured landing — an internal stage receives JSON files the
--       app drops; COPY INTO loads them verbatim into a VARIANT column. This is the
--       immutable landing zone: schema-on-read, captures everything the app sends.
--       (In production the continuous path is Snowpipe or Snowpipe Streaming.)
--
--   (b) CURATED / structured — LATERAL FLATTEN turns the VARIANT into typed tables
--       (APP_THREADS / APP_MESSAGES / APP_FEEDBACK) that are governed, joinable to
--       CUSTOMERS, performant, and feed the AI functions + semantic view.
--
-- Notebook 1 tours these already-loaded objects read-only (SELECT from the raw and
-- curated tables) to explain how the data got here — it does not regenerate them.

-- 4a. Internal stage that simulates where the app drops event files.
CREATE STAGE IF NOT EXISTS AI_FUNCTIONS.APP_EVENTS_STAGE
  FILE_FORMAT = (TYPE = JSON)
  COMMENT = 'Landing zone for raw app UX telemetry (one JSON doc per chat thread)';

-- 4b. Raw landing table — one VARIANT payload per file/record, loaded as-is.
CREATE OR REPLACE TABLE AI_FUNCTIONS.RAW_APP_EVENTS (
    payload        VARIANT,
    source_file    STRING,
    loaded_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Raw app telemetry exactly as the app emitted it (schema-on-read).';

-- 4c. Seed the message-level events (topic + sentiment drive realistic text + feedback).
CREATE OR REPLACE TEMPORARY TABLE AI_FUNCTIONS.APP_EVENTS_SEED AS
WITH base AS (
    SELECT
        'thr_' || LPAD(seq4() + 1, 5, '0')                            AS thread_id,
        UNIFORM(1, 500, RANDOM())                                     AS customer_id,
        ['web_chat','in_app','mobile'][UNIFORM(0, 2, RANDOM())]::STRING AS channel,
        '3.' || UNIFORM(1, 9, RANDOM())::STRING || '.0'               AS app_version,
        DATEADD('minute', -UNIFORM(1, 260000, RANDOM()), CURRENT_TIMESTAMP()) AS started_at,
        UNIFORM(1, 100, RANDOM())                                     AS s,
        UNIFORM(0, 5, RANDOM())                                       AS topic_idx
    FROM TABLE(GENERATOR(ROWCOUNT => 150))
),
labeled AS (
    SELECT base.*, CASE WHEN s <= 45 THEN 0 WHEN s <= 80 THEN 1 ELSE 2 END AS sentiment_idx
    FROM base
)
SELECT
    thread_id, customer_id, channel, app_version, started_at, sentiment_idx,
    GET(CASE topic_idx
        WHEN 0 THEN ARRAY_CONSTRUCT(
            'Your valuation is way off - it says my house is worth 80k less than three appraisers told me.',
            'The home value estimate was spot on, within a couple percent of my appraisal.',
            'How often does the estimated value refresh after I update the square footage?')
        WHEN 1 THEN ARRAY_CONSTRUCT(
            'I was charged twice this month and the Pro price jumped with no notice.',
            'Upgrading to Pro was worth it - the comps report alone pays for it.',
            'Can you explain the difference between the Starter and Pro plans?')
        WHEN 2 THEN ARRAY_CONSTRUCT(
            'I have been stuck on onboarding for an hour, the address import keeps failing.',
            'Setup was painless, I had a dashboard in ten minutes.',
            'Where is the guide for importing my B2B property portfolio?')
        WHEN 3 THEN ARRAY_CONSTRUCT(
            'The valuation chart is completely broken, it errors every time I open it.',
            'Thanks for the quick fix - the map view loads correctly now.',
            'Is the mobile app supposed to show the same comps as web?')
        WHEN 4 THEN ARRAY_CONSTRUCT(
            'I want to cancel immediately and get a refund, this is not working for me.',
            'I was going to cancel but the new market-trends feature convinced me to stay.',
            'If I cancel mid-cycle, do I keep access until the end of the period?')
        ELSE ARRAY_CONSTRUCT(
            'Every competitor has API access and you still do not. Dealbreaker for our team.',
            'Love the product - rental yield estimates would make it perfect.',
            'Are there plans to support commercial property valuations for B2B?')
    END, sentiment_idx)::STRING                                       AS user_text,
    GET(ARRAY_CONSTRUCT(
        'I hear you - I am escalating this to our team right now.',
        'Glad to hear it! Anything else I can help with?',
        'Here is what I found for you.'), sentiment_idx)::STRING      AS asst_text,
    'msg_' || thread_id || '_1'                                       AS user_msg_id,
    'msg_' || thread_id || '_2'                                       AS asst_msg_id,
    -- ~65% of threads leave feedback; negatives skew thumbs-down, positives thumbs-up
    CASE WHEN UNIFORM(1, 100, RANDOM()) <= 65
         THEN CASE sentiment_idx WHEN 0 THEN -1 WHEN 1 THEN 1
                   ELSE GET(ARRAY_CONSTRUCT(-1, 1), UNIFORM(0, 1, RANDOM()))::INT END
         ELSE NULL END                                                AS rating
FROM labeled;

-- 4d. Serialize each thread to a single JSON document (messages[] + feedback[]).
CREATE OR REPLACE TEMPORARY TABLE AI_FUNCTIONS.APP_EVENTS_JSON AS
SELECT OBJECT_CONSTRUCT(
    'thread_id',   thread_id,
    'customer_id', customer_id,
    'channel',     channel,
    'app_version', app_version,
    'started_at',  started_at::STRING,
    'messages', ARRAY_CONSTRUCT(
        OBJECT_CONSTRUCT('message_id', user_msg_id, 'turn_no', 1, 'role', 'user',
                         'content', user_text, 'created_at', started_at::STRING),
        OBJECT_CONSTRUCT('message_id', asst_msg_id, 'turn_no', 2, 'role', 'assistant',
                         'content', asst_text, 'model', 'llama3.1-8b',
                         'created_at', DATEADD('second', 20, started_at)::STRING)
    ),
    'feedback', IFF(rating IS NULL, ARRAY_CONSTRUCT(),
        ARRAY_CONSTRUCT(OBJECT_CONSTRUCT('message_id', asst_msg_id, 'rating', rating,
                         'created_at', DATEADD('second', 30, started_at)::STRING)))
) AS payload
FROM AI_FUNCTIONS.APP_EVENTS_SEED;

-- 4e. Drop the JSON docs into the stage (this is the step your app would do).
COPY INTO @AI_FUNCTIONS.APP_EVENTS_STAGE/app_events
FROM (SELECT payload FROM AI_FUNCTIONS.APP_EVENTS_JSON)
FILE_FORMAT = (TYPE = JSON)
OVERWRITE = TRUE;

-- 4f. Load the raw events, as-is, into the VARIANT landing table.
TRUNCATE TABLE AI_FUNCTIONS.RAW_APP_EVENTS;
COPY INTO AI_FUNCTIONS.RAW_APP_EVENTS (payload, source_file)
FROM (SELECT $1, METADATA$FILENAME FROM @AI_FUNCTIONS.APP_EVENTS_STAGE/app_events)
FILE_FORMAT = (TYPE = JSON);

-- 4g. Curate into typed tables via LATERAL FLATTEN of the messages[]/feedback[] arrays.
CREATE OR REPLACE TABLE AI_FUNCTIONS.APP_THREADS AS
SELECT
    payload:thread_id::STRING                                         AS thread_id,
    payload:customer_id::NUMBER                                       AS customer_id,
    payload:channel::STRING                                          AS channel,
    payload:app_version::STRING                                      AS app_version,
    payload:started_at::TIMESTAMP_NTZ                                AS started_at
FROM AI_FUNCTIONS.RAW_APP_EVENTS;

CREATE OR REPLACE TABLE AI_FUNCTIONS.APP_MESSAGES AS
SELECT
    m.value:message_id::STRING                                       AS message_id,
    r.payload:thread_id::STRING                                      AS thread_id,
    m.value:turn_no::NUMBER                                          AS turn_no,
    m.value:role::STRING                                             AS role,
    m.value:content::STRING                                          AS content,
    m.value:model::STRING                                            AS model,
    m.value:created_at::TIMESTAMP_NTZ                                AS created_at
FROM AI_FUNCTIONS.RAW_APP_EVENTS r,
     LATERAL FLATTEN(input => r.payload:messages) m;

CREATE OR REPLACE TABLE AI_FUNCTIONS.APP_FEEDBACK AS
SELECT
    f.value:message_id::STRING                                       AS message_id,
    r.payload:thread_id::STRING                                      AS thread_id,
    f.value:rating::NUMBER                                           AS rating,
    f.value:comment::STRING                                          AS comment,
    f.value:created_at::TIMESTAMP_NTZ                                AS created_at
FROM AI_FUNCTIONS.RAW_APP_EVENTS r,
     LATERAL FLATTEN(input => r.payload:feedback) f;

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
-- governed "thumbs-down rate". Sourced from the app telemetry curated above in
-- Section 4 — so this is populated with real ratings, not zeros.
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
-- Built over AI_FUNCTIONS.CHAT_THREADS, which Section 3 already populated — so the
-- service indexes real transcripts immediately, with no re-create step.

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
-- Setup complete — the environment is fully populated and every object is valid.
--   You just created the schemas, warehouse, ALL structured + unstructured data,
--   the app-telemetry (raw + curated), the semantic view, the search service, and
--   the agent. Cortex Search returns hits, thumbs_down_rate is non-zero, and the
--   agent answers — no second data step, no re-create.
--
-- Next:
--   1) Open lab/cx-ai-functions-lab.ipynb — run the AI-function pipeline (and tour
--      the app-telemetry setup loaded), AI Function Studio, and cost.
--   2) Open lab/cx-ai-functions-extensions.ipynb — integrate the semantic view /
--      Cortex Analyst / Cortex Search / Agent + cost & guardrails.
--   Or just chat with CX_INTELLIGENCE_AGENT in Snowsight.
-- ─────────────────────────────────────────────────────────────────────────────
