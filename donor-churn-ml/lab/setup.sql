-- =============================================================================
-- Donor Lapse/Churn Intelligence: Snowflake ML -> Agent — Lab Setup
-- =============================================================================
-- Run this script ONCE before the notebook. It creates the demo database, four
-- schemas (RAW / FEATURES / MODELS / ANALYTICS), two warehouses, an optional
-- compute pool for ML Jobs, the synthetic nonprofit-donor dataset, the point-in-
-- time training base, the Cortex ML Function objects (Forecast / Anomaly /
-- Classification), and the Cortex Analyst semantic view.
--
-- Scenario (generic, client-agnostic): a nonprofit fundraising CRM platform
-- wants to predict which donors are likely to LAPSE (stop giving) so fundraising
-- teams can intervene. All data is synthetic.
--
-- Run order:
--   1) This script                          (data + ML functions + semantic view)
--   2) lab/donor-churn-ml-lab.ipynb          (Feature Store -> Registry -> Serving
--                                             -> Observability -> tool fns -> Agent)
--   3) app/streamlit_app.py                  (chat UI over the agent)
--
-- NOTE: the Model Registry model, Model Monitor, the PREDICT_DONOR_CHURN /
-- TOP_CHURN_RISK tool functions, and the Cortex Agent are created by the NOTEBOOK,
-- because they depend on the trained/deployed model. Do not expect them after this
-- script alone.
--
-- Prerequisites:
--   - A role that can CREATE DATABASE/SCHEMA, CREATE WAREHOUSE, CREATE SEMANTIC VIEW,
--     and (for the ML Function section) has CREATE SNOWFLAKE.ML.CLASSIFICATION /
--     .FORECAST / .ANOMALY_DETECTION on the MODELS schema.
--   - The SNOWFLAKE.CORTEX_USER database role (for AI_COMPLETE + the agent).
--   - For the notebook: snowflake-ml-python >= 1.26 and (for ML Jobs / SPCS serving)
--     privileges to CREATE COMPUTE POOL + CREATE MODEL / MODEL MONITOR / AGENT.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE AND SCHEMAS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS DONOR_CHURN_ML_DEMO;
USE DATABASE DONOR_CHURN_ML_DEMO;

CREATE SCHEMA IF NOT EXISTS RAW;        -- synthetic source tables
CREATE SCHEMA IF NOT EXISTS FEATURES;   -- Feature Store (created in notebook)
CREATE SCHEMA IF NOT EXISTS MODELS;     -- ML Functions, Registry, Monitor, tools, agent
CREATE SCHEMA IF NOT EXISTS ANALYTICS;  -- Cortex Analyst semantic view

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WAREHOUSES  (+ optional compute pool for ML Jobs / Container Runtime)
-- ─────────────────────────────────────────────────────────────────────────────

-- General interactive warehouse for SQL, Analyst, and the agent.
CREATE WAREHOUSE IF NOT EXISTS DONOR_CHURN_ML_WH
  WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND = 120
  AUTO_RESUME = TRUE;

-- Snowpark-optimized warehouse for ML Function training (higher memory).
CREATE WAREHOUSE IF NOT EXISTS DONOR_CHURN_ML_SOWH
  WAREHOUSE_SIZE = 'MEDIUM'
  WAREHOUSE_TYPE = 'SNOWPARK-OPTIMIZED'
  AUTO_SUSPEND = 120
  AUTO_RESUME = TRUE;

USE WAREHOUSE DONOR_CHURN_ML_WH;

-- Optional: compute pool used by the notebook's ML Jobs / Container Runtime cell
-- and (optionally) SPCS model serving. Requires CREATE COMPUTE POOL privilege.
-- Uncomment if your role can create compute pools.
-- CREATE COMPUTE POOL IF NOT EXISTS DONOR_CHURN_ML_POOL
--   MIN_NODES = 1
--   MAX_NODES = 2
--   INSTANCE_FAMILY = CPU_X64_M;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. STRUCTURED SAMPLE DATA (SQL GENERATOR)  — ~50k donors
-- ─────────────────────────────────────────────────────────────────────────────
USE SCHEMA RAW;

