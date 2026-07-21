-- =============================================================================
-- Proactive Retail Intelligence with Snowflake Cortex — Lab: Setup Script
-- =============================================================================
-- Run this ONCE before the notebook. This script is the SINGLE SOURCE OF TRUTH:
-- it fully populates every table AND builds every consumer object (Cortex ML
-- Function models, findings + drivers tables, semantic view, Cortex Search)
-- in strict dependency order, so nothing has to be re-created in the notebook.
--
-- Scenario: a multi-tenant retail analytics SaaS provider ingests several retail
-- chains' point-of-sale and returns/refunds data and sells them an embedded,
-- in-app assistant. This lab builds the PROACTIVE layer: cheap in-warehouse ML
-- scans store metrics for anomalies, Top Insights explains the "why", a semantic
-- view answers ad-hoc store questions, and (in the notebook) a Cortex Agent
-- narrates it all.
--
-- Prerequisites:
--   - A role that can CREATE DATABASE / WAREHOUSE (e.g. SYSADMIN) and
--     CREATE SNOWFLAKE.ML.ANOMALY_DETECTION / TOP_INSIGHTS on the schema.
--   - Cortex ML Functions and Cortex Search available in your region.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE, SCHEMAS, WAREHOUSE
-- ─────────────────────────────────────────────────────────────────────────────

USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS PROACTIVE_RETAIL_DEMO;
USE DATABASE PROACTIVE_RETAIL_DEMO;
CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS ANALYTICS;

CREATE WAREHOUSE IF NOT EXISTS PROACTIVE_RETAIL_WH
  WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND = 120
  AUTO_RESUME = TRUE;

USE WAREHOUSE PROACTIVE_RETAIL_WH;
USE SCHEMA RAW;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. STRUCTURED SAMPLE DATA (SQL GENERATOR) — populated FIRST
-- ─────────────────────────────────────────────────────────────────────────────
-- Retailers (tenants) — generic personas only, no real company names.
CREATE OR REPLACE TABLE RAW.RETAILERS AS
SELECT
    (SEQ4() + 1)                                                          AS retailer_id,
    ARRAY_CONSTRUCT(
      'Northwind Grocery Group',
      'Summit Big-Box Retail',
      'Harbor & Co. Apparel',
      'Evergreen Pharmacy Retail'
    )[SEQ4()]::STRING                                                     AS retailer_name,
    ARRAY_CONSTRUCT('Grocery','General Merchandise','Apparel','Pharmacy')[SEQ4()]::STRING AS vertical
FROM TABLE(GENERATOR(ROWCOUNT => 4));

-- Stores — 60 stores across the 4 retailers. Stores 1003 / 1017 / 1042 are the
-- "anomaly" stores (concentrated in one metro) that the ML layer should surface.
CREATE OR REPLACE TABLE RAW.STORES AS
WITH s AS (
    SELECT SEQ4() AS seq FROM TABLE(GENERATOR(ROWCOUNT => 60))
)
SELECT
    1000 + seq                                                            AS store_id,
    MOD(seq, 4) + 1                                                       AS retailer_id,
    (seq IN (3, 17, 42))                                                  AS is_anomaly_store,
    CASE WHEN seq IN (3, 17, 42) THEN 'Midwest'
         ELSE ARRAY_CONSTRUCT('West','Northeast','Southeast','Midwest','Southwest')[MOD(seq, 5)]::STRING
    END                                                                   AS region,
    CASE WHEN seq IN (3, 17, 42) THEN 'Lakeshore Metro'
         ELSE ARRAY_CONSTRUCT('Bay Metro','Harbor Metro','Prairie Metro','Sunbelt Metro','Capital Metro')[MOD(seq, 5)]::STRING
    END                                                                   AS metro,
    ARRAY_CONSTRUCT('Supercenter','Neighborhood','Express')[MOD(seq, 3)]::STRING AS store_format
FROM s;

