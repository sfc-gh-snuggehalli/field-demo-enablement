// MCP end to end (npm run test:mcp): a tiny local MCP server (Streamable HTTP, JSON-RPC over POST,
// one tool, bearer auth) + the real proxy + the real agent. Checks the agent calls the MCP tool
// through the proxy, the auth header is stored server-side per user and never echoed back.
import { spawn, type ChildProcess } from "node:child_process";
import { createServer } from "node:http";

const MCP_PORT = 8094;
const PORT = 8095;
const base = `http://127.0.0.1:${PORT}`;
const TOKEN = `mcp-test-${crypto.randomUUID()}`;
const CANARY = "Drizzle, 58F, wind 12 mph NW (code MCP-4471)";
let failures = 0;
const check = (ok: boolean, name: string, detail = "") => {
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? `  (${detail})` : ""}`);
};

const seen: Array<{ method: string; auth: string | undefined; args?: unknown }> = [];
const mcp = createServer(async (req, res) => {
  let raw = "";
  for await (const c of req) raw += c;
  const msg = JSON.parse(raw || "{}");
  seen.push({ method: msg.method, auth: req.headers.authorization, args: msg.params?.arguments });
  if (req.headers.authorization !== `Bearer ${TOKEN}`) {
    res.writeHead(401, { "Content-Type": "application/json" });
    return res.end(JSON.stringify({ jsonrpc: "2.0", id: msg.id, error: { code: -32001, message: "unauthorized" } }));
  }
  const reply = (result: unknown) => {
    res.writeHead(200, { "Content-Type": "application/json", "Mcp-Session-Id": "s-1" });
    res.end(JSON.stringify({ jsonrpc: "2.0", id: msg.id, result }));
  };
  if (msg.method === "initialize") return reply({ protocolVersion: "2025-03-26", capabilities: { tools: {} }, serverInfo: { name: "acme-weather", version: "1.0.0" } });
  if (msg.method === "tools/list") return reply({ tools: [{ name: "store_weather", description: "Current weather at an ACME store by store code. Use for any store weather question.", inputSchema: { type: "object", properties: { store: { type: "string" } }, required: ["store"] } }] });
  if (msg.method === "tools/call") return reply({ content: [{ type: "text", text: `Store ${msg.params?.arguments?.store}: ${CANARY}` }] });
  reply({});
});
await new Promise<void>((r) => mcp.listen(MCP_PORT, r));

let logs = "";
const srv: ChildProcess = spawn(process.execPath, ["--import", "tsx", "server/express.ts"], { env: { ...process.env, PORT: String(PORT), DEV_USER: "alice", TRUST_SF_CONTEXT_HEADER: "true", NODE_ENV: "production" }, stdio: ["ignore", "pipe", "pipe"] });
srv.stdout!.on("data", (d) => (logs += d));
srv.stderr!.on("data", (d) => (logs += d));
for (let i = 0; i < 120; i++) {
  if (await fetch(`${base}/api/health`).then((r) => r.ok, () => false)) break;
  await new Promise((r) => setTimeout(r, 250));
}

const conn = { id: "mcp-weather", name: "ACME Weather", url: `http://127.0.0.1:${MCP_PORT}/mcp`, enabled: true };
const bodies: string[] = [];
const call = async (path: string, init: RequestInit = {}) => {
  const r = await fetch(`${base}${path}`, init);
  const t = await r.text();
  bodies.push(t);
  return { status: r.status, text: t };
};

const put = await call(`/api/mcp/credentials/${conn.id}`, { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ authHeader: `Authorization: Bearer ${TOKEN}` }) });
check(put.status === 200 && JSON.parse(put.text).hasAuth === true, "store MCP auth header server-side", put.text);
const get = await call(`/api/mcp/credentials/${conn.id}`);
check(JSON.parse(get.text).hasAuth === true && !get.text.includes(TOKEN), "GET credentials returns hasAuth only", get.text);
const test = await call("/api/mcp/test", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(conn) });
check(JSON.parse(test.text).tools?.[0] === "mcp__acme_weather__store_weather", "tools/list via stored credential", test.text);
const bob = await call("/api/mcp/test", { method: "POST", headers: { "Content-Type": "application/json", "Sf-Context-Current-User": "bob" }, body: JSON.stringify(conn) });
check(/unauthorized/.test(bob.text), "another user cannot use alice's credential", bob.text);

const chat = await call("/api/chat", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ conversationId: "mcp-e2e", mode: "assist", browserTools: false, mcp: [conn], content: [{ type: "text", text: "What's the weather at store W-17 right now? Use the ACME Weather MCP tool and quote its answer." }] }),
});
const events = chat.text.split("\n\n").map((b) => ({ event: b.match(/^event: (.*)$/m)?.[1], data: b.match(/^data: (.*)$/m)?.[1] }));
const toolUse = events.find((e) => e.event === "response.tool_use" && e.data?.includes("mcp__acme_weather__store_weather"));
const toolResult = events.find((e) => e.event === "response.tool_result" && e.data?.includes("MCP-4471"));
const text = events.filter((e) => e.event === "response.text.delta").map((e) => JSON.parse(e.data!).text ?? "").join("");
const done = events.find((e) => e.event === "acme.done");
check(!!toolUse, "agent called the MCP tool");
check(!!toolResult && seen.some((s) => s.method === "tools/call" && s.auth === `Bearer ${TOKEN}`), "proxy executed tools/call with the stored header", JSON.stringify(seen.filter((s) => s.method === "tools/call").map((s) => s.args)));
check(/MCP-4471|drizzle/i.test(text) && JSON.parse(done?.data ?? "{}").status === "completed", "agent answered from the MCP result", text.trim().slice(0, 140));
check(!bodies.some((b) => b.includes(TOKEN)) && !logs.includes(TOKEN), "auth header never echoed in responses or logs");

srv.kill("SIGTERM");
mcp.close();
await new Promise((r) => srv.once("exit", r));
console.log(failures ? `\n${failures} MCP check(s) failed` : "\nAll MCP checks passed");
process.exit(failures ? 1 : 0);
