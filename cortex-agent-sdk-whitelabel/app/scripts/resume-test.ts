// Live production-hardening checks against a real server process (npm run test:resume):
//  1. restart-resume: start a run, SIGKILL the server mid-run, start a new process, reattach with
//     ?after=<last seq>, run completes from Snowflake's run stream
//  2. Stop: cancel a live run (client.runs.cancel upstream) -> acme.done cancelled
//  3. Stop after restart: cancel a run the new process only knows from the run store
//  4. graceful SIGTERM: health 503 while draining, SSE ends, process exits
//  5. rate limit 429, describe failure 503, security headers, X-Request-Id, no prompt in logs
import { spawn, type ChildProcess } from "node:child_process";
import { loadEnv } from "../server/env";

loadEnv();
const PORT = Number(process.env.RESUME_TEST_PORT || 8093);
const base = `http://127.0.0.1:${PORT}`;
const SECRET_PROMPT = "zebra-canary-7781";
let failures = 0;
const check = (ok: boolean, name: string, detail = "") => {
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? `  (${detail})` : ""}`);
};

let logs = "";
function start(env: Record<string, string> = {}): Promise<ChildProcess> {
  const p = spawn(process.execPath, ["--import", "tsx", "server/express.ts"], { env: { ...process.env, PORT: String(PORT), DEV_USER: "alice", TRUST_SF_CONTEXT_HEADER: "true", NODE_ENV: "production", RUN_STORE_DIR: ".data/runs-test", ...env }, stdio: ["ignore", "pipe", "pipe"] });
  p.stdout!.on("data", (d) => (logs += d));
  p.stderr!.on("data", (d) => (logs += d));
  return new Promise((resolve, reject) => {
    const t0 = Date.now();
    const poll = async () => {
      try {
        if ((await fetch(`${base}/api/health`)).ok) return resolve(p);
      } catch {
        /* not up yet */
      }
      if (Date.now() - t0 > 30_000) return reject(new Error("server did not start"));
      setTimeout(poll, 250);
    };
    poll();
  });
}
const stopped = (p: ChildProcess) => new Promise<number | null>((r) => (p.exitCode !== null ? r(p.exitCode) : p.once("exit", (c) => r(c))));

interface Ev {
  seq: number;
  event: string;
  data: any;
}
/** Reads SSE frames; `until` returning true stops reading (and aborts the request). */
async function readSse(res: Response, until: (e: Ev, all: Ev[]) => boolean = () => false): Promise<{ events: Ev[]; closed: boolean }> {
  const events: Ev[] = [];
  const reader = res.body!.pipeThrough(new TextDecoderStream()).getReader();
  let buf = "";
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) return { events, closed: true };
      buf += value;
      let i: number;
      while ((i = buf.indexOf("\n\n")) >= 0) {
        const block = buf.slice(0, i);
        buf = buf.slice(i + 2);
        const id = block.match(/^id: (\d+)$/m)?.[1];
        const event = block.match(/^event: (.*)$/m)?.[1];
        const data = block.match(/^data: (.*)$/m)?.[1];
        if (!id || !event) continue;
        const e = { seq: Number(id), event, data: JSON.parse(data ?? "null") };
        events.push(e);
        if (until(e, events)) {
          await reader.cancel().catch(() => undefined);
          return { events, closed: false };
        }
      }
    }
  } catch {
    return { events, closed: true };
  }
}

const chat = (text: string, conv: string) =>
  fetch(`${base}/api/chat`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ conversationId: conv, mode: "assist", browserTools: false, content: [{ type: "text", text }] }) });

const LONG = `Using acme_analyst, get 7-day revenue by region, then write a detailed 600-word briefing for the regional managers with a section per region. Tag: ${SECRET_PROMPT}`;

// ---- 1. restart-resume ------------------------------------------------------------------
let srv = await start();
{
  const res = await chat(LONG, "resume-test");
  const runId = res.headers.get("x-acme-run-id")!;
  check(!!res.headers.get("x-request-id"), "X-Request-Id on /api/chat");
  let textBefore = "";
  const first = await readSse(res, (e) => {
    if (e.event === "response.text.delta") textBefore += e.data.text ?? "";
    return e.event === "response.text.delta" && textBefore.length > 40;
  });
  const lastSeq = first.events.at(-1)!.seq;
  const upstream = first.events.find((e) => e.event === "acme.run");
  check(!!runId && lastSeq > 3, "run streaming before kill", `runId=${runId} lastSeq=${lastSeq} thread=${upstream?.data.threadId}`);
  srv.kill("SIGKILL");
  await stopped(srv);
  srv = await start();
  const other = await fetch(`${base}/api/runs/${runId}/events?after=0`, { headers: { "Sf-Context-Current-User": "mallory" } });
  check(other.status === 404, "other user cannot reattach to a persisted run", String(other.status));
  await other.body?.cancel();
  const t0 = Date.now();
  const re = await fetch(`${base}/api/runs/${runId}/events?after=${lastSeq}`);
  check(re.status === 200, "reattach to run unknown to the new process", `status ${re.status}`);
  let textAfter = "";
  const rest = await readSse(re);
  for (const e of rest.events) if (e.event === "response.text.delta") textAfter += e.data.text ?? "";
  const done = rest.events.find((e) => e.event === "acme.done");
  const seqs = rest.events.map((e) => e.seq);
  check(done?.data.status === "completed", "resumed run completes", `status=${done?.data.status} events=${rest.events.length} ${Date.now() - t0}ms`);
  check(seqs[0] === lastSeq + 1 && seqs.every((s, i) => i === 0 || s > seqs[i - 1]), "resumed seqs continue the client cursor", `first=${seqs[0]} after=${lastSeq}`);
  check(textAfter.length > 200 && !textAfter.startsWith(textBefore.slice(0, 20)), "resumed text continues (no replay of seen deltas)", `${textBefore.length} chars before, ${textAfter.length} after`);
  check(logs.includes('"resuming run from upstream"'), "server log shows upstream resume");
}

// ---- 2. Stop on a live run ----------------------------------------------------------------
{
  const res = await chat(LONG, "stop-test");
  const runId = res.headers.get("x-acme-run-id")!;
  const reading = readSse(res);
  await new Promise((r) => setTimeout(r, 6000));
  const c = await (await fetch(`${base}/api/runs/${runId}/cancel`, { method: "POST" })).json();
  const { events } = await reading;
  const done = events.find((e) => e.event === "acme.done");
  await new Promise((r) => setTimeout(r, 1500));
  check(c.status === "cancelled" && done?.data.status === "cancelled" && /"upstream run cancelled".*"status":200/.test(logs), "Stop cancels a live run (client.runs.cancel upstream 200)", JSON.stringify(c));
}

// ---- 3. Stop after restart (persisted record -> client.runs.cancel upstream) -------------------
{
  const res = await chat(LONG, "stop-restart");
  const runId = res.headers.get("x-acme-run-id")!;
  await readSse(res, (_e, all) => all.length > 4);
  srv.kill("SIGKILL");
  await stopped(srv);
  srv = await start();
  const c = await fetch(`${base}/api/runs/${runId}/cancel`, { method: "POST" });
  const body = await c.json();
  check(c.status === 200 && body.status === "cancelled", "Stop after restart cancels upstream", JSON.stringify(body));
}

// ---- 4. graceful SIGTERM -----------------------------------------------------------------------
{
  const res = await chat(LONG, "sigterm-test");
  const reading = readSse(res);
  await new Promise((r) => setTimeout(r, 4000));
  const t0 = Date.now();
  srv.kill("SIGTERM");
  await new Promise((r) => setTimeout(r, 300));
  const h = await fetch(`${base}/api/health`).catch(() => undefined);
  const { events, closed } = await reading;
  const code = await stopped(srv);
  check(closed && code === 0 && logs.includes('"shutdown: draining"'), "SIGTERM drains SSE and exits 0", `exit=${code} health=${h?.status ?? "closed"} ${Date.now() - t0}ms, ${events.length} events`);
}

// ---- 5. rate limit, describe 503, headers, logging --------------------------------------------
srv = await start({ RATE_LIMIT_BURST: "2", RATE_LIMIT_PER_MIN: "1" });
{
  const bad = () => fetch(`${base}/api/chat`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ conversationId: "x", content: [] }) });
  const codes = [(await bad()).status, (await bad()).status, (await bad()).status];
  const r = await bad();
  check(codes.join(",") === "400,400,429" && !!r.headers.get("retry-after"), "per-user rate limit -> 429 + Retry-After", codes.join(","));
  const page = await fetch(`${base}/`);
  const cspH = page.headers.get("content-security-policy") ?? "";
  check(/default-src 'self'/.test(cspH) && /frame-src 'self'/.test(cspH) && !/unsafe-eval/.test(cspH) && page.headers.get("x-content-type-options") === "nosniff", "security headers on pages", cspH.slice(0, 90) + "…");
  const lines = logs.split("\n").filter(Boolean);
  const nonJson = lines.filter((l) => !l.startsWith("{") && !/^\s*$/.test(l));
  check(lines.filter((l) => l.includes('"msg":"request"')).every((l) => /"rid":"[^"]+"/.test(l)), "structured access logs carry request ids");
  check(!logs.includes(SECRET_PROMPT), "prompts are not logged (LOG_PROMPTS=false)");
  check(nonJson.length === 0, "all server log lines are JSON", nonJson.slice(0, 2).join(" | "));
}
srv.kill("SIGTERM");
await stopped(srv);
srv = await start({ AGENT_NAME: "ACME_NO_SUCH_AGENT" });
{
  const r = await chat("hello", "describe-fail");
  const b = await r.json().catch(() => ({}));
  check(r.status === 503 && /unavailable/i.test(b.error ?? ""), "describe failure -> clear 503", `${r.status} ${String(b.error).slice(0, 100)}`);
}
srv.kill("SIGTERM");
await stopped(srv);

console.log(failures ? `\n${failures} check(s) failed` : "\nAll production checks passed");
process.exit(failures ? 1 : 0);
