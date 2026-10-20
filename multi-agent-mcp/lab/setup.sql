-- =============================================================================
-- setup.sql  (run with a role that can USE ROLE ACCOUNTADMIN; ./demo.sh setup runs it)
-- Multi-agent orchestration over MCP: the governed stack behind the front door.
--
-- Builds, in order: account-level objects (Part 1, ACCOUNTADMIN), then as
-- MULTI_AGENT_MCP_DEMO_ADMIN the synthetic data, two semantic views, a fail-
-- closed row access policy, two caller's-rights bridge procedures, three agents
-- (SALES_AGENT, SUPPORT_AGENT, ORCHESTRATOR_AGENT) and the persona grants.
--
-- The lab notebook then exposes this stack through Snowflake-managed MCP servers,
-- adds the agent-toolset alternative, and evaluates both. Persona key pairs and
-- the host-model PAT are issued by ./demo.sh setup, not here.
--
-- Idempotent: safe to re-run end to end. Teardown: lab/cleanup.sql.
-- =============================================================================


-- =============================================================================
-- Part 1: account-level objects  (as ACCOUNTADMIN)
-- Multi-agent orchestration: account-scoped setup.
--
-- Creates the demo database, warehouse, an admin role that owns the demo
-- objects, three persona roles, and three persona service users. These are the
-- only statements in setup.sql that need ACCOUNTADMIN. Everything after this
-- part runs as MULTI_AGENT_MCP_DEMO_ADMIN.
--
-- The persona users are TYPE = SERVICE with no password and no key, so nobody
-- can sign in as them until you attach a key pair (./demo.sh setup does).
-- They exist because Cortex Agents authorize a run against the calling user's
-- DEFAULT role, so the persona boundary is only testable as a user whose
-- default role is the persona role.
--
-- Idempotent.
-- =============================================================================


SET demo_db    = 'MULTI_AGENT_MCP_DEMO';
SET demo_wh    = 'MULTI_AGENT_MCP_DEMO_WH';
SET admin_role     = 'MULTI_AGENT_MCP_DEMO_ADMIN';
SET sales_global   = 'MULTI_AGENT_MCP_DEMO_SALES_GLOBAL';
SET sales_emea     = 'MULTI_AGENT_MCP_DEMO_SALES_EMEA';
SET support_role   = 'MULTI_AGENT_MCP_DEMO_SUPPORT';
SET sales_global_u = 'MULTI_AGENT_MCP_DEMO_SALES_GLOBAL_USER';
SET sales_emea_u   = 'MULTI_AGENT_MCP_DEMO_SALES_EMEA_USER';
SET support_u      = 'MULTI_AGENT_MCP_DEMO_SUPPORT_USER';
SET my_user        = '"' || CURRENT_USER() || '"';

USE ROLE ACCOUNTADMIN;

-- ---------------------------------------------------------------------------
-- Admin role: owns every demo object. Granted to you so you can run parts 2-7.
-- ---------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS IDENTIFIER($admin_role)
  COMMENT = 'Multi-agent MCP demo: owns the demo objects.';
GRANT ROLE IDENTIFIER($admin_role) TO USER IDENTIFIER($my_user);
-- In the SYSADMIN hierarchy, so ACCOUNTADMIN can always manage and drop what it owns.
GRANT ROLE IDENTIFIER($admin_role) TO ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS IDENTIFIER($demo_wh)
  WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Multi-agent MCP demo warehouse.';
GRANT OWNERSHIP ON WAREHOUSE IDENTIFIER($demo_wh) TO ROLE IDENTIFIER($admin_role) COPY CURRENT GRANTS;

CREATE DATABASE IF NOT EXISTS IDENTIFIER($demo_db)
  COMMENT = 'Multi-agent MCP demo.';
GRANT OWNERSHIP ON DATABASE IDENTIFIER($demo_db) TO ROLE IDENTIFIER($admin_role) COPY CURRENT GRANTS;

GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE IDENTIFIER($admin_role);
-- Agent evaluations (lab notebook) run on serverless tasks.
GRANT EXECUTE TASK ON ACCOUNT TO ROLE IDENTIFIER($admin_role);

-- ---------------------------------------------------------------------------
-- Persona roles. Granted to the admin role so it can manage their grants.
-- ---------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS IDENTIFIER($sales_global)
  COMMENT = 'Persona: global sales exec. Reaches the sales specialist, all theaters.';
CREATE ROLE IF NOT EXISTS IDENTIFIER($sales_emea)
  COMMENT = 'Persona: EMEA seller. Reaches the sales specialist, EMEA rows only.';
CREATE ROLE IF NOT EXISTS IDENTIFIER($support_role)
  COMMENT = 'Persona: support rep. Reaches the support specialist only.';

GRANT ROLE IDENTIFIER($sales_global) TO ROLE IDENTIFIER($admin_role);
GRANT ROLE IDENTIFIER($sales_emea)   TO ROLE IDENTIFIER($admin_role);
GRANT ROLE IDENTIFIER($support_role) TO ROLE IDENTIFIER($admin_role);

GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE IDENTIFIER($sales_global);
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE IDENTIFIER($sales_emea);
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE IDENTIFIER($support_role);

