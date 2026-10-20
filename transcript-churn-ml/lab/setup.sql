-- =============================================================================
-- Call-transcript topics to churn: setup
-- =============================================================================
-- Scenario: a home-ownership engagement SaaS company that sells monthly homeowner
-- reports and lead alerts to loan officers and real-estate agents. Its sales and
-- success teams record their calls. Every row below is synthetic.
--
-- Creates: database TRANSCRIPT_CHURN_ML_DEMO (schemas RAW, CORE, ML, FEATURES,
-- ANALYTICS), warehouse TRANSCRIPT_CHURN_ML_WH, and the raw data:
--   RAW.ACCOUNTS, RAW.USAGE_EVENTS, RAW.SUBSCRIPTIONS, RAW.CRM_OPPORTUNITIES,
--   RAW.CALLS + RAW.UTTERANCES (two history months), RAW.CALLS_NEW_MONTH +
--   RAW.UTTERANCES_NEW_MONTH (one held-back month the lab loads later),
--   ML.TOPIC_TAXONOMY (the eight business-defined topics), RAW.SEED_TRUTH (answer key).
-- The notebooks build everything else (segments, redaction, embeddings, topics,
-- Feature Store, models, monitor).
--
-- Prerequisites: a role that can CREATE DATABASE and CREATE WAREHOUSE (SYSADMIN),
-- and SNOWFLAKE.CORTEX_USER (granted to PUBLIC by default) for the AI functions.
-- Safe to re-run: it replaces the raw data with the same deterministic rows.
-- =============================================================================

USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS TRANSCRIPT_CHURN_ML_DEMO COMMENT = 'Call-transcript topics to churn demo; every row is synthetic';
CREATE SCHEMA IF NOT EXISTS TRANSCRIPT_CHURN_ML_DEMO.RAW COMMENT = 'Landed source data: calls, utterances, CRM, subscriptions, usage';
CREATE SCHEMA IF NOT EXISTS TRANSCRIPT_CHURN_ML_DEMO.CORE COMMENT = 'Segments, redaction and embeddings';
CREATE SCHEMA IF NOT EXISTS TRANSCRIPT_CHURN_ML_DEMO.ML COMMENT = 'Topics, clusterer, models and registry';
CREATE SCHEMA IF NOT EXISTS TRANSCRIPT_CHURN_ML_DEMO.FEATURES COMMENT = 'Feature Store';
CREATE SCHEMA IF NOT EXISTS TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS COMMENT = 'Price sentiment, semantic view, churn scores';

CREATE WAREHOUSE IF NOT EXISTS TRANSCRIPT_CHURN_ML_WH
  WAREHOUSE_SIZE = MEDIUM AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Call-transcript topics to churn demo';
USE WAREHOUSE TRANSCRIPT_CHURN_ML_WH;
USE SCHEMA TRANSCRIPT_CHURN_ML_DEMO.RAW;

-- Deterministic uniform draw in [0, 1) from any key: re-runs produce the same rows.
CREATE OR REPLACE FUNCTION RAW.U(K VARCHAR) RETURNS FLOAT
  AS '(MOD(ABS(HASH(K)), 1000000) / 1000000.0)::FLOAT';

-- -----------------------------------------------------------------------------
-- 1. Accounts, with the hidden drivers of churn (kept only in SEED_TRUTH)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE RAW.ACCOUNTS_GEN AS
SELECT
  'ACC' || LPAD(SEQ4() + 1, 5, '0') AS ACCOUNT_ID,
  SEQ4() + 1 AS N
FROM TABLE(GENERATOR(ROWCOUNT => 2000));

CREATE OR REPLACE TABLE RAW.ACCOUNTS_LATENT AS
SELECT
  ACCOUNT_ID,
  CASE WHEN RAW.U(ACCOUNT_ID || 'seg') < 0.55 THEN 'LOAN_OFFICER'
       WHEN RAW.U(ACCOUNT_ID || 'seg') < 0.85 THEN 'AGENT' ELSE 'TEAM' END AS SEGMENT,
  CASE WHEN RAW.U(ACCOUNT_ID || 'tier') < 0.5 THEN 'ESSENTIALS'
       WHEN RAW.U(ACCOUNT_ID || 'tier') < 0.85 THEN 'PRO' ELSE 'ENTERPRISE' END AS PLAN_TIER,
  DATEADD(day, -FLOOR(RAW.U(ACCOUNT_ID || 'signup') * 900)::INT - 60, '2026-01-01'::DATE) AS SIGNUP_DATE,
  RAW.U(ACCOUNT_ID || 'pain') < 0.25 AS LATENT_PRICE_PAIN,
  RAW.U(ACCOUNT_ID || 'share') < 0.12 AS LATENT_SEAT_SHARE,
  RAW.U(ACCOUNT_ID || 'dis') AS LATENT_DISENGAGE,
  CASE WHEN RAW.U(ACCOUNT_ID || 'drv') < 0.4 THEN 'competitor price'
       WHEN RAW.U(ACCOUNT_ID || 'drv') < 0.7 THEN 'pricing model' ELSE 'value for money' END AS LATENT_PRICE_DRIVER
