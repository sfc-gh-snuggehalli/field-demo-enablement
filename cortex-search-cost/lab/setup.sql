-- =============================================================================
-- Cortex Search: BYO Embeddings & Cost Optimization — Lab Setup Script
-- =============================================================================
-- Run this script once before starting the notebook.
-- It creates the database, schema, warehouse, and structured metadata tables.
-- The DOCUMENT_CHUNKS table (with embeddings) is created by lab/data_gen.py.
-- The Cortex Search Service is created in the notebook.
--
-- Prerequisites:
-- * A role with CREATE DATABASE, CREATE WAREHOUSE privileges (e.g. SYSADMIN)
-- * The SNOWFLAKE.CORTEX_USER database role granted to your role
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. DATABASE AND SCHEMA
-- ---------------------------------------------------------------------------

CREATE DATABASE IF NOT EXISTS CORTEX_SEARCH_COST_DEMO;
USE DATABASE CORTEX_SEARCH_COST_DEMO;
CREATE SCHEMA IF NOT EXISTS DEMO;
USE SCHEMA DEMO;

-- ---------------------------------------------------------------------------
-- 2. WAREHOUSE
-- ---------------------------------------------------------------------------

CREATE WAREHOUSE IF NOT EXISTS CORTEX_SEARCH_COST_WH
  WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND = 120
  AUTO_RESUME = TRUE;

USE WAREHOUSE CORTEX_SEARCH_COST_WH;

-- ---------------------------------------------------------------------------
-- 3. STRUCTURED SAMPLE DATA (SQL GENERATOR)
-- ---------------------------------------------------------------------------
-- A metadata table representing the source document catalog.
-- data_gen.py will generate the actual chunks and embeddings.

CREATE OR REPLACE TABLE DOCUMENTS AS
SELECT
    'DOC_' || LPAD(SEQ4()::VARCHAR, 5, '0')                       AS DOC_ID,
    ARRAY_CONSTRUCT(
        'policy_guide', 'faq', 'procedure', 'product_spec',
        'compliance', 'onboarding', 'release_notes', 'architecture'
    )[UNIFORM(0, 7, RANDOM())]::VARCHAR                            AS DOC_TYPE,
    ARRAY_CONSTRUCT(
        'Engineering', 'Legal', 'HR', 'Product',
        'Security', 'Finance', 'Operations', 'Support'
    )[UNIFORM(0, 7, RANDOM())]::VARCHAR                            AS CATEGORY,
    ARRAY_CONSTRUCT(
        'docs/engineering/', 'docs/legal/', 'docs/hr/', 'docs/product/',
        'docs/security/', 'docs/finance/', 'docs/operations/', 'docs/support/'
    )[UNIFORM(0, 7, RANDOM())]::VARCHAR
        || 'DOC_' || LPAD(SEQ4()::VARCHAR, 5, '0') || '.pdf'      AS FILE_PATH,
    DATEADD('day', -UNIFORM(0, 730, RANDOM()), CURRENT_DATE())     AS CREATED_AT,
    DATEADD('day', -UNIFORM(0, 60, RANDOM()), CURRENT_DATE())      AS UPDATED_AT,
    ARRAY_CONSTRUCT('active', 'active', 'active', 'archived')
        [UNIFORM(0, 3, RANDOM())]::VARCHAR                         AS STATUS
FROM TABLE(GENERATOR(ROWCOUNT => 500));

-- ---------------------------------------------------------------------------
-- 4. DOCUMENT CHUNKS + EMBEDDINGS
-- ---------------------------------------------------------------------------
-- The DOCUMENT_CHUNKS table (~5,000 rows) contains:
--   CHUNK_ID (TEXT)      -- primary key, e.g. DOC_00001_CHUNK_01
--   DOC_ID (TEXT)        -- FK to DOCUMENTS
--   CHUNK_TEXT (TEXT)    -- paragraph-length content
--   DOC_TYPE (TEXT)      -- attribute for filtering
--   CATEGORY (TEXT)      -- attribute for filtering
--   FILE_NAME (TEXT)     -- source file path
--   PAGE_NUMBER (NUMBER) -- page within the document
--   EMBEDDING (VECTOR)   -- 768-dim vector from EMBED_TEXT_768
--
-- This block generates the chunks entirely in SQL, so setup.sql alone is
-- sufficient. (lab/data_gen.py is an equivalent Python path if you prefer
-- pandas + write_pandas; run it in a notebook cell where get_active_session()
-- works, since the local Python connector cannot drive oauth_authorization_code.)