-- Daily per-store metrics time series (~400 days). Baseline return_rate ~7-9%
-- with weekend + noise; the 3 anomaly stores spike ~+13pts over the last 10 days.
CREATE OR REPLACE TABLE RAW.STORE_DAY_METRICS AS
WITH days AS (
    SELECT SEQ4() AS day_offset FROM TABLE(GENERATOR(ROWCOUNT => 400))
),
grid AS (
    SELECT
        st.store_id, st.retailer_id, st.region, st.metro, st.is_anomaly_store,
        DATEADD(day, d.day_offset - 399, CURRENT_DATE())::TIMESTAMP_NTZ    AS metric_date
    FROM RAW.STORES st
    CROSS JOIN days d
),
base AS (
    SELECT
        g.store_id, g.retailer_id, g.region, g.metro, g.metric_date,
        UNIFORM(400, 1200, RANDOM())                                      AS transaction_count,
        LEAST(0.95, GREATEST(0.01,
            0.07
            + IFF(DAYOFWEEK(g.metric_date) IN (0, 6), 0.02, 0)
            + UNIFORM(-15, 15, RANDOM()) / 1000.0
            + IFF(g.is_anomaly_store AND g.metric_date >= DATEADD(day, -10, CURRENT_DATE()), 0.13, 0)
        ))                                                                AS return_rate
    FROM grid g
),
calc AS (
    SELECT
        base.*,
        ROUND(transaction_count * return_rate)                            AS return_count
    FROM base
)
SELECT
    store_id, retailer_id, region, metro, metric_date, transaction_count,
    return_count,
    ROUND(transaction_count * UNIFORM(25, 60, RANDOM()), 2)               AS sales_amount,
    ROUND(return_count * UNIFORM(18, 45, RANDOM()), 2)                    AS refund_amount,
    ROUND(return_rate, 4)                                                 AS return_rate
FROM calc;

-- Individual return records with dimensions Top Insights uses to explain "why".
-- (a) baseline returns over the last 60 days across all stores/categories.
CREATE OR REPLACE TABLE RAW.RETURNS_FACT AS
WITH r AS (
    SELECT
        SEQ4()                                                            AS return_id,
        1000 + UNIFORM(0, 59, RANDOM())                                   AS store_id,
        ARRAY_CONSTRUCT('Electronics','Apparel','Home & Kitchen','Grocery','Toys','Health & Beauty')[UNIFORM(0, 5, RANDOM())]::STRING AS product_category,
        DATEADD(day, -UNIFORM(0, 59, RANDOM()), CURRENT_DATE())::TIMESTAMP_NTZ AS return_date,
        ROUND(UNIFORM(1000, 12000, RANDOM()) / 100.0, 2)                  AS refund_amount,
        ARRAY_CONSTRUCT('DEFECTIVE','WRONG_SIZE','CHANGED_MIND','DAMAGED_IN_TRANSIT','PRICE_MATCH','NOT_AS_DESCRIBED')[UNIFORM(0, 5, RANDOM())]::STRING AS reason_code,
        IFF(UNIFORM(1, 100, RANDOM()) <= 4, TRUE, FALSE)                  AS is_fraud_suspected
    FROM TABLE(GENERATOR(ROWCOUNT => 45000))
)
SELECT
    r.return_id, r.store_id, s.retailer_id, s.region, s.metro,
    r.product_category, r.return_date, r.refund_amount, r.reason_code, r.is_fraud_suspected
FROM r
JOIN RAW.STORES s ON s.store_id = r.store_id;