-- 3a. DONORS — one row per donor. Each donor gets a LATENT churn propensity that
--     drives how recently / how often they give and engage. The latent columns
--     (churn_prob, is_churner, base_recency_days, lifetime_gifts, engage_target)
--     are used ONLY to shape the DONATIONS/ENGAGEMENTS timelines below — they are
--     NOT used as model features and NOT exposed to the semantic view, so the
--     trained models must learn lapse from RFM + engagement behavior (no leakage).
CREATE OR REPLACE TABLE DONORS AS
SELECT
    seq4() + 1                                                            AS donor_id,
    'ORG_' || LPAD(UNIFORM(1, 8, RANDOM())::STRING, 2, '0')              AS org_id,
    -- Acquired at least ~14 months ago so every donor is eligible for a fair label.
    DATEADD('day', -UNIFORM(430, 3650, RANDOM()), CURRENT_DATE())         AS acquisition_date,
    ['Direct Mail','Online','Event','Peer-to-Peer','Grant','Major Gifts Officer']
        [UNIFORM(0, 5, RANDOM())]::STRING                                 AS channel,
    ['West','Northeast','Southeast','Midwest','Southwest']
        [UNIFORM(0, 4, RANDOM())]::STRING                                 AS region,
    ROUND(UNIFORM(0, 1000, RANDOM()) / 1000.0, 3)                         AS wealth_signal_score
FROM TABLE(GENERATOR(ROWCOUNT => 50000));

-- Enrich: donor_segment (from wealth) + latent behavior drivers. Higher wealth and
-- high-touch channels lower churn propensity; noise keeps it non-deterministic.
CREATE OR REPLACE TABLE DONORS AS
WITH e AS (
    SELECT
        donor_id, org_id, acquisition_date, channel, region, wealth_signal_score,
        CASE
            WHEN wealth_signal_score >= 0.85 THEN 'Major'
            WHEN wealth_signal_score >= 0.45 THEN 'Mid'
            ELSE 'Grassroots'
        END                                                               AS donor_segment,
        LEAST(0.92, GREATEST(0.03,
            0.60 - 0.55 * wealth_signal_score
            + CASE channel
                WHEN 'Major Gifts Officer' THEN -0.10
                WHEN 'Grant'               THEN -0.05
                WHEN 'Online'              THEN  0.05
                ELSE 0 END
            + UNIFORM(-100, 100, RANDOM()) / 1000.0))                     AS churn_prob,
        UNIFORM(0, 1000, RANDOM()) / 1000.0                               AS u
    FROM DONORS
)
SELECT
    donor_id, org_id, acquisition_date, channel, region, wealth_signal_score,
    donor_segment, churn_prob,
    (u < churn_prob)                                                      AS is_churner,
    -- Most-recent gift is OLD for churners, recent for retained donors.
    IFF(u < churn_prob, UNIFORM(430, 1100, RANDOM()), UNIFORM(1, 250, RANDOM())) AS base_recency_days,
    IFF(u < churn_prob, UNIFORM(1, 6, RANDOM()),      UNIFORM(8, 24, RANDOM()))  AS lifetime_gifts,
    IFF(u < churn_prob, UNIFORM(0, 10, RANDOM()),     UNIFORM(6, 45, RANDOM()))  AS engage_target
FROM e;

-- 3b. DONATIONS — expand each donor into `lifetime_gifts` gifts. The most recent
--     gift sits ~base_recency_days ago; older gifts step further back.
CREATE OR REPLACE TABLE DONATIONS AS
WITH nums AS (SELECT seq4() AS k FROM TABLE(GENERATOR(ROWCOUNT => 25)))
SELECT
    ROW_NUMBER() OVER (ORDER BY d.donor_id, n.k)                          AS gift_id,
    d.donor_id,
    GREATEST(d.acquisition_date,
        DATEADD('day', -(d.base_recency_days + n.k * UNIFORM(20, 90, RANDOM())),
                CURRENT_DATE()))                                          AS gift_date,
    'CMP_' || LPAD(UNIFORM(1, 40, RANDOM())::STRING, 3, '0')             AS campaign_id,
    ['Annual Fund','Year-End','Emergency Appeal','Capital Campaign','Membership','Giving Tuesday']
        [UNIFORM(0, 5, RANDOM())]::STRING                                 AS appeal_type,
    ROUND(
        CASE d.donor_segment
            WHEN 'Major' THEN 250 + UNIFORM(1, 1000, RANDOM()) * 9.5
            WHEN 'Mid'   THEN  50 + UNIFORM(1, 1000, RANDOM()) * 1.2
            ELSE               10 + UNIFORM(1, 1000, RANDOM()) * 0.15
        END, 2)                                                           AS gift_amount
FROM DONORS d
JOIN nums n ON n.k < d.lifetime_gifts;