FROM RAW.ACCOUNTS_GEN;

CREATE OR REPLACE TABLE RAW.ACCOUNTS COMMENT = 'Customer accounts (loan officers, agents, teams)' AS
SELECT ACCOUNT_ID, SEGMENT, PLAN_TIER, SIGNUP_DATE,
       ROUND(CASE PLAN_TIER WHEN 'ESSENTIALS' THEN 89 WHEN 'PRO' THEN 179 ELSE 449 END
             * IFF(SEGMENT = 'TEAM', 3, 1), 2) AS MRR
FROM RAW.ACCOUNTS_LATENT;

-- -----------------------------------------------------------------------------
-- 2. Monthly product usage (2024-07 .. 2025-12): disengaged accounts fade in the last 6 months
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE RAW.USAGE_EVENTS COMMENT = 'Monthly product usage per account' AS
WITH months AS (
  SELECT DATEADD(month, SEQ4(), '2024-07-01'::DATE) AS MONTH_START FROM TABLE(GENERATOR(ROWCOUNT => 18))
)
SELECT a.ACCOUNT_ID, m.MONTH_START,
       LAST_DAY(m.MONTH_START)::TIMESTAMP_NTZ AS MONTH_END_TS,
       GREATEST(0, ROUND((20 + 25 * RAW.U(a.ACCOUNT_ID || 'base'))
         * (1 - IFF(DATEDIFF(month, m.MONTH_START, '2026-01-01'::DATE) <= 6,
                    a.LATENT_DISENGAGE * (7 - DATEDIFF(month, m.MONTH_START, '2026-01-01'::DATE)) / 6 * 0.85, 0))
         * (0.85 + 0.3 * RAW.U(a.ACCOUNT_ID || m.MONTH_START::STRING)))) AS LOGINS,
       GREATEST(0, ROUND((40 + 60 * RAW.U(a.ACCOUNT_ID || 'rep'))
         * (1 - IFF(DATEDIFF(month, m.MONTH_START, '2026-01-01'::DATE) <= 6,
                    a.LATENT_DISENGAGE * (7 - DATEDIFF(month, m.MONTH_START, '2026-01-01'::DATE)) / 6 * 0.7, 0))
         * (0.85 + 0.3 * RAW.U(m.MONTH_START::STRING || a.ACCOUNT_ID)))) AS REPORTS_SENT,
       ROUND(1 + IFF(a.SEGMENT = 'TEAM', 4, 0) * RAW.U(a.ACCOUNT_ID || 'users')) AS ACTIVE_USERS
FROM RAW.ACCOUNTS_LATENT a JOIN months m ON m.MONTH_START >= DATE_TRUNC(month, a.SIGNUP_DATE);

-- -----------------------------------------------------------------------------
-- 3. Subscriptions: churn after 2026-01-01 follows a hazard driven by usage AND the
--    price pain and seat sharing that surface on calls. Follow-up ends 2026-10-01.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE RAW.SUBSCRIPTIONS COMMENT = 'One subscription per account; CHURN_DATE is NULL while active' AS
WITH h AS (
  SELECT ACCOUNT_ID, SIGNUP_DATE,
         0.0003 * EXP(0.8 * (LATENT_DISENGAGE - 0.5) + 2.6 * IFF(LATENT_PRICE_PAIN, 1, 0)
                      + 2.0 * IFF(LATENT_SEAT_SHARE, 1, 0)) AS DAILY_HAZARD,
         -LN(GREATEST(RAW.U(ACCOUNT_ID || 'churn'), 1e-6)) AS E
  FROM RAW.ACCOUNTS_LATENT
)
SELECT ACCOUNT_ID, SIGNUP_DATE AS START_DATE,
       IFF(E / DAILY_HAZARD < 273, DATEADD(day, CEIL(E / DAILY_HAZARD)::INT, '2026-01-01'::DATE), NULL) AS CHURN_DATE
FROM h;

-- -----------------------------------------------------------------------------
-- 4. CRM opportunities (renewals and upsells) with outcomes
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE RAW.CRM_OPPORTUNITIES COMMENT = 'Renewal and upsell opportunities' AS
SELECT 'OPP' || LPAD(ROW_NUMBER() OVER (ORDER BY a.ACCOUNT_ID), 5, '0') AS OPPORTUNITY_ID,
       a.ACCOUNT_ID,
       IFF(RAW.U(a.ACCOUNT_ID || 'opptype') < 0.6, 'RENEWAL', 'UPSELL') AS OPPORTUNITY_TYPE,
       DATEADD(day, FLOOR(RAW.U(a.ACCOUNT_ID || 'oppdate') * 80)::INT, '2025-11-05'::DATE) AS CLOSE_DATE,
       IFF(RAW.U(a.ACCOUNT_ID || 'won') < IFF(a.LATENT_PRICE_PAIN, 0.35, 0.7), 'WON', 'LOST') AS OUTCOME,
       ROUND(12 * b.MRR * (0.8 + 0.4 * RAW.U(a.ACCOUNT_ID || 'amt')), 0) AS AMOUNT
