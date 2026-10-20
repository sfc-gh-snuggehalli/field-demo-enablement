-- Call-transcript topics to churn: the presenter path (story app + agent).
--
-- Run after the five lab notebooks (./demo.sh build) with ./demo.sh app, which also deploys the
-- Streamlit app. Re-runnable: every statement is CREATE OR REPLACE. Re-run it after any notebook
-- rebuild, because the notebooks recreate the tables the search service and drivers read.
--
-- Creates, all in TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS:
--   LIVE_RUN_LOG              one row per step of each live "January arrives" run
--   LIVE_STEP(step, run_id)   runs one step of the January load and logs it
--   LOAD_JANUARY(run_id)      runs every step in order; the app starts it asynchronously and polls the log
--   DEMO_RESET_JANUARY()      removes January again so the live step can be shown again
--   ACCOUNT_RISK_DRIVERS      per-account feature contributions from the churn model's EXPLAIN
--   ACCOUNT_RISK              latest churn probability, risk band and top driver per account
--   CHURN_STORY_SV            semantic view for the agent: topics, price, deals, accounts, risk
--   CALL_SEARCH               Cortex Search over redacted segments only
--   CHURN_INSIGHTS_AGENT      the agent shown in Snowflake Intelligence

USE ROLE SYSADMIN;
USE WAREHOUSE TRANSCRIPT_CHURN_ML_WH;
USE SCHEMA TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS;

-- ---------------------------------------------------------------------------------------------
-- 1. The live step: January's calls arrive and flow through the same pipeline
-- ---------------------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.LIVE_RUN_LOG (
  RUN_ID STRING, STEP_NO INT, STEP STRING, LABEL STRING,
  ROWS_OUT INT, AI_CALLS INT, INPUT_TOKENS INT, SECONDS FLOAT,
  DETAIL VARIANT, LOGGED_AT TIMESTAMP_NTZ)
  COMMENT = 'One row per step of each live January run: rows produced, AI calls, input tokens, seconds';

CREATE OR REPLACE PROCEDURE TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.LIVE_STEP(STEP STRING, RUN_ID STRING)
RETURNS VARIANT LANGUAGE SQL
COMMENT = 'One step of the January load: arrive, segments, redact, embed, topics, price. Idempotent: only new rows are processed'
EXECUTE AS OWNER
AS
$$
DECLARE
  t0 TIMESTAMP_LTZ;
  step_no INT;
  label STRING;
  rows_out INT DEFAULT 0;
  ai_calls INT DEFAULT 0;
  tokens INT DEFAULT 0;
  detail VARIANT DEFAULT OBJECT_CONSTRUCT();
  res VARIANT;
  n INT;
  n2 INT;