-- (b) injected anomaly: last 10 days, the 3 anomaly stores, concentrated in
-- Electronics, higher refunds, more fraud-suspected — the driver signal.
INSERT INTO RAW.RETURNS_FACT
WITH r AS (
    SELECT
        1000000 + SEQ4()                                                  AS return_id,
        ARRAY_CONSTRUCT(1003, 1017, 1042)[UNIFORM(0, 2, RANDOM())]::NUMBER AS store_id,
        DATEADD(day, -UNIFORM(0, 9, RANDOM()), CURRENT_DATE())::TIMESTAMP_NTZ AS return_date,
        ROUND(UNIFORM(8000, 20000, RANDOM()) / 100.0, 2)                  AS refund_amount,
        ARRAY_CONSTRUCT('DEFECTIVE','NOT_AS_DESCRIBED','DAMAGED_IN_TRANSIT')[UNIFORM(0, 2, RANDOM())]::STRING AS reason_code,
        IFF(UNIFORM(1, 100, RANDOM()) <= 25, TRUE, FALSE)                 AS is_fraud_suspected
    FROM TABLE(GENERATOR(ROWCOUNT => 5000))
)
SELECT
    r.return_id, r.store_id, s.retailer_id, s.region, s.metro,
    'Electronics'::STRING                                                 AS product_category,
    r.return_date, r.refund_amount, r.reason_code, r.is_fraud_suspected
FROM r
JOIN RAW.STORES s ON s.store_id = r.store_id;

-- Free-text return reasons for Cortex Search (templated topic + sentiment text).
CREATE OR REPLACE TABLE RAW.RETURN_REASONS AS
WITH r AS (
    SELECT
        return_id, store_id, product_category, reason_code,
        UNIFORM(0, 4, RANDOM()) AS tone_idx
    FROM RAW.RETURNS_FACT
    SAMPLE (8000 ROWS)
)
SELECT
    return_id, store_id, product_category,
    CONCAT(
        CASE reason_code
            WHEN 'DEFECTIVE'          THEN 'The item stopped working within a few days. '
            WHEN 'WRONG_SIZE'         THEN 'The fit was off and did not match the size chart. '
            WHEN 'CHANGED_MIND'       THEN 'Customer changed their mind after purchase. '
            WHEN 'DAMAGED_IN_TRANSIT' THEN 'The package arrived damaged and unusable. '
            WHEN 'PRICE_MATCH'        THEN 'Found the same product cheaper elsewhere and asked for a match. '
            ELSE                            'The product did not match the online description. '
        END,
        'Category: ', product_category, '. ',
        ARRAY_CONSTRUCT(
          'Staff handled the return quickly and were helpful.',
          'Customer was frustrated by the wait at the counter.',
          'Overall a neutral experience, no strong complaints.',
          'Customer suspected the item may have been used or repackaged.',
          'Great service, customer said they would shop again.'
        )[tone_idx]::STRING
    )                                                                     AS reason_text
FROM r;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. CORTEX ML FUNCTIONS — anomaly detection (proactive scan, no LLM)
-- ─────────────────────────────────────────────────────────────────────────────
-- Multi-series model: one return_rate series PER store. Train on everything
-- before the recent 14-day window; detect on the recent window (test timestamps
-- must be strictly after training timestamps).
USE SCHEMA ANALYTICS;

CREATE OR REPLACE VIEW ANALYTICS.RETURN_RATE_TRAIN AS
    SELECT store_id, metric_date, return_rate
    FROM RAW.STORE_DAY_METRICS
    WHERE metric_date < DATEADD(day, -14, CURRENT_DATE());

CREATE OR REPLACE VIEW ANALYTICS.RETURN_RATE_RECENT AS
    SELECT store_id, metric_date, return_rate
    FROM RAW.STORE_DAY_METRICS
    WHERE metric_date >= DATEADD(day, -14, CURRENT_DATE());

-- Training the model is a schema-level object (takes ~1-2 min on MEDIUM).
CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION ANALYTICS.RETURN_RATE_DETECTOR(
    INPUT_DATA      => TABLE(ANALYTICS.RETURN_RATE_TRAIN),
    SERIES_COLNAME  => 'store_id',
    TIMESTAMP_COLNAME => 'metric_date',
    TARGET_COLNAME  => 'return_rate',
    LABEL_COLNAME   => ''
);

-- Persist the anomaly findings so the agent's custom tool can read them cheaply.
CREATE OR REPLACE TABLE ANALYTICS.STORE_ANOMALY_FINDINGS AS
SELECT *
FROM TABLE(ANALYTICS.RETURN_RATE_DETECTOR!DETECT_ANOMALIES(
    INPUT_DATA        => TABLE(ANALYTICS.RETURN_RATE_RECENT),
    SERIES_COLNAME    => 'store_id',
    TIMESTAMP_COLNAME => 'metric_date',
    TARGET_COLNAME    => 'return_rate',
    CONFIG_OBJECT     => {'prediction_interval': 0.99}
));

