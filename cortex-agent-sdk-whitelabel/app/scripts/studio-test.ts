// Studio mode, live (npm run test:studio): local coco-runner (local `cortex` CLI) + proxy.
// Requests an XLSX of orders by status, approves tool calls programmatically, downloads the file
// through the proxy's /api/files endpoint and checks it is a real XLSX (zip magic).
import { spawn, type ChildProcess } from "node:child_process";
import { mkdirSync } from "node:fs";

const RUNNER = 8790;
const PORT = 8098;
const base = `http://127.0.0.1:${PORT}`;
const work = `/tmp/acme-studio-work-${Date.now()}`;
mkdirSync(work, { recursive: true });
let failures = 0;
const check = (ok: boolean, name: string, detail = "") => {
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? `  (${detail})` : ""}`);
};
const up = async (url: string) => {
  for (let i = 0; i < 160; i++) {
    if (await fetch(url).then(() => true, () => false)) return;
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error(`${url} did not start`);
};

const procs: ChildProcess[] = [];
procs.push(spawn("npm", ["start"], { cwd: "coco-runner", env: { ...process.env, PORT: String(RUNNER), WORK_ROOT: work, STUDIO_ROLE: process.env.STUDIO_ROLE || "ACME_DEMO_ROLE" }, stdio: process.env.STUDIO_DEBUG ? ["ignore", "inherit", "inherit"] : "ignore", detached: true }));
procs.push(spawn(process.execPath, ["--import", "tsx", "server/express.ts"], { env: { ...process.env, PORT: String(PORT), DEV_USER: "alice", COCO_RUNNER_URL: `http://127.0.0.1:${RUNNER}` }, stdio: "ignore" }));
await up(`http://127.0.0.1:${RUNNER}/health`);
await up(`${base}/api/health`);

const conv = `studio-${Date.now()}`;
const prompts = [
  "Using read-only SQL on ACME_ASSIST_DEMO.DATA.ORDERS, build an Excel workbook output/orders_by_status.xlsx with one sheet: status, order count, total value (qty*unit_price). Use python with openpyxl. Reply with the file name.",
];
const res = await fetch(`${base}/api/chat`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ conversationId: conv, mode: "studio", content: [{ type: "text", text: prompts[0] }] }) });
const runId = res.headers.get("x-acme-run-id")!;
const reader = res.body!.pipeThrough(new TextDecoderStream()).getReader();
let buf = "";
const files: any[] = [];
const tools: string[] = [];
let approvals = 0;
let status = "";
let answer = "";
const t0 = Date.now();
for (;;) {
  const { value, done } = await reader.read();
  if (done) break;
  buf += value;
  let i: number;
  while ((i = buf.indexOf("\n\n")) >= 0) {
    const block = buf.slice(0, i);
    buf = buf.slice(i + 2);
    const ev = block.match(/^event: (.*)$/m)?.[1];
    const d = block.match(/^data: (.*)$/m)?.[1];
    if (!ev || !d) continue;
    const data = JSON.parse(d);
    if (ev === "acme.approval") {
      approvals++;
      await fetch(`${base}/api/studio/approve`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ runId, id: data.id, decision: "allow" }) });
    }
    if (ev === "acme.studio.tool") tools.push(data.name ?? data.label), process.env.DEBUG_STUDIO && console.log("DBG tool", data.name, JSON.stringify(data.detail).slice(0, 400));
    if (ev === "acme.studio.tool_result" && process.env.DEBUG_STUDIO) console.log("DBG result", JSON.stringify(data));
    if (ev === "acme.studio.files") files.push(...data.files);
    if (ev === "acme.error") console.log("acme.error", data.message);
    if (ev === "acme.studio.text") answer += data.text ?? "";
    if (ev === "acme.done") status = data.status;
  }
}
console.log(`tools: ${tools.join(" → ")}`);
console.log(`answer: ${answer.trim().slice(-400)}`);
console.log(`approvals: ${approvals}, ${Math.round((Date.now() - t0) / 1000)}s, files: ${JSON.stringify(files)}`);
check(status === "completed", "studio turn completes", status);
const xlsx = files.find((f) => /\.xlsx$/i.test(f.name));
check(!!xlsx, "XLSX announced", xlsx?.url);
if (xlsx) {
  const r = await fetch(base + xlsx.url);
  const b = Buffer.from(await r.arrayBuffer());
  check(r.ok && b.subarray(0, 2).toString() === "PK" && /attachment/.test(r.headers.get("content-disposition") ?? ""), "XLSX downloads via /api/files", `${r.status} ${r.headers.get("content-type")} ${b.length} bytes`);
  const bob = await fetch(base + xlsx.url, { headers: { "X-Forwarded-User": "bob" } });
  check(bob.ok, "(info) owner fetch ok", String(bob.status));
}
for (const p of procs) {
  try {
    if (p.pid) process.kill(p === procs[0] ? -p.pid : p.pid, "SIGTERM");
  } catch {
    /* gone */
  }
}
console.log(failures ? `\n${failures} studio check(s) failed` : "\nAll Studio checks passed");
process.exit(failures ? 1 : 0);
