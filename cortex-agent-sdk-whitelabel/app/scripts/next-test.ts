// Next.js app-runtime, live (npm run test:next): `npm run dev` in app-runtime/, then
//  - stream a run, disconnect mid-run, reattach in the same process (fast path) -> completes
//  - stream a run, kill the dev server, start it again, reattach -> resumes from the upstream run
//  - security headers on the page
import { spawn, type ChildProcess } from "node:child_process";

const PORT = 3005;
const base = `http://127.0.0.1:${PORT}`;
let failures = 0;
const check = (ok: boolean, name: string, detail = "") => {
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? `  (${detail})` : ""}`);
};

function startNext(): Promise<ChildProcess> {
  const p = spawn("npx", ["next", "dev", "-p", String(PORT)], { cwd: "app-runtime", env: { ...process.env, DEV_USER: "alice", NODE_ENV: "development" }, stdio: "ignore", detached: true });
  return new Promise(async (resolve, reject) => {
    for (let i = 0; i < 240; i++) {
      if (await fetch(`${base}/api/health`).then((r) => r.ok, () => false)) return resolve(p);
      await new Promise((r) => setTimeout(r, 500));
    }
    reject(new Error("next dev did not start"));
  });
}
const kill = async (p: ChildProcess) => {
  try {
    process.kill(-p.pid!, "SIGKILL");
  } catch {
    /* gone */
  }
  for (let i = 0; i < 40 && (await fetch(`${base}/api/health`).then(() => true, () => false)); i++) await new Promise((r) => setTimeout(r, 250));
};

async function read(res: Response, stopAfter?: number) {
  const events: Array<{ seq: number; event: string; data: any }> = [];
  const reader = res.body!.pipeThrough(new TextDecoderStream()).getReader();
  let buf = "";
  for (;;) {
    const { value, done } = await reader.read().catch(() => ({ value: undefined, done: true }));
    if (done) return events;
    buf += value;
    let i: number;
    while ((i = buf.indexOf("\n\n")) >= 0) {
      const b = buf.slice(0, i);
      buf = buf.slice(i + 2);
      const id = b.match(/^id: (\d+)$/m)?.[1];
      const ev = b.match(/^event: (.*)$/m)?.[1];
      const d = b.match(/^data: (.*)$/m)?.[1];
      if (!id || !ev) continue;
      events.push({ seq: Number(id), event: ev, data: JSON.parse(d ?? "null") });
      if (stopAfter && events.filter((e) => e.event === "response.text.delta").length >= stopAfter) {
        await reader.cancel().catch(() => undefined);
        return events;
      }
    }
  }
}
const chat = (conv: string) =>
  fetch(`${base}/api/chat`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ conversationId: conv, mode: "assist", browserTools: false, content: [{ type: "text", text: "Using acme_analyst, get failed orders by region, then write a 300-word summary for the regional managers." }] }) });

let next = await startNext();
const page = await fetch(`${base}/`);
const csp = page.headers.get("content-security-policy") ?? "";
check(page.ok && /default-src 'self'/.test(csp) && /frame-src 'self'/.test(csp), "Next page served with CSP", csp.slice(0, 80) + "…");

// 1. stream + in-process resume
{
  const res = await chat("next-resume-1");
  const runId = res.headers.get("x-acme-run-id")!;
  const first = await read(res, 5);
  const last = first.at(-1)!.seq;
  const rest = await read(await fetch(`${base}/api/runs/${runId}/events?after=${last}`));
  const done = rest.find((e) => e.event === "acme.done");
  check(first.length > 0 && done?.data.status === "completed" && rest[0].seq === last + 1, "stream + reattach (same process)", `after=${last} first=${rest[0]?.seq} events=${rest.length}`);
}
// 2. stream, kill dev server, restart, resume from upstream
{
  const res = await chat("next-resume-2");
  const runId = res.headers.get("x-acme-run-id")!;
  const first = await read(res, 5);
  const last = first.at(-1)!.seq;
  await kill(next);
  next = await startNext();
  const rest = await read(await fetch(`${base}/api/runs/${runId}/events?after=${last}`));
  const done = rest.find((e) => e.event === "acme.done");
  const text = rest.filter((e) => e.event === "response.text.delta").map((e) => e.data.text).join("");
  check(done?.data.status === "completed" && rest[0]?.seq === last + 1 && text.length > 100, "resume after Next.js restart", `after=${last} first=${rest[0]?.seq} ${text.length} chars`);
}
await kill(next);
console.log(failures ? `\n${failures} Next.js check(s) failed` : "\nAll Next.js checks passed");
process.exit(failures ? 1 : 0);
