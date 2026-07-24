-- =============================================================================
-- Semantic Views & the AI-BI Stack on Snowflake — Lab: Setup Script
-- =============================================================================
-- Scenario: an SMS/MMS marketing platform used by e-commerce brands. Shoppers
-- opt in to a brand's list via a keyword (e.g. text "JOIN" to a shortcode).
-- Brands send two kinds of campaigns: one-off "broadcast" blasts and automated
-- "flow" messages (welcome, abandoned-cart, winback). Revenue from the store
-- (Shopify-style orders) is attributed back to the send that drove it.
--
-- This one script is idempotent and builds the ENTIRE AI-BI stack end to end:
--   (1) star-schema data via SQL GENERATOR  (~90k message + order rows)
--   (2) a governed document corpus for grounded retrieval
--   (2b) a call-transcript corpus (24 synthetic calls) + several ingestion patterns
--   (3) the native SEMANTIC VIEW that defines every KPI once
--   (4) TWO Cortex Search services (marketing docs + call transcripts)
--   (5) a Cortex Agent that uses the semantic view (Analyst) AND both Search
--       services as tools, plus a RAG closer over the transcripts
--
-- POSITIONING (read aloud): the whole point of the semantic view is that a
-- metric like "attributed revenue" is defined ONCE, in the platform, and then
-- reused identically by Cortex Analyst, Cortex Agents, Cortex Search grounding,
-- raw SQL, and any BI tool (Omni, Tableau, Excel). No re-implementing the metric
-- in five places, no drift, no text-to-SQL guessing.
--
-- Prerequisites:
--   - A role that can CREATE DATABASE/WAREHOUSE and use Cortex (SYSADMIN works;
--     the role needs SNOWFLAKE.CORTEX_USER to build Search + run the Agent).
--   - Cortex Analyst, Cortex Search, and Cortex Agents available in your region
--     (enable cross-region inference if a model is not local:
--      ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';).
--   - The document corpus PDFs (shipped in lab/docs/) uploaded to the @SMS_DOCS
--     stage, AND the call transcripts (shipped in lab/transcripts/) uploaded to
--     the @CALL_TRANSCRIPTS_STAGE stage. Sections 3 and 3b create the stages;
--     upload with the PUT commands shown there (SnowSQL / `snow sql`) BEFORE the
--     parse/chunk steps, or use the Snowsight stage file-upload button. The parse
--     and COPY steps read whatever files are on the stages.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE, SCHEMA, WAREHOUSE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS SMS_MARKETING_DEMO;
USE DATABASE SMS_MARKETING_DEMO;
CREATE SCHEMA IF NOT EXISTS CORE;
USE SCHEMA CORE;

CREATE WAREHOUSE IF NOT EXISTS SMS_MARKETING_WH
  WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND = 120
  AUTO_RESUME = TRUE;

USE WAREHOUSE SMS_MARKETING_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. STRUCTURED SAMPLE DATA (star schema via SQL GENERATOR)
-- ─────────────────────────────────────────────────────────────────────────────
-- Grain:
--   DIM_BRAND       one row per store on the platform
--   DIM_SUBSCRIBER  one row per opted-in shopper (belongs to a brand)
--   DIM_CAMPAIGN    one row per campaign (broadcast or automated flow)
--   FACT_MESSAGE    one row per message sent to a subscriber for a campaign
--   FACT_ORDER      one row per store order, attributed to the campaign that
--                   drove it (Shopify-style last-touch attribution)
-- Window: last 18 months. Region codes NE/SE/MW/SW/W slice the subscriber base
-- in the semantic view (e.g. opt-in growth or consent rate by region).

-- ---- DIM_BRAND ---------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_BRAND AS
SELECT
    seq4() + 1                                                        AS brand_id,
    'brand_' || LPAD(seq4() + 1, 3, '0')                             AS store_name,
    ARRAY_CONSTRUCT('Starter','Growth','Pro','Enterprise')[UNIFORM(0, 3, RANDOM())]::STRING  AS plan_tier,
    ARRAY_CONSTRUCT('Apparel','Beauty','Food & Beverage','Home','Electronics')[UNIFORM(0, 4, RANDOM())]::STRING AS industry
FROM TABLE(GENERATOR(ROWCOUNT => 40));

-- ---- DIM_SUBSCRIBER ----------------------------------------------------------
-- ~12k subscribers. opt_in_date spread across the last 18 months so opt-in
-- growth trends are visible. consent_status is mostly opted_in, with a realistic
-- slice of opted_out (list churn) and pending (double opt-in not yet confirmed).
CREATE OR REPLACE TABLE DIM_SUBSCRIBER AS
SELECT
    seq4() + 1                                                        AS subscriber_id,
    UNIFORM(1, 40, RANDOM())                                         AS brand_id,
    DATEADD('day', -1 * UNIFORM(0, 545, RANDOM()), CURRENT_DATE())   AS opt_in_date,
    ARRAY_CONSTRUCT('JOIN','SAVE','VIP','SALE','DEALS','LOYAL')[UNIFORM(0, 5, RANDOM())]::STRING AS opt_in_keyword,
    ARRAY_CONSTRUCT('SMS','SMS','SMS','MMS')[UNIFORM(0, 3, RANDOM())]::STRING  AS channel,   -- ~75% SMS
    ARRAY_CONSTRUCT('NE','SE','MW','SW','W')[UNIFORM(0, 4, RANDOM())]::STRING  AS region,
    -- ~82% opted_in, ~11% opted_out (churn), ~7% pending
    CASE
        WHEN UNIFORM(1, 100, RANDOM()) <= 82 THEN 'opted_in'
        WHEN UNIFORM(1, 100, RANDOM()) <= 62 THEN 'opted_out'
        ELSE 'pending'
    END                                                              AS consent_status
FROM TABLE(GENERATOR(ROWCOUNT => 12000));

-- ---- DIM_CAMPAIGN ------------------------------------------------------------
-- 600 campaigns. campaign_type is deterministic by id (ids 1-270 = broadcast,
-- 271-600 = flow, ~45/55) so the fact generators below can realistically bias
-- volume and conversion by type. Themes are correlated with type: flows skew
-- Welcome/Abandoned Cart/Winback; broadcasts skew Product Launch/Sale/Back in Stock.
CREATE OR REPLACE TABLE DIM_CAMPAIGN AS
WITH base AS (
  SELECT seq4() + 1                                                  AS campaign_id,
         UNIFORM(1, 40, RANDOM())                                    AS brand_id,
         DATEADD('day', -1 * UNIFORM(0, 540, RANDOM()), CURRENT_DATE()) AS send_date,
         ARRAY_CONSTRUCT('JOIN','SAVE','VIP','SALE','DEALS','LOYAL')[UNIFORM(0, 5, RANDOM())]::STRING AS keyword
  FROM TABLE(GENERATOR(ROWCOUNT => 600))
)
SELECT campaign_id, brand_id,
  IFF(campaign_id <= 270, 'broadcast', 'flow')                       AS campaign_type,
  keyword, send_date,
  CASE WHEN campaign_id <= 270
       THEN ARRAY_CONSTRUCT('Product Launch','Seasonal Sale','Back in Stock')[UNIFORM(0, 2, RANDOM())]::STRING
       ELSE ARRAY_CONSTRUCT('Welcome','Abandoned Cart','Winback')[UNIFORM(0, 2, RANDOM())]::STRING
  END                                                                AS theme
FROM base;

-- ---- FACT_MESSAGE ------------------------------------------------------------
-- ~70k sends. delivered ~96%. Broadcasts blast high volume: ~70% of sends go to
-- broadcast campaigns (ids 1-270). Clicked is conditional on delivered and skews
-- higher for flows (triggered, high-intent: ~14% vs ~7% for broadcasts). cost per
-- send is a few tenths of a cent to a couple cents.
CREATE OR REPLACE TABLE FACT_MESSAGE AS
WITH base AS (
  SELECT seq4() + 1                                                  AS message_id,
    (CASE WHEN UNIFORM(1, 100, RANDOM()) <= 70 THEN UNIFORM(1, 270, RANDOM()) ELSE UNIFORM(271, 600, RANDOM()) END) AS campaign_id,
    UNIFORM(1, 12000, RANDOM())                                      AS subscriber_id,
    DATEADD('minute', -1 * UNIFORM(0, 777600, RANDOM()), CURRENT_TIMESTAMP()) AS sent_ts,
    UNIFORM(1, 100, RANDOM()) <= 96                                  AS delivered,
    ROUND(UNIFORM(30, 250, RANDOM()) / 10000.0, 4)                   AS cost      -- $0.0030 – $0.0250
  FROM TABLE(GENERATOR(ROWCOUNT => 70000))
)
SELECT message_id, campaign_id, subscriber_id, sent_ts, delivered,
  delivered AND IFF(campaign_id <= 270, UNIFORM(1, 100, RANDOM()) <= 7, UNIFORM(1, 100, RANDOM()) <= 14) AS clicked,
  cost
FROM base;

-- ---- FACT_ORDER --------------------------------------------------------------
-- ~20k orders attributed (last-touch) to a campaign. Flows convert far better
-- relative to their send volume: ~60% of orders are attributed to flow campaigns
-- (ids 271-600), and flow orders carry a slightly higher basket (+15%). Combined
-- with the send skew above, this makes flow revenue-per-send >> broadcast.
CREATE OR REPLACE TABLE FACT_ORDER AS
WITH base AS (
  SELECT seq4() + 1                                                  AS order_id,
    UNIFORM(1, 12000, RANDOM())                                      AS subscriber_id,
    (CASE WHEN UNIFORM(1, 100, RANDOM()) <= 60 THEN UNIFORM(271, 600, RANDOM()) ELSE UNIFORM(1, 270, RANDOM()) END) AS attributed_campaign_id,
    DATEADD('minute', -1 * UNIFORM(0, 777600, RANDOM()), CURRENT_TIMESTAMP()) AS order_ts
  FROM TABLE(GENERATOR(ROWCOUNT => 20000))
)
SELECT order_id, subscriber_id, attributed_campaign_id, order_ts,
  ROUND((15 + ABS(NORMAL(0, 1, RANDOM())) * 95) * IFF(attributed_campaign_id > 270, 1.15, 1.0), 2) AS revenue
FROM base;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. GOVERNED DOCUMENT CORPUS (for Cortex Search grounding)
-- ─────────────────────────────────────────────────────────────────────────────
-- The Search service is grounded on a corpus of REAL operational marketing PDFs
-- (brand "Juniper & Coast" on the RelayFox SMS platform): campaign briefs, the
-- SMS/MMS copy library, TCPA/consent guidelines, deliverability best practices,
-- a segmentation playbook, support macros, a quarterly performance review, an
-- attribution-methodology whitepaper, and an incident postmortem.
--
-- The PDFs ship with this demo in lab/docs/. We land them on an internal stage
-- and parse them with SNOWFLAKE.CORTEX.PARSE_DOCUMENT, then index the parsed
-- text with Cortex Search. doc_type is inferred from the filename so the Search
-- service (and the agent) can filter by document type.

-- Internal stage for the PDFs.
CREATE STAGE IF NOT EXISTS SMS_DOCS
  DIRECTORY = (ENABLE = TRUE)
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

-- Upload the shipped PDFs, then make them visible to DIRECTORY().
-- Run this PUT from SnowSQL or the Snowflake CLI (`snow sql`) — PUT is a
-- client-side command and needs local file access. Adjust the path to wherever
-- you cloned the repo. The Snowsight worksheet UI cannot run PUT; use its file
-- upload button on the SMS_DOCS stage instead, then run the ALTER STAGE REFRESH.
--   PUT 'file://<repo>/sms-marketing-ai/lab/docs/*.pdf'
--       @SMS_MARKETING_DEMO.CORE.SMS_DOCS AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
ALTER STAGE SMS_DOCS REFRESH;

-- Parse every PDF and classify it by filename. Titles are prettified from the
-- filename for clean citations. region is 'ALL' (none of these docs are
-- region-specific); tag per file here if you have region-scoped documents.
CREATE OR REPLACE TABLE SMS_DOC_CHUNKS AS
SELECT
    ROW_NUMBER() OVER (ORDER BY RELATIVE_PATH)                            AS doc_id,
    INITCAP(REPLACE(REGEXP_REPLACE(RELATIVE_PATH, '^[0-9]+_|\\.pdf$', ''), '_', ' ')) AS title,
    CASE
      WHEN RELATIVE_PATH ILIKE '%campaign_brief%'     THEN 'campaign_brief'
      WHEN RELATIVE_PATH ILIKE '%copy_library%'       THEN 'copy_library'
      WHEN RELATIVE_PATH ILIKE '%tcpa%'               THEN 'tcpa_consent'
      WHEN RELATIVE_PATH ILIKE '%deliverability%'     THEN 'deliverability'
      WHEN RELATIVE_PATH ILIKE '%segmentation%'       THEN 'segmentation'
      WHEN RELATIVE_PATH ILIKE '%support_macro%'      THEN 'support_macro'
      WHEN RELATIVE_PATH ILIKE '%performance_review%' THEN 'performance_review'
      WHEN RELATIVE_PATH ILIKE '%attribution%'        THEN 'attribution'
      WHEN RELATIVE_PATH ILIKE '%postmortem%'         THEN 'postmortem'
      ELSE 'other'
    END                                                                  AS doc_type,
    'ALL'                                                                AS region,
    TO_VARCHAR(
      SNOWFLAKE.CORTEX.PARSE_DOCUMENT(
        @SMS_DOCS, RELATIVE_PATH, {'mode':'LAYOUT'}
      ):content
    )                                                                    AS text
FROM DIRECTORY(@SMS_DOCS);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3b. CALL TRANSCRIPTS — the second Search corpus + ingestion patterns
-- ─────────────────────────────────────────────────────────────────────────────
-- A corpus of 24 synthetic customer call transcripts (10 support, 8 sales,
-- 6 compliance) for the RelayFox SMS platform, shipped in lab/transcripts/.
-- Transcripts are the HARDEST corpus for keyword search — multi-speaker,
-- conversational, timestamped — which is exactly where Cortex Search's hybrid
-- vector + keyword retrieval wins. We land them, chunk them (preserving dialogue
-- turns), and index them with a second Cortex Search service.
--
-- This section deliberately shows SEVERAL INGESTION PATTERNS so the demo can
-- narrate the trade-offs:
--   Pattern A  chunk DIRECTLY off the stage (no landing table)      — runnable
--   Pattern B  COPY INTO a durable raw table, then chunk (ELT)      — runnable, PROD path
--   Pattern C  Snowpipe auto-ingest / Snowpipe Streaming            — narrated DDL
-- Pattern B is the durable path the Search service is built on below.

-- Internal stage for the .txt transcripts + manifest.csv (directory table on).
CREATE STAGE IF NOT EXISTS CALL_TRANSCRIPTS_STAGE
  DIRECTORY = (ENABLE = TRUE)
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

-- Upload the shipped corpus, then make it visible to DIRECTORY().
-- PUT is a client-side command (SnowSQL / `snow sql`); the Snowsight worksheet
-- cannot run PUT — use the stage file-upload button there instead, then REFRESH.
--   PUT 'file://<repo>/sms-marketing-ai/lab/transcripts/*.txt'
--       @SMS_MARKETING_DEMO.CORE.CALL_TRANSCRIPTS_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
--   PUT 'file://<repo>/sms-marketing-ai/lab/transcripts/manifest.csv'
--       @SMS_MARKETING_DEMO.CORE.CALL_TRANSCRIPTS_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
ALTER STAGE CALL_TRANSCRIPTS_STAGE REFRESH;

-- File format that reads each transcript LINE as one field ($1). FIELD_DELIMITER
-- = NONE keeps commas inside a line intact; RECORD_DELIMITER = newline makes one
-- row per dialogue line. We reassemble whole transcripts with LISTAGG below.
CREATE OR REPLACE FILE FORMAT FF_TRANSCRIPT_LINES
  TYPE = CSV
  FIELD_DELIMITER = NONE
  RECORD_DELIMITER = '\n'
  FIELD_OPTIONALLY_ENCLOSED_BY = NONE
  ESCAPE_UNENCLOSED_FIELD = NONE
  SKIP_HEADER = 0;

-- ---- Call metadata (manifest.csv) --------------------------------------------
-- CALL_ID joins each transcript to its brand, date, and one-line summary.
CREATE OR REPLACE FILE FORMAT FF_MANIFEST_CSV
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  FIELD_DELIMITER = ','
  ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE;

CREATE OR REPLACE TABLE CALL_MANIFEST (
  call_id          STRING,
  call_date        DATE,
  call_type_detail STRING,   -- granular type from the manifest, e.g. "Customer Support - Deliverability"
  brand            STRING,
  summary          STRING
);

COPY INTO CALL_MANIFEST (call_id, call_date, call_type_detail, brand, summary)
  FROM @CALL_TRANSCRIPTS_STAGE/manifest.csv
  FILE_FORMAT = (FORMAT_NAME = 'FF_MANIFEST_CSV')
  ON_ERROR = ABORT_STATEMENT;

-- ---- Pattern A — chunk DIRECTLY off the stage (no landing table) -------------
-- Reassemble + chunk staged files in a single query. Nothing is persisted; this
-- is handy for exploration or when the stage IS your system of record. Run it to
-- see the chunk shape without materializing anything.
SELECT
    REGEXP_SUBSTR(f.transcript_text, 'CALL_ID:\\s*(\\S+)', 1, 1, 'e', 1) AS call_id,
    c.index                                                             AS chunk_index,
    c.value::STRING                                                     AS chunk_text
FROM (
    SELECT REGEXP_REPLACE(METADATA$FILENAME, '^.*/', '')                          AS file_name,
           LISTAGG($1, '\n') WITHIN GROUP (ORDER BY METADATA$FILE_ROW_NUMBER)     AS transcript_text
    FROM @CALL_TRANSCRIPTS_STAGE (FILE_FORMAT => 'FF_TRANSCRIPT_LINES',
                                  PATTERN => '.*transcript_.*[.]txt')
    GROUP BY file_name
) f,
LATERAL FLATTEN(input => SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(f.transcript_text, 'none', 1200, 200)) c
LIMIT 10;

-- ---- Pattern B — COPY INTO a durable raw table (ELT), the production path ----
-- Bulk-load every line into a landing table (one row per line, carrying the
-- source filename + line number from COPY metadata), then reassemble each file
-- into one transcript with LISTAGG. This is the durable, re-queryable pattern
-- most pipelines use, and it is what the chunk table + Search service build on.
CREATE OR REPLACE TABLE CALL_TRANSCRIPTS_RAW_LINES (
  file_name STRING,
  row_num   NUMBER,
  line      STRING
);

COPY INTO CALL_TRANSCRIPTS_RAW_LINES (file_name, row_num, line)
  FROM (
    SELECT REGEXP_REPLACE(METADATA$FILENAME, '^.*/', ''),
           METADATA$FILE_ROW_NUMBER,
           $1
    FROM @CALL_TRANSCRIPTS_STAGE
  )
  FILE_FORMAT = (FORMAT_NAME = 'FF_TRANSCRIPT_LINES')
  PATTERN = '.*transcript_.*[.]txt'
  ON_ERROR = ABORT_STATEMENT;

-- One row per transcript: reassemble text, extract CALL_ID from the header, and
-- derive a coarse call_type from the CALL_ID prefix (CS=support, SD/SE=sales,
-- CE=compliance) for a clean Search attribute.
CREATE OR REPLACE TABLE CALL_TRANSCRIPTS_RAW AS
WITH files AS (
  SELECT file_name,
         LISTAGG(line, '\n') WITHIN GROUP (ORDER BY row_num) AS transcript_text
  FROM CALL_TRANSCRIPTS_RAW_LINES
  GROUP BY file_name
)
SELECT
    REGEXP_SUBSTR(transcript_text, 'CALL_ID:\\s*(\\S+)', 1, 1, 'e', 1) AS call_id,
    file_name,
    CASE LEFT(REGEXP_SUBSTR(transcript_text, 'CALL_ID:\\s*(\\S+)', 1, 1, 'e', 1), 2)
        WHEN 'CS' THEN 'support'
        WHEN 'SD' THEN 'sales'
        WHEN 'SE' THEN 'sales'
        WHEN 'CE' THEN 'compliance'
        ELSE 'other'
    END                                                                AS call_type,
    transcript_text
FROM files;

-- ---- Pattern C — Snowpipe (continuous ingestion) — NARRATED, not run ---------
-- When transcripts land continuously (e.g. a nightly export to cloud storage),
-- swap the one-time COPY for a Snowpipe that auto-ingests new files. On an
-- EXTERNAL stage (S3/GCS/Azure) with an event notification, this needs no task:
--
--   CREATE PIPE CALL_TRANSCRIPTS_PIPE
--     AUTO_INGEST = TRUE
--   AS
--     COPY INTO CALL_TRANSCRIPTS_RAW_LINES (file_name, row_num, line)
--     FROM (SELECT METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, $1
--           FROM @MY_EXTERNAL_TRANSCRIPTS_STAGE)
--     FILE_FORMAT = (FORMAT_NAME = 'FF_TRANSCRIPT_LINES')
--     PATTERN = '.*transcript_.*[.]txt';
--   -- then wire the pipe's notification channel (SYSTEM$PIPE_STATUS) to the
--   -- bucket's event notifications; new files flow in within ~a minute.
--
-- For true real-time (row-level, sub-second) ingestion of live call events,
-- use Snowpipe Streaming: rows are appended via the SDK straight into the
-- landing table with no files or COPY at all. A downstream Dynamic Table or
-- Task then keeps TRANSCRIPT_CHUNKS fresh, and the Search service's TARGET_LAG
-- pulls the new chunks into the index automatically.

-- ---- Chunk into TRANSCRIPT_CHUNKS (join manifest for brand/date/summary) -----
-- SPLIT_TEXT_RECURSIVE_CHARACTER keeps dialogue turns together (~1200 chars,
-- 200 overlap). The manifest join is 1:1 on call_id (brand/date/summary as
-- filterable attributes); LATERAL FLATTEN is the intended one-transcript-to-many
-- -chunks expansion.
CREATE OR REPLACE TABLE TRANSCRIPT_CHUNKS AS
WITH chunked AS (
  SELECT
      r.call_id,
      r.call_type,
      m.brand,
      m.call_date,
      m.summary,
      c.index          AS chunk_index,
      c.value::STRING  AS chunk_text
  FROM CALL_TRANSCRIPTS_RAW r
  LEFT JOIN CALL_MANIFEST m ON r.call_id = m.call_id,
  LATERAL FLATTEN(input => SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(r.transcript_text, 'none', 1200, 200)) c
)
SELECT
    ROW_NUMBER() OVER (ORDER BY call_id, chunk_index) AS chunk_id,
    call_id,
    call_type,
    brand,
    call_date,
    summary,
    chunk_index,
    chunk_text
FROM chunked;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. SEMANTIC VIEW — the centerpiece: define every KPI ONCE
-- ─────────────────────────────────────────────────────────────────────────────
-- This native, governed object is the single source of truth for the business
-- metrics. Cortex Analyst, Cortex Agents, raw SQL, and BI tools all read the
-- SAME definitions here — "attributed revenue" means one thing everywhere.
--
-- It defines: 5 logical tables, 6 relationships, dimensions (region, channel,
-- campaign_type, plan tier, industry, theme, months), table-scoped metrics, and
-- derived metrics (revenue_per_send, ctr, subscriber_ltv, list_churn_rate,
-- consent_rate) that combine facts across tables — plus synonyms, sample values,
-- and verified queries that raise Cortex Analyst accuracy.

CREATE OR REPLACE SEMANTIC VIEW SMS_MARKETING_SV

  TABLES (
    brands AS DIM_BRAND
      PRIMARY KEY (brand_id)
      WITH SYNONYMS ('stores', 'merchants', 'accounts')
      COMMENT = 'E-commerce brands (stores) on the SMS marketing platform',
    subscribers AS DIM_SUBSCRIBER
      PRIMARY KEY (subscriber_id)
      WITH SYNONYMS ('contacts', 'members', 'shoppers', 'list members')
      COMMENT = 'Opted-in shoppers on a brand''s marketing list',
    campaigns AS DIM_CAMPAIGN
      PRIMARY KEY (campaign_id)
      WITH SYNONYMS ('sends', 'blasts', 'flows', 'automations')
      COMMENT = 'Broadcast blasts and automated flow campaigns',
    messages AS FACT_MESSAGE
      PRIMARY KEY (message_id)
      WITH SYNONYMS ('texts', 'sends', 'deliveries')
      COMMENT = 'One row per SMS/MMS message sent to a subscriber',
    orders AS FACT_ORDER
      PRIMARY KEY (order_id)
      WITH SYNONYMS ('purchases', 'transactions', 'sales')
      COMMENT = 'Store orders, last-touch attributed to the campaign that drove them'
  )

  RELATIONSHIPS (
    subscribers_to_brands AS
      subscribers (brand_id) REFERENCES brands,
    campaigns_to_brands AS
      campaigns (brand_id) REFERENCES brands,
    messages_to_campaigns AS
      messages (campaign_id) REFERENCES campaigns,
    messages_to_subscribers AS
      messages (subscriber_id) REFERENCES subscribers,
    orders_to_subscribers AS
      orders (subscriber_id) REFERENCES subscribers,
    orders_to_campaigns AS
      orders (attributed_campaign_id) REFERENCES campaigns
  )

  FACTS (
    messages.delivered_flag AS IFF(delivered, 1, 0)
      COMMENT = 'Row-level helper: 1 if the message was delivered',
    messages.clicked_flag AS IFF(clicked, 1, 0)
      COMMENT = 'Row-level helper: 1 if the delivered message was clicked',
    messages.send_cost AS cost
      COMMENT = 'Carrier cost of the individual send, in USD',
    subscribers.is_opted_in AS IFF(consent_status = 'opted_in', 1, 0)
      COMMENT = 'Row-level helper: 1 if the subscriber is opted in',
    subscribers.is_opted_out AS IFF(consent_status = 'opted_out', 1, 0)
      COMMENT = 'Row-level helper: 1 if the subscriber has opted out (churned)',
    orders.order_revenue AS revenue
      COMMENT = 'Revenue of the individual attributed order, in USD'
  )

  DIMENSIONS (
    brands.plan_tier AS plan_tier
      WITH SYNONYMS = ('plan', 'tier', 'subscription plan')
      COMMENT = 'Brand subscription plan on the platform'
      SAMPLE_VALUES ('Starter', 'Growth', 'Pro', 'Enterprise') IS_ENUM,
    brands.industry AS industry
      WITH SYNONYMS = ('vertical', 'category')
      COMMENT = 'Brand industry vertical'
      SAMPLE_VALUES ('Apparel', 'Beauty', 'Food & Beverage', 'Home', 'Electronics') IS_ENUM,
    subscribers.region AS region
      WITH SYNONYMS = ('geo', 'area', 'territory')
      COMMENT = 'Subscriber region: NE=Northeast, SE=Southeast, MW=Midwest, SW=Southwest, W=West'
      SAMPLE_VALUES ('NE', 'SE', 'MW', 'SW', 'W') IS_ENUM,
    subscribers.channel AS channel
      WITH SYNONYMS = ('message type', 'sms or mms')
      COMMENT = 'Preferred messaging channel for the subscriber'
      SAMPLE_VALUES ('SMS', 'MMS') IS_ENUM,
    subscribers.consent_status AS consent_status
      WITH SYNONYMS = ('opt-in status', 'consent')
      COMMENT = 'Consent state: opted_in (marketable), opted_out (churned), pending (unconfirmed)'
      SAMPLE_VALUES ('opted_in', 'opted_out', 'pending') IS_ENUM,
    subscribers.opt_in_keyword AS opt_in_keyword
      WITH SYNONYMS = ('join keyword', 'signup keyword')
      COMMENT = 'Keyword the subscriber texted to opt in',
    subscribers.opt_in_date AS opt_in_date
      COMMENT = 'Date the subscriber opted in',
    subscribers.opt_in_month AS DATE_TRUNC('month', opt_in_date)
      WITH SYNONYMS = ('signup month', 'join month')
      COMMENT = 'Month the subscriber opted in (for opt-in growth trends)',
    campaigns.campaign_type AS campaign_type
      WITH SYNONYMS = ('send type', 'broadcast or flow', 'automation type')
      COMMENT = 'broadcast = one-time blast; flow = automated triggered message'
      SAMPLE_VALUES ('broadcast', 'flow') IS_ENUM,
    campaigns.theme AS theme
      WITH SYNONYMS = ('campaign theme', 'use case')
      COMMENT = 'Campaign theme / use case'
      SAMPLE_VALUES ('Welcome', 'Abandoned Cart', 'Winback', 'Product Launch', 'Seasonal Sale', 'Back in Stock') IS_ENUM,
    campaigns.campaign_keyword AS keyword
      COMMENT = 'Keyword associated with the campaign',
    campaigns.send_date AS send_date
      COMMENT = 'Date the campaign was sent',
    campaigns.send_month AS DATE_TRUNC('month', send_date)
      WITH SYNONYMS = ('campaign month')
      COMMENT = 'Month the campaign was sent',
    orders.order_date AS TO_DATE(order_ts)
      COMMENT = 'Date of the attributed order',
    orders.order_month AS DATE_TRUNC('month', order_ts)
      WITH SYNONYMS = ('revenue month', 'sales month')
      COMMENT = 'Month of the attributed order (for revenue trends)'
  )

  METRICS (
    -- Base table-scoped metrics
    orders.attributed_revenue AS SUM(orders.order_revenue)
      WITH SYNONYMS = ('revenue', 'attributed sales', 'sales driven', 'campaign revenue')
      COMMENT = 'Total store revenue attributed (last-touch) to campaigns, in USD',
    orders.order_count AS COUNT(orders.order_id)
      WITH SYNONYMS = ('orders', 'number of orders', 'purchases')
      COMMENT = 'Number of attributed orders',
    messages.send_count AS COUNT(messages.message_id)
      WITH SYNONYMS = ('sends', 'messages sent', 'volume')
      COMMENT = 'Number of messages sent',
    messages.delivered_count AS SUM(messages.delivered_flag)
      COMMENT = 'Number of messages delivered',
    messages.click_count AS SUM(messages.clicked_flag)
      WITH SYNONYMS = ('clicks')
      COMMENT = 'Number of clicks on delivered messages',
    messages.total_send_cost AS SUM(messages.send_cost)
      WITH SYNONYMS = ('messaging cost', 'send spend')
      COMMENT = 'Total carrier cost of sends, in USD',
    subscribers.subscriber_count AS COUNT(subscribers.subscriber_id)
      WITH SYNONYMS = ('subscribers', 'list size', 'contacts')
      COMMENT = 'Number of subscribers',
    subscribers.opt_in_growth AS COUNT(subscribers.subscriber_id)
      WITH SYNONYMS = ('new opt-ins', 'list growth', 'new subscribers', 'signups')
      COMMENT = 'New opt-ins; group by opt_in_month or region to see opt-in growth',
    subscribers.opted_out_count AS SUM(subscribers.is_opted_out)
      WITH SYNONYMS = ('churned subscribers', 'unsubscribes')
      COMMENT = 'Number of subscribers who have opted out (churned)',
    subscribers.consented_count AS SUM(subscribers.is_opted_in)
      COMMENT = 'Number of subscribers currently opted in',

    -- Derived (view-scoped) metrics: defined ONCE, referencing the base metrics
    -- above so they compose across logical tables (Analyst, Agent, BI all reuse).
    revenue_per_send AS DIV0(orders.attributed_revenue, messages.send_count)
      WITH SYNONYMS = ('rps', 'revenue per message', 'rev per send')
      COMMENT = 'Attributed revenue divided by number of sends (USD per send) — flows usually beat broadcasts',
    ctr AS DIV0(messages.click_count, messages.delivered_count)
      WITH SYNONYMS = ('click-through rate', 'click rate')
      COMMENT = 'Clicks divided by delivered messages',
    subscriber_ltv AS DIV0(orders.attributed_revenue, subscribers.subscriber_count)
      WITH SYNONYMS = ('lifetime value', 'ltv', 'value per subscriber')
      COMMENT = 'Attributed revenue per subscriber, in USD',
    list_churn_rate AS DIV0(subscribers.opted_out_count, subscribers.subscriber_count)
      WITH SYNONYMS = ('churn rate', 'opt-out rate', 'unsubscribe rate')
      COMMENT = 'Share of subscribers who have opted out (0-1)',
    consent_rate AS DIV0(subscribers.consented_count, subscribers.subscriber_count)
      WITH SYNONYMS = ('opt-in rate', 'consent percentage')
      COMMENT = 'Share of subscribers currently opted in (0-1)'
  )

  COMMENT = 'AI-BI single source of truth for the SMS/MMS marketing platform: brands, subscribers, campaigns, messages, and attributed orders, with governed KPIs (attributed revenue, revenue per send, CTR, opt-in growth, subscriber LTV, list churn, consent rate).'

  AI_VERIFIED_QUERIES (
    attributed_revenue_by_type AS (
      QUESTION 'What is the attributed revenue by campaign type?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT * FROM SEMANTIC_VIEW(SMS_MARKETING_SV
             DIMENSIONS campaigns.campaign_type
             METRICS orders.attributed_revenue)
           ORDER BY attributed_revenue DESC'
    ),
    rps_flow_vs_broadcast AS (
      QUESTION 'How does revenue per send compare for flows versus broadcasts?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT * FROM SEMANTIC_VIEW(SMS_MARKETING_SV
             DIMENSIONS campaigns.campaign_type
             METRICS revenue_per_send)
           ORDER BY revenue_per_send DESC'
    ),
    opt_in_growth_by_region AS (
      QUESTION 'Which region has the fastest opt-in growth?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT * FROM SEMANTIC_VIEW(SMS_MARKETING_SV
             DIMENSIONS subscribers.region
             METRICS subscribers.opt_in_growth)
           ORDER BY opt_in_growth DESC'
    ),
    consent_rate_by_region AS (
      QUESTION 'What is the consent rate and list churn rate by region?'
      SQL 'SELECT * FROM SEMANTIC_VIEW(SMS_MARKETING_SV
             DIMENSIONS subscribers.region
             METRICS consent_rate, list_churn_rate)
           ORDER BY consent_rate DESC'
    ),
    ctr_by_theme AS (
      QUESTION 'What is the click-through rate by campaign theme?'
      SQL 'SELECT * FROM SEMANTIC_VIEW(SMS_MARKETING_SV
             DIMENSIONS campaigns.theme
             METRICS ctr)
           ORDER BY ctr DESC'
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. CORTEX SEARCH SERVICE — grounded, cited retrieval over the doc corpus
-- ─────────────────────────────────────────────────────────────────────────────
-- Semantic search over the operational marketing documents. The agent uses this
-- for "how / why / what's the policy" questions that live in text, not in the
-- star schema. Filterable attributes let the agent scope by doc_type or region.

