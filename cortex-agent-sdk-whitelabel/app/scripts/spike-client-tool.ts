// Step 0 spike: client-side tool execution through @snowflake/cortex-agent-sdk@0.0.1.
//  A. Named agent (client.agent.runData) + an extra `generic` tool  -> expected: not usable
//  B. Lite run (client.agent.stream) with the named agent's spec (client.agent.describe)
//     + the generic tool, inside a thread -> expect response.tool_use client_side_execute:true,
//     then send ONLY a tool_result (parent_message_id = assistant message id) and get an answer.
// Usage: npm run spike
import { CortexAgentClient } from "@snowflake/cortex-agent-sdk";
import { loadEnv } from "../server/env";

loadEnv();
const { agentClient } = await import("../server/auth");
const { agentSpec } = await import("../server/agent");
const { config } = await import("../server/config");

const cfg = config();
const client: CortexAgentClient = agentClient();
const target = { database: cfg.agentDatabase, schema: cfg.agentSchema, name: cfg.agentName };
const tool = { tool_spec: { type: "generic", name: "get_store_weather", description: "Returns current weather at an ACME store. Use it for any weather question.", input_schema: { type: "object", properties: { store: { type: "string" } }, required: ["store"] } } };
const ask = { role: "user", content: [{ type: "text", text: "What's the weather at store W-17? Use the get_store_weather tool." }] };

console.log("A. runData (named agent) + extra generic tool");
let aClient = false;
let aError = "";
for await (const ev of client.agent.runData(target, { messages: [ask], tools: [tool], tool_choice: { type: "tool", name: ["get_store_weather"] } } as any) as AsyncIterable<any>) {
  if (ev.event === "response.tool_use" && ev.client_side_execute) aClient = true;
  if (ev.event === "error") aError = ev.message;
}
console.log(`   client_side_execute seen: ${aClient}${aError ? `; error: ${aError}` : ""}`);

console.log("B. lite run with hydrated named-agent spec + generic tool, in a thread");
const spec = await agentSpec(client, cfg.agentName);
const thread = await client.threads.create({ origin_application: "acme_assist" } as any);
const thread_id = String((thread.responseBody as any).thread_id);
const instructions = { ...(spec.instructions ?? {}) };
delete (instructions as any).sample_questions;
const base = { models: spec.models, instructions, tools: [...(spec.tools ?? []), tool], tool_resources: spec.tool_resources, thread_id };

async function turn(content: unknown[], parent: string) {
  let use: any;
  let assistantId = "";
  let text = "";
  for await (const ev of client.agent.stream({ ...base, parent_message_id: parent, messages: [{ role: "user", content }] } as any) as AsyncIterable<any>) {
    if (ev.event === "response.tool_use") console.log(`   tool_use ${ev.name} client_side_execute=${ev.client_side_execute} input=${JSON.stringify(ev.input)}`);
    if (ev.event === "response.tool_use" && ev.client_side_execute) use = ev;
    if (ev.event === "metadata" && ev.metadata?.role === "assistant") assistantId = String(ev.metadata.message_id);
    if (ev.event === "metadata" && ev.metadata?.run_id) console.log(`   run_id ${ev.metadata.run_id}`);
    if (ev.event === "response.text.delta") text += ev.text ?? "";
    if (ev.event === "error") console.log("   error", ev.message);
  }
  return { use, assistantId, text };
}

const t1 = await turn(ask.content, "0");
if (!t1.use) {
  console.error("FAIL: no client_side_execute tool_use on the lite path");
  process.exit(1);
}
const t2 = await turn([{ type: "tool_result", tool_result: { tool_use_id: t1.use.tool_use_id, name: t1.use.name, content: [{ type: "json", json: { store: "W-17", condition: "Sunny", temp_f: 71 } }] } }], t1.assistantId);
console.log(`   answer: ${t2.text.trim().slice(0, 200)}`);
const pass = /71|sunny/i.test(t2.text);
console.log(pass ? "PASS: client_side_execute:true round trip completed with tool_result" : "FAIL: answer did not use the tool_result");
process.exit(pass ? 0 : 1);
