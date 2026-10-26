-- =============================================================================
-- AI Gateway Tools: Glean + Snowflake MCP for CoCo Desktop (run AFTER setup.sql)
-- =============================================================================
-- Tools (AI & ML > AI Gateway > MCP & Tools) is administered in Snowsight by
-- ACCOUNTADMIN. Do the UI steps in the README ("Gateway Tools: Glean and Snowflake
-- MCP") first: enabling Tools creates the SNOWFLAKE$OPS database used below.
--
-- 1. Snowflake server entry: values to paste into Tools
--      host     <org-account>.snowflakecomputing.com   (hyphens, not underscores)
--      database CORTEX_GATEWAY_MEDTECH_LAB
--      schema   PUBLIC
--      name     MEDTECH_MCP
--      client id / secret: from the query below
-- 2. Glean: Add app > Remote URL with the server URL from your Glean MCP
--    Configurator (the URL must end in /mcp). Allow only read tools.
-- 3. Grant access, then CoCo Desktop discovers both servers automatically.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- OAuth client created by setup.sql §7b. Copy both values into the Snowflake
-- server's configuration in Tools. Treat the secret like a password.
SELECT PARSE_JSON(SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('GATEWAY_MEDTECH_TOOLS_OAUTH')):OAUTH_CLIENT_ID::STRING     AS OAUTH_CLIENT_ID,
       PARSE_JSON(SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('GATEWAY_MEDTECH_TOOLS_OAUTH')):OAUTH_CLIENT_SECRET::STRING AS OAUTH_CLIENT_SECRET;

-- Automatic discovery in CoCo Desktop and CLI: grant the Tools user database role
-- to every account role that should see the enabled servers.
GRANT DATABASE ROLE SNOWFLAKE$OPS.MCP$USER TO ROLE SYSADMIN;

-- The MCP OAuth session runs as the user's DEFAULT_ROLE and needs a
-- DEFAULT_WAREHOUSE, otherwise listing tools fails. Check yours:
--   SHOW USERS LIKE '<you>';
--   ALTER USER <you> SET DEFAULT_ROLE = SYSADMIN DEFAULT_WAREHOUSE = GATEWAY_MEDTECH_WH;

-- Tool calls made through Tools land in the same trace table as inference calls.
-- After one CoCo Desktop prompt, look for them:
USE ROLE SYSADMIN;
SELECT TIMESTAMP,
       SCOPE:"name"::STRING              AS SCOPE_NAME,
       RECORD:"name"::STRING             AS SPAN_NAME,
       RESOURCE_ATTRIBUTES:"snow.user.name"::STRING AS USER_NAME,
       RECORD_ATTRIBUTES                 AS ATTRS
FROM TABLE(AGENT_TRACE_TABLE('SNOWFLAKE'))
WHERE TIMESTAMP > DATEADD('hour', -1, CURRENT_TIMESTAMP())
ORDER BY TIMESTAMP DESC
LIMIT 50;