BEGIN
  t0 := CURRENT_TIMESTAMP();
  IF (STEP = 'arrive') THEN
    step_no := 1; label := 'New calls land in RAW';
    -- Inserts only calls and turns not already there, so a partial run can simply be run again.
    INSERT INTO TRANSCRIPT_CHURN_ML_DEMO.RAW.CALLS
      SELECT n.* FROM TRANSCRIPT_CHURN_ML_DEMO.RAW.CALLS_NEW_MONTH n
      WHERE NOT EXISTS (SELECT 1 FROM TRANSCRIPT_CHURN_ML_DEMO.RAW.CALLS c WHERE c.CALL_ID = n.CALL_ID);
    rows_out := SQLROWCOUNT;
    INSERT INTO TRANSCRIPT_CHURN_ML_DEMO.RAW.UTTERANCES
      SELECT n.* FROM TRANSCRIPT_CHURN_ML_DEMO.RAW.UTTERANCES_NEW_MONTH n
      WHERE NOT EXISTS (SELECT 1 FROM TRANSCRIPT_CHURN_ML_DEMO.RAW.UTTERANCES u
                        WHERE u.CALL_ID = n.CALL_ID AND u.TURN_NO = n.TURN_NO);
    detail := OBJECT_CONSTRUCT('calls', rows_out, 'turns', SQLROWCOUNT);
  ELSEIF (STEP = 'segments') THEN
    step_no := 2; label := 'Conversations split into segments (short dials dropped)';
    ALTER DYNAMIC TABLE TRANSCRIPT_CHURN_ML_DEMO.CORE.SEGMENTS REFRESH;
    SELECT COUNT(*) INTO :rows_out FROM TRANSCRIPT_CHURN_ML_DEMO.CORE.SEGMENTS
     WHERE CALL_ID IN (SELECT CALL_ID FROM TRANSCRIPT_CHURN_ML_DEMO.RAW.CALLS_NEW_MONTH);
    SELECT COUNT_IF(CALL_TYPE = 'OUTBOUND_DIAL') INTO :n FROM TRANSCRIPT_CHURN_ML_DEMO.RAW.CALLS_NEW_MONTH;
    detail := OBJECT_CONSTRUCT('short_dials_skipped', n);
  ELSEIF (STEP = 'redact') THEN
    step_no := 3; label := 'PII redacted with AI_REDACT (new segments only)';
    CALL TRANSCRIPT_CHURN_ML_DEMO.CORE.REDACT_NEW_SEGMENTS() INTO :res;
    rows_out := res:redacted_rows::INT;
    ai_calls := 2 * rows_out;
    SELECT COUNT_IF(REGEXP_LIKE(REDACTED_TEXT, '.*[0-9]{3}-555-[0-9]{4}.*', 's')),
           COUNT_IF(REDACTED_TEXT ILIKE '%@homemail.example%')
      INTO :n, :n2 FROM TRANSCRIPT_CHURN_ML_DEMO.CORE.SEGMENTS_REDACTED
     WHERE CALL_ID IN (SELECT CALL_ID FROM TRANSCRIPT_CHURN_ML_DEMO.RAW.CALLS_NEW_MONTH);
    detail := OBJECT_CONSTRUCT('phones_left', n, 'emails_left', n2);
  ELSEIF (STEP = 'embed') THEN
    step_no := 4; label := 'Redacted text embedded with AI_EMBED (incremental refresh)';
    ALTER DYNAMIC TABLE TRANSCRIPT_CHURN_ML_DEMO.CORE.SEGMENT_EMBEDDINGS REFRESH;
    SELECT COUNT(*), COALESCE(SUM(AI_COUNT_TOKENS('ai_embed', 'snowflake-arctic-embed-l-v2.0', REDACTED_TEXT)), 0)
      INTO :rows_out, :tokens FROM TRANSCRIPT_CHURN_ML_DEMO.CORE.SEGMENT_EMBEDDINGS
     WHERE CALL_ID IN (SELECT CALL_ID FROM TRANSCRIPT_CHURN_ML_DEMO.RAW.CALLS_NEW_MONTH);
    ai_calls := rows_out;
    SELECT COUNT(*) INTO :n FROM TRANSCRIPT_CHURN_ML_DEMO.CORE.SEGMENT_EMBEDDINGS;
    detail := OBJECT_CONSTRUCT('embeddings_total', n);
  ELSEIF (STEP = 'topics') THEN
    step_no := 5; label := 'Topics assigned: business topics first, then the registered clustering model';
    -- Same rule as notebook 02 (similarity >= 0.47 and margin >= 0.03), then the registry's default
    -- TOPIC_CLUSTERER version for the rest. Only segments without a topic yet are scored.
    INSERT INTO TRANSCRIPT_CHURN_ML_DEMO.ML.SEGMENT_TOPICS
    WITH new_seg AS (
      SELECT e.* FROM TRANSCRIPT_CHURN_ML_DEMO.CORE.SEGMENT_EMBEDDINGS e
      WHERE NOT EXISTS (SELECT 1 FROM TRANSCRIPT_CHURN_ML_DEMO.ML.SEGMENT_TOPICS t WHERE t.SEGMENT_ID = e.SEGMENT_ID)),
    sims AS (
      SELECT n.SEGMENT_ID, x.TOPIC_ID, MAX(VECTOR_COSINE_SIMILARITY(n.EMBEDDING, x.EMBEDDING)) AS SIM
      FROM new_seg n CROSS JOIN TRANSCRIPT_CHURN_ML_DEMO.ML.TOPIC_EXEMPLAR_EMBEDDINGS x GROUP BY 1, 2),
    ranked AS (
      SELECT SEGMENT_ID, TOPIC_ID, SIM,
             ROW_NUMBER() OVER (PARTITION BY SEGMENT_ID ORDER BY SIM DESC) AS RN,
             LEAD(SIM) OVER (PARTITION BY SEGMENT_ID ORDER BY SIM DESC) AS SIM2
      FROM sims),
    seed AS (
      SELECT SEGMENT_ID, TOPIC_ID AS BEST_TOPIC, SIM AS BEST_SIM,
             COALESCE(SIM >= 0.47 AND SIM - SIM2 >= 0.03, FALSE) AS ASSIGNED
      FROM ranked WHERE RN = 1),
    pred AS (
      SELECT n.SEGMENT_ID, TRANSCRIPT_CHURN_ML_DEMO.ML.TOPIC_CLUSTERER!PREDICT(n.EMBEDDING::ARRAY) AS P
      FROM new_seg n JOIN seed s USING (SEGMENT_ID) WHERE NOT s.ASSIGNED)
    SELECT n.SEGMENT_ID, n.CALL_ID, n.ACCOUNT_ID, n.CALL_TS, n.CALL_TYPE, n.OPPORTUNITY_ID,
           CASE WHEN s.ASSIGNED THEN s.BEST_TOPIC
                WHEN p.P:CLUSTER_ID::INT >= 0 THEN 'NEW_' || p.P:CLUSTER_ID::INT ELSE 'UNASSIGNED' END,
           CASE WHEN s.ASSIGNED THEN tx.TOPIC_NAME WHEN p.P:CLUSTER_ID::INT >= 0 THEN pt.LABEL ELSE 'Unassigned' END,
           CASE WHEN s.ASSIGNED THEN 'SEEDED' WHEN p.P:CLUSTER_ID::INT >= 0 THEN 'DISCOVERED' ELSE 'NOISE' END,
           IFF(s.ASSIGNED, s.BEST_SIM, p.P:STRENGTH::FLOAT)
    FROM new_seg n
    JOIN seed s USING (SEGMENT_ID)
    LEFT JOIN pred p USING (SEGMENT_ID)
    LEFT JOIN (SELECT DISTINCT TOPIC_ID, TOPIC_NAME FROM TRANSCRIPT_CHURN_ML_DEMO.ML.TOPIC_TAXONOMY) tx ON tx.TOPIC_ID = s.BEST_TOPIC
    LEFT JOIN TRANSCRIPT_CHURN_ML_DEMO.ML.PROPOSED_TOPICS pt
      ON pt.RUN_LABEL = 'V2' AND pt.CLUSTER_ID = p.P:CLUSTER_ID::INT;
    rows_out := SQLROWCOUNT;
    SELECT COUNT_IF(TOPIC_SOURCE = 'SEEDED'), COUNT_IF(TOPIC_SOURCE = 'DISCOVERED')
      INTO :n, :n2 FROM TRANSCRIPT_CHURN_ML_DEMO.ML.SEGMENT_TOPICS
     WHERE CALL_ID IN (SELECT CALL_ID FROM TRANSCRIPT_CHURN_ML_DEMO.RAW.CALLS_NEW_MONTH);
    -- PREDICT calls on the registered clustering model are not Cortex AI function calls.
    detail := OBJECT_CONSTRUCT('seeded', n, 'discovered', n2, 'unassigned', rows_out - n - n2,
                               'model_calls', rows_out - n);
  ELSEIF (STEP = 'price') THEN
    step_no := 6; label := 'Price sentiment: AI_SENTIMENT on price talk, AI_CLASSIFY on the negatives';
    -- Same cascade as notebook 03, for new segments only.
    INSERT INTO TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.PRICE_SENTIMENT
    WITH pre AS (
      SELECT t.SEGMENT_ID, t.ACCOUNT_ID, t.CALL_TS, t.TOPIC_ID, e.REDACTED_CUSTOMER_TEXT AS CUSTOMER_TEXT
      FROM TRANSCRIPT_CHURN_ML_DEMO.ML.SEGMENT_TOPICS t
      JOIN TRANSCRIPT_CHURN_ML_DEMO.CORE.SEGMENT_EMBEDDINGS e USING (SEGMENT_ID)
      WHERE t.CALL_ID IN (SELECT CALL_ID FROM TRANSCRIPT_CHURN_ML_DEMO.RAW.CALLS_NEW_MONTH)
        AND NOT EXISTS (SELECT 1 FROM TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.PRICE_SENTIMENT p WHERE p.SEGMENT_ID = t.SEGMENT_ID)
        AND (t.TOPIC_ID = 'PRICING'
             OR REGEXP_LIKE(e.REDACTED_CUSTOMER_TEXT, '.*(price|cost|pay|expensive|cheaper|quote|seat|bill).*', 'is'))),
    s AS (SELECT *, AI_SENTIMENT(CUSTOMER_TEXT, ['pricing model', 'competitor price', 'value for money']) AS SENTIMENT FROM pre),
    labeled AS (SELECT *, SENTIMENT:categories[0]:sentiment::STRING AS OVERALL_SENTIMENT FROM s)
    SELECT SEGMENT_ID, ACCOUNT_ID, CALL_TS, TOPIC_ID, CUSTOMER_TEXT, SENTIMENT, OVERALL_SENTIMENT,
           OVERALL_SENTIMENT IN ('negative', 'mixed'),
           IFF(OVERALL_SENTIMENT IN ('negative', 'mixed'),
               AI_CLASSIFY(CUSTOMER_TEXT, ['competitor price', 'pricing model', 'value for money']):labels[0]::STRING, NULL)
    FROM labeled;
    rows_out := SQLROWCOUNT;
    SELECT COUNT_IF(IS_NEGATIVE) INTO :n FROM TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.PRICE_SENTIMENT
     WHERE SEGMENT_ID IN (SELECT SEGMENT_ID FROM TRANSCRIPT_CHURN_ML_DEMO.ML.SEGMENT_TOPICS
                          WHERE CALL_ID IN (SELECT CALL_ID FROM TRANSCRIPT_CHURN_ML_DEMO.RAW.CALLS_NEW_MONTH));
    ai_calls := rows_out + n;
    detail := OBJECT_CONSTRUCT('negative', n);
    -- Make the new segments searchable for the agent now rather than at the next scheduled refresh.
    ALTER CORTEX SEARCH SERVICE TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.CALL_SEARCH REFRESH;
  ELSE
    RETURN OBJECT_CONSTRUCT('status', 'error', 'message', 'Unknown step: ' || STEP);
  END IF;

  INSERT INTO TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.LIVE_RUN_LOG
    SELECT :RUN_ID, :step_no, :STEP, :label, :rows_out, :ai_calls, :tokens,
           DATEDIFF('millisecond', :t0, CURRENT_TIMESTAMP()) / 1000, :detail, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
  RETURN OBJECT_CONSTRUCT('status', 'ok', 'step', STEP, 'label', label, 'rows', rows_out, 'ai_calls', ai_calls,
                          'input_tokens', tokens, 'seconds', DATEDIFF('millisecond', t0, CURRENT_TIMESTAMP()) / 1000,
                          'detail', detail);
