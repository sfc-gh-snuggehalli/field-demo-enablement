// Power Mode, full scenario, live (npm run test:power): approvals driven programmatically
// ("Allow this command", never "Allow all"), deliverables downloaded via GET /api/files/... .
import { spawn } from "node:child_process";

const PORT = 8097;
const base = `http://127.0.0.1:${PORT}`;
const PROMPT = "Build me a CSV of all failed orders this week with carrier and age, and a bar chart by exception reason.";
let failures = 0;
const check = (ok: boolean, name: string, detail = "") => {
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? `  (${detail})` : ""}`);
};

const srv = spawn(process.execPath, ["--import", "tsx", "server/express.ts"], { env: { ...process.env, PORT: String(PORT), DEV_USER: "alice", POWER_MODE_ENABLED: "true", RATE_LIMIT_BURST: "50" }, stdio: "ignore" });
for (let i = 0; i < 120; i++) {
  if (await fetch(`${base}/api/health`).then((r) => r.ok, () => false)) break;
  await new Promise((r) => setTimeout(r, 250));
}

const conv = `power-${Date.now()}`;
let threadId: string | undefined;
let parentMessageId: string | undefined;
let content: any[] = [{ type: "text", text: PROMPT }];
const files: Array<{ name: string; url: string; size: number }> = [];
const tools: string[] = [];
let approvals = 0;
let finalText = "";
const t0 = Date.now();
for (let hop = 0; hop < 12; hop++) {
  const res = await fetch(`${base}/api/chat`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ conversationId: conv, mode: "power", threadId, parentMessageId, content, browserTools: false }) });
  const text = await res.text();
  const pending: any[] = [];
  for (const block of text.split("\n\n")) {
    const ev = block.match(/^event: (.*)$/m)?.[1];
    const d = block.match(/^data: (.*)$/m)?.[1];
    if (!ev || !d) continue;
    const data = JSON.parse(d);
    if (ev === "acme.run") threadId = data.threadId;
    if (ev === "metadata" && data.metadata?.role === "assistant") parentMessageId = String(data.metadata.message_id);
    if (ev === "response.tool_use") {
      tools.push(data.name);
      if (data.permission?.options?.length) pending.push(data);
    }
    if (ev === "acme.studio.files") files.push(...data.files);
    if (process.env.DEBUG_POWER && ev === "response.tool_use" && /bash|write/.test(data.name)) console.log("DBG", data.name, JSON.stringify(data.input).match(/savefig[^)]*\)|"command":"[^"]{0,160}/g));
    if (process.env.DEBUG_POWER && ev === "response.tool_result" && data.name === "bash") console.log("DBG result", data.status, JSON.stringify(data.content).slice(0, 160), "len", JSON.stringify(data.content).length);
    if (process.env.DEBUG_POWER && ev === "response.tool_use" && data.name === "bash") console.log("DBG cmd", JSON.stringify(data.input?.command).slice(0, 200));
    if (process.env.DEBUG_POWER && ev === "response.status" && /proxy/.test(data.status)) console.log("DBG status", data.message);
    if (ev === "response.text.delta") finalText += data.text ?? "";
    if (ev === "acme.error") console.log("acme.error", data.message);
  }
  if (!pending.length) break;
  approvals += pending.length;
  content = pending.map((p) => {
    const allow = p.permission.options.find((o: string) => /^allow this/i.test(o)) ?? p.permission.options.find((o: string) => /allow/i.test(o) && !/all/i.test(o));
    return { type: "permission_decision", permission_decision: { tool_use_id: p.tool_use_id, decision: allow } };
  });
}
console.log(`tools: ${tools.join(" → ")}`);
console.log(`approvals sent: ${approvals}, ${Math.round((Date.now() - t0) / 1000)}s`);
console.log(`files: ${JSON.stringify(files)}`);
const csv = files.find((f) => /\.csv$/i.test(f.name));
const chart = files.find((f) => /\.(svg|png|html)$/i.test(f.name));
check(approvals > 0, "approvals driven programmatically (Allow this command)", String(approvals));
check(!!csv && csv.url.startsWith(`/api/files/${conv}/`), "CSV announced as a server download", csv?.url);
check(!!chart && chart.url.startsWith(`/api/files/${conv}/`), "chart announced as a server download", chart?.url);
if (csv) {
  const r = await fetch(base + csv.url);
  const body = await r.text();
  const header = body.split("\n")[0].toLowerCase();
  check(r.ok && /attachment/.test(r.headers.get("content-disposition") ?? "") && /carrier/.test(header) && /age/.test(header), "CSV downloads with carrier + age columns", `${r.status} ${header} · ${body.trim().split("\n").length - 1} rows`);
}
if (chart) {
  const r = await fetch(base + chart.url);
  const buf = Buffer.from(await r.arrayBuffer());
  const body = buf.toString("latin1");
  check(r.ok && /attachment/.test(r.headers.get("content-disposition") ?? "") && (/<svg|<html/i.test(body) || buf.subarray(1, 4).toString() === "PNG") && r.headers.get("content-security-policy")?.includes("sandbox") === true, "chart downloads as an attachment (sandboxed)", `${r.headers.get("content-type")} ${body.length} bytes`);
}
const other = csv ? await fetch(base + csv.url, { headers: { "X-Forwarded-User": "bob" } }) : undefined;
check(!other || other.status === 200, "(info) same-user fetch status", String(other?.status));
console.log(`answer: ${finalText.trim().slice(-240)}`);
srv.kill("SIGTERM");
await new Promise((r) => srv.once("exit", r));
console.log(failures ? `\n${failures} power check(s) failed` : "\nAll Power Mode checks passed");
process.exit(failures ? 1 : 0);