CREATE OR REPLACE TABLE DOCUMENT_CHUNKS AS
WITH doc_params AS (
    SELECT
        SEQ4() AS doc_num,
        'DOC_' || LPAD(SEQ4()::VARCHAR, 5, '0') AS DOC_ID,
        ARRAY_CONSTRUCT('policy_guide','faq','procedure','product_spec','compliance','onboarding','release_notes','architecture')[MOD(SEQ4(), 8)]::VARCHAR AS DOC_TYPE,
        ARRAY_CONSTRUCT('Engineering','Legal','HR','Product','Security','Finance','Operations','Support')[MOD(SEQ4(), 8)]::VARCHAR AS CATEGORY,
        'docs/' || LOWER(ARRAY_CONSTRUCT('Engineering','Legal','HR','Product','Security','Finance','Operations','Support')[MOD(SEQ4(), 8)]::VARCHAR) || '/DOC_' || LPAD(SEQ4()::VARCHAR, 5, '0') || '.pdf' AS FILE_NAME
    FROM TABLE(GENERATOR(ROWCOUNT => 500))
),
chunks AS (
    SELECT SEQ4() AS chunk_num FROM TABLE(GENERATOR(ROWCOUNT => 10))
),
topics AS (
    SELECT ARRAY_CONSTRUCT(
        'data access','API authentication','infrastructure scaling',
        'audit logging','vendor management','cost allocation',
        'disaster recovery','user provisioning','network security',
        'CI/CD pipeline','monitoring and alerting','database migration',
        'document retention','incident management','performance tuning'
    ) AS t
),
templates AS (
    SELECT ARRAY_CONSTRUCT(
        'This section covers the %TOPIC% requirements for the %DEPT% team. All employees must complete the mandatory training within 30 days of enrollment. Failure to comply may result in restricted system access until the requirement is fulfilled.',
        'The %DEPT% department has updated its %TOPIC% guidelines effective this quarter. Key changes include enhanced approval workflows, revised escalation paths, and new documentation standards for audit readiness.',
        'When handling %TOPIC% requests, follow the standard operating procedure: verify the requester identity, check authorization level, log the request in the tracking system, and route to the appropriate reviewer.',
        'Frequently asked question: How do I request access to %TOPIC% resources? Submit a request through the internal portal, select the %DEPT% category, and provide your manager approval code. Typical turnaround is 2-3 business days.',
        'The latest release introduces improvements to %TOPIC% functionality. Performance benchmarks show a 40 percent reduction in processing time for batch operations. See the migration guide for breaking changes.',
        'Architecture overview: the %TOPIC% subsystem uses a three-tier design pattern. The presentation layer communicates with the %DEPT% API gateway, which routes to backend microservices. All inter-service communication is encrypted.',
        'Compliance requirement: all %TOPIC% data must be encrypted at rest and in transit. The %DEPT% team is responsible for rotating encryption keys quarterly and maintaining an audit trail of all key management operations.',
        'Onboarding checklist for %TOPIC% access: Complete security awareness training, set up multi-factor authentication, request role-based access from %DEPT% admin, review the acceptable use policy.',
        'Troubleshooting guide for %TOPIC% integration issues: check the service health dashboard, verify API credentials have not expired, confirm the endpoint URL matches the environment, and review recent deployment logs.',
        'Best practices for %TOPIC% data management in the %DEPT% domain: partition large datasets by date, implement retention policies aligned with regulatory requirements, and schedule regular data quality checks.'
    ) AS tmpl
)
SELECT
    d.DOC_ID || '_CHUNK_' || LPAD(c.chunk_num::VARCHAR, 2, '0') AS CHUNK_ID,
    d.DOC_ID,
    REPLACE(REPLACE(
        tmpl.tmpl[MOD(d.doc_num * 10 + c.chunk_num, 10)]::VARCHAR,
        '%TOPIC%', t.t[MOD(d.doc_num + c.chunk_num, 15)]::VARCHAR),
        '%DEPT%', d.CATEGORY) AS CHUNK_TEXT,
    d.DOC_TYPE,
    d.CATEGORY,
    d.FILE_NAME,
    c.chunk_num + 1 AS PAGE_NUMBER
FROM doc_params d
CROSS JOIN chunks c
CROSS JOIN topics t
CROSS JOIN templates tmpl;

-- Add the BYO embedding column. In production these vectors would come from an
-- external model (OpenAI, SageMaker, etc.). Here we pre-compute them with
-- EMBED_TEXT_768 so the lab runs with no external API keys -- the Cortex Search
-- Service still treats them as user-provided vectors (zero embedding cost).
ALTER TABLE DOCUMENT_CHUNKS ADD COLUMN EMBEDDING VECTOR(FLOAT, 768);

UPDATE DOCUMENT_CHUNKS
SET EMBEDDING = SNOWFLAKE.CORTEX.EMBED_TEXT_768('snowflake-arctic-embed-m-v1.5', CHUNK_TEXT)
WHERE EMBEDDING IS NULL;

-- ---------------------------------------------------------------------------
-- 5. FEATURE OBJECTS
-- ---------------------------------------------------------------------------
-- The Cortex Search Service is created in the notebook (Section 2) so you can
-- inspect each step interactively. It depends on DOCUMENT_CHUNKS, created above.

-- ---------------------------------------------------------------------------
-- Setup complete.
--   1) You just ran this script (database, schema, warehouse, DOCUMENTS,
--      DOCUMENT_CHUNKS with 5,000 rows + 768-dim embeddings).
--   2) Open lab/cortex-search-cost-lab.ipynb in Snowflake Notebooks.
-- ---------------------------------------------------------------------------