END;
$$;

DROP PROCEDURE IF EXISTS TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.LOAD_JANUARY();

CREATE OR REPLACE PROCEDURE TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.LOAD_JANUARY(RUN_ID STRING)
RETURNS VARIANT LANGUAGE SQL
COMMENT = 'Runs every LIVE_STEP in order under one run id, logging start, done or error. Safe to re-run after a partial run'
EXECUTE AS OWNER
AS
$$
DECLARE
  res VARIANT;
  steps ARRAY DEFAULT ARRAY_CONSTRUCT('arrive', 'segments', 'redact', 'embed', 'topics', 'price');
  s STRING;
  busy INT;
BEGIN
  -- One run at a time: a run that logged a start in the last 15 minutes and has not finished is still going.
  SELECT COUNT(*) INTO :busy FROM (
    SELECT RUN_ID FROM TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.LIVE_RUN_LOG
    GROUP BY RUN_ID
    HAVING COUNT_IF(STEP = 'start') > 0 AND COUNT_IF(STEP IN ('done', 'error')) = 0
       AND MAX(LOGGED_AT) > DATEADD('minute', -15, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ));
  IF (busy > 0) THEN
    RETURN OBJECT_CONSTRUCT('status', 'busy', 'message', 'Another January run is still in progress.');
  END IF;
  INSERT INTO TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.LIVE_RUN_LOG
    SELECT :RUN_ID, 0, 'start', 'Run started', 0, 0, 0, 0, NULL, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
  FOR i IN 0 TO 5 DO
    s := GET(steps, i)::STRING;
    CALL TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.LIVE_STEP(:s, :RUN_ID) INTO :res;
  END FOR;
  INSERT INTO TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.LIVE_RUN_LOG
    SELECT :RUN_ID, 7, 'done', 'Run complete', 0, 0, 0, 0, NULL, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
  RETURN OBJECT_CONSTRUCT('status', 'ok', 'run_id', RUN_ID);