-- ---------------------------------------------------------------------------
-- Persona users. DEFAULT_ROLE and DEFAULT_WAREHOUSE are load-bearing: agent
-- runs authorize against the default role, and fail without a default
-- warehouse the default role can use. DEFAULT_SECONDARY_ROLES = () keeps the
-- session to exactly one role, so the row access policy sees one role.
-- ---------------------------------------------------------------------------
CREATE USER IF NOT EXISTS IDENTIFIER($sales_global_u) TYPE = SERVICE
  COMMENT = 'Persona: global sales exec.';
CREATE USER IF NOT EXISTS IDENTIFIER($sales_emea_u) TYPE = SERVICE
  COMMENT = 'Persona: EMEA seller.';
CREATE USER IF NOT EXISTS IDENTIFIER($support_u) TYPE = SERVICE
  COMMENT = 'Persona: support rep.';

-- Re-assert on every run: CREATE USER IF NOT EXISTS does not update an existing user.
ALTER USER IDENTIFIER($sales_global_u) SET DEFAULT_ROLE = $sales_global DEFAULT_WAREHOUSE = $demo_wh DEFAULT_SECONDARY_ROLES = ();
ALTER USER IDENTIFIER($sales_emea_u)   SET DEFAULT_ROLE = $sales_emea   DEFAULT_WAREHOUSE = $demo_wh DEFAULT_SECONDARY_ROLES = ();
ALTER USER IDENTIFIER($support_u)      SET DEFAULT_ROLE = $support_role DEFAULT_WAREHOUSE = $demo_wh DEFAULT_SECONDARY_ROLES = ();

GRANT ROLE IDENTIFIER($sales_global) TO USER IDENTIFIER($sales_global_u);
GRANT ROLE IDENTIFIER($sales_emea)   TO USER IDENTIFIER($sales_emea_u);
GRANT ROLE IDENTIFIER($support_role) TO USER IDENTIFIER($support_u);

SHOW USERS LIKE 'MULTI_AGENT_MCP_DEMO%';


-- =============================================================================
-- Part 2: schema and synthetic data  (as MULTI_AGENT_MCP_DEMO_ADMIN)
-- Schema, sample data for the two specialist domains.
--
-- SALES_BOOKINGS is stored at a single grain (one row per territory per fiscal
-- quarter), so SUM and AVG are always correct and no row is a pre-aggregated
-- roll-up. If a real table mixes grains, model each grain separately before
-- you point an agent at it.
--
-- All data is synthetic. Idempotent: CREATE TABLE IF NOT EXISTS plus INSERT
-- OVERWRITE keeps grants and the row access policy attachment on re-runs.
-- =============================================================================


SET demo_db     = 'MULTI_AGENT_MCP_DEMO';
SET demo_schema = 'MULTI_AGENT_MCP_DEMO.APP';
SET demo_wh     = 'MULTI_AGENT_MCP_DEMO_WH';
SET admin_role      = 'MULTI_AGENT_MCP_DEMO_ADMIN';

USE ROLE IDENTIFIER($admin_role);
USE WAREHOUSE IDENTIFIER($demo_wh);
USE DATABASE IDENTIFIER($demo_db);

CREATE SCHEMA IF NOT EXISTS IDENTIFIER($demo_schema)
  COMMENT = 'Multi-agent MCP demo objects.';
USE SCHEMA IDENTIFIER($demo_schema);

-- ---------------------------------------------------------------------------
-- Sales domain: one row per territory per fiscal quarter. Values in USD millions.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS SALES_BOOKINGS (
  FISCAL_QUARTER     VARCHAR(10)   NOT NULL,
  THEATER            VARCHAR(20)   NOT NULL,
  TERRITORY          VARCHAR(40)   NOT NULL,
  NEW_BOOKINGS_USD_M NUMBER(10, 2) NOT NULL,
  TARGET_USD_M       NUMBER(10, 2) NOT NULL,
  PIPELINE_USD_M     NUMBER(10, 2) NOT NULL
)
COMMENT = 'Northwind Software sales bookings (synthetic). One row per territory per fiscal quarter.';

INSERT OVERWRITE INTO SALES_BOOKINGS
WITH quarters AS (
  SELECT * FROM VALUES ('FY25-Q1', 1.00), ('FY25-Q2', 1.05), ('FY25-Q3', 1.10), ('FY25-Q4', 1.20)
    AS q(fiscal_quarter, growth)
),
territories AS (
  SELECT * FROM VALUES
    ('Americas', 'West',          20.0, 0.97),
    ('Americas', 'East',          16.0, 1.04),
    ('Americas', 'Central',        9.0, 0.91),
    ('Americas', 'LATAM',          5.0, 1.08),
    ('EMEA',     'UK and Ireland', 12.0, 1.02),
    ('EMEA',     'DACH',          10.0, 0.94),
    ('EMEA',     'France',         6.0, 1.06),
    ('EMEA',     'Nordics',        4.0, 0.99),
    ('APAC',     'ANZ',            7.0, 1.03),
    ('APAC',     'Japan',          6.0, 0.95),
    ('APAC',     'Southeast Asia', 5.0, 1.10)
    AS t(theater, territory, base_target, attainment)
)
SELECT
  q.fiscal_quarter,
  t.theater,
  t.territory,
  ROUND(t.base_target * q.growth * t.attainment, 2) AS new_bookings_usd_m,
  ROUND(t.base_target * q.growth, 2)                AS target_usd_m,
  ROUND(t.base_target * q.growth * 3.0, 2)          AS pipeline_usd_m
FROM quarters q CROSS JOIN territories t;

