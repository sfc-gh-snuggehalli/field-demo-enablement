-- =============================================================================
-- Claude Code + MCP -> Cortex Agents + CoWork  |  Lab: Setup Script
-- =============================================================================
-- PART 0 — Shared foundation. BOTH the "BEFORE" (Claude Code + Snowflake MCP)
-- and "AFTER" (Cortex Agents + CoWork) paths reuse everything created here.
--
-- Run this script ONCE before the notebooks. It is the single source of truth:
-- it fully creates and populates all data + tools before any consumer touches
-- them, in strict dependency order.
--
-- Scenario: a B2B sales-intelligence / go-to-market (GTM) SaaS
-- company whose sales org sends high email volume. Today they score every rep
-- email with an AI function and mine winning email patterns. This demo migrates
-- that workload from an external "brain" (Claude Code over the Snowflake MCP
-- server) to an in-data-plane multi-agent architecture (Cortex Agents + CoWork).
--
-- Prerequisites:
--   * Role that can CREATE DATABASE / WAREHOUSE / ROLE (SYSADMIN + a grant, or
--     ACCOUNTADMIN). The OAuth security integration in gtm-02 needs ACCOUNTADMIN.
--   * Cortex enabled in the account (SNOWFLAKE.CORTEX_USER database role).
--
-- Naming note (MCP gotcha): the database is a SINGLE TOKEN "GTMAGENTS" with NO
-- underscore. Some MCP clients mis-parse hostnames/paths with underscores, so we
-- keep the DB (which appears in the MCP endpoint URL path) underscore-free. The
-- deck teaches this as a talking point.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE, SCHEMA, WAREHOUSE, ROLE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS GTMAGENTS;
USE DATABASE GTMAGENTS;
CREATE SCHEMA IF NOT EXISTS DEMO;
USE SCHEMA GTMAGENTS.DEMO;

CREATE WAREHOUSE IF NOT EXISTS GTMAGENTS_WH
  WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND = 120
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE GTMAGENTS_WH;

-- Dedicated least-privilege role that the MCP server session and the agents use.
-- (Governance talking point: one role scopes every tool, MCP or agent, the same way.)
USE ROLE SECURITYADMIN;
CREATE ROLE IF NOT EXISTS GTMAGENTS_ROLE;
GRANT ROLE GTMAGENTS_ROLE TO ROLE SYSADMIN;
-- Cortex access for the role (needed for Analyst / agents / AI functions).
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE GTMAGENTS_ROLE;
USE ROLE SYSADMIN;

GRANT USAGE ON DATABASE GTMAGENTS TO ROLE GTMAGENTS_ROLE;
GRANT USAGE ON SCHEMA GTMAGENTS.DEMO TO ROLE GTMAGENTS_ROLE;
GRANT USAGE, OPERATE ON WAREHOUSE GTMAGENTS_WH TO ROLE GTMAGENTS_ROLE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. STRUCTURED SAMPLE DATA (SQL GENERATOR)  —  reps, emails, outcomes, framework
-- ─────────────────────────────────────────────────────────────────────────────
-- Email subject/body text is generated here with quality-tiered templates so the
-- corpus spreads across good / mixed / poor quality. That guarantees intent
-- scores (Part B) and eval results (Part C) separate, and it keeps the data fully
-- reproducible with no local Python dependency.

-- 2a. Sales reps ---------------------------------------------------------------
CREATE OR REPLACE TABLE REPS AS
SELECT
    seq4() + 1                                                        AS rep_id,
    'Rep ' || LPAD((seq4() + 1)::STRING, 3, '0')                      AS rep_name,
    ARRAY_CONSTRUCT('Enterprise','Mid-Market','SMB','Strategic')[UNIFORM(0,3,RANDOM())]::STRING AS team,
    ARRAY_CONSTRUCT('AMER','EMEA','APAC')[UNIFORM(0,2,RANDOM())]::STRING                          AS region,
    UNIFORM(1, 96, RANDOM())                                          AS tenure_months
FROM TABLE(GENERATOR(ROWCOUNT => 40));