EXCEPTION
  WHEN OTHER THEN
    INSERT INTO TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.LIVE_RUN_LOG
      SELECT :RUN_ID, 8, 'error', 'Run failed', 0, 0, 0, 0,
             OBJECT_CONSTRUCT('step', :s, 'message', :SQLERRM), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    RETURN OBJECT_CONSTRUCT('status', 'error', 'run_id', RUN_ID, 'step', s, 'message', SQLERRM);
END;
$$;

CREATE OR REPLACE PROCEDURE TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.DEMO_RESET_JANUARY()
RETURNS VARIANT LANGUAGE SQL
COMMENT = 'Removes January from raw, redacted, topic and price tables so the live step can run again'
EXECUTE AS OWNER
AS
$$
DECLARE
  res VARIANT;
  n INT;
BEGIN
  DELETE FROM TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.PRICE_SENTIMENT
   WHERE SEGMENT_ID IN (SELECT SEGMENT_ID FROM TRANSCRIPT_CHURN_ML_DEMO.ML.SEGMENT_TOPICS
                        WHERE CALL_ID IN (SELECT CALL_ID FROM TRANSCRIPT_CHURN_ML_DEMO.RAW.CALLS_NEW_MONTH));
  DELETE FROM TRANSCRIPT_CHURN_ML_DEMO.ML.SEGMENT_TOPICS
   WHERE CALL_ID IN (SELECT CALL_ID FROM TRANSCRIPT_CHURN_ML_DEMO.RAW.CALLS_NEW_MONTH);
  DELETE FROM TRANSCRIPT_CHURN_ML_DEMO.RAW.UTTERANCES
   WHERE CALL_ID IN (SELECT CALL_ID FROM TRANSCRIPT_CHURN_ML_DEMO.RAW.CALLS_NEW_MONTH);
  DELETE FROM TRANSCRIPT_CHURN_ML_DEMO.RAW.CALLS
   WHERE CALL_ID IN (SELECT CALL_ID FROM TRANSCRIPT_CHURN_ML_DEMO.RAW.CALLS_NEW_MONTH);
  -- Refreshes SEGMENTS and consumes the stream's delete records; there are no inserts to redact.
  CALL TRANSCRIPT_CHURN_ML_DEMO.CORE.REDACT_NEW_SEGMENTS() INTO :res;
  DELETE FROM TRANSCRIPT_CHURN_ML_DEMO.CORE.SEGMENTS_REDACTED
   WHERE CALL_ID IN (SELECT CALL_ID FROM TRANSCRIPT_CHURN_ML_DEMO.RAW.CALLS_NEW_MONTH);
  ALTER DYNAMIC TABLE TRANSCRIPT_CHURN_ML_DEMO.CORE.SEGMENT_EMBEDDINGS REFRESH;
  ALTER CORTEX SEARCH SERVICE TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.CALL_SEARCH REFRESH;
  SELECT COUNT(*) INTO :n FROM TRANSCRIPT_CHURN_ML_DEMO.ML.SEGMENT_TOPICS;
  RETURN OBJECT_CONSTRUCT('status', 'ok', 'segments_with_topics', n, 'redact_call', res);