CREATE OR REPLACE CORTEX SEARCH SERVICE SMS_DOCS_SEARCH
  ON text
  ATTRIBUTES doc_type, region
  WAREHOUSE = SMS_MARKETING_WH
  TARGET_LAG = '1 hour'
  EMBEDDING_MODEL = 'snowflake-arctic-embed-l-v2.0'
  COMMENT = 'Search over SMS marketing briefs, copy library, TCPA/consent, deliverability, and support macros'
AS (
  SELECT
      doc_id,
      title,
      doc_type,
      region,
      text
  FROM SMS_DOC_CHUNKS
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 5b. CORTEX SEARCH SERVICE — call transcripts (voice of the customer)
-- ─────────────────────────────────────────────────────────────────────────────
-- The second Search service, over the chunked call transcripts. Attributes let
-- the agent scope retrieval to "compliance calls only", a specific brand, or a
-- date range without re-indexing. This is the "what did the customer actually
-- SAY on the call" corpus — complementary to SMS_DOCS_SEARCH (policy/playbook).
CREATE OR REPLACE CORTEX SEARCH SERVICE CALL_TRANSCRIPTS_SEARCH
  ON chunk_text
  ATTRIBUTES call_type, brand, call_date
  WAREHOUSE = SMS_MARKETING_WH
  TARGET_LAG = '1 hour'
  EMBEDDING_MODEL = 'snowflake-arctic-embed-l-v2.0'
  COMMENT = 'Hybrid search over synthetic customer call transcripts (support, sales, compliance) for the SMS marketing platform'
AS (
  SELECT
      chunk_id,
      call_id,
      call_type,
      brand,
      call_date,
      summary,
      chunk_text
  FROM TRANSCRIPT_CHUNKS
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. CORTEX AGENT — semantic view (via Analyst) + Cortex Search as tools
-- ─────────────────────────────────────────────────────────────────────────────
-- The agent blends structured analytics (governed by the semantic view) with
-- grounded document retrieval. Ask it a business question and it routes: metrics
-- to the Analyst tool (which reads SMS_MARKETING_SV), policy/brief questions to
-- the Search tool.
--
-- This spec is already OPTIMIZED per the agent best practices (tool descriptions
-- are the highest-leverage factor): each tool has a clear name, coverage,
-- when-to-use / when-NOT-to-use boundaries; orchestration and response
-- instructions are separated; sample questions seed the UI. The lab notebook
-- (Section 7) walks the before→after by first building a deliberately weak
-- baseline agent, then deploying this optimized version.

CREATE OR REPLACE AGENT SMS_MARKETING_AGENT
  COMMENT = 'AI-BI assistant for the SMS/MMS marketing platform (optimized per agent best practices)'
  PROFILE = '{"display_name": "SMS Marketing Analyst", "color": "blue"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto

instructions:
  response: |
    - Lead with the direct answer, then supporting detail. Be concise — marketers are busy.
    - Report currency as USD (e.g. $59.29) and rates as percentages (e.g. 13.5%).
    - Use a table for multi-row results (more than 3 rows); state single values inline.
    - When you use a document, cite it by its title.
    - If a metric is unavailable or the question is out of scope, say so and suggest the closest available metric.
  orchestration: |
    Role: You are the SMS Marketing Analyst for an SMS/MMS marketing platform used by e-commerce brands. Users are marketing managers and analysts asking about campaign performance, list health, and playbook guidance.
    Domain context:
    - Campaign types: "broadcast" (one-time blast) and "flow" (automated, triggered: welcome, abandoned-cart, winback). Flows fire at high intent and usually earn far more revenue per send than broadcasts.
    - consent_status: opted_in (marketable), opted_out (churned), pending (double opt-in unconfirmed). Consent rate = opted_in / total; list churn rate = opted_out / total.
    - Revenue is last-touch attributed from store orders back to the send that drove them. Regions are NE, SE, MW, SW, W.
    Tool selection:
    - Use Marketing_KPI_Analyst for any question about numbers, rates, trends, rankings, or comparisons of metrics (attributed revenue, revenue per send, CTR, opt-in growth, subscriber LTV, list churn, consent rate) sliced by region, channel, campaign type, theme, plan tier, industry, or month.
    - Use Marketing_Playbook_Search for how / why / policy / copy questions answered by our own documents (campaign briefs, copy library, TCPA/consent, deliverability, segmentation playbook, support macros, quarterly performance review, attribution whitepaper, incident postmortem).
    - Use Call_Transcript_Search for the voice of the CUSTOMER: what was said on a specific support, sales, or compliance call — objections, complaints, root-cause discussions, promises made, or which brand/call raised an issue. Scope with its filters (call_type = support/sales/compliance, brand, call_date) when the user names one.
    - For blended "what happened and why" questions, get the number from Marketing_KPI_Analyst, our policy/brief from Marketing_Playbook_Search, and what the customer actually said from Call_Transcript_Search, then combine them.
    - Distinguish the two Search corpora: Marketing_Playbook_Search = OUR internal policy/playbook documents; Call_Transcript_Search = transcripts of CALLS with customers. "What's our policy" -> Playbook; "what did the customer say / what happened on the call" -> Transcripts.
    Business rules:
    - Do not conflate historical aggregates (semantic view) with predictions — this agent does not forecast.
    - If the time range is ambiguous, default to the last 12 months and say so.
    - Only reference metrics defined in the semantic view; never invent a metric.
  sample_questions:
    - question: "What is attributed revenue by campaign type, and how does revenue per send compare between flows and broadcasts?"
    - question: "Which region has the fastest opt-in growth, and what is its consent rate and list churn?"
    - question: "Attributed revenue for the Q3 flash sale came in below plan — what does the incident postmortem say caused the PNW throughput issue, and which campaign brief covered that send?"
    - question: "What does our playbook say about TCPA consent and quiet hours before a broadcast?"
    - question: "Trace the brand that had a 10DLC campaign suspension across its support and compliance calls — what did the customer say, and what was the remediation?"

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "Marketing_KPI_Analyst"
      description: |
        Governed marketing KPIs from the SMS_MARKETING_SV semantic view (text-to-SQL over a star schema).
        Data coverage: brands, subscribers, campaigns, message sends, and last-touch attributed orders for roughly the last 18 months.
        Metrics: attributed_revenue, revenue_per_send, ctr, opt_in_growth, subscriber_ltv, list_churn_rate, consent_rate, plus counts (send_count, order_count, subscriber_count).
        Dimensions: region (NE/SE/MW/SW/W), channel (SMS/MMS), campaign_type (broadcast/flow), theme, plan_tier, industry, opt_in_month, send_month, order_month.
        When to use: questions about numbers, rates, trends, rankings, or comparisons of the metrics above.
        When NOT to use: how/why/policy questions, message copy, or TCPA/deliverability guidance (use Marketing_Playbook_Search); forecasting the future (not supported).
        Query tips: name the metric and the slice explicitly (e.g. "revenue per send by campaign type"); use exact region codes; give a month range for trends.
  - tool_spec:
      type: "cortex_search"
      name: "Marketing_Playbook_Search"
      description: |
        Semantic search over the marketing playbook and policy corpus (real PDFs for brand "Juniper & Coast"): campaign briefs, the SMS/MMS copy library, TCPA/consent guidelines, deliverability best practices, a segmentation playbook, support macros, a quarterly performance review, an attribution-methodology whitepaper, and an incident postmortem.
        When to use: "how", "why", "what's the policy", "what should the copy say", "which brief", "what happened in the incident/postmortem", or "what did the quarterly review say" questions; explanations that live in documents.
        When NOT to use: numeric/metric questions (use Marketing_KPI_Analyst).
        Filterable attributes: doc_type (campaign_brief, copy_library, tcpa_consent, deliverability, segmentation, support_macro, performance_review, attribution, postmortem) and region (currently ALL for every document). Cite results by their title.
  - tool_spec:
      type: "cortex_search"
      name: "Call_Transcript_Search"
      description: |
        Semantic search over 24 synthetic customer CALL TRANSCRIPTS on the SMS platform: 10 support, 8 sales, and 6 compliance calls, chunked to preserve dialogue turns.
        When to use: "what did the customer say", "what happened on the call", objections raised (e.g. vs a competitor), complaints, deliverability/10DLC/attribution root-cause discussions, consent/STOP/TCPA disputes, or tracing one brand's issue across multiple calls; the voice of the customer.
        When NOT to use: aggregate numbers/rates (use Marketing_KPI_Analyst); our own policy, copy, or playbook guidance (use Marketing_Playbook_Search).
        Filterable attributes: call_type (support, sales, compliance), brand (e.g. "Harbor & Pine Home", "LumaLeaf Beauty"), and call_date. Cite results by brand and call_id.
  - tool_spec:
      type: "data_to_chart"
      name: "data_to_chart"
      description: "Generates a chart from tabular results when a visualization helps a comparison, trend, or ranking."

tool_resources:
  Marketing_KPI_Analyst:
    semantic_view: "SMS_MARKETING_DEMO.CORE.SMS_MARKETING_SV"
    execution_environment:
      type: warehouse
      warehouse: "SMS_MARKETING_WH"
  Marketing_Playbook_Search:
    name: "SMS_MARKETING_DEMO.CORE.SMS_DOCS_SEARCH"
    max_results: "5"
    title_column: "title"
    id_column: "doc_id"
  Call_Transcript_Search:
    name: "SMS_MARKETING_DEMO.CORE.CALL_TRANSCRIPTS_SEARCH"
    max_results: "6"
    title_column: "call_id"
    id_column: "chunk_id"
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. VALIDATE — prove the metric is defined once and queryable everywhere
-- ─────────────────────────────────────────────────────────────────────────────
-- Attributed revenue by campaign type (the same metric the Agent + BI tools use):
SELECT * FROM SEMANTIC_VIEW(
    SMS_MARKETING_SV
    DIMENSIONS campaigns.campaign_type
    METRICS orders.attributed_revenue, revenue_per_send
) ORDER BY attributed_revenue DESC;

-- Consent + churn by region (subscriber regions NE/SE/MW/SW/W in the star schema):
SELECT * FROM SEMANTIC_VIEW(
    SMS_MARKETING_SV
    DIMENSIONS subscribers.region
    METRICS consent_rate, list_churn_rate, subscriber_count
) ORDER BY region;

-- Smoke-test the Search service against the real PDF corpus:
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'SMS_MARKETING_DEMO.CORE.SMS_DOCS_SEARCH',
    '{ "query": "what caused the PNW flash sale throughput incident", "columns": ["title","doc_type"], "limit": 3 }'
  )
)['results'] AS results;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7b. CALL-TRANSCRIPT SEARCH — demo queries (hybrid retrieval beats keyword)
-- ─────────────────────────────────────────────────────────────────────────────
-- Sanity: chunk + call counts (expect 24 calls; ~5-7 chunks each).
SELECT COUNT(DISTINCT call_id) AS calls, COUNT(*) AS chunks,
       COUNT(*) - COUNT(brand) AS chunks_missing_manifest   -- expect 0 (1:1 join)
