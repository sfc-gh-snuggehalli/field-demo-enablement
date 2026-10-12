// Per-user token bucket for /api/chat. RATE_LIMIT_PER_MIN tokens refill per minute,
// RATE_LIMIT_BURST is the bucket size. 0 disables the limiter.
interface Bucket {
  tokens: number;
  at: number;
}
const g = globalThis as unknown as { __acmeBuckets?: Map<string, Bucket> };
const buckets = (g.__acmeBuckets ??= new Map());

export function rateLimit(key: string, now = Date.now()): { ok: true } | { ok: false; retryAfterS: number } {
  const perMin = Number(process.env.RATE_LIMIT_PER_MIN ?? 20);
  const burst = Number(process.env.RATE_LIMIT_BURST ?? 10);
  if (!(perMin > 0) || !(burst > 0)) return { ok: true };
  const rate = perMin / 60_000;
  const b = buckets.get(key) ?? { tokens: burst, at: now };
  b.tokens = Math.min(burst, b.tokens + (now - b.at) * rate);
  b.at = now;
  buckets.set(key, b);
  if (buckets.size > 10_000) for (const [k, v] of buckets) if (now - v.at > 600_000) buckets.delete(k);
  if (b.tokens >= 1) {
    b.tokens -= 1;
    return { ok: true };
  }
  return { ok: false, retryAfterS: Math.ceil((1 - b.tokens) / rate / 1000) };
}

export function resetRateLimits(): void {
  buckets.clear();
}