END;
$$;

-- ---------------------------------------------------------------------------------------------
-- 2. Churn risk per account, with the model's own explanation
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE TABLE TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.ACCOUNT_RISK_DRIVERS
  COMMENT = 'Per-account feature contributions at the latest snapshot, from the default churn model EXPLAIN method' AS
-- COX_CALLS is the version notebook 04 registers as default and scores with; it is the one with an EXPLAIN method.
WITH latest AS (SELECT * FROM TRANSCRIPT_CHURN_ML_DEMO.FEATURES.SCORING_INPUT
           WHERE AS_OF = (SELECT MAX(AS_OF) FROM TRANSCRIPT_CHURN_ML_DEMO.FEATURES.SCORING_INPUT)),
x AS (
  SELECT s.ACCOUNT_ID, e.*
  FROM latest s,
       TABLE(MODEL(TRANSCRIPT_CHURN_ML_DEMO.ML.CHURN_SURVIVAL, COX_CALLS)!EXPLAIN(s.LOGINS_L3M, s.LOGIN_TREND, s.REPORTS_L3M, s.ACTIVE_USERS, s.TENURE_DAYS, s.MRR, s.IS_TEAM,
                       s.CALLS_90D, s.SEGMENTS_90D, s.PRICE_NEG_90D, s.PRICE_COMPETITOR_90D, s.PRICE_MODEL_90D,
                       s.PRICE_VALUE_90D, s.DISCOVERED_SEGMENTS_90D, s.RENEWAL_SEGMENTS_90D)) e),
c AS (
  SELECT ACCOUNT_ID, REPLACE(FEATURE, '_CONTRIB', '') AS FEATURE, CONTRIB
  FROM x UNPIVOT (CONTRIB FOR FEATURE IN (
    LOGINS_L3M_CONTRIB, LOGIN_TREND_CONTRIB, REPORTS_L3M_CONTRIB, ACTIVE_USERS_CONTRIB, TENURE_DAYS_CONTRIB,
    MRR_CONTRIB, IS_TEAM_CONTRIB, CALLS_90D_CONTRIB, SEGMENTS_90D_CONTRIB, PRICE_NEG_90D_CONTRIB,
    PRICE_COMPETITOR_90D_CONTRIB, PRICE_MODEL_90D_CONTRIB, PRICE_VALUE_90D_CONTRIB,
    DISCOVERED_SEGMENTS_90D_CONTRIB, RENEWAL_SEGMENTS_90D_CONTRIB))),
