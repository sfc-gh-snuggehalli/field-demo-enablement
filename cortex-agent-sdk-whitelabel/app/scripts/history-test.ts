// HISTORY_STORE=snowflake end to end (npm run test:history): DEV_USER=alice saves a conversation,
// the row is in ACME_ASSIST_DEMO.APP.CONVERSATIONS (checked with a bind-parameter query),
// DEV_USER=bob cannot see / fetch / delete it, alice deletes it.
import { spawn, type ChildProcess } from "node:child_process";
import { loadEnv } from "../server/env";

loadEnv();
const { sql } = await import("../server/sqlapi");
const PORT = 8096;
const base = `http://127.0.0.1:${PORT}`;
let failures = 0;
const check = (ok: boolean, name: string, detail = "") => {
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? `  (${detail})` : ""}`);
};

async function server(user: string): Promise<ChildProcess> {
  const p = spawn(process.execPath, ["--import", "tsx", "server/express.ts"], { env: { ...process.env, PORT: String(PORT), DEV_USER: user, HISTORY_STORE: "snowflake" }, stdio: "ignore" });
  for (let i = 0; i < 120; i++) {
    if (await fetch(`${base}/api/health`).then((r) => r.ok, () => false)) return p;
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error("server did not start");
}
const stop = (p: ChildProcess) => new Promise((r) => (p.kill("SIGTERM"), p.once("exit", r)));

const id = `hist-${Date.now()}`;
const now = new Date().toISOString();
const rec = { id, title: "History store test", brand: "acme", ui: [{ role: "user", text: "hello" }], wire: { threadId: "1" }, created: now, updated: now };
const row = async () => sql("SELECT owner_user, title FROM ACME_ASSIST_DEMO.APP.CONVERSATIONS WHERE conversation_id = ?", [id], { role: process.env.HISTORY_ROLE || "ACME_HISTORY_ROLE" });

let p = await server("alice");
const put = await fetch(`${base}/api/conversations/${id}`, { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify(rec) });
check(put.status === 200, "alice saves a conversation", String(put.status));
const rows = await row();
check(rows.length === 1 && rows[0].owner_user === "alice", "row in ACME_ASSIST_DEMO.APP.CONVERSATIONS (bind params)", JSON.stringify(rows));
const own = (await (await fetch(`${base}/api/conversations`)).json()) as any[];
check(own.some((c) => c.id === id), "alice lists it");
await stop(p);

p = await server("bob");
const bobList = (await (await fetch(`${base}/api/conversations`)).json()) as any[];
check(!bobList.some((c) => c.id === id), "bob's list does not include it", `${bobList.length} items`);
const bobGet = await fetch(`${base}/api/conversations/${id}`);
check(bobGet.status === 404, "bob GET -> 404", String(bobGet.status));
await fetch(`${base}/api/conversations/${id}`, { method: "DELETE" });
check((await row()).length === 1, "bob DELETE does not remove alice's row");
// An injection-shaped id is rejected by the route before any SQL.
const inj = await fetch(`${base}/api/conversations/${encodeURIComponent("x' OR '1'='1")}`);
check(inj.status === 404, "injection-shaped id rejected", String(inj.status));
await stop(p);

p = await server("alice");
const del = await fetch(`${base}/api/conversations/${id}`, { method: "DELETE" });
check(del.status === 200 && (await row()).length === 0, "alice deletes it; row gone");
await stop(p);
console.log(failures ? `\n${failures} history check(s) failed` : "\nAll history checks passed");
process.exit(failures ? 1 : 0);