FROM RAW.ACCOUNTS_LATENT a JOIN RAW.ACCOUNTS b USING (ACCOUNT_ID)
WHERE RAW.U(a.ACCOUNT_ID || 'hasopp') < 0.45;

-- -----------------------------------------------------------------------------
-- 5. Calls: ~1,500 over three months, about 60% short dials (voicemail, no conversation).
--    Accounts with price pain or seat sharing are likelier to have a real conversation.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE RAW.PEOPLE AS
SELECT * FROM VALUES
  (0,'Maria','Lopez'),(1,'James','Carter'),(2,'Priya','Shah'),(3,'Daniel','Kim'),(4,'Olivia','Brooks'),
  (5,'Marcus','Reed'),(6,'Sofia','Nguyen'),(7,'Ethan','Walsh'),(8,'Grace','Patel'),(9,'Lucas','Bennett'),
  (10,'Hannah','Ortiz'),(11,'Noah','Fischer'),(12,'Ava','Morales'),(13,'Caleb','Hughes'),(14,'Zoe','Ramirez'),
  (15,'Owen','Price'),(16,'Leah','Coleman'),(17,'Isaac','Turner'),(18,'Mia','Jensen'),(19,'Ryan','Douglas')
  AS P(I, FIRST_NAME, LAST_NAME);

CREATE OR REPLACE TABLE RAW.REPS COMMENT = 'Customer-success and sales reps (an allowlist for selective redaction)' AS
SELECT * FROM VALUES (0,'Jordan Ellis'),(1,'Taylor Brandt'),(2,'Morgan Hale'),(3,'Casey Lin'),(4,'Riley Dawson'),(5,'Avery Stone')
  AS R(REP_IDX, REP_NAME);

CREATE OR REPLACE TABLE RAW.CALLS_ALL AS
WITH real_calls AS (
  SELECT ACCOUNT_ID, 'R' AS KIND, 1 AS K FROM RAW.ACCOUNTS_LATENT
  WHERE RAW.U(ACCOUNT_ID || 'realcall') < IFF(LATENT_PRICE_PAIN OR LATENT_SEAT_SHARE, 0.62, 0.115)
),
short_dials AS (
  SELECT 'ACC' || LPAD(1 + FLOOR(RAW.U('dial' || SEQ4()) * 2000)::INT, 5, '0') AS ACCOUNT_ID, 'S' AS KIND, SEQ4() AS K
  FROM TABLE(GENERATOR(ROWCOUNT => 900))
),
all_calls AS (SELECT * FROM real_calls UNION ALL SELECT * FROM short_dials)
SELECT 'CALL' || LPAD(ROW_NUMBER() OVER (ORDER BY KIND, ACCOUNT_ID, K), 5, '0') AS CALL_ID,
       ACCOUNT_ID, KIND,
       DATEADD(minute, FLOOR(RAW.U(ACCOUNT_ID || KIND || K || 'ts') * 92 * 24 * 60)::INT, '2025-11-01'::TIMESTAMP_NTZ) AS CALL_TS,
       FLOOR(RAW.U(ACCOUNT_ID || KIND || K || 'rep') * 6)::INT AS REP_IDX
FROM all_calls;

CREATE OR REPLACE TABLE RAW.CALLS_ALL2 AS
SELECT c.CALL_ID, c.ACCOUNT_ID, c.CALL_TS, r.REP_NAME, c.KIND,
       IFF(c.KIND = 'S', 'OUTBOUND_DIAL',
           CASE WHEN RAW.U(c.CALL_ID || 'type') < 0.35 THEN 'RENEWAL'
                WHEN RAW.U(c.CALL_ID || 'type') < 0.65 THEN 'SUPPORT'
                WHEN RAW.U(c.CALL_ID || 'type') < 0.85 THEN 'SALES' ELSE 'ONBOARDING' END) AS CALL_TYPE,
       IFF(c.KIND = 'S', 15 + FLOOR(RAW.U(c.CALL_ID || 'd') * 40)::INT, 600 + FLOOR(RAW.U(c.CALL_ID || 'd') * 1800)::INT) AS DURATION_SEC,
       o.OPPORTUNITY_ID