FROM TRANSCRIPT_CHUNKS;

-- Q1 (support): deliverability / 10DLC throttling.
SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
  'SMS_MARKETING_DEMO.CORE.CALL_TRANSCRIPTS_SEARCH',
  '{ "query": "carrier filtering and 10DLC throttling causing a deliverability drop",
     "columns": ["call_id","brand","call_type","chunk_text"], "limit": 3 }'))['results'] AS results;

-- Q2 (support): attribution discrepancy vs Shopify revenue.
SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
  'SMS_MARKETING_DEMO.CORE.CALL_TRANSCRIPTS_SEARCH',
  '{ "query": "why does our revenue not match the Shopify report attribution window",
     "columns": ["call_id","brand","chunk_text"], "limit": 3 }'))['results'] AS results;

-- Q3 (compliance, ATTRIBUTE FILTER): TCPA consent / STOP handling on compliance calls only.
SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
  'SMS_MARKETING_DEMO.CORE.CALL_TRANSCRIPTS_SEARCH',
  '{ "query": "express written consent dispute and STOP opt-out handling",
     "columns": ["call_id","brand","call_type","chunk_text"],
     "filter": { "@eq": { "call_type": "compliance" } }, "limit": 3 }'))['results'] AS results;

-- Q4 (sales): competitor objections during discovery/expansion calls.
SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
  'SMS_MARKETING_DEMO.CORE.CALL_TRANSCRIPTS_SEARCH',
  '{ "query": "objections about migrating off a competing SMS platform, pricing and churn concerns",
     "columns": ["call_id","brand","call_type","chunk_text"],
     "filter": { "@eq": { "call_type": "sales" } }, "limit": 3 }'))['results'] AS results;

