// Probe: background lite runs (stream:false, background:true) with a client-side tool,
// replayed through client.runs.stream(runId, { startingAfter }). Usage: npx tsx scripts/bg-probe.ts
import { loadEnv } from "../server/env";
loadEnv();
const { agentClient } = await import("../server/auth");
const { agentSpec } = await import("../server/agent");
const { config } = await import("../server/config");
const cfg = config();
const client = agentClient();
const tool = { tool_spec: { type: "generic", name: "get_store_weather", description: "Returns current weather at an ACME store. Use it for any weather question.", input_schema: { type: "object", properties: { store: { type: "string" } }, required: ["store"] } } };
const spec = await agentSpec(client, cfg.agentName);
const thread = await client.threads.create({ origin_application: "acme_assist" } as any);
const thread_id = String((thread.responseBody as any).thread_id);
const instructions: any = { ...(spec.instructions ?? {}) };
delete instructions.sample_questions;
const base = { models: spec.models, instructions, tools: [...(spec.tools ?? []), tool], tool_resources: spec.tool_resources, thread_id };

async function turn(content: unknown[], parent: string) {
  const t0 = Date.now();
  const r: any = await client.agent.run({ ...base, parent_message_id: parent, messages: [{ role: "user", content }], stream: false, background: true } as any);
  console.log(`kickoff ${Date.now() - t0}ms runId=${r.runId} status=${r.initialStatus} body=${JSON.stringify(r.responseBody).slice(0, 300)}`);
  let use: any, assistantId = "", text = "", n = 0, firstSeqs: unknown[] = [];
  // read a few events, then disconnect and replay from startingAfter
  const ctrl = new AbortController();
  let last: number | undefined;
  try {
    for await (const ev of client.runs.stream(r.runId, { signal: ctrl.signal }) as AsyncIterable<any>) {
      n++;
      if (n <= 3) firstSeqs.push(Object.keys(ev).join(","));
      last = ev.sequence_number ?? ev.seq ?? ev.id ?? last;
      if (n === 4) { ctrl.abort(); break; }
    }
  } catch (e: any) { console.log("abort:", e.name); }
  console.log(`first events keys: ${JSON.stringify(firstSeqs)} lastSeq=${last}`);
  let m = 0;
  for await (const ev of client.runs.stream(r.runId, last !== undefined ? { startingAfter: Number(last) } : {}) as AsyncIterable<any>) {
    m++;
    if (ev.event === "response.tool_use") console.log(`  tool_use ${ev.name} client_side_execute=${ev.client_side_execute}`);
    if (ev.event === "response.tool_use" && ev.client_side_execute) use = ev;
    if (ev.event === "metadata" && ev.metadata?.role === "assistant") assistantId = String(ev.metadata.message_id);
    if (ev.event === "response.text.delta") text += ev.text ?? "";
    if (ev.event === "error") console.log("  error", ev.message);
  }
  console.log(`replay events=${m}`);
  return { use, assistantId, text, runId: r.runId };
}
const t1 = await turn([{ type: "text", text: "What's the weather at store W-17? Use the get_store_weather tool." }], "0");
if (!t1.use) { console.log("RESULT: no client_side_execute tool_use in background run"); process.exit(1); }
const t2 = await turn([{ type: "tool_result", tool_result: { tool_use_id: t1.use.tool_use_id, name: t1.use.name, content: [{ type: "json", json: { store: "W-17", condition: "Sunny", temp_f: 71 } }] } }], t1.assistantId);
console.log("answer:", t2.text.slice(0, 200));
// cancel test on a fresh run
const r3: any = await client.agent.run({ ...base, thread_id: String(((await client.threads.create({ origin_application: "acme_assist" } as any)).responseBody as any).thread_id), parent_message_id: "0", messages: [{ role: "user", content: [{ type: "text", text: "Write a 400 word essay on retail fulfillment." }] }], stream: false, background: true } as any);
await new Promise((s) => setTimeout(s, 3000));
const c = await client.runs.cancel(r3.runId);
let tail = 0, sawCancel = "";
for await (const ev of client.runs.stream(r3.runId) as AsyncIterable<any>) { tail++; if (/status|response$/.test(ev.event)) sawCancel = JSON.stringify(ev).slice(0, 160); }
console.log("after cancel events:", tail, sawCancel);
console.log("cancel:", c.response.status, JSON.stringify(c.responseBody).slice(0, 200));
console.log("RESULT:", /71|sunny/i.test(t2.text) ? "PASS" : "FAIL");
