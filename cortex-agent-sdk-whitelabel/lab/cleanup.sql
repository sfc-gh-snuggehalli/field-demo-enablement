-- ACME Assist — remove everything this demo creates.
-- Fast path: dropping the database removes tables, semantic view, both agents,
-- history table, image repository and any services/app services inside it.
USE ROLE ACCOUNTADMIN;

-- Services first (they hold the compute pool).
DROP SERVICE IF EXISTS ACME_ASSIST_DEMO.APP.ACME_ASSIST_SERVICE;
-- App Runtime application service (created by `snow app deploy`, app name acme_assist).
-- Its code stage ACME_ASSIST_CODE and artifact repo ACME_ASSIST_REPO live in APP and drop with the DB.
DROP APPLICATION SERVICE IF EXISTS ACME_ASSIST_DEMO.APP.ACME_ASSIST;

DROP DATABASE IF EXISTS ACME_ASSIST_DEMO;

-- Account-level objects DROP DATABASE does not cascade to.
DROP COMPUTE POOL IF EXISTS ACME_ASSIST_POOL;
DROP WAREHOUSE IF EXISTS ACME_ASSIST_WH;
DROP ROLE IF EXISTS ACME_APP_ROLE;
DROP ROLE IF EXISTS ACME_HISTORY_ROLE;
DROP ROLE IF EXISTS ACME_STUDIO_ROLE;
DROP ROLE IF EXISTS ACME_DEMO_ROLE;