FROM RAW.CALLS_ALL c JOIN RAW.REPS r ON r.REP_IDX = c.REP_IDX
LEFT JOIN RAW.CRM_OPPORTUNITIES o ON o.ACCOUNT_ID = c.ACCOUNT_ID AND c.KIND = 'R';

-- -----------------------------------------------------------------------------
-- 6. Phrase library for the generator (temporary: only this session reads it)
--    TOPIC, SPEAKER_SIDE, DRIVER (pricing only), V (variant), TEXT
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE RAW.PHRASES (TOPIC STRING, SIDE STRING, DRIVER STRING, V INT, TEXT STRING);
INSERT INTO RAW.PHRASES VALUES
 ('ONBOARDING','REP',NULL,0,'Let''s walk through setup today. Once your client list is uploaded, the system builds a personalized home digest for each homeowner and you choose how often it goes out.'),
 ('ONBOARDING','REP',NULL,1,'For onboarding I recommend importing your past clients first, then we brand the emails with your photo and contact details so it feels like it comes from you.'),
 ('ONBOARDING','REP',NULL,2,'The training video covers the dashboard in about ten minutes, and I can schedule a second session for your assistant if they will manage the contact import.'),
 ('ONBOARDING','CUSTOMER',NULL,0,'I uploaded my contacts yesterday but about a third of them came in without addresses, so I am not sure the digests will work for those clients.'),
 ('ONBOARDING','CUSTOMER',NULL,1,'Can my assistant get her own login for setup? She handles the spreadsheet and I just want to approve the branding before anything goes out.'),
 ('ONBOARDING','CUSTOMER',NULL,2,'I am new to this kind of tool, so walking me through the import step by step would really help before I send anything to my past clients.'),
 ('REPORT_ENGAGEMENT','REP',NULL,0,'Your monthly reports had a strong open rate last month, and the homeowners who clicked into the equity estimate are the ones I would call first.'),
 ('REPORT_ENGAGEMENT','REP',NULL,1,'Each digest shows the estimated home value, equity, and recent nearby sales, so it gives your clients a reason to open it every month.'),
 ('REPORT_ENGAGEMENT','REP',NULL,2,'If engagement drops we can adjust the send day or the subject line, small changes there usually lift opens by a few points.'),
 ('REPORT_ENGAGEMENT','CUSTOMER',NULL,0,'My clients actually reply to the monthly home value email, a couple of them asked me about refinancing after seeing their equity number.'),
 ('REPORT_ENGAGEMENT','CUSTOMER',NULL,1,'Open rates were good at first but they have been sliding for the last two months and I am not sure people still read the reports.'),
 ('REPORT_ENGAGEMENT','CUSTOMER',NULL,2,'One homeowner said the value estimate looked too low compared to a neighbor''s sale, so I want to understand how that number is calculated.'),
 ('LEAD_ALERTS','REP',NULL,0,'The lead alerts flag homeowners who look ready to move, for example someone who checked their value three times this week or viewed a refinance scenario.'),
 ('LEAD_ALERTS','REP',NULL,1,'You can set the alert to come by text or email, and each alert links straight to the homeowner''s activity so you know what to say when you call.'),
 ('LEAD_ALERTS','REP',NULL,2,'Most teams set a rule that alerts are worked within one business day, because those homeowners cool off quickly.'),
 ('LEAD_ALERTS','CUSTOMER',NULL,0,'I got an alert that a past client was looking at selling, I called her the same day and we are now talking about a listing in the spring.'),
 ('LEAD_ALERTS','CUSTOMER',NULL,1,'The alerts come in too often for me, half of them are people who just opened an email once, so I started ignoring them.'),
 ('LEAD_ALERTS','CUSTOMER',NULL,2,'Can the alerts go to my partner agent as well? She handles the listing side when a homeowner is ready to sell.'),
 ('CRM_INTEGRATION','REP',NULL,0,'The integration syncs contacts both ways every night, so new clients in your CRM show up here and engagement notes flow back automatically.'),
 ('CRM_INTEGRATION','REP',NULL,1,'If the sync fails it is usually a field mapping problem, I can look at the mapping with you and fix the phone and address fields.'),
 ('CRM_INTEGRATION','REP',NULL,2,'We support the major loan origination and CRM systems, and for the others there is a CSV export you can schedule weekly.'),
 ('CRM_INTEGRATION','CUSTOMER',NULL,0,'Our CRM sync has been failing since we switched systems, and I am having to export spreadsheets by hand every Friday.'),
 ('CRM_INTEGRATION','CUSTOMER',NULL,1,'I need the engagement data in our CRM so my processors can see who opened the report before they make follow up calls.'),
 ('CRM_INTEGRATION','CUSTOMER',NULL,2,'The duplicate contacts from the sync are a mess, some clients now show up three times with different email addresses.'),
 ('BILLING_ADMIN','REP',NULL,0,'I can see two invoices this month because the plan change happened mid cycle, the second one is a prorated adjustment.'),
 ('BILLING_ADMIN','REP',NULL,1,'To update the card on file go to account settings, then billing, and you can also add a second billing contact for your office manager.'),
 ('BILLING_ADMIN','REP',NULL,2,'I will send you a receipt with the company name and tax details so your accounting team can file it.'),
 ('BILLING_ADMIN','CUSTOMER',NULL,0,'I was charged twice this month and I need someone to explain the second invoice before my office manager disputes it.'),
 ('BILLING_ADMIN','CUSTOMER',NULL,1,'Our company card expired and I want to switch billing to the brokerage account instead of my personal card.'),
 ('BILLING_ADMIN','CUSTOMER',NULL,2,'Can you resend last quarter''s invoices? Our accountant needs them with the company name on the receipt.'),
 ('RATE_MARKET','REP',NULL,0,'With rates moving again, a lot of loan officers are using the refinance scenario in the report to restart conversations with past clients.'),
 ('RATE_MARKET','REP',NULL,1,'Inventory is still tight in most markets, so homeowners with high equity are getting more calls from agents than usual.'),
 ('RATE_MARKET','REP',NULL,2,'We added a rate watch section so homeowners can see what their payment would be if rates drop another half point.'),
 ('RATE_MARKET','CUSTOMER',NULL,0,'Nobody is refinancing at these rates, so I mostly use the reports to stay in touch until the market turns.'),
 ('RATE_MARKET','CUSTOMER',NULL,1,'My purchase business is slow because inventory is so low, I need homeowners who are thinking about selling, not just refinancing.'),
 ('RATE_MARKET','CUSTOMER',NULL,2,'When rates dipped last month I had five past clients ask about refinancing within a week, the timing was perfect.'),
 ('RENEWAL_TERMS','REP',NULL,0,'Your annual agreement renews next month, I wanted to walk through what is included and whether the current tier still fits your team.'),
 ('RENEWAL_TERMS','REP',NULL,1,'If you renew for two years we can lock the current rate, otherwise the renewal follows the standard terms.'),
 ('RENEWAL_TERMS','REP',NULL,2,'I can send the renewal paperwork today so it is signed before the current term ends and nothing is interrupted.'),
 ('RENEWAL_TERMS','CUSTOMER',NULL,0,'Before I sign the renewal I want to understand what changed in the contract, the auto renew clause surprised me last year.'),
 ('RENEWAL_TERMS','CUSTOMER',NULL,1,'We are planning to renew, but I need the paperwork by the end of the month so it goes through our approval process.'),
 ('RENEWAL_TERMS','CUSTOMER',NULL,2,'I would like to move to a month to month agreement instead of locking into another full year.'),
 ('PRICING','REP',NULL,0,'I understand the price concern, let me walk through what the plan includes and how other loan officers measure the return.'),
 ('PRICING','REP',NULL,1,'The price per seat went up this year because we added the lead alerts and the rate watch section to every plan.'),
 ('PRICING','REP',NULL,2,'If budget is the issue, we can look at the smaller tier or a discount for an annual commitment.'),
 ('PRICING','CUSTOMER','competitor price',0,'Another vendor quoted us almost half of what we pay you for a very similar monthly report, so I have to justify staying.'),
 ('PRICING','CUSTOMER','competitor price',1,'Honestly the competitor''s price is a lot lower and their sales rep keeps calling me, I need a reason not to switch.'),
 ('PRICING','CUSTOMER','pricing model',0,'Paying per seat does not work for our team, we have part time loan officers and we pay full price for every login.'),
 ('PRICING','CUSTOMER','pricing model',1,'The new pricing structure charges by contact count, and our database keeps growing, so the bill keeps going up.'),
 ('PRICING','CUSTOMER','value for money',0,'I do not see enough closed loans from this to justify what it costs every month, the return just is not there yet.'),
 ('PRICING','CUSTOMER','value for money',1,'For what we pay, I expected more referrals, right now it feels expensive for the business it brings in.'),
 ('PRICING','CUSTOMER','positive',0,'The price is fair for what we get, two closed loans this year already paid for the whole subscription.'),
 ('PRICING','CUSTOMER','positive',1,'Cost is not really a concern for us, the reports bring in enough repeat business to cover it easily.'),
 ('AI_LISTING_ASSISTANT','REP',NULL,0,'A few customers have asked about writing listing descriptions with AI, it is not in the product today but I can log the request.'),
 ('AI_LISTING_ASSISTANT','REP',NULL,1,'We do not generate marketing copy yet, but I will pass along that you want help drafting the homeowner emails automatically.'),
 ('AI_LISTING_ASSISTANT','REP',NULL,2,'An assistant that writes the first draft for you is a common request, I will add your vote to the product feedback.'),
 ('AI_LISTING_ASSISTANT','CUSTOMER',NULL,0,'Can the tool write the listing description for me with AI? My agent friends already use something like that and it saves hours.'),
 ('AI_LISTING_ASSISTANT','CUSTOMER',NULL,1,'It would be great if the system drafted a personal note to each homeowner automatically, writing them one by one takes me forever.'),
 ('AI_LISTING_ASSISTANT','CUSTOMER',NULL,2,'Do you have an AI assistant that can summarize a homeowner''s activity and suggest what I should say when I call them?'),
 ('TEAM_SEAT_SHARING','REP',NULL,0,'I noticed several people logging in under one seat, our terms require a seat per user, so let us talk about the right plan for your team.'),
 ('TEAM_SEAT_SHARING','REP',NULL,1,'If the team shares one login you lose the per agent reporting, so it is hard to see who is following up on alerts.'),
 ('TEAM_SEAT_SHARING','REP',NULL,2,'We can move the extra users to view only access, which costs less than a full seat and keeps the reporting separate.'),
 ('TEAM_SEAT_SHARING','CUSTOMER',NULL,0,'Honestly our whole team shares one login to keep the cost down, we have four loan officers using a single seat right now.'),
 ('TEAM_SEAT_SHARING','CUSTOMER',NULL,1,'We are consolidating seats, two of our officers left and I only want to pay for the people who still use it.'),
 ('TEAM_SEAT_SHARING','CUSTOMER',NULL,2,'Can we share one account across the branch? Buying a separate seat for every part time officer is too expensive.'),
 ('VOICEMAIL','REP',NULL,0,'Sorry I missed you, I was calling to check in on your account, give me a call back when you have a minute.'),
 ('VOICEMAIL','REP',NULL,1,'Just following up on our last conversation, I will try you again tomorrow morning.'),
 ('VOICEMAIL','CUSTOMER',NULL,0,'Hello? Sorry, I am driving right now, can you call me back later this afternoon?'),
 ('VOICEMAIL','CUSTOMER',NULL,1,'I am with a client, can we talk tomorrow instead?');