-- 2b. Emails -------------------------------------------------------------------
-- Latent quality_tier (1=poor, 2=mixed, 3=good) drives BOTH the text template and
-- the downstream engagement outcomes, so behavior is genuinely predictable from
-- the email content (no leakage — the model in Part B only sees subject/body).
CREATE OR REPLACE TABLE EMAILS AS
WITH base AS (
    SELECT
        seq4() + 1                                                   AS id,
        UNIFORM(1, 40, RANDOM())                                     AS rep_id,
        UNIFORM(1000, 9999, RANDOM())                                AS prospect_id,
        DATEADD('minute', -UNIFORM(0, 259200, RANDOM()), CURRENT_TIMESTAMP()) AS sent_ts,
        -- weighted quality: ~30% poor, ~40% mixed, ~30% good
        CASE
            WHEN UNIFORM(1, 100, RANDOM()) <= 30 THEN 1
            WHEN UNIFORM(1, 100, RANDOM()) <= 70 THEN 2
            ELSE 3
        END                                                          AS quality_tier,
        UNIFORM(0, 3, RANDOM())                                      AS variant
    FROM TABLE(GENERATOR(ROWCOUNT => 3000))
)
SELECT
    id,
    rep_id,
    prospect_id,
    sent_ts,
    quality_tier,
    -- Subject line by tier x variant --------------------------------------------
    CASE quality_tier
        WHEN 3 THEN ARRAY_CONSTRUCT(
            'Cutting your ramp time in half — a specific idea for your SDR team',
            'Noticed your Q3 hiring push — 3 ways to protect pipeline quality',
            'Your team + our intent data: a 20-minute working session?',
            'Idea to lift reply rates for the AMER pod next quarter'
        )[variant]::STRING
        WHEN 2 THEN ARRAY_CONSTRUCT(
            'Following up on sales productivity',
            'Quick question about your outbound',
            'Checking in re: pipeline tools',
            'Thoughts on improving rep efficiency?'
        )[variant]::STRING
        ELSE ARRAY_CONSTRUCT(
            'Touching base',
            'Circling back',
            'Just following up again',
            'Re: re: re: quick sync?'
        )[variant]::STRING
    END                                                              AS subject,
    -- Body by tier x variant ----------------------------------------------------
    CASE quality_tier
        WHEN 3 THEN ARRAY_CONSTRUCT(
            'Hi — I saw your team recently expanded the SDR org. Teams at that stage usually lose 4-6 weeks per rep to manual research. We help GTM teams auto-surface the highest-intent accounts so reps spend time selling, not sifting. Worth a focused 20 minutes Thursday to show you the exact workflow for your AMER pod? If not, no worries — happy to send a 3-minute Loom instead.',
            'Hi — congrats on the Q3 hiring push. The risk at that pace is pipeline quality slipping as new reps blast generic outreach. We give each rep an intent score per account plus a coached rewrite of weak emails, which lifted reply rates ~18% for a similar mid-market team. Open to a working session next week where we look at your own send data?',
            'Hi — quick and specific: your reply rate on cold outbound is likely sitting under 3%. We benchmark every rep email against a proven framework (personalization, clear CTA, brevity, value-prop, intent-match) and auto-draft a stronger version. Can I show you the before/after on 5 of your own emails Friday?',
            'Hi — I pulled a few of your public job posts and it looks like outbound volume is a priority. Rather than pitch, I would rather show you a 20-minute teardown of what is working vs not in your current emails, scored against a best-practice rubric. Does Wednesday 10am work, or should I send times?'
        )[variant]::STRING
        WHEN 2 THEN ARRAY_CONSTRUCT(
            'Hi there, I wanted to reach out because we work with sales teams on productivity. We have some tools that could help your reps. Would you have time for a call this week to discuss?',
            'Hello, following up on my last note. We help companies improve their outbound results with AI. Let me know if you would like to learn more and I can send over some information.',
            'Hi, I am reaching out about your pipeline tooling. A lot of teams like yours are looking at ways to be more efficient. Happy to share how we can help — are you free sometime?',
            'Hey, just checking in to see if improving rep efficiency is on your radar this quarter. We have a platform that assists with that. Would love to connect if the timing is right.'
        )[variant]::STRING
        ELSE ARRAY_CONSTRUCT(
            'Hi, just touching base to see if you are interested. Let me know.',
            'Circling back on this. Are you the right person? Please advise.',
            'Following up again since I have not heard back. Can we set up a call?',
            'Wanted to bump this to the top of your inbox. Let me know your availability.'
        )[variant]::STRING
    END                                                              AS body,
    -- Engagement outcomes correlated with quality (still probabilistic) ---------
    IFF(UNIFORM(1,100,RANDOM()) <= (30 + quality_tier * 18), TRUE, FALSE)  AS opened,
    IFF(UNIFORM(1,100,RANDOM()) <= (2  + quality_tier * quality_tier * 4), TRUE, FALSE) AS replied,
    IFF(UNIFORM(1,100,RANDOM()) <= (quality_tier * quality_tier), TRUE, FALSE)          AS meeting_booked,
    -- Intent score is filled by the model in Part B; nullable for now.
    CAST(NULL AS FLOAT)                                              AS intent_score