v AS (
  SELECT ACCOUNT_ID, FEATURE, FEATURE_VALUE
  FROM (SELECT ACCOUNT_ID, LOGINS_L3M, LOGIN_TREND, REPORTS_L3M, ACTIVE_USERS, TENURE_DAYS, MRR, IS_TEAM, CALLS_90D,
               SEGMENTS_90D, PRICE_NEG_90D, PRICE_COMPETITOR_90D, PRICE_MODEL_90D, PRICE_VALUE_90D,
               DISCOVERED_SEGMENTS_90D, RENEWAL_SEGMENTS_90D FROM latest)
  UNPIVOT (FEATURE_VALUE FOR FEATURE IN (
    LOGINS_L3M, LOGIN_TREND, REPORTS_L3M, ACTIVE_USERS, TENURE_DAYS, MRR, IS_TEAM, CALLS_90D, SEGMENTS_90D,
    PRICE_NEG_90D, PRICE_COMPETITOR_90D, PRICE_MODEL_90D, PRICE_VALUE_90D, DISCOVERED_SEGMENTS_90D,
    RENEWAL_SEGMENTS_90D))),
labels (FEATURE, LABEL, SOURCE) AS (
  SELECT * FROM VALUES
    ('LOGINS_L3M', 'Logins, last 3 months', 'Product usage'),
    ('LOGIN_TREND', 'Login trend', 'Product usage'),
    ('REPORTS_L3M', 'Reports run, last 3 months', 'Product usage'),
    ('ACTIVE_USERS', 'Active users', 'Product usage'),
    ('TENURE_DAYS', 'Tenure', 'Account'),
    ('MRR', 'Monthly revenue', 'Account'),
    ('IS_TEAM', 'Team plan', 'Account'),
    ('CALLS_90D', 'Calls, last 90 days', 'Calls'),
    ('SEGMENTS_90D', 'Conversation volume, last 90 days', 'Calls'),
    ('PRICE_NEG_90D', 'Negative price remarks', 'Calls'),
    ('PRICE_COMPETITOR_90D', 'Competitor-price remarks', 'Calls'),
    ('PRICE_MODEL_90D', 'Pricing-model complaints', 'Calls'),
    ('PRICE_VALUE_90D', 'Value-for-money complaints', 'Calls'),
    ('DISCOVERED_SEGMENTS_90D', 'Emerging-topic mentions', 'Calls'),
    ('RENEWAL_SEGMENTS_90D', 'Renewal conversations', 'Calls'))
SELECT c.ACCOUNT_ID, c.FEATURE, l.LABEL, l.SOURCE, c.CONTRIB, v.FEATURE_VALUE,
       ROW_NUMBER() OVER (PARTITION BY c.ACCOUNT_ID ORDER BY c.CONTRIB DESC) AS DRIVER_RANK
FROM c JOIN v USING (ACCOUNT_ID, FEATURE) JOIN labels l USING (FEATURE);

CREATE OR REPLACE TABLE TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.ACCOUNT_RISK
  COMMENT = 'Latest churn probability per account, risk band (top 10% HIGH, next 20% MEDIUM) and top driver' AS
WITH latest AS (
  SELECT * FROM TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.CHURN_SCORES
  WHERE SCORED_AT = (SELECT MAX(SCORED_AT) FROM TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.CHURN_SCORES)),
ranked AS (SELECT *, PERCENT_RANK() OVER (ORDER BY CHURN_PROB DESC) AS PR FROM latest)
SELECT r.ACCOUNT_ID, r.SCORED_AT AS AS_OF, r.CHURN_PROB,
       CASE WHEN r.PR < 0.10 THEN 'HIGH' WHEN r.PR < 0.30 THEN 'MEDIUM' ELSE 'LOW' END AS RISK_BAND,
       a.SEGMENT AS CUSTOMER_SEGMENT, a.PLAN_TIER, a.MRR,
       d.LABEL AS TOP_DRIVER, d.SOURCE AS TOP_DRIVER_SOURCE,
       r.PRICE_NEG_90D, r.PRICE_COMPETITOR_90D, r.DISCOVERED_SEGMENTS_90D, r.LOGIN_TREND