-- -----------------------------------------------------------------------------
-- 7. Topic blocks per call. A real call has 3-4 blocks of 4 turns (rep, customer,
--    rep, customer) on one topic each; a short dial has one 2-turn voicemail block.
--    The two emerging topics are not in the business taxonomy and grow in January.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE RAW.CALL_BLOCKS AS
WITH c AS (
  SELECT c.*, a.LATENT_PRICE_PAIN, a.LATENT_SEAT_SHARE, a.LATENT_PRICE_DRIVER,
         c.CALL_TS >= '2026-01-01'::TIMESTAMP_NTZ AS IS_NEW_MONTH
  FROM RAW.CALLS_ALL2 c JOIN RAW.ACCOUNTS_LATENT a USING (ACCOUNT_ID)
),
base_topics AS (
  SELECT column1 AS T_IDX, column2 AS TOPIC FROM VALUES
    (0,'ONBOARDING'),(1,'REPORT_ENGAGEMENT'),(2,'LEAD_ALERTS'),(3,'CRM_INTEGRATION'),
    (4,'BILLING_ADMIN'),(5,'RATE_MARKET'),(6,'RENEWAL_TERMS'),(7,'PRICING')
),
slots AS (SELECT SEQ4() AS SLOT FROM TABLE(GENERATOR(ROWCOUNT => 4)))
SELECT c.CALL_ID, s.SLOT AS BLOCK_NO,
       CASE
         WHEN c.KIND = 'S' THEN 'VOICEMAIL'
         WHEN s.SLOT = 0 AND c.LATENT_PRICE_PAIN THEN 'PRICING'
         WHEN s.SLOT = 1 AND c.LATENT_SEAT_SHARE THEN 'TEAM_SEAT_SHARING'
         WHEN s.SLOT = 2 AND RAW.U(c.CALL_ID || 'ai') < IFF(c.IS_NEW_MONTH, 0.40, 0.14) THEN 'AI_LISTING_ASSISTANT'
         WHEN s.SLOT = 3 AND c.IS_NEW_MONTH AND RAW.U(c.CALL_ID || 'share2') < 0.18 THEN 'TEAM_SEAT_SHARING'
         ELSE bt.TOPIC
       END AS TOPIC,
       IFF(c.LATENT_PRICE_PAIN, c.LATENT_PRICE_DRIVER, 'positive') AS PRICE_DRIVER