FROM base;

-- 2c. Outcomes (deal progression per email) ------------------------------------
CREATE OR REPLACE TABLE OUTCOMES AS
SELECT
    e.id                                                             AS email_id,
    e.rep_id,
    CASE
        WHEN e.meeting_booked AND UNIFORM(1,100,RANDOM()) <= (20 + e.quality_tier * 15) THEN 'Won'
        WHEN e.meeting_booked THEN 'Opportunity'
        WHEN e.replied THEN 'Qualified'
        WHEN e.opened THEN 'Engaged'
        ELSE 'No Response'
    END                                                              AS stage,
    IFF(e.meeting_booked AND UNIFORM(1,100,RANDOM()) <= (20 + e.quality_tier * 15), TRUE, FALSE) AS won,
    CASE
        WHEN e.meeting_booked AND UNIFORM(1,100,RANDOM()) <= (20 + e.quality_tier * 15)
            THEN UNIFORM(8000, 90000, RANDOM())
        ELSE 0
    END                                                              AS revenue
FROM EMAILS e;

-- 2d. Email best-practice framework (rubric) -----------------------------------
-- Cortex Search (below) indexes this so the Coaching agent can retrieve the
-- rubric text when rewriting weak emails.
CREATE OR REPLACE TABLE EMAIL_FRAMEWORK (
    principle_id   INT,
    principle      STRING,
    weight         FLOAT,
    guidance       STRING
);
INSERT INTO EMAIL_FRAMEWORK (principle_id, principle, weight, guidance) VALUES
(1, 'Personalization', 0.25, 'Reference a specific, verifiable detail about the prospect or their company (hiring, funding, product launch, public post). Generic openers like "touching base" score zero on this principle.'),
(2, 'Clear CTA',       0.25, 'Ask for exactly one low-friction next step with a concrete option (a specific time, or a 3-minute async alternative). Vague asks like "let me know" or "are you free sometime" score low.'),
(3, 'Brevity',         0.15, 'Keep the email under ~120 words and one core idea. Long, multi-topic emails and "re: re: re:" threads score low.'),
(4, 'Value Prop',      0.20, 'State a specific, quantified outcome the prospect gets (time saved, reply-rate lift, pipeline protected). Feature dumps without an outcome score low.'),
(5, 'Intent Match',    0.15, 'Tie the message to a signal that this prospect is in-market right now (job posts, expansion, tooling changes). Blind blasts with no signal score low.');

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. GOVERNED SQL TOOL  (reused by MCP GENERIC tool AND agents)
-- ─────────────────────────────────────────────────────────────────────────────
-- A read-only, single-cell scalar UDF. Returns a JSON array of rows so it honors
-- the Cortex custom-tool contract (1 row x 1 column). Owner's-rights: it reads
-- the demo tables regardless of the previewing role, but only exposes curated,
-- aggregate GTM metrics — never raw PII — which is the "governed tool" story.
CREATE OR REPLACE FUNCTION GTM_TEAM_PERFORMANCE(REGION_FILTER STRING)
RETURNS ARRAY
LANGUAGE SQL
AS
$$
    SELECT ARRAY_AGG(OBJECT_CONSTRUCT(
        'region', region,
        'team', team,
        'emails', emails,
        'reply_rate', reply_rate,
        'meeting_rate', meeting_rate,
        'won_deals', won_deals,
        'revenue', revenue
    ))
    FROM (
        SELECT
            r.region,
            r.team,
            COUNT(*)                                                   AS emails,
            ROUND(AVG(IFF(e.replied, 1, 0)), 4)                        AS reply_rate,
            ROUND(AVG(IFF(e.meeting_booked, 1, 0)), 4)                 AS meeting_rate,
            SUM(IFF(o.won, 1, 0))                                      AS won_deals,
            SUM(o.revenue)                                            AS revenue
        FROM EMAILS e
        JOIN REPS r      ON e.rep_id = r.rep_id
        JOIN OUTCOMES o  ON o.email_id = e.id
        WHERE REGION_FILTER IS NULL OR REGION_FILTER = '' OR r.region = REGION_FILTER
        GROUP BY r.region, r.team
        ORDER BY revenue DESC
    )
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. SEMANTIC VIEW  (Cortex Analyst — used by MCP Analyst tool AND the Rec agent)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE SEMANTIC VIEW EMAIL_GTM_SV
  TABLES (
    emails   AS EMAILS   PRIMARY KEY (id),
    reps     AS REPS     PRIMARY KEY (rep_id),
    outcomes AS OUTCOMES PRIMARY KEY (email_id)
  )
  RELATIONSHIPS (
    email_to_rep     AS emails (rep_id)  REFERENCES reps (rep_id),
    outcome_to_email AS outcomes (email_id) REFERENCES emails (id)
  )
  FACTS (
    emails.opened_flag       AS IFF(opened, 1, 0),
    emails.replied_flag      AS IFF(replied, 1, 0),
    emails.meeting_flag      AS IFF(meeting_booked, 1, 0),
    emails.intent            AS intent_score,
    outcomes.won_flag        AS IFF(won, 1, 0),
    outcomes.revenue_amount  AS revenue
  )
  DIMENSIONS (
    emails.quality_tier   AS quality_tier,
    emails.sent_month     AS DATE_TRUNC('month', sent_ts),
    reps.team             AS team,
    reps.region           AS region,
    reps.rep_name         AS rep_name
  )
  METRICS (
    emails.email_count     AS COUNT(emails.id),
    emails.open_rate       AS AVG(emails.opened_flag),
    emails.reply_rate      AS AVG(emails.replied_flag),
    emails.meeting_rate    AS AVG(emails.meeting_flag),
    emails.avg_intent      AS AVG(emails.intent),
    outcomes.win_rate      AS AVG(outcomes.won_flag),
    outcomes.total_revenue AS SUM(outcomes.revenue_amount)
  )
  COMMENT = 'GTM sales-email performance: reply/meeting/win rates and revenue by rep, team, region, quality tier, and month.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. CORTEX SEARCH  (used by MCP Search tool AND the Coaching agent)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE CORTEX SEARCH SERVICE FRAMEWORK_SEARCH
  ON guidance
  ATTRIBUTES principle, weight
  WAREHOUSE = GTMAGENTS_WH
  TARGET_LAG = '1 hour'
  AS
    SELECT principle_id, principle, weight, guidance
    FROM EMAIL_FRAMEWORK;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. SHARED LOGGING / METRICS TABLES  (used by Parts A, B, C, D, E)
