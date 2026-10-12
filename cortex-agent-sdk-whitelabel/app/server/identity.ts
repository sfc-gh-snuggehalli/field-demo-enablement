// resolveUser(request): the one place the signed-in user is determined.
//  1. Snowflake ingress (SPCS / App Runtime): Sf-Context-Current-User
//  2. Trusted SSO proxy header (only with TRUST_PROXY_HEADER=true), validated
//  3. DEV_USER
import { createHash } from "node:crypto";
import { config } from "./config";
import { inSnowflakeRuntime } from "./auth";

export interface ResolvedUser {
  name: string | null;
  source: "snowflake" | "sso" | "dev" | "none";
  /** Sf-Context-Current-User-Token, used for caller's rights. */
  callerToken?: string;
}

const USER_RE = /^[A-Za-z0-9._@+\-]{1,128}$/;

export function resolveUser(req: Request): ResolvedUser {
  const cfg = config();
  const sf = req.headers.get("sf-context-current-user");
  // Trust the ingress header when running inside Snowflake, or when explicitly allowed for tests.
  if (sf && USER_RE.test(sf) && (inSnowflakeRuntime() || process.env.TRUST_SF_CONTEXT_HEADER === "true")) {
    return { name: sf, source: "snowflake", callerToken: req.headers.get("sf-context-current-user-token") ?? undefined };
  }
  if (cfg.trustProxyHeader) {
    const h = req.headers.get(cfg.trustedUserHeader);
    if (h && USER_RE.test(h.trim())) return { name: h.trim(), source: "sso" };
  }
  if (cfg.devUser) return { name: cfg.devUser, source: "dev" };
  return { name: null, source: "none" };
}

/** Stable, path-safe owner hash used by the Studio runner work directories. */
export function ownerHash(user: string): string {
  return createHash("sha256").update(user.toLowerCase()).digest("hex").slice(0, 16);
}