-- Convenience view: only the flagged rows, joined to store context.
CREATE OR REPLACE VIEW ANALYTICS.STORE_ANOMALIES_ENRICHED AS
SELECT
    f."SERIES"::NUMBER          AS store_id,
    s.retailer_id, s.region, s.metro, s.store_format,
    f."TS"::TIMESTAMP_NTZ       AS metric_date,
    f."Y"::FLOAT                AS return_rate,
    f."FORECAST"::FLOAT         AS expected_return_rate,
    f."UPPER_BOUND"::FLOAT      AS upper_bound,
    f."DISTANCE"::FLOAT         AS distance
FROM ANALYTICS.STORE_ANOMALY_FINDINGS f
JOIN RAW.STORES s ON s.store_id = f."SERIES"::NUMBER
WHERE f."IS_ANOMALY" = TRUE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. CORTEX ML FUNCTIONS — Top Insights (the "why" / driver analysis)
-- ─────────────────────────────────────────────────────────────────────────────
-- Label = recent window (last 10 days) is the TEST group; the prior 50 days are
-- the CONTROL group. store_id cast to STRING so it is treated as categorical.
CREATE OR REPLACE VIEW ANALYTICS.RETURN_DRIVERS_INPUT AS
SELECT
    refund_amount::FLOAT                                                  AS metric,
    region, metro, product_category, reason_code,
    store_id::STRING                                                      AS store_id,
    (return_date >= DATEADD(day, -10, CURRENT_DATE()))                    AS label
FROM RAW.RETURNS_FACT;

CREATE OR REPLACE SNOWFLAKE.ML.TOP_INSIGHTS ANALYTICS.RETURN_DRIVERS_MODEL();