FROM c JOIN slots s ON (c.KIND = 'R' AND s.SLOT < 3 + IFF(RAW.U(c.CALL_ID || 'nb') < 0.5, 1, 0)) OR (c.KIND = 'S' AND s.SLOT = 0)
JOIN base_topics bt ON bt.T_IDX = FLOOR(RAW.U(c.CALL_ID || s.SLOT || 'topic')
                                        * IFF(c.LATENT_PRICE_PAIN, 7, 8))::INT;

-- Turns: 4 per real block, 2 per voicemail. PII is planted in customer and rep turns.
CREATE OR REPLACE TABLE RAW.UTTERANCES_ALL AS
WITH turns AS (SELECT SEQ4() AS T FROM TABLE(GENERATOR(ROWCOUNT => 4))),
t AS (
  SELECT b.CALL_ID, b.BLOCK_NO, b.TOPIC, b.PRICE_DRIVER, x.T,
         b.BLOCK_NO * 4 + x.T + 1 AS TURN_NO,
         IFF(MOD(x.T, 2) = 0, 'REP', 'CUSTOMER') AS SPEAKER_SIDE
  FROM RAW.CALL_BLOCKS b JOIN turns x ON x.T < IFF(b.TOPIC = 'VOICEMAIL', 2, 4)
),
picked AS (
  SELECT t.*,
         p.TEXT AS PHRASE,
         pp.FIRST_NAME, pp.LAST_NAME,
         r.REP_NAME
  FROM t
  JOIN RAW.CALLS_ALL2 c ON c.CALL_ID = t.CALL_ID
  JOIN RAW.REPS r ON r.REP_NAME = c.REP_NAME
  JOIN RAW.PEOPLE pp ON pp.I = FLOOR(RAW.U(c.ACCOUNT_ID || 'person') * 20)::INT
  JOIN RAW.PHRASES p
    ON p.TOPIC = t.TOPIC AND p.SIDE = t.SPEAKER_SIDE
   AND (t.TOPIC <> 'PRICING' OR t.SPEAKER_SIDE = 'REP' OR p.DRIVER = t.PRICE_DRIVER)
   AND p.V = MOD(ABS(HASH(t.CALL_ID, t.TURN_NO)),
                 IFF(t.TOPIC = 'VOICEMAIL' OR (t.TOPIC = 'PRICING' AND t.SPEAKER_SIDE = 'CUSTOMER'), 2, 3))
)
SELECT CALL_ID, TURN_NO, SPEAKER_SIDE,
       CASE
         WHEN SPEAKER_SIDE = 'REP' AND TURN_NO = 1 THEN 'Hi, this is ' || REP_NAME || ' from customer success. ' || PHRASE
         WHEN SPEAKER_SIDE = 'CUSTOMER' AND TURN_NO = 2 AND RAW.U(CALL_ID || 'nm') < 0.6
           THEN 'This is ' || FIRST_NAME || ' ' || LAST_NAME || '. ' || PHRASE
         WHEN SPEAKER_SIDE = 'CUSTOMER' AND RAW.U(CALL_ID || TURN_NO || 'ph') < 0.12
           THEN PHRASE || ' You can reach me at 303-555-' || LPAD(FLOOR(RAW.U(CALL_ID || 'num') * 10000)::INT, 4, '0') || '.'
         WHEN SPEAKER_SIDE = 'CUSTOMER' AND RAW.U(CALL_ID || TURN_NO || 'em') < 0.06
           THEN PHRASE || ' My email is ' || LOWER(FIRST_NAME) || '.' || LOWER(LAST_NAME) || '@homemail.example.'
         ELSE PHRASE
       END AS TEXT,
       TOPIC AS TRUE_TOPIC