FROM ranked r
JOIN TRANSCRIPT_CHURN_ML_DEMO.RAW.ACCOUNTS a USING (ACCOUNT_ID)
LEFT JOIN TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.ACCOUNT_RISK_DRIVERS d ON d.ACCOUNT_ID = r.ACCOUNT_ID AND d.DRIVER_RANK = 1;

-- ---------------------------------------------------------------------------------------------
-- 3. What the agent reads: one semantic view and one search service (redacted text only)
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE SEMANTIC VIEW TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.CHURN_STORY_SV
  TABLES (
    seg AS TRANSCRIPT_CHURN_ML_DEMO.ML.SEGMENT_TOPICS PRIMARY KEY (SEGMENT_ID)
      WITH SYNONYMS = ('conversation segment', 'call excerpt')
      COMMENT = 'One row per conversation segment (four turns of a call) with its topic',
    price AS TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.PRICE_SENTIMENT PRIMARY KEY (SEGMENT_ID)
      WITH SYNONYMS = ('price remark', 'pricing feedback')
      COMMENT = 'Price sentiment for segments where the customer talks about price',
    opp AS TRANSCRIPT_CHURN_ML_DEMO.RAW.CRM_OPPORTUNITIES PRIMARY KEY (OPPORTUNITY_ID)
      WITH SYNONYMS = ('deal', 'renewal', 'opportunity')
      COMMENT = 'Renewal and upsell opportunities and their outcome',
    acct AS TRANSCRIPT_CHURN_ML_DEMO.RAW.ACCOUNTS PRIMARY KEY (ACCOUNT_ID)
      WITH SYNONYMS = ('customer', 'account')
      COMMENT = 'Customer accounts',
    risk AS TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.ACCOUNT_RISK PRIMARY KEY (ACCOUNT_ID)
      WITH SYNONYMS = ('churn risk', 'churn score', 'at-risk accounts')
      COMMENT = 'Latest churn probability per account from the registered churn model, with its top driver'
  )
  RELATIONSHIPS (
    price_to_segment AS price (SEGMENT_ID) REFERENCES seg,
    segment_to_opportunity AS seg (OPPORTUNITY_ID) REFERENCES opp,
    segment_to_account AS seg (ACCOUNT_ID) REFERENCES acct,
    risk_to_account AS risk (ACCOUNT_ID) REFERENCES acct
  )
  DIMENSIONS (
    seg.topic AS seg.TOPIC_NAME COMMENT = 'Topic of the segment: a business-defined topic or one discovered by clustering',
    seg.topic_source AS seg.TOPIC_SOURCE COMMENT = 'SEEDED (business topic), DISCOVERED (found by clustering) or NOISE',
    seg.call_type AS seg.CALL_TYPE COMMENT = 'RENEWAL, SUPPORT, SALES or ONBOARDING',
    seg.call_month AS DATE_TRUNC('MONTH', seg.CALL_TS) COMMENT = 'Month of the call',
    price.price_driver AS price.PRICE_DRIVER COMMENT = 'Main driver of a negative price remark: competitor price, pricing model or value for money',
    price.price_sentiment AS price.OVERALL_SENTIMENT COMMENT = 'Overall sentiment of a price remark',
    opp.deal_outcome AS opp.OUTCOME COMMENT = 'WON or LOST',
    opp.opportunity_type AS opp.OPPORTUNITY_TYPE COMMENT = 'RENEWAL or UPSELL',
    acct.account_id AS acct.ACCOUNT_ID COMMENT = 'Account identifier',
    acct.customer_segment AS acct.SEGMENT COMMENT = 'LOAN_OFFICER, AGENT or TEAM',
    acct.plan_tier AS acct.PLAN_TIER COMMENT = 'ESSENTIALS, PRO or ENTERPRISE',
    risk.risk_band AS risk.RISK_BAND
      WITH SYNONYMS = ('risk level', 'risk tier')
      COMMENT = 'HIGH (top 10% churn probability), MEDIUM (next 20%) or LOW',
    risk.top_driver AS risk.TOP_DRIVER
      WITH SYNONYMS = ('main reason', 'churn reason', 'risk driver')
      COMMENT = 'Feature that raises this account''s churn probability most, from the model''s EXPLAIN method',
    risk.top_driver_source AS risk.TOP_DRIVER_SOURCE COMMENT = 'Where the top driver comes from: Calls, Product usage or Account'
  )
  METRICS (
    seg.segment_count AS COUNT(seg.SEGMENT_ID) COMMENT = 'Number of conversation segments',
    seg.call_count AS COUNT(DISTINCT seg.CALL_ID) COMMENT = 'Number of calls',
    price.price_remarks AS COUNT(price.SEGMENT_ID) COMMENT = 'Segments that mention price',
    price.negative_price_remarks AS SUM(IFF(price.IS_NEGATIVE, 1, 0)) COMMENT = 'Negative or mixed price remarks',
    risk.account_count AS COUNT(risk.ACCOUNT_ID) COMMENT = 'Number of accounts',
    risk.avg_churn_probability AS AVG(risk.CHURN_PROB)
      WITH SYNONYMS = ('average churn risk')
      COMMENT = 'Average predicted probability of churning within the model horizon',
    risk.high_risk_accounts AS SUM(IFF(risk.RISK_BAND = 'HIGH', 1, 0)) COMMENT = 'Accounts in the HIGH risk band',
    risk.mrr_at_risk AS SUM(IFF(risk.RISK_BAND = 'HIGH', risk.MRR, 0))
      WITH SYNONYMS = ('revenue at risk')
      COMMENT = 'Monthly revenue of HIGH-risk accounts'
  )
  COMMENT = 'Call topics, price sentiment, deal outcomes and churn risk per account (synthetic demo data)';

