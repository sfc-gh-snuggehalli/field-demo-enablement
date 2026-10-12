// Structured JSON logging (one line per event, stdout/stderr). Prompts, tool inputs, tokens and
// auth headers are never logged; message content only when LOG_PROMPTS=true.
const bool = (v: string | undefined) => /^(1|true|yes|on)$/i.test(v ?? "");

export const logPrompts = () => bool(process.env.LOG_PROMPTS);

type Level = "debug" | "info" | "warn" | "error";
const ORDER: Record<Level, number> = { debug: 10, info: 20, warn: 30, error: 40 };

/** Keys that are always dropped, whatever the caller passes. */
const SECRET_KEY = /token|authorization|auth_?header|password|secret|pat\b|cookie/i;

function scrub(fields: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(fields)) {
    if (SECRET_KEY.test(k)) continue;
    if (k === "prompt" && !logPrompts()) continue;
    out[k] = v;
  }
  return out;
}

export function log(level: Level, msg: string, fields: Record<string, unknown> = {}): void {
  const min = ORDER[(process.env.LOG_LEVEL as Level) || "info"] ?? 20;
  if (ORDER[level] < min) return;
  const line = JSON.stringify({ ts: new Date().toISOString(), level, msg, ...scrub(fields) });
  (level === "error" || level === "warn" ? process.stderr : process.stdout).write(line + "\n");
}

const REQ_ID = /^[A-Za-z0-9._-]{8,64}$/;
/** Reuses a well-formed incoming X-Request-Id, else mints one. */
export function requestId(incoming: string | null): string {
  return incoming && REQ_ID.test(incoming) ? incoming : crypto.randomUUID();
}
