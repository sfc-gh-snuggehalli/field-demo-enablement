-- ACME Assist: SPCS deployment objects. Run ONCE, manually, as an admin (ACCOUNTADMIN),
-- after ../../lab/setup.sql and ../../lab/history.sql. These scripts are not run
-- automatically by any npm script. Suggested connection: your admin connection, e.g.
--   snow sql -c <admin_connection> -f snowflake/spcs/setup.sql
USE ROLE ACCOUNTADMIN;

-- Service role that owns the service and runs the app.
CREATE ROLE IF NOT EXISTS ACME_APP_ROLE;
GRANT ROLE ACME_APP_ROLE TO ROLE SYSADMIN;

-- Data + Cortex privileges come from ACME_DEMO_ROLE (created by ../../lab/setup.sql),
-- which already holds SNOWFLAKE.CORTEX_USER, warehouse usage, table/semantic view SELECT
-- and USAGE on both agents.
GRANT ROLE ACME_DEMO_ROLE TO ROLE ACME_APP_ROLE;
GRANT ROLE ACME_HISTORY_ROLE TO ROLE ACME_APP_ROLE;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE ACME_APP_ROLE;
GRANT USAGE ON WAREHOUSE ACME_ASSIST_WH TO ROLE ACME_APP_ROLE;

-- Image repository + service live in ACME_ASSIST_DEMO.APP.
GRANT USAGE ON DATABASE ACME_ASSIST_DEMO TO ROLE ACME_APP_ROLE;
GRANT USAGE, CREATE SERVICE, CREATE IMAGE REPOSITORY ON SCHEMA ACME_ASSIST_DEMO.APP TO ROLE ACME_APP_ROLE;

CREATE COMPUTE POOL IF NOT EXISTS ACME_ASSIST_POOL
  MIN_NODES = 1 MAX_NODES = 1 INSTANCE_FAMILY = CPU_X64_XS
  AUTO_RESUME = TRUE AUTO_SUSPEND_SECS = 3600
  COMMENT = 'ACME Assist app (single instance: resumable runs are buffered in-process)';
GRANT USAGE, MONITOR ON COMPUTE POOL ACME_ASSIST_POOL TO ROLE ACME_APP_ROLE;

-- Public endpoint (Snowflake sign-in at the ingress).
GRANT BIND SERVICE ENDPOINT ON ACCOUNT TO ROLE ACME_APP_ROLE;

USE ROLE ACME_APP_ROLE;
CREATE IMAGE REPOSITORY IF NOT EXISTS ACME_ASSIST_DEMO.APP.ACME_REPO;
SHOW IMAGE REPOSITORIES IN SCHEMA ACME_ASSIST_DEMO.APP;   -- note repository_url for deploy.sh

-- After deploy.sh has created the service, grant the endpoint to consumer roles:
--   USE ROLE ACME_APP_ROLE;
--   GRANT SERVICE ROLE ACME_ASSIST_DEMO.APP.ACME_ASSIST_SERVICE!ALL_ENDPOINTS_USAGE TO ROLE <consumer_role>;
-- Consumers also need USAGE on the agent(s) when CALLERS_RIGHTS=true:
--   GRANT ROLE ACME_DEMO_ROLE TO ROLE <consumer_role>;