-- 3c. ENGAGEMENTS — expand each donor into `engage_target` touchpoints, more
--     recent than gifts. Churners engage less and less recently.
CREATE OR REPLACE TABLE ENGAGEMENTS AS
WITH nums AS (SELECT seq4() AS k FROM TABLE(GENERATOR(ROWCOUNT => 50)))
SELECT
    ROW_NUMBER() OVER (ORDER BY d.donor_id, n.k)                          AS engagement_id,
    d.donor_id,
    GREATEST(d.acquisition_date,
        DATEADD('day', -(ROUND(d.base_recency_days * 0.7) + n.k * UNIFORM(10, 40, RANDOM())),
                CURRENT_DATE()))::TIMESTAMP_NTZ                           AS event_date,
    ['email_open','click','event_attend','volunteer']
        [UNIFORM(0, 3, RANDOM())]::STRING                                 AS event_type
FROM DONORS d
JOIN nums n ON n.k < d.engage_target;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. POINT-IN-TIME TRAINING BASE  (features as-of a snapshot; label from the
--    forward 12-month window — no leakage)
-- ─────────────────────────────────────────────────────────────────────────────
-- AS-OF date = 12 months ago. Features use only activity <= as_of_date. Label
-- is_lapsed = 1 when the donor made NO gift in the 12 months AFTER as_of_date.

CREATE OR REPLACE VIEW DONOR_TRAINING_BASE AS
WITH params AS (
    SELECT DATEADD('month', -12, CURRENT_DATE()) AS as_of_date
),
gift_hist AS (
    SELECT
        d.donor_id,
        COUNT(dn.gift_id)                                                 AS frequency_lifetime,
        COALESCE(SUM(dn.gift_amount), 0)                                  AS monetary_total,
        COALESCE(AVG(dn.gift_amount), 0)                                  AS avg_gift_amount,
        DATEDIFF('day', MAX(dn.gift_date), (SELECT as_of_date FROM params)) AS recency_days,
        COUNT(CASE WHEN dn.gift_date >= DATEADD('month', -12, (SELECT as_of_date FROM params))
                   THEN 1 END)                                            AS gifts_last_12m
    FROM DONORS d
    LEFT JOIN DONATIONS dn
      ON dn.donor_id = d.donor_id
     AND dn.gift_date <= (SELECT as_of_date FROM params)
    GROUP BY d.donor_id
),
eng_hist AS (
    SELECT
        d.donor_id,
        COUNT(en.engagement_id)                                          AS engagement_count,
        COUNT(CASE WHEN en.event_date >= DATEADD('month', -6, (SELECT as_of_date FROM params))
                   THEN 1 END)                                           AS engagement_last_6m
    FROM DONORS d
    LEFT JOIN ENGAGEMENTS en
      ON en.donor_id = d.donor_id
     AND en.event_date <= (SELECT as_of_date FROM params)
    GROUP BY d.donor_id
),
forward AS (
    SELECT
        d.donor_id,
        COUNT(dn.gift_id)                                                AS gifts_forward_12m
    FROM DONORS d
    LEFT JOIN DONATIONS dn
      ON dn.donor_id = d.donor_id
     AND dn.gift_date >  (SELECT as_of_date FROM params)
     AND dn.gift_date <= DATEADD('month', 12, (SELECT as_of_date FROM params))
    GROUP BY d.donor_id
)
SELECT
    d.donor_id,
    d.org_id,
    d.region,
    d.channel,
    d.donor_segment,
    d.wealth_signal_score,
    DATEDIFF('day', d.acquisition_date, (SELECT as_of_date FROM params)) AS tenure_days,
    COALESCE(gh.frequency_lifetime, 0)                                   AS frequency_lifetime,
    COALESCE(gh.gifts_last_12m, 0)                                       AS frequency_last_12m,
    COALESCE(gh.monetary_total, 0)                                       AS monetary_total,
    COALESCE(gh.avg_gift_amount, 0)                                      AS avg_gift_amount,
    COALESCE(gh.recency_days, 1500)                                      AS recency_days,
    COALESCE(eh.engagement_count, 0)                                     AS engagement_count,
    COALESCE(eh.engagement_last_6m, 0)                                   AS engagement_last_6m,
    -- Label: no gift in the forward 12-month window => lapsed.
    IFF(COALESCE(fw.gifts_forward_12m, 0) = 0, 1, 0)                     AS is_lapsed
FROM DONORS d
LEFT JOIN gift_hist gh ON gh.donor_id = d.donor_id
LEFT JOIN eng_hist  eh ON eh.donor_id = d.donor_id
LEFT JOIN forward   fw ON fw.donor_id = d.donor_id
-- Only donors acquired before the snapshot are eligible for a fair label.
WHERE d.acquisition_date <= (SELECT as_of_date FROM params);

-- Weekly donation-volume time series for Forecasting / Anomaly Detection.
CREATE OR REPLACE VIEW DONATION_VOLUME_TS AS
SELECT
    DATE_TRUNC('week', gift_date)::TIMESTAMP_NTZ                          AS week_ts,
    SUM(gift_amount)                                                      AS total_amount