-- ---------------------------------------------------------------------------
-- Support domain: product knowledge base articles.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS SUPPORT_KB (
  ARTICLE_ID VARCHAR(10) NOT NULL,
  TITLE      VARCHAR     NOT NULL,
  CATEGORY   VARCHAR(40) NOT NULL,
  CONTENT    VARCHAR     NOT NULL
)
COMMENT = 'Northwind Software support knowledge base (synthetic).';

INSERT OVERWRITE INTO SUPPORT_KB VALUES
  ('KB-001', 'Set up single sign-on with SAML 2.0', 'Authentication',
   'Go to Settings > Security > SSO, choose your identity provider, and paste its metadata URL. Map the SAML NameID to the user email attribute. Test with one admin account before you enable "Require SSO for all members", to avoid locking everyone out.'),
  ('KB-002', 'Generate and use API tokens', 'API',
   'Create a token under Settings > Developer > API Tokens. Tokens are scoped (read, write, admin) and expire after 90 days. Send the token in the Authorization header as "Bearer <token>". Revoking a token invalidates it immediately.'),
  ('KB-003', 'Troubleshoot 401 and 403 API errors', 'API',
   'A 401 means authentication failed: check the Authorization header format, and confirm the token has not expired or been revoked. A 403 means the token is valid but lacks the scope for that endpoint: create a token with the right scope. Rate-limited requests return 429, not 401.'),
  ('KB-004', 'Understand your invoice and seat count', 'Billing',
   'Invoices are generated monthly from the active seats on the billing date. A seat is any member with a non-Viewer role. Moving a member to Viewer reduces billed seats from the next cycle.'),
  ('KB-005', 'Schedule a recurring data export', 'Data management',
   'Use Settings > Data > Scheduled Exports to deliver CSV or JSON files daily or weekly to a cloud storage bucket. Exports respect the requesting member role: Viewers export only the data they can see.'),
  ('KB-006', 'Reset a password', 'Authentication',
   'Use "Forgot password" on the sign-in page to receive a reset link, valid for 60 minutes. If SSO is enforced, password reset is disabled and you recover access through your identity provider.'),
  ('KB-007', 'Why a dashboard loads slowly', 'Performance',
   'Slow dashboards are usually caused by very wide date ranges or unfiltered high-cardinality views. Narrow the date range, add filters, and keep a single view under 50,000 rows. Use scheduled reports for large extracts.'),
  ('KB-008', 'Review audit logs', 'Administration',
   'Admins see sign-ins, permission changes, exports, and token activity under Settings > Security > Audit Log. Logs are retained for 90 days, or one year on the Enterprise plan.');

SELECT THEATER, COUNT(*) AS ROWS_LOADED, SUM(NEW_BOOKINGS_USD_M) AS BOOKINGS_USD_M
FROM SALES_BOOKINGS GROUP BY THEATER ORDER BY THEATER;


-- =============================================================================
-- Part 3: one semantic view per specialist  (as MULTI_AGENT_MCP_DEMO_ADMIN)
-- One semantic view per specialist. Each specialist agent gets a Cortex Analyst
-- tool over exactly one of these, which keeps each domain's context small.
--
-- CREATE OR ALTER keeps grants on re-runs.
-- Names inside the DDL are literals. Object names are fixed; do not rename them.
-- =============================================================================


SET demo_schema = 'MULTI_AGENT_MCP_DEMO.APP';
SET demo_wh     = 'MULTI_AGENT_MCP_DEMO_WH';
SET admin_role      = 'MULTI_AGENT_MCP_DEMO_ADMIN';

USE ROLE IDENTIFIER($admin_role);
USE WAREHOUSE IDENTIFIER($demo_wh);
USE SCHEMA IDENTIFIER($demo_schema);

CREATE OR ALTER SEMANTIC VIEW SALES_SEMANTIC_VIEW
  TABLES (
    bookings AS MULTI_AGENT_MCP_DEMO.APP.SALES_BOOKINGS
      PRIMARY KEY (FISCAL_QUARTER, TERRITORY)
      COMMENT = 'One row per sales territory per fiscal quarter. Values are in USD millions.'
  )
  FACTS (
    bookings.new_bookings AS NEW_BOOKINGS_USD_M
      COMMENT = 'New bookings for the territory and quarter, USD millions.',
    bookings.target AS TARGET_USD_M
      COMMENT = 'Bookings target for the territory and quarter, USD millions.',
    bookings.pipeline AS PIPELINE_USD_M
      COMMENT = 'Open pipeline for the territory and quarter, USD millions.'
  )
  DIMENSIONS (
    bookings.fiscal_quarter AS FISCAL_QUARTER
      WITH SYNONYMS = ('quarter', 'fiscal period')
      COMMENT = 'Fiscal quarter, FY25-Q1 through FY25-Q4.',
    bookings.theater AS THEATER
      WITH SYNONYMS = ('region', 'geo')
      COMMENT = 'Sales theater: Americas, EMEA, or APAC.',
    bookings.territory AS TERRITORY
      COMMENT = 'Sales territory within a theater.'
  )
  METRICS (
    bookings.total_new_bookings AS SUM(bookings.new_bookings)
      WITH SYNONYMS = ('bookings', 'new bookings')
      COMMENT = 'Total new bookings, USD millions.',
    bookings.total_target AS SUM(bookings.target)
      COMMENT = 'Total bookings target, USD millions.',
    bookings.total_pipeline AS SUM(bookings.pipeline)
      COMMENT = 'Total open pipeline, USD millions.',
    bookings.attainment_pct AS ROUND(100 * SUM(bookings.new_bookings) / NULLIF(SUM(bookings.target), 0), 1)
      WITH SYNONYMS = ('attainment', 'percent of target')
      COMMENT = 'New bookings as a percentage of target.'
  )
  COMMENT = 'Northwind Software sales bookings, pipeline, and targets by quarter, theater, and territory.';

