// One auth helper for the Agent API (via the SDK) and the SQL API (raw fetch).
//  - SPCS / App Runtime: OAuth token read from /snowflake/session/token on every request
//    (it rotates), against https://$SNOWFLAKE_HOST. With CALLERS_RIGHTS=true the token is
//    "<service token>.<Sf-Context-Current-User-Token>".
//  - Local: PAT (SNOWFLAKE_PAT or SNOWFLAKE_PAT_FILE) or key-pair JWT (SNOWFLAKE_PRIVATE_KEY_PATH).
import { createHash, createPrivateKey, createPublicKey, sign } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { CallableAuth, CortexAgentClient, OAuthAuth, PatAuth, type Authenticator } from "@snowflake/cortex-agent-sdk";
import { config } from "./config";

export const SPCS_TOKEN_PATH = "/snowflake/session/token";

export function inSnowflakeRuntime(): boolean {
  return existsSync(SPCS_TOKEN_PATH);
}

function readPat(): string | undefined {
  const e = process.env;
  if (e.SNOWFLAKE_PAT) return e.SNOWFLAKE_PAT.trim();
  if (e.SNOWFLAKE_PAT_FILE && existsSync(e.SNOWFLAKE_PAT_FILE)) return readFileSync(e.SNOWFLAKE_PAT_FILE, "utf8").trim();
  return undefined;
}

function b64url(b: Buffer | string): string {
  return Buffer.from(b).toString("base64url");
}

/** Key-pair JWT per Snowflake docs (iss = ACCOUNT.USER.SHA256:<fp>, 59 min lifetime). */
function keyPairJwt(): string {
  const cfg = config();
  const pem = readFileSync(process.env.SNOWFLAKE_PRIVATE_KEY_PATH!, "utf8");
  const key = createPrivateKey({ key: pem, passphrase: process.env.SNOWFLAKE_PRIVATE_KEY_PASSPHRASE });
  const der = createPublicKey(key).export({ type: "spki", format: "der" });
  const fp = "SHA256:" + createHash("sha256").update(der).digest("base64");
  const acct = cfg.account.toUpperCase().split(".")[0];
  const user = (cfg.user ?? "").toUpperCase();
  const now = Math.floor(Date.now() / 1000);
  const head = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const body = b64url(JSON.stringify({ iss: `${acct}.${user}.${fp}`, sub: `${acct}.${user}`, iat: now, exp: now + 3540 }));
  const sig = sign("RSA-SHA256", Buffer.from(`${head}.${body}`), key);
  return `${head}.${body}.${b64url(sig)}`;
}

export function baseUrl(): string {
  const cfg = config();
  if (cfg.host) return `https://${cfg.host}`;
  return `https://${cfg.account.toLowerCase()}.snowflakecomputing.com`;
}

/** Builds the authenticator for one request. `callerToken` comes from the ingress header. */
export function authenticator(callerToken?: string): Authenticator {
  if (inSnowflakeRuntime()) {
    return new OAuthAuth(() => {
      const svc = readFileSync(SPCS_TOKEN_PATH, "utf8").trim();
      return config().callersRights && callerToken ? `${svc}.${callerToken}` : svc;
    });
  }
  const pat = readPat();
  if (pat) return new PatAuth(pat);
  if (process.env.SNOWFLAKE_PRIVATE_KEY_PATH) return new CallableAuth(keyPairJwt, "KEYPAIR_JWT");
  throw new Error("No Snowflake credentials: set SNOWFLAKE_PAT, SNOWFLAKE_PAT_FILE or SNOWFLAKE_PRIVATE_KEY_PATH (or run inside SPCS/App Runtime).");
}

export function agentClient(callerToken?: string): CortexAgentClient {
  return new CortexAgentClient({ baseUrl: baseUrl(), auth: authenticator(callerToken) });
}

export async function authHeaders(callerToken?: string): Promise<Record<string, string>> {
  return authenticator(callerToken).getAuthHeaders();
}