FROM DONATIONS
GROUP BY 1
ORDER BY 1;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. CORTEX ML FUNCTIONS (no-code "heuristics -> ML" bridge)
-- ─────────────────────────────────────────────────────────────────────────────
-- These built-in ML Functions are created in the MODELS schema. They train on
-- the views above. (Also demonstrated interactively in notebook Section 4.)
USE SCHEMA MODELS;
USE WAREHOUSE DONOR_CHURN_ML_SOWH;   -- Snowpark-optimized for ML-function training

-- 5a. FORECAST — projected weekly donation volume (e.g., next quarter).
CREATE OR REPLACE SNOWFLAKE.ML.FORECAST DONATION_VOLUME_FORECAST(
    INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'DONOR_CHURN_ML_DEMO.RAW.DONATION_VOLUME_TS'),
    TIMESTAMP_COLNAME => 'WEEK_TS',
    TARGET_COLNAME => 'TOTAL_AMOUNT'
);
-- Usage (run in notebook / worksheet):
--   CALL DONATION_VOLUME_FORECAST!FORECAST(FORECASTING_PERIODS => 13);

-- 5b. ANOMALY DETECTION — flag unusual giving drop-off / spikes.
--   Train on data older than 6 months; detect anomalies on the recent 6 months.
CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION DONATION_VOLUME_ANOMALY(
    INPUT_DATA => SYSTEM$QUERY_REFERENCE('SELECT * FROM DONOR_CHURN_ML_DEMO.RAW.DONATION_VOLUME_TS WHERE WEEK_TS < DATEADD(MONTH, -6, CURRENT_DATE())'),
    TIMESTAMP_COLNAME => 'WEEK_TS',
    TARGET_COLNAME => 'TOTAL_AMOUNT',
    LABEL_COLNAME => ''
);
-- Usage (run in notebook / worksheet):
--   CALL DONATION_VOLUME_ANOMALY!DETECT_ANOMALIES(
--     INPUT_DATA => SYSTEM$QUERY_REFERENCE('SELECT * FROM DONOR_CHURN_ML_DEMO.RAW.DONATION_VOLUME_TS WHERE WEEK_TS >= DATEADD(MONTH, -6, CURRENT_DATE())'),
--     TIMESTAMP_COLNAME => 'WEEK_TS', TARGET_COLNAME => 'TOTAL_AMOUNT');

-- 5c. CLASSIFICATION — baseline lapse classifier (no-code) + feature importance.
CREATE OR REPLACE VIEW MODELS.LAPSE_CLASSIFY_INPUT AS
SELECT
    region, channel, donor_segment, wealth_signal_score, tenure_days,
    frequency_lifetime, frequency_last_12m, monetary_total, avg_gift_amount,
    recency_days, engagement_count, engagement_last_6m,
    is_lapsed
FROM DONOR_CHURN_ML_DEMO.RAW.DONOR_TRAINING_BASE;

CREATE OR REPLACE SNOWFLAKE.ML.CLASSIFICATION LAPSE_BASELINE_MODEL(
    INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'DONOR_CHURN_ML_DEMO.MODELS.LAPSE_CLASSIFY_INPUT'),
    TARGET_COLNAME => 'IS_LAPSED'
);
-- Usage (run in notebook / worksheet):
--   SELECT *, LAPSE_BASELINE_MODEL!PREDICT(INPUT_DATA => {*}) AS prediction
--     FROM DONOR_CHURN_ML_DEMO.MODELS.LAPSE_CLASSIFY_INPUT LIMIT 20;
--   CALL LAPSE_BASELINE_MODEL!SHOW_EVALUATION_METRICS();
--   CALL LAPSE_BASELINE_MODEL!SHOW_FEATURE_IMPORTANCE();
--   CALL LAPSE_BASELINE_MODEL!SHOW_CONFUSION_MATRIX();

-- 5d. TOP INSIGHTS — driver discovery: which segments move the lapse rate.
--   SELECT * FROM TABLE(SNOWFLAKE.ML.TOP_INSIGHTS(
--     INPUT_DATA => TABLE(
--       SELECT is_lapsed AS metric,
--              OBJECT_CONSTRUCT('region', region, 'channel', channel,
--                               'segment', donor_segment) AS dimensions
--       FROM DONOR_CHURN_ML_DEMO.RAW.DONOR_TRAINING_BASE)));