-- Q5 (cross-type, BRAND FILTER): trace the suspended-10DLC brand across its calls.
SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
  'SMS_MARKETING_DEMO.CORE.CALL_TRANSCRIPTS_SEARCH',
  '{ "query": "10DLC campaign suspension remediation and reinstatement",
     "columns": ["call_id","brand","call_type","chunk_text"],
     "filter": { "@eq": { "brand": "Harbor & Pine Home" } }, "limit": 4 }'))['results'] AS results;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7c. RAG CLOSER — retrieve top chunks, then AI_COMPLETE a cited answer
-- ─────────────────────────────────────────────────────────────────────────────
-- Grounded generation: pull the most relevant transcript chunks for a question,
-- feed them to AI_COMPLETE as context, and ask for a cited answer. No hallucination
-- on "what did the customer say?" — the model only sees retrieved evidence.
WITH hits AS (
  SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'SMS_MARKETING_DEMO.CORE.CALL_TRANSCRIPTS_SEARCH',
    '{ "query": "attribution discrepancy between our platform and Shopify revenue",
       "columns": ["call_id","brand","chunk_text"], "limit": 5 }'))['results'] AS results
),
context AS (
  SELECT LISTAGG(r.value:brand::STRING || ' [' || r.value:call_id::STRING || ']: '
                 || r.value:chunk_text::STRING, '\n---\n') AS ctx
  FROM hits, LATERAL FLATTEN(input => hits.results) r
)
SELECT SNOWFLAKE.CORTEX.AI_COMPLETE(
  'llama3.1-70b',
  'You are a support analyst. Using ONLY the call transcript excerpts below, explain what caused '
  || 'the attribution discrepancy between our platform and Shopify, and cite the brand and call_id '
  || 'for each point. If the excerpts do not answer it, say so.\n\nEXCERPTS:\n' || ctx
) AS grounded_answer
FROM context;

-- ─────────────────────────────────────────────────────────────────────────────
-- Setup complete.
--   1) You just ran this script (data + semantic view + search + agent).
--   2) Open lab/sms-marketing-ai-lab.ipynb to walk the AI-BI stack, or
--   3) Chat with SMS_MARKETING_AGENT in Snowsight → AI & ML → Agents.
-- ─────────────────────────────────────────────────────────────────────────────