-- Run driver analysis and persist the result so the agent can read it.
CALL ANALYTICS.RETURN_DRIVERS_MODEL!GET_DRIVERS(
    INPUT_DATA     => TABLE(ANALYTICS.RETURN_DRIVERS_INPUT),
    LABEL_COLNAME  => 'label',
    METRIC_COLNAME => 'metric'
);
CREATE OR REPLACE TABLE ANALYTICS.RETURN_DRIVERS AS
    SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. SEMANTIC VIEW — powers Cortex Analyst (ad-hoc "what should I focus on?")
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE SEMANTIC VIEW ANALYTICS.RETAIL_RETURNS_SV
  TABLES (
    retailers AS RAW.RETAILERS
      PRIMARY KEY (retailer_id)
      COMMENT = 'Retail chains (tenants) served by the platform',
    stores AS RAW.STORES
      PRIMARY KEY (store_id)
      COMMENT = 'Physical stores, one per retailer',
    returns AS RAW.RETURNS_FACT
      PRIMARY KEY (return_id)
      COMMENT = 'Individual product return / refund records',
    store_metrics AS RAW.STORE_DAY_METRICS
      PRIMARY KEY (store_id, metric_date)
      COMMENT = 'Daily per-store sales and return metrics'
  )
  RELATIONSHIPS (
    stores_to_retailers AS stores (retailer_id) REFERENCES retailers,
    returns_to_stores AS returns (store_id) REFERENCES stores,
    metrics_to_stores AS store_metrics (store_id) REFERENCES stores
  )
  FACTS (
    returns.refund AS returns.refund_amount,
    returns.fraud_flag AS IFF(returns.is_fraud_suspected, 1, 0),
    store_metrics.daily_sales AS store_metrics.sales_amount,
    store_metrics.daily_returns AS store_metrics.return_count,
    store_metrics.daily_txns AS store_metrics.transaction_count
  )
  DIMENSIONS (
    retailers.retailer_name AS retailers.retailer_name
      WITH SYNONYMS = ('retailer','chain','tenant') COMMENT = 'Retail chain name',
    stores.store_id_dim AS stores.store_id
      WITH SYNONYMS = ('store','store number') COMMENT = 'Store identifier',
    stores.region AS stores.region
      WITH SYNONYMS = ('area') COMMENT = 'Geographic region',
    stores.metro AS stores.metro
      WITH SYNONYMS = ('metro area','market') COMMENT = 'Metro market',
    stores.store_format AS stores.store_format
      COMMENT = 'Store format (Supercenter, Neighborhood, Express)',
    returns.product_category AS returns.product_category
      WITH SYNONYMS = ('category','department') COMMENT = 'Product category of the returned item',
    returns.reason_code AS returns.reason_code
      WITH SYNONYMS = ('return reason') COMMENT = 'Reason the item was returned',
    returns.return_date AS returns.return_date
      COMMENT = 'Date the item was returned',
    store_metrics.metric_date AS store_metrics.metric_date
      COMMENT = 'Calendar date of the daily store metrics'
  )
  METRICS (
    returns.total_refund AS SUM(returns.refund_amount)
      COMMENT = 'Total refunded dollars',
    returns.return_txn_count AS COUNT(returns.return_id)
      COMMENT = 'Number of return transactions',
    returns.fraud_suspected_count AS SUM(IFF(returns.is_fraud_suspected, 1, 0))
      COMMENT = 'Number of returns flagged as fraud-suspected',
    returns.avg_refund AS AVG(returns.refund_amount)
      COMMENT = 'Average refund amount per return',
    store_metrics.total_sales AS SUM(store_metrics.sales_amount)
      COMMENT = 'Total sales dollars',
    store_metrics.avg_return_rate AS AVG(store_metrics.return_rate)
      COMMENT = 'Average daily return rate (returns / transactions)'
  )
  COMMENT = 'Retail returns and store performance for proactive intelligence';

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. CORTEX SEARCH — semantic search over return-reason free text
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE CORTEX SEARCH SERVICE ANALYTICS.RETURN_REASONS_SEARCH
  ON reason_text
  ATTRIBUTES store_id, product_category
  WAREHOUSE = PROACTIVE_RETAIL_WH
  TARGET_LAG = '1 hour'
  AS
    SELECT return_id, store_id, product_category, reason_text
    FROM RAW.RETURN_REASONS;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. (OPTIONAL) SCHEDULED MONITORING TASK — the proactive engine
-- ─────────────────────────────────────────────────────────────────────────────
-- In production the findings table is refreshed on a schedule so the assistant
-- always has fresh anomalies to narrate. Created SUSPENDED; RESUME to activate.
CREATE OR REPLACE TASK ANALYTICS.REFRESH_ANOMALY_FINDINGS_TASK
  WAREHOUSE = PROACTIVE_RETAIL_WH
  SCHEDULE = '60 MINUTE'
AS
  CREATE OR REPLACE TABLE ANALYTICS.STORE_ANOMALY_FINDINGS AS
  SELECT *
  FROM TABLE(ANALYTICS.RETURN_RATE_DETECTOR!DETECT_ANOMALIES(
      INPUT_DATA        => TABLE(ANALYTICS.RETURN_RATE_RECENT),
      SERIES_COLNAME    => 'store_id',
      TIMESTAMP_COLNAME => 'metric_date',
      TARGET_COLNAME    => 'return_rate',
      CONFIG_OBJECT     => {'prediction_interval': 0.99}
  ));
-- ALTER TASK ANALYTICS.REFRESH_ANOMALY_FINDINGS_TASK RESUME;  -- enable in demo

-- ─────────────────────────────────────────────────────────────────────────────
-- Setup complete.
--   1) You just ran this script (data + ML models + findings + semantic view + search).
--   2) Open lab/proactive-retail-intelligence-lab.ipynb — it tours the layer and
--      creates the custom "briefing" tool + the optimized Cortex Agent.
--   3) Finish in Snowflake CoWork (AI & ML -> Agents).
-- ─────────────────────────────────────────────────────────────────────────────