FROM picked;

-- History (Nov-Dec 2025) and the held-back new month (Jan 2026)
CREATE OR REPLACE TABLE RAW.CALLS COMMENT = 'Recorded calls, history months' AS
SELECT CALL_ID, ACCOUNT_ID, CALL_TS, REP_NAME, CALL_TYPE, DURATION_SEC, OPPORTUNITY_ID
FROM RAW.CALLS_ALL2 WHERE CALL_TS < '2026-01-01'::TIMESTAMP_NTZ;
CREATE OR REPLACE TABLE RAW.CALLS_NEW_MONTH COMMENT = 'Recorded calls, the held-back month the lab loads later' AS
SELECT CALL_ID, ACCOUNT_ID, CALL_TS, REP_NAME, CALL_TYPE, DURATION_SEC, OPPORTUNITY_ID
FROM RAW.CALLS_ALL2 WHERE CALL_TS >= '2026-01-01'::TIMESTAMP_NTZ;

CREATE OR REPLACE TABLE RAW.UTTERANCES (CALL_ID STRING, TURN_NO INT, SPEAKER_SIDE STRING, TEXT STRING)
  CHANGE_TRACKING = TRUE COMMENT = 'One row per speaker turn, as the call-recording platform delivers them';
INSERT INTO RAW.UTTERANCES
SELECT u.CALL_ID, u.TURN_NO, u.SPEAKER_SIDE, u.TEXT FROM RAW.UTTERANCES_ALL u
JOIN RAW.CALLS c ON c.CALL_ID = u.CALL_ID;
CREATE OR REPLACE TABLE RAW.UTTERANCES_NEW_MONTH COMMENT = 'Turns for the held-back month' AS
SELECT u.CALL_ID, u.TURN_NO, u.SPEAKER_SIDE, u.TEXT FROM RAW.UTTERANCES_ALL u
JOIN RAW.CALLS_NEW_MONTH c ON c.CALL_ID = u.CALL_ID;
ALTER TABLE RAW.CALLS SET CHANGE_TRACKING = TRUE;

