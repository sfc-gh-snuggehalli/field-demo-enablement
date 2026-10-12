// fetch with a per-attempt timeout and retry with exponential backoff (+ jitter) on 429 / 5xx /
// network errors. Used for the SQL API and MCP; the SDK calls use the SDK's own retryPolicy.
import { log } from "./log";

export interface RetryOpts {
  retries?: number;
  timeoutMs?: number;
  baseDelayMs?: number;
  /** Label for logs only. */
  op?: string;
}

const retryable = (status: number) => status === 429 || status >= 500;

export function backoffMs(attempt: number, base = 250, retryAfter?: string | null): number {
  const ra = Number(retryAfter);
  if (retryAfter && Number.isFinite(ra) && ra >= 0) return Math.min(ra * 1000, 10_000);
  return Math.min(base * 2 ** attempt, 8_000) + Math.floor(Math.random() * base);
}

export async function fetchRetry(url: string, init: RequestInit, opts: RetryOpts = {}): Promise<Response> {
  const retries = opts.retries ?? 3;
  let lastErr: unknown;
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      const signal = AbortSignal.any([AbortSignal.timeout(opts.timeoutMs ?? 30_000), ...(init.signal ? [init.signal] : [])]);
      const res = await fetch(url, { ...init, signal });
      if (!retryable(res.status) || attempt === retries) return res;
      log("warn", "upstream retry", { op: opts.op, status: res.status, attempt: attempt + 1 });
      await res.body?.cancel().catch(() => undefined);
      await new Promise((r) => setTimeout(r, backoffMs(attempt, opts.baseDelayMs, res.headers.get("retry-after"))));
    } catch (e: any) {
      if (init.signal?.aborted) throw e;
      lastErr = e;
      if (attempt === retries) break;
      log("warn", "upstream retry", { op: opts.op, error: e?.name ?? "error", attempt: attempt + 1 });
      await new Promise((r) => setTimeout(r, backoffMs(attempt, opts.baseDelayMs)));
    }
  }
  throw lastErr instanceof Error ? lastErr : new Error(String(lastErr));
}
