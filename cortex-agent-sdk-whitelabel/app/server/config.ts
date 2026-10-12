// Server configuration, read once from the environment. Never sent to the browser
// except through publicConfig() in handlers.ts.

const bool = (v: string | undefined, d = false) => (v === undefined || v === "" ? d : /^(1|true|yes|on)$/i.test(v));

export interface ServerConfig {
  account: string;
  host: string | undefined;
  user: string | undefined;
  role: string | undefined;
  warehouse: string;
  agentDatabase: string;
  agentSchema: string;
  agentName: string;
  powerAgentName: string;
  powerModeEnabled: boolean;
  semanticView: string;
  brand: string;
  trustProxyHeader: boolean;
  trustedUserHeader: string;
  requireAuth: boolean;
  devUser: string | undefined;
  callersRights: boolean;
  historyStore: "local" | "snowflake";
  historyRole: string;
  historyTable: string;
  sqlReadonlyRole: string | undefined;
  cocoRunnerUrl: string | undefined;
  port: number;
}

let cached: ServerConfig | undefined;

export function config(): ServerConfig {
  if (cached) return cached;
  const e = process.env;
  cached = {
    account: e.SNOWFLAKE_ACCOUNT ?? "",
    host: e.SNOWFLAKE_HOST || undefined,
    user: e.SNOWFLAKE_USER || undefined,
    role: e.SNOWFLAKE_ROLE || undefined,
    warehouse: e.SNOWFLAKE_WAREHOUSE || "ACME_ASSIST_WH",
    agentDatabase: e.AGENT_DATABASE || "ACME_ASSIST_DEMO",
    agentSchema: e.AGENT_SCHEMA || "DATA",
    agentName: e.AGENT_NAME || "ACME_ASSIST_AGENT",
    powerAgentName: e.POWER_AGENT_NAME || "ACME_POWER_AGENT",
    powerModeEnabled: bool(e.POWER_MODE_ENABLED),
    semanticView: e.SEMANTIC_VIEW || "ACME_ASSIST_DEMO.DATA.ACME_SEMANTIC_VIEW",
    brand: e.NEXT_PUBLIC_BRAND || e.VITE_BRAND || "acme",
    trustProxyHeader: bool(e.TRUST_PROXY_HEADER),
    trustedUserHeader: (e.TRUSTED_USER_HEADER || "X-Forwarded-User").toLowerCase(),
    requireAuth: bool(e.REQUIRE_AUTH),
    devUser: e.DEV_USER || undefined,
    callersRights: bool(e.CALLERS_RIGHTS),
    historyStore: e.HISTORY_STORE === "snowflake" ? "snowflake" : "local",
    historyRole: e.HISTORY_ROLE || "ACME_HISTORY_ROLE",
    historyTable: e.HISTORY_TABLE || "ACME_ASSIST_DEMO.APP.CONVERSATIONS",
    sqlReadonlyRole: e.SQL_READONLY_ROLE || undefined,
    cocoRunnerUrl: e.COCO_RUNNER_URL || e.STUDIO || undefined,
    port: Number(e.PORT || 8080),
  };
  return cached;
}

/** Test hook: re-read env (used by check:identity). */
export function resetConfig(): void {
  cached = undefined;
}