-- -----------------------------------------------------------------------------
-- 8. Answer key (what the generator planted) and the business topic taxonomy
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE RAW.SEED_TRUTH COMMENT = 'What the generator planted; the lab checks results against it' AS
SELECT u.CALL_ID, u.TURN_NO, u.TRUE_TOPIC, b.PRICE_DRIVER,
       a.ACCOUNT_ID, a.LATENT_PRICE_PAIN, a.LATENT_SEAT_SHARE, a.LATENT_DISENGAGE
FROM RAW.UTTERANCES_ALL u
JOIN RAW.CALL_BLOCKS b ON b.CALL_ID = u.CALL_ID AND b.BLOCK_NO = FLOOR((u.TURN_NO - 1) / 4)
JOIN RAW.CALLS_ALL2 c ON c.CALL_ID = u.CALL_ID
JOIN RAW.ACCOUNTS_LATENT a ON a.ACCOUNT_ID = c.ACCOUNT_ID;

CREATE OR REPLACE TABLE ML.TOPIC_TAXONOMY COMMENT = 'Business-defined topics with exemplar phrasing written by the team' AS
SELECT * FROM VALUES
 ('ONBOARDING','Onboarding and setup','Getting a new customer set up: importing the client list, branding, training sessions.'),
 ('ONBOARDING','Onboarding and setup','Help me load my contacts and brand the emails before the first send.'),
 ('REPORT_ENGAGEMENT','Report engagement','How homeowners open and respond to the monthly home value and equity digest.'),
 ('REPORT_ENGAGEMENT','Report engagement','Open rates on the monthly report are dropping and clients may not read it.'),
 ('LEAD_ALERTS','Lead alerts','Alerts that flag homeowners who look ready to sell or refinance, and how fast reps work them.'),
 ('LEAD_ALERTS','Lead alerts','I got a notification that a past client is thinking about selling.'),
 ('CRM_INTEGRATION','CRM integration','Syncing contacts and engagement data with the customer''s CRM or loan origination system.'),
 ('CRM_INTEGRATION','CRM integration','The CRM sync broke and contacts are duplicated.'),
 ('BILLING_ADMIN','Billing and invoices','Invoices, duplicate charges, payment method and receipts.'),
 ('BILLING_ADMIN','Billing and invoices','I was billed twice and need a copy of the invoice for accounting.'),
 ('RATE_MARKET','Rates and market','Mortgage rate moves, refinance demand and housing inventory.'),
 ('RATE_MARKET','Rates and market','Nobody refinances at today''s rates and inventory is tight.'),
 ('RENEWAL_TERMS','Renewal and contract terms','Annual renewal, contract clauses, term length and paperwork.'),
 ('RENEWAL_TERMS','Renewal and contract terms','Send me the renewal paperwork and explain the auto renew clause.'),
 ('PRICING','Price and cost','The cost of the subscription, price per seat, discounts and competitor quotes.'),
 ('PRICING','Price and cost','It costs too much for what it brings in, another vendor is cheaper.')
 AS T(TOPIC_ID, TOPIC_NAME, EXEMPLAR_TEXT);

-- Generator scaffolding is not part of the demo: keep only the latent drivers in SEED_TRUTH.
DROP TABLE IF EXISTS RAW.ACCOUNTS_GEN;
DROP TABLE IF EXISTS RAW.CALLS_ALL;
DROP TABLE IF EXISTS RAW.UTTERANCES_ALL;
DROP TABLE IF EXISTS RAW.CALLS_ALL2;
DROP TABLE IF EXISTS RAW.CALL_BLOCKS;
CREATE OR REPLACE TABLE RAW.SEED_ACCOUNTS COMMENT = 'Answer key: the hidden churn drivers per account' AS SELECT * FROM RAW.ACCOUNTS_LATENT;
DROP TABLE IF EXISTS RAW.ACCOUNTS_LATENT;

SELECT 'setup complete' AS STATUS,
       (SELECT COUNT(*) FROM RAW.ACCOUNTS) AS ACCOUNTS,
       (SELECT COUNT(*) FROM RAW.CALLS) + (SELECT COUNT(*) FROM RAW.CALLS_NEW_MONTH) AS CALLS,
       (SELECT COUNT(*) FROM RAW.UTTERANCES) AS HISTORY_TURNS,
       (SELECT COUNT(*) FROM RAW.UTTERANCES_NEW_MONTH) AS NEW_MONTH_TURNS;