CREATE OR REPLACE CORTEX SEARCH SERVICE TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.CALL_SEARCH
  ON SEGMENT_TEXT
  ATTRIBUTES TOPIC, CALL_TYPE, CALL_MONTH, RISK_BAND, ACCOUNT_ID
  WAREHOUSE = TRANSCRIPT_CHURN_ML_WH
  TARGET_LAG = '5 minutes'
  COMMENT = 'Search over redacted call segments only; raw transcript text is never indexed'
AS
SELECT r.SEGMENT_ID, r.REDACTED_TEXT AS SEGMENT_TEXT, r.ACCOUNT_ID, r.CALL_TYPE,
       TO_CHAR(r.CALL_TS, 'YYYY-MM') AS CALL_MONTH, t.TOPIC_NAME AS TOPIC, k.RISK_BAND
FROM TRANSCRIPT_CHURN_ML_DEMO.CORE.SEGMENTS_REDACTED r
JOIN TRANSCRIPT_CHURN_ML_DEMO.ML.SEGMENT_TOPICS t USING (SEGMENT_ID)
LEFT JOIN TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.ACCOUNT_RISK k ON k.ACCOUNT_ID = r.ACCOUNT_ID;

CREATE OR REPLACE AGENT TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.CHURN_INSIGHTS_AGENT
  COMMENT = 'Answers why accounts are at risk from call topics, price sentiment and churn scores (synthetic demo data)'
  PROFILE = '{"display_name": "Call insights and churn risk", "color": "#29B5E8"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto
instructions:
  system: >-
    You help customer success and revenue leaders understand what customers say on calls and which
    accounts are likely to churn. The data is a synthetic demo dataset of a subscription software
    business: call transcripts split into conversation segments, the topic of each segment, price
    sentiment, renewal and upsell deals, and a churn probability per account from a registered model.
  orchestration: >-
    Use call_metrics for counts, rates, revenue, topics by risk band and anything numeric. Use
    call_quotes when the user asks what customers said, wants examples or quotes, or asks why;
    filter it by TOPIC, RISK_BAND or CALL_MONTH when the question names one. For "why" questions,
    answer with the numbers first, then two or three short quotes.
  response: >-
    Lead with the answer in one or two sentences, then a short table or bullets. Quote customers
    only from call_quotes results, verbatim, and keep placeholders such as [NAME] as they are.
    Never guess personal details. Say the figures come from synthetic demo data when you give a
    number about revenue.
  sample_questions:
    - question: Which topics come up most on calls with high-risk accounts compared with low-risk accounts?
    - question: What are customers saying about competitor pricing? Show a few quotes.
    - question: How much monthly revenue is in high-risk accounts by plan tier, and what is their most common risk driver?
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: call_metrics
      description: >-
        Call topics, price sentiment, deal outcomes, accounts and churn risk (probability, risk band,
        top driver, monthly revenue at risk). Use for any count, share, trend or revenue question.
  - tool_spec:
      type: cortex_search
      name: call_quotes
      description: >-
        Redacted excerpts of customer calls with their topic, call type, call month, account and the
        account's risk band. Use to find what customers said.
tool_resources:
  call_metrics:
    execution_environment:
      type: warehouse
      warehouse: TRANSCRIPT_CHURN_ML_WH
    semantic_view: TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.CHURN_STORY_SV
  call_quotes:
    search_service: TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.CALL_SEARCH
    id_column: SEGMENT_ID
    title_column: TOPIC
    max_results: 5
$$;