-- ─────────────────────────────────────────────────────────────────────────────
-- 6a. Per-request latency & cost — one row per BEFORE (MCP) or AFTER (Agents) call
CREATE TABLE IF NOT EXISTS REQUEST_LOG (
    request_id   STRING,
    source       STRING,          -- 'MCP' (before) | 'AGENTS' (after)
    scenario     STRING,          -- e.g. 'score_email', 'recommend', 'coach'
    latency_ms   NUMBER,
    tokens       NUMBER,
    est_credits  FLOAT,
    ts           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- 6b. Scoring-agent routing decisions (model used, confidence, escalation)
CREATE TABLE IF NOT EXISTS ROUTING_LOG (
    email_id     NUMBER,
    model_used   STRING,
    confidence   FLOAT,
    escalated    BOOLEAN,
    intent_score FLOAT,
    ts           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- 6c. Targeted-analysis cost comparison (AI_FILTER gate vs analyze-everything)
CREATE TABLE IF NOT EXISTS COST_COMPARISON (
    approach       STRING,        -- 'analyze_all' | 'targeted_filter'
    emails_scanned NUMBER,
    emails_treated NUMBER,
    est_credits    FLOAT,
    ts             TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- 6d. Native agent-evaluation infrastructure (Part C) ---------------------------
-- Internal stage that holds the eval-config YAML consumed by EXECUTE_AI_EVALUATION.
CREATE STAGE IF NOT EXISTS EVAL_STAGE
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Holds eval_config.yaml for the native GTM_SUPERVISOR agent evaluation.';

-- Labeled agent-evaluation dataset. One row per question. GROUND_TRUTH is a JSON
-- object carrying: ground_truth_output (what a correct answer looks like),
-- ground_truth_invocations (the specialist tool(s) the supervisor SHOULD call),
-- intent (user goal), and process (complexity tier: single_tool | multi_tool | refusal).
-- The supervisor's tool names are ScoringSpecialist / RecommendationSpecialist /
-- CoachingSpecialist (see gtm-03), so tool_name must match those exactly.
CREATE OR REPLACE TABLE AGENT_EVAL_QUESTIONS (
    INPUT_QUERY   VARCHAR,
    GROUND_TRUTH  VARIANT
);

INSERT INTO AGENT_EVAL_QUESTIONS (INPUT_QUERY, GROUND_TRUTH)
SELECT column1, TRY_PARSE_JSON(column2) FROM VALUES
-- 1-3. score / single_tool -> ScoringSpecialist ------------------------------
('Score the buyer intent of email 2.',
 '{"ground_truth_output": "Returns a buyer-intent score between 0.00 and 1.00 for email id 2, along with the model used and whether it escalated. The answer must be grounded in the scoring specialist output, not a guess.", "ground_truth_invocations": [{"tool_name": "ScoringSpecialist", "tool_input": "Score the buyer intent of email 2"}], "intent": "score_email", "process": "single_tool"}'),
('What is the intent score for email 15?',
 '{"ground_truth_output": "Returns a single buyer-intent score (0.00-1.00) for email id 15 from the scoring specialist. Should not answer a metrics or rewrite question.", "ground_truth_invocations": [{"tool_name": "ScoringSpecialist", "tool_input": "Score the buyer intent of email 15"}], "intent": "score_email", "process": "single_tool"}'),
('How strong is the buyer intent of email 100? Give me the score.',
 '{"ground_truth_output": "Returns the buyer-intent score for email id 100 from the scoring specialist.", "ground_truth_invocations": [{"tool_name": "ScoringSpecialist", "tool_input": "Score the buyer intent of email 100"}], "intent": "score_email", "process": "single_tool"}'),
-- 4-6. recommend / single_tool -> RecommendationSpecialist -------------------
('Which region has the highest win rate?',
 '{"ground_truth_output": "Identifies the region with the highest win rate using GTM performance metrics and cites the metric. Grounded in the recommendation specialist / semantic view, not fabricated.", "ground_truth_invocations": [{"tool_name": "RecommendationSpecialist", "tool_input": "Which region has the highest win rate?"}], "intent": "recommend_pattern", "process": "single_tool"}'),
('Which email quality tier drives the most revenue?',
 '{"ground_truth_output": "Reports total revenue by quality tier and identifies the top tier (expected: higher tiers produce more revenue). Cites the metric used.", "ground_truth_invocations": [{"tool_name": "RecommendationSpecialist", "tool_input": "Which quality tier drives the most revenue?"}], "intent": "recommend_pattern", "process": "single_tool"}'),
('What is our overall reply rate across all emails?',
 '{"ground_truth_output": "Returns the aggregate reply rate across all emails as a single percentage/rate, grounded in the semantic view metrics.", "ground_truth_invocations": [{"tool_name": "RecommendationSpecialist", "tool_input": "What is the overall reply rate?"}], "intent": "recommend_pattern", "process": "single_tool"}'),
-- 7-8. coach / single_tool -> CoachingSpecialist -----------------------------
('Rewrite this weak email to the best-practice framework: "just checking in, let me know if you are interested."',
 '{"ground_truth_output": "Returns a rewritten cold email under 120 words that satisfies the five framework principles (personalization, single clear CTA, brevity, quantified value prop, in-market signal). Should not return a metric or a score.", "ground_truth_invocations": [{"tool_name": "CoachingSpecialist", "tool_input": "Rewrite: just checking in, let me know if you are interested."}], "intent": "coach_email", "process": "single_tool"}'),
('Improve this cold email so it follows our framework: "Circling back. Are you the right person? Please advise."',
 '{"ground_truth_output": "Returns an improved email that adds a specific personalization hook, one low-friction CTA, a quantified value prop, and an in-market signal, kept under 120 words.", "ground_truth_invocations": [{"tool_name": "CoachingSpecialist", "tool_input": "Improve: Circling back. Are you the right person? Please advise."}], "intent": "coach_email", "process": "single_tool"}'),
-- 9-10. compound / multi_tool -> two specialists -----------------------------
('Score email 2, then tell me which region has the highest win rate.',
 '{"ground_truth_output": "Two-part answer: (1) the buyer-intent score for email id 2, and (2) the region with the highest win rate. Requires calling both the scoring and recommendation specialists.", "ground_truth_invocations": [{"tool_name": "ScoringSpecialist", "tool_input": "Score the buyer intent of email 2"}, {"tool_name": "RecommendationSpecialist", "tool_input": "Which region has the highest win rate?"}], "intent": "score_and_recommend", "process": "multi_tool"}'),
('Which quality tier wins the most, and rewrite this weak email to match: "Following up again since I have not heard back."',
 '{"ground_truth_output": "Two-part answer: (1) the quality tier with the highest win rate from the metrics, and (2) a framework-compliant rewrite of the supplied weak email. Requires the recommendation and coaching specialists.", "ground_truth_invocations": [{"tool_name": "RecommendationSpecialist", "tool_input": "Which quality tier has the highest win rate?"}, {"tool_name": "CoachingSpecialist", "tool_input": "Rewrite: Following up again since I have not heard back."}], "intent": "recommend_and_coach", "process": "multi_tool"}'),
-- 11-12. out_of_scope / refusal -> NO tool -----------------------------------
('What is the weather forecast for New York City this weekend?',
 '{"ground_truth_output": "The agent should politely decline. Weather is out of scope; it should explain it can only help with GTM sales-email scoring, performance recommendations, and coaching. It must NOT call any specialist tool.", "ground_truth_invocations": [], "intent": "out_of_scope", "process": "refusal"}'),
('Who are our top competitors and what is their pricing?',
 '{"ground_truth_output": "The agent should decline gracefully. Competitor intelligence and pricing are not in the governed GTM data; it should redirect to what it can do (scoring, recommendations, coaching). It must NOT call any specialist tool.", "ground_truth_invocations": [], "intent": "out_of_scope", "process": "refusal"}');

-- Rollup of eval scores per run x metric — powers the Streamlit Eval Dashboard and
-- the scheduled regression check without re-reading GET_AI_EVALUATION_DATA live.
CREATE TABLE IF NOT EXISTS EVAL_SCORE_HISTORY (
    run_name       STRING,
    run_ts         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    metric_name    STRING,
    avg_score      FLOAT,
    min_score      FLOAT,
    max_score      FLOAT,
    num_records    NUMBER
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. GRANTS  (least-privilege: role gets USAGE/SELECT on each tool object)
-- ─────────────────────────────────────────────────────────────────────────────
GRANT SELECT ON ALL TABLES IN SCHEMA GTMAGENTS.DEMO   TO ROLE GTMAGENTS_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA GTMAGENTS.DEMO TO ROLE GTMAGENTS_ROLE;
GRANT INSERT ON TABLE REQUEST_LOG      TO ROLE GTMAGENTS_ROLE;
GRANT INSERT ON TABLE ROUTING_LOG      TO ROLE GTMAGENTS_ROLE;
GRANT INSERT ON TABLE COST_COMPARISON  TO ROLE GTMAGENTS_ROLE;
GRANT SELECT ON TABLE AGENT_EVAL_QUESTIONS TO ROLE GTMAGENTS_ROLE;
GRANT INSERT, SELECT ON TABLE EVAL_SCORE_HISTORY TO ROLE GTMAGENTS_ROLE;
GRANT READ, WRITE ON STAGE EVAL_STAGE  TO ROLE GTMAGENTS_ROLE;
GRANT SELECT ON SEMANTIC VIEW EMAIL_GTM_SV        TO ROLE GTMAGENTS_ROLE;
GRANT USAGE  ON CORTEX SEARCH SERVICE FRAMEWORK_SEARCH TO ROLE GTMAGENTS_ROLE;
GRANT USAGE  ON FUNCTION GTM_TEAM_PERFORMANCE(STRING)  TO ROLE GTMAGENTS_ROLE;

-- ─────────────────────────────────────────────────────────────────────────────
-- Setup complete. Next:
--   1) lab/gtm-01-foundation.ipynb   (tour data + Cortex Analyst)
--   2) lab/gtm-02-before-mcp.ipynb   (MCP server + OAuth + Claude connect)
--   3) lab/gtm-03-after-agents.ipynb (multi-agent supervisor + AI_FILTER)
--   4) lab/gtm-04-evals.ipynb        (native agent evaluation of GTM_SUPERVISOR)
--   5) app/streamlit_app.py          (observability + comparison — Parts D & E)
--
-- Internal QA (not client-facing): lab/tests/checkpoints.ipynb runs the PASS/FAIL
-- checkpoints for all four notebooks after they've been executed.
-- ─────────────────────────────────────────────────────────────────────────────