CREATE OR ALTER SEMANTIC VIEW SUPPORT_SEMANTIC_VIEW
  TABLES (
    kb AS MULTI_AGENT_MCP_DEMO.APP.SUPPORT_KB
      PRIMARY KEY (ARTICLE_ID)
      COMMENT = 'One row per support knowledge base article.'
  )
  DIMENSIONS (
    kb.article_id AS ARTICLE_ID
      COMMENT = 'Article identifier, for example KB-003.',
    kb.title AS TITLE
      COMMENT = 'Article title.',
    kb.category AS CATEGORY
      COMMENT = 'Article category: Authentication, API, Billing, Data management, Performance, Administration.',
    kb.content AS CONTENT
      WITH SYNONYMS = ('instructions', 'steps', 'article body')
      COMMENT = 'Full article text with the step-by-step answer.'
  )
  METRICS (
    kb.article_count AS COUNT(kb.article_id)
      COMMENT = 'Number of articles.'
  )
  COMMENT = 'Northwind Software support knowledge base. Answer how-to questions from CONTENT.';

SHOW SEMANTIC VIEWS IN SCHEMA IDENTIFIER($demo_schema);


-- =============================================================================
-- Part 4: row access policy on SALES_BOOKINGS  (as MULTI_AGENT_MCP_DEMO_ADMIN)
-- One fail-closed row access policy on SALES_BOOKINGS.
--
-- Two questions, two mechanisms:
--   * Which specialist can a persona reach?   -> USAGE grants on the agents (part 7)
--   * Which rows does the sales specialist return for that persona? -> this part
--
-- The policy looks the caller's role up in SALES_ENTITLEMENTS. A role with no
-- row sees no rows (fail closed). 'ALL' grants every theater. The table has
-- exactly one row access policy: re-runs update the body in place and never
-- attach a second policy.
--
-- Why CURRENT_ROLE(): an agent run executes tool queries under one primary
-- role (the user's default role, or the X-Snowflake-Role override on REST).
-- Keying on the primary role means the answer depends on that single role and
-- not on whatever secondary roles the user happens to hold.
-- =============================================================================


SET demo_schema = 'MULTI_AGENT_MCP_DEMO.APP';
SET demo_wh     = 'MULTI_AGENT_MCP_DEMO_WH';
SET admin_role      = 'MULTI_AGENT_MCP_DEMO_ADMIN';

USE ROLE IDENTIFIER($admin_role);
USE WAREHOUSE IDENTIFIER($demo_wh);
USE SCHEMA IDENTIFIER($demo_schema);

-- Entitlements: role -> theater. Maintained by the data owner, not by the app.
CREATE TABLE IF NOT EXISTS SALES_ENTITLEMENTS (
  ROLE_NAME VARCHAR NOT NULL,
  THEATER   VARCHAR NOT NULL   -- a THEATER value, or 'ALL'
)
COMMENT = 'Row access entitlements for SALES_BOOKINGS. No row for a role = no data.';

INSERT OVERWRITE INTO SALES_ENTITLEMENTS VALUES
  ('MULTI_AGENT_MCP_DEMO_ADMIN',        'ALL'),
  ('MULTI_AGENT_MCP_DEMO_SALES_GLOBAL', 'ALL'),
  ('MULTI_AGENT_MCP_DEMO_SALES_EMEA',   'EMEA');

-- Create once, then keep the body current. ALTER ... SET BODY works while the
-- policy is attached, so no detach/re-attach cycle is needed on re-runs.
CREATE ROW ACCESS POLICY IF NOT EXISTS SALES_THEATER_POLICY
  AS (theater_col VARCHAR) RETURNS BOOLEAN -> FALSE
  COMMENT = 'Fail closed: rows are visible only for theaters entitled to CURRENT_ROLE().';

ALTER ROW ACCESS POLICY SALES_THEATER_POLICY SET BODY ->
  EXISTS (
    SELECT 1
    FROM MULTI_AGENT_MCP_DEMO.APP.SALES_ENTITLEMENTS e
    WHERE e.ROLE_NAME = CURRENT_ROLE()
      AND (e.THEATER = 'ALL' OR e.THEATER = theater_col)
  );

-- Exactly one policy on the table: drop whatever is attached, then attach ours.
ALTER TABLE SALES_BOOKINGS DROP ALL ROW ACCESS POLICIES;
ALTER TABLE SALES_BOOKINGS ADD ROW ACCESS POLICY SALES_THEATER_POLICY ON (THEATER);

-- Verify with POLICY_CONTEXT, which evaluates the policy as if another role
-- were current. Expect 44 (admin), 16 EMEA rows (EMEA seller), 0 (support,
-- which has no entitlement row).
SELECT 'admin' AS context, COUNT(*) AS rows_visible FROM SALES_BOOKINGS;
EXECUTE USING POLICY_CONTEXT(CURRENT_ROLE => 'MULTI_AGENT_MCP_DEMO_SALES_EMEA')
  AS SELECT 'sales_emea' AS context, THEATER, COUNT(*) AS rows_visible FROM SALES_BOOKINGS GROUP BY THEATER;
EXECUTE USING POLICY_CONTEXT(CURRENT_ROLE => 'MULTI_AGENT_MCP_DEMO_SUPPORT')
  AS SELECT 'support (unmapped)' AS context, COUNT(*) AS rows_visible FROM SALES_BOOKINGS;


-- =============================================================================
-- Part 5: caller's-rights bridges  (as MULTI_AGENT_MCP_DEMO_ADMIN)
-- Delegation bridges: the orchestrator's "call a specialist" tools.
--
-- Cortex Agents have no tool type that runs another agent. Delegation is a
-- generic (custom) tool backed by a procedure that calls DATA_AGENT_RUN on the
-- specialist. (agent_toolset is different: it copies another agent's tools
-- into the caller, so the specialist's own instructions never run.)
--
-- EXECUTE AS CALLER is the security property of this demo. The nested
-- DATA_AGENT_RUN is authorized against the caller's role, so a persona without
-- USAGE on a specialist is denied by Snowflake, not by a prompt. Under
-- EXECUTE AS OWNER every caller would get the specialist's answer with the
-- owner's privileges, and the row access policy would evaluate the owner role.
--
-- The user's question is passed to DATA_AGENT_RUN as a bind parameter inside
-- a JSON body built with json.dumps. Nothing is concatenated into SQL.
--
-- DATA_AGENT_RUN returns an error payload rather than raising, so each handler
-- inspects the parsed response and turns an authorization error into a fixed
-- NOT_ENTITLED marker the orchestrator is instructed to relay.
--
-- Names inside the $$ bodies are literals. Object names are fixed; do not
-- rename them.
-- =============================================================================


SET demo_schema = 'MULTI_AGENT_MCP_DEMO.APP';
SET demo_wh     = 'MULTI_AGENT_MCP_DEMO_WH';
SET admin_role      = 'MULTI_AGENT_MCP_DEMO_ADMIN';

USE ROLE IDENTIFIER($admin_role);
USE WAREHOUSE IDENTIFIER($demo_wh);
USE SCHEMA IDENTIFIER($demo_schema);

CREATE OR REPLACE PROCEDURE ASK_SALES_SPECIALIST(USER_QUERY VARCHAR)
  COPY GRANTS
  RETURNS VARCHAR
  LANGUAGE PYTHON
  RUNTIME_VERSION = '3.11'
  PACKAGES = ('snowflake-snowpark-python')
  HANDLER = 'run'
  COMMENT = 'Delegates a question to SALES_AGENT with the caller''s rights.'
  EXECUTE AS CALLER
AS
$$
import json

SUB_AGENT = 'MULTI_AGENT_MCP_DEMO.APP.SALES_AGENT'
NOT_ENTITLED = ("NOT_ENTITLED: the user is not authorized for the sales specialist. "
                "Tell them this type of question is not available at their access level.")
# 399513: the agent does not exist or the current role is not authorized for it.
DENIED_CODES = {'399513'}
MAX_QUERY_CHARS = 4000


def _md_table(tbl):
    """Render a Cortex Analyst 'table' content block as markdown, so numbers survive the hop."""
    rs = tbl.get('result_set', {})
    cols = [c.get('name', '') for c in rs.get('resultSetMetaData', {}).get('rowType', [])]
    rows = rs.get('data', [])
    if not cols or not rows:
        return ''
    out = ['| ' + ' | '.join(cols) + ' |', '| ' + ' | '.join(['---'] * len(cols)) + ' |']
    out += ['| ' + ' | '.join('' if v is None else str(v) for v in r) + ' |' for r in rows]
    return '\n'.join(out)


def run(session, user_query):
    if not user_query or not user_query.strip():
        return '[empty question]'
    body = json.dumps({"messages": [{"role": "user",
                                     "content": [{"type": "text", "text": user_query[:MAX_QUERY_CHARS]}]}]})
    try:
        rows = session.sql("SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(?, ?) AS RESP",
                           params=[SUB_AGENT, body]).collect()
    except Exception as e:
        if any(code in str(e) for code in DENIED_CODES):
            return NOT_ENTITLED
        return '[sales specialist call failed]'
    try:
        resp = json.loads(rows[0]['RESP'])
    except (IndexError, TypeError, ValueError):
        return '[no response from sales specialist]'
    if resp.get('code'):
        return NOT_ENTITLED if str(resp['code']) in DENIED_CODES else '[sales specialist call failed]'
    content = resp.get('content', [])
    texts = [b.get('text', '') for b in content if b.get('type') == 'text']
    tables = [_md_table(b['table']) for b in content if b.get('type') == 'table' and b.get('table')]
    parts = ['\n'.join(texts).strip()] + [t for t in tables if t]
    answer = '\n\n'.join(p for p in parts if p)
    return answer or '[no text in sales specialist response]'
$$;

CREATE OR REPLACE PROCEDURE ASK_SUPPORT_SPECIALIST(USER_QUERY VARCHAR)
  COPY GRANTS
  RETURNS VARCHAR
  LANGUAGE PYTHON
  RUNTIME_VERSION = '3.11'
  PACKAGES = ('snowflake-snowpark-python')
  HANDLER = 'run'
  COMMENT = 'Delegates a question to SUPPORT_AGENT with the caller''s rights.'
  EXECUTE AS CALLER
AS
$$
import json

SUB_AGENT = 'MULTI_AGENT_MCP_DEMO.APP.SUPPORT_AGENT'
NOT_ENTITLED = ("NOT_ENTITLED: the user is not authorized for the support specialist. "
                "Tell them this type of question is not available at their access level.")
DENIED_CODES = {'399513'}
MAX_QUERY_CHARS = 4000


def run(session, user_query):
    if not user_query or not user_query.strip():
        return '[empty question]'
    body = json.dumps({"messages": [{"role": "user",
                                     "content": [{"type": "text", "text": user_query[:MAX_QUERY_CHARS]}]}]})
    try:
        rows = session.sql("SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(?, ?) AS RESP",
                           params=[SUB_AGENT, body]).collect()
    except Exception as e:
        if any(code in str(e) for code in DENIED_CODES):
            return NOT_ENTITLED
        return '[support specialist call failed]'
    try:
        resp = json.loads(rows[0]['RESP'])
    except (IndexError, TypeError, ValueError):
        return '[no response from support specialist]'
    if resp.get('code'):
        return NOT_ENTITLED if str(resp['code']) in DENIED_CODES else '[support specialist call failed]'
    texts = [b.get('text', '') for b in resp.get('content', []) if b.get('type') == 'text']
    return '\n'.join(texts).strip() or '[no text in support specialist response]'
$$;

SHOW PROCEDURES LIKE 'ASK_%' IN SCHEMA IDENTIFIER($demo_schema);


-- =============================================================================
-- Part 6: specialist and orchestrator agents  (as MULTI_AGENT_MCP_DEMO_ADMIN)
-- Two specialists and one orchestrator.
--
--   SALES_AGENT        Cortex Analyst over SALES_SEMANTIC_VIEW
--   SUPPORT_AGENT      Cortex Analyst over SUPPORT_SEMANTIC_VIEW
--   ORCHESTRATOR_AGENT generic tools -> ASK_*_SPECIALIST bridges (part 5)
--
-- The orchestrator's specification is identical for every persona. What each
-- persona can reach is decided by the grants in part 7, evaluated on every nested
-- run. The orchestrator's instructions choose a specialist; they are not an
-- access control.
--
-- CREATE OR REPLACE ... COPY GRANTS keeps existing grants on re-runs. Put COPY
-- GRANTS directly before FROM SPECIFICATION; placed before COMMENT or PROFILE
-- it is a syntax error. This differs from the published CREATE AGENT syntax,
-- which lists COPY GRANTS first (CREATE OR REPLACE AGENT ... COPY GRANTS).
-- The orchestration model is pinned (not auto) so evaluation runs compare the
-- same configuration; change it here if claude-sonnet-4-6 is not available to
-- you. Names inside the $$ bodies are literals. Object names are fixed; do not
-- rename them.
-- =============================================================================


SET demo_schema = 'MULTI_AGENT_MCP_DEMO.APP';
SET demo_wh     = 'MULTI_AGENT_MCP_DEMO_WH';
SET admin_role      = 'MULTI_AGENT_MCP_DEMO_ADMIN';

USE ROLE IDENTIFIER($admin_role);
USE WAREHOUSE IDENTIFIER($demo_wh);
USE SCHEMA IDENTIFIER($demo_schema);

-- ── Specialist 1: sales ─────────────────────────────────────────────────────
CREATE OR REPLACE AGENT SALES_AGENT
  COMMENT = 'Sales specialist: bookings, pipeline, and targets via Cortex Analyst.'
  PROFILE = '{"display_name": "Sales Specialist"}'
  COPY GRANTS
  FROM SPECIFICATION
$$
models:
  orchestration: claude-sonnet-4-6
orchestration:
  budget:
    seconds: 180
    tokens: 60000
instructions:
  orchestration: >-
    Use sales_analyst for every question about new bookings, targets, attainment,
    or pipeline by fiscal quarter, theater, or territory. Always state the fiscal
    quarter and theater you answered for.
  response: >-
    Lead with the number. Values are in USD millions; format as $X.XM.
    Keep markdown tables intact.
  sample_questions:
    - question: "What were total new bookings in FY25-Q4 by theater?"
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: sales_analyst
      description: >-
        Sales bookings, targets, attainment, and pipeline by fiscal quarter
        (FY25-Q1 to FY25-Q4), theater (Americas, EMEA, APAC), and territory.
tool_resources:
  sales_analyst:
    semantic_view: MULTI_AGENT_MCP_DEMO.APP.SALES_SEMANTIC_VIEW
    execution_environment:
      type: warehouse
      warehouse: MULTI_AGENT_MCP_DEMO_WH
      query_timeout: 120
$$;

-- ── Specialist 2: support ───────────────────────────────────────────────────
CREATE OR REPLACE AGENT SUPPORT_AGENT
  COMMENT = 'Support specialist: answers product how-to questions from the knowledge base.'
  PROFILE = '{"display_name": "Support Specialist"}'
  COPY GRANTS
  FROM SPECIFICATION
$$
models:
  orchestration: claude-sonnet-4-6
orchestration:
  budget:
    seconds: 120
    tokens: 40000
instructions:
  orchestration: >-
    Use support_kb for every question. Retrieve the CONTENT of the relevant
    article and answer from it.
  response: >-
    Answer step by step and cite the article ID you used, for example KB-003.
  sample_questions:
    - question: "How do I set up single sign-on?"
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: support_kb
      description: >-
        Support knowledge base articles: SSO, passwords, API tokens and 401/403
        errors, billing and seats, scheduled exports, dashboard performance,
        audit logs. Returns article IDs, titles, categories, and content.
tool_resources:
  support_kb:
    semantic_view: MULTI_AGENT_MCP_DEMO.APP.SUPPORT_SEMANTIC_VIEW
    execution_environment:
      type: warehouse
      warehouse: MULTI_AGENT_MCP_DEMO_WH
      query_timeout: 120
$$;

-- ── Orchestrator ────────────────────────────────────────────────────────────
CREATE OR REPLACE AGENT ORCHESTRATOR_AGENT
  COMMENT = 'Single entry point that delegates to the sales and support specialists through caller''s-rights bridges.'
  PROFILE = '{"display_name": "Northwind Assistant"}'
  COPY GRANTS
  FROM SPECIFICATION
$$
models:
  orchestration: claude-sonnet-4-6
orchestration:
  budget:
    seconds: 600
    tokens: 100000
instructions:
  orchestration: |
    Delegate every question to a specialist. Do not answer from your own knowledge.
    - ask_sales: new bookings, targets, attainment, pipeline, fiscal quarters,
      theaters, territories.
    - ask_support: product how-to and troubleshooting: SSO, passwords, API tokens,
      401/403 errors, billing and seats, exports, dashboard performance, audit logs.
    If a question spans both domains, call both and answer each part under its own heading.
    When a follow-up refers to earlier turns ("break that down by territory"),
    rewrite it as a self-contained question before delegating, because the
    specialists do not see the conversation history.
    If a specialist returns text starting with "NOT_ENTITLED:", do not retry and do
    not call another specialist for that part. Reply: "This type of question is not
    available at your access level. Contact your administrator for access."
  response: |
    Return each specialist's answer faithfully, including markdown tables, without
    adding numbers of your own. No preamble.
  sample_questions:
    - question: "What were total new bookings in FY25-Q4 by theater?"
    - question: "How do I set up single sign-on?"
tools:
  - tool_spec:
      type: generic
      name: ask_sales
      description: >-
        Ask the sales specialist about new bookings, targets, attainment, and
        pipeline by fiscal quarter, theater, and territory. Not for product support.
      input_schema:
        type: object
        properties:
          user_query:
            type: string
            description: A self-contained sales question.
        required: [user_query]
  - tool_spec:
      type: generic
      name: ask_support
      description: >-
        Ask the support specialist a product how-to or troubleshooting question.
        Not for sales numbers.
      input_schema:
        type: object
        properties:
          user_query:
            type: string
            description: A self-contained support question.
        required: [user_query]
tool_resources:
  ask_sales:
    type: procedure
    identifier: MULTI_AGENT_MCP_DEMO.APP.ASK_SALES_SPECIALIST
    execution_environment:
      type: warehouse
      warehouse: MULTI_AGENT_MCP_DEMO_WH
  ask_support:
    type: procedure
    identifier: MULTI_AGENT_MCP_DEMO.APP.ASK_SUPPORT_SPECIALIST
    execution_environment:
      type: warehouse
      warehouse: MULTI_AGENT_MCP_DEMO_WH
$$;

SHOW AGENTS IN SCHEMA IDENTIFIER($demo_schema);


-- =============================================================================
-- Part 7: the persona boundary (grants)  (as MULTI_AGENT_MCP_DEMO_ADMIN)
-- The persona boundary. No prompt, no application code, and no model decision
-- participates in it.
--
--   Layer 1  USAGE on the orchestrator and on both bridges: every persona can
--            open the front door and call either bridge. Caller's-rights
--            bridges carry no authority of their own, so this grants nothing
--            beyond the ability to ask.
--   Layer 2  USAGE on a specialist agent: the nested DATA_AGENT_RUN is
--            authorized against the caller's role. No USAGE -> error 399513
--            -> the bridge returns NOT_ENTITLED.
--   Layer 3  SELECT on the specialist's semantic view AND its base table: the
--            specialist's Cortex Analyst tool runs its generated SQL against
--            the base table as the caller, so this holds even if layer 2 were
--            wrong. Without SELECT on the table the tool returns a compilation
--            error even though the semantic view grant is present.
--   Layer 4  The row access policy (part 4) filters rows inside the sales domain.
--
-- REVOKE statements make re-runs converge on exactly this set of grants.
-- For a full audit of who can reach which agent and tool, use the
-- check-agent-access skill in Cortex Code.
-- =============================================================================


SET demo_db     = 'MULTI_AGENT_MCP_DEMO';
SET demo_schema = 'MULTI_AGENT_MCP_DEMO.APP';
SET demo_wh     = 'MULTI_AGENT_MCP_DEMO_WH';
SET admin_role      = 'MULTI_AGENT_MCP_DEMO_ADMIN';
SET sales_global    = 'MULTI_AGENT_MCP_DEMO_SALES_GLOBAL';
SET sales_emea      = 'MULTI_AGENT_MCP_DEMO_SALES_EMEA';
SET support_role    = 'MULTI_AGENT_MCP_DEMO_SUPPORT';

USE ROLE IDENTIFIER($admin_role);
USE SCHEMA IDENTIFIER($demo_schema);

-- ── Shared plumbing and layer 1 (all three personas) ────────────────────────
GRANT USAGE ON DATABASE  IDENTIFIER($demo_db)     TO ROLE IDENTIFIER($sales_global);
GRANT USAGE ON DATABASE  IDENTIFIER($demo_db)     TO ROLE IDENTIFIER($sales_emea);
GRANT USAGE ON DATABASE  IDENTIFIER($demo_db)     TO ROLE IDENTIFIER($support_role);
GRANT USAGE ON SCHEMA    IDENTIFIER($demo_schema) TO ROLE IDENTIFIER($sales_global);
GRANT USAGE ON SCHEMA    IDENTIFIER($demo_schema) TO ROLE IDENTIFIER($sales_emea);
GRANT USAGE ON SCHEMA    IDENTIFIER($demo_schema) TO ROLE IDENTIFIER($support_role);
GRANT USAGE ON WAREHOUSE IDENTIFIER($demo_wh)     TO ROLE IDENTIFIER($sales_global);
GRANT USAGE ON WAREHOUSE IDENTIFIER($demo_wh)     TO ROLE IDENTIFIER($sales_emea);
GRANT USAGE ON WAREHOUSE IDENTIFIER($demo_wh)     TO ROLE IDENTIFIER($support_role);

GRANT USAGE ON AGENT ORCHESTRATOR_AGENT TO ROLE IDENTIFIER($sales_global);
GRANT USAGE ON AGENT ORCHESTRATOR_AGENT TO ROLE IDENTIFIER($sales_emea);
GRANT USAGE ON AGENT ORCHESTRATOR_AGENT TO ROLE IDENTIFIER($support_role);

GRANT USAGE ON PROCEDURE ASK_SALES_SPECIALIST(VARCHAR)   TO ROLE IDENTIFIER($sales_global);
GRANT USAGE ON PROCEDURE ASK_SALES_SPECIALIST(VARCHAR)   TO ROLE IDENTIFIER($sales_emea);
GRANT USAGE ON PROCEDURE ASK_SALES_SPECIALIST(VARCHAR)   TO ROLE IDENTIFIER($support_role);
GRANT USAGE ON PROCEDURE ASK_SUPPORT_SPECIALIST(VARCHAR) TO ROLE IDENTIFIER($sales_global);
GRANT USAGE ON PROCEDURE ASK_SUPPORT_SPECIALIST(VARCHAR) TO ROLE IDENTIFIER($sales_emea);
GRANT USAGE ON PROCEDURE ASK_SUPPORT_SPECIALIST(VARCHAR) TO ROLE IDENTIFIER($support_role);

-- ── Layers 2 and 3: sales personas reach sales only ─────────────────────────
GRANT USAGE  ON AGENT SALES_AGENT                   TO ROLE IDENTIFIER($sales_global);
GRANT USAGE  ON AGENT SALES_AGENT                   TO ROLE IDENTIFIER($sales_emea);
GRANT SELECT ON SEMANTIC VIEW SALES_SEMANTIC_VIEW   TO ROLE IDENTIFIER($sales_global);
GRANT SELECT ON SEMANTIC VIEW SALES_SEMANTIC_VIEW   TO ROLE IDENTIFIER($sales_emea);
GRANT SELECT ON TABLE SALES_BOOKINGS                TO ROLE IDENTIFIER($sales_global);
GRANT SELECT ON TABLE SALES_BOOKINGS                TO ROLE IDENTIFIER($sales_emea);
REVOKE USAGE  ON AGENT SUPPORT_AGENT                 FROM ROLE IDENTIFIER($sales_global);
REVOKE USAGE  ON AGENT SUPPORT_AGENT                 FROM ROLE IDENTIFIER($sales_emea);
REVOKE SELECT ON SEMANTIC VIEW SUPPORT_SEMANTIC_VIEW FROM ROLE IDENTIFIER($sales_global);
REVOKE SELECT ON SEMANTIC VIEW SUPPORT_SEMANTIC_VIEW FROM ROLE IDENTIFIER($sales_emea);
REVOKE SELECT ON TABLE SUPPORT_KB                    FROM ROLE IDENTIFIER($sales_global);
REVOKE SELECT ON TABLE SUPPORT_KB                    FROM ROLE IDENTIFIER($sales_emea);

-- ── Layers 2 and 3: support persona reaches support only ────────────────────
GRANT USAGE  ON AGENT SUPPORT_AGENT                 TO ROLE IDENTIFIER($support_role);
GRANT SELECT ON SEMANTIC VIEW SUPPORT_SEMANTIC_VIEW TO ROLE IDENTIFIER($support_role);
GRANT SELECT ON TABLE SUPPORT_KB                    TO ROLE IDENTIFIER($support_role);
REVOKE USAGE  ON AGENT SALES_AGENT                   FROM ROLE IDENTIFIER($support_role);
REVOKE SELECT ON SEMANTIC VIEW SALES_SEMANTIC_VIEW   FROM ROLE IDENTIFIER($support_role);
REVOKE SELECT ON TABLE SALES_BOOKINGS                FROM ROLE IDENTIFIER($support_role);

SHOW GRANTS TO ROLE IDENTIFIER($sales_emea);
SHOW GRANTS TO ROLE IDENTIFIER($support_role);
