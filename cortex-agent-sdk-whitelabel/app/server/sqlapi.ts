// Minimal Snowflake SQL API client (POST /api/v2/statements) with bind parameters,
// per-attempt timeout and retry/backoff on 429 / 5xx (server/http.ts).
import { authHeaders, baseUrl } from "./auth";
import { config } from "./config";
import { fetchRetry } from "./http";

export type Bind = string | number | boolean | null;

export async function sql(statement: string, binds: Bind[] = [], opts: { role?: string; callerToken?: string } = {}): Promise<Record<string, unknown>[]> {
  const bindings: Record<string, { type: string; value: string | null }> = {};
  binds.forEach((v, i) => {
    bindings[String(i + 1)] = { type: typeof v === "number" ? "FIXED" : typeof v === "boolean" ? "BOOLEAN" : "TEXT", value: v === null ? null : String(v) };
  });
  const res = await fetchRetry(
    `${baseUrl()}/api/v2/statements`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json", ...(await authHeaders(opts.callerToken)) },
      body: JSON.stringify({ statement, bindings, warehouse: config().warehouse, role: opts.role, timeout: 60 }),
    },
    { op: "sql", timeoutMs: Number(process.env.SQL_TIMEOUT_MS || 65_000), retries: Number(process.env.UPSTREAM_RETRIES ?? 3) },
  );
  const body: any = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`SQL API ${res.status}: ${body.message ?? res.statusText}`);
  const cols: string[] = (body.resultSetMetaData?.rowType ?? []).map((c: any) => String(c.name).toLowerCase());
  return (body.data ?? []).map((row: unknown[]) => Object.fromEntries(cols.map((c, i) => [c, row[i]])));
}