USE WAREHOUSE DONOR_CHURN_ML_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. CORTEX ANALYST SEMANTIC VIEW  (descriptive Q&A tool for the agent)
-- ─────────────────────────────────────────────────────────────────────────────
USE SCHEMA ANALYTICS;

CREATE OR REPLACE SEMANTIC VIEW DONOR_CHURN_SV
  TABLES (
    donors AS DONOR_CHURN_ML_DEMO.RAW.DONORS
      PRIMARY KEY (donor_id)
      COMMENT = 'Donors of a nonprofit fundraising CRM (synthetic)',
    donations AS DONOR_CHURN_ML_DEMO.RAW.DONATIONS
      PRIMARY KEY (gift_id)
      COMMENT = 'Individual gifts',
    engagements AS DONOR_CHURN_ML_DEMO.RAW.ENGAGEMENTS
      PRIMARY KEY (engagement_id)
      COMMENT = 'Non-gift engagement touchpoints',
    training AS DONOR_CHURN_ML_DEMO.RAW.DONOR_TRAINING_BASE
      PRIMARY KEY (donor_id)
      COMMENT = 'Point-in-time RFM/engagement features + lapse label'
  )
  RELATIONSHIPS (
    donations_to_donors AS donations (donor_id) REFERENCES donors,
    engagements_to_donors AS engagements (donor_id) REFERENCES donors,
    training_to_donors AS training (donor_id) REFERENCES donors
  )
  FACTS (
    donations.gift_amount_fact AS gift_amount,
    training.lapsed_flag AS is_lapsed
  )
  DIMENSIONS (
    donors.region AS region
      COMMENT = 'Donor region (West, Northeast, Southeast, Midwest, Southwest)',
    donors.channel AS channel
      WITH SYNONYMS = ('acquisition channel')
      COMMENT = 'How the donor was acquired',
    donors.donor_segment AS donor_segment
      WITH SYNONYMS = ('segment','giving level','major gift')
      COMMENT = 'Major, Mid, or Grassroots (major-gift donors = Major)',
    donors.acquisition_month AS DATE_TRUNC('month', acquisition_date)
      COMMENT = 'Month the donor was acquired',
    donations.appeal_type AS appeal_type
      COMMENT = 'Type of appeal the gift responded to',
    donations.gift_month AS DATE_TRUNC('month', gift_date)
      COMMENT = 'Month of the gift',
    engagements.event_type AS event_type
      COMMENT = 'Type of engagement touchpoint',
    training.is_lapsed AS is_lapsed
      COMMENT = 'Whether the donor lapsed in the label window (1 = lapsed)'
  )
  METRICS (
    donors.donor_count AS COUNT(donors.donor_id)
      COMMENT = 'Number of donors',
    donations.total_giving AS SUM(donations.gift_amount_fact)
      COMMENT = 'Total giving amount',
    donations.avg_gift AS AVG(donations.gift_amount_fact)
      COMMENT = 'Average gift amount',
    donations.gift_count AS COUNT(donations.gift_id)
      COMMENT = 'Number of gifts',
    engagements.engagement_count AS COUNT(engagements.engagement_id)
      COMMENT = 'Number of engagement touchpoints',
    training.lapsed_donors AS SUM(training.lapsed_flag)
      COMMENT = 'Number of lapsed donors',
    training.lapse_rate AS DIV0(SUM(training.lapsed_flag), COUNT(training.donor_id))
      COMMENT = 'Share of donors that lapsed'
  )
  COMMENT = 'Governed donor / donation / engagement + lapse definitions for Cortex Analyst'
  AI_VERIFIED_QUERIES (
    lapse_rate_by_region AS (
      QUESTION 'What is the lapse rate by region?'
      SQL 'SELECT * FROM SEMANTIC_VIEW(DONOR_CHURN_SV METRICS lapse_rate DIMENSIONS donors.region)'
    ),
    major_gift_lapse_west AS (
      QUESTION 'What is the lapse rate for major-gift donors in the West region?'
      SQL 'SELECT * FROM SEMANTIC_VIEW(DONOR_CHURN_SV METRICS lapse_rate DIMENSIONS donors.region, donors.donor_segment) WHERE region = ''West'' AND donor_segment = ''Major'''
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- Setup complete.
--   1) You just ran this script (data + ML functions + semantic view).
--   2) Open lab/donor-churn-ml-lab.ipynb and walk sections 2-13 (Feature Store ->
--      Datasets -> Snowpark ML -> ML Jobs -> Registry -> Explainability -> Serving
--      -> Observability -> tool functions -> Cortex Agent).
--   3) Launch app/streamlit_app.py to chat with the agent, or use Snowsight
--      AI & ML -> Agents.
-- ─────────────────────────────────────────────────────────────────────────────
