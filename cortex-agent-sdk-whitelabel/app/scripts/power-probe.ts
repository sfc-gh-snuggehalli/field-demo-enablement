// Power Mode probe: observes code_toolset_all permission prompts and how sandbox files surface.
// Sends one turn to ACME_POWER_AGENT through the proxy, answers every permission prompt with
// "Allow Once" (sandbox-only actions), and prints tool_use/tool_result/asset event shapes.
// Usage: npx tsx scripts/power-probe.ts
import { loadEnv } from "../server/env";

loadEnv();
process.env.POWER_MODE_ENABLED = "true";
const { dispatch } = await import("../server/handlers");

let threadId: string | undefined;
let parentMessageId: string | undefined;
let content: any[] = [{ type: "text", text: "Using acme_analyst, get the count of FAILED orders by carrier. Then in the sandbox write output/failed_by_carrier.csv with those rows. Reply with the file name." }];
for (let hop = 0; hop < 8; hop++) {
  const res = await dispatch(new Request("http://local/api/chat", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ conversationId: "powerprobe", mode: "power", threadId, parentMessageId, content, browserTools: false }) }));
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
      console.log(`tool_use name=${data.name} type=${data.type} client=${data.client_side_execute} permission=${JSON.stringify(data.permission)} input=${JSON.stringify(data.input).slice(0, 200)}`);
      if (data.permission?.options?.length) pending.push(data);
    }
    if (ev === "response.tool_result") console.log(`tool_result ${data.name ?? ""} ${JSON.stringify(data.content).slice(0, 300)}`);
    if (!/delta|status|tool_use|tool_result|^response$|metadata|acme.run/.test(ev)) console.log(`event ${ev} ${JSON.stringify(data).slice(0, 400)}`);
    if (ev === "response") console.log(`response content types: ${JSON.stringify((data.content ?? []).map((c: any) => c.type))}`);
    if (ev === "response.text") console.log(`text: ${String(data.text).slice(0, 300)}`);
  }
  if (!pending.length) break;
  content = pending.map((p) => ({ type: "permission_decision", permission_decision: { tool_use_id: p.tool_use_id, decision: p.permission.options.find((o: string) => /allow/i.test(o)) ?? p.permission.options[0] } }));
  console.log(`-> replying ${JSON.stringify(content.map((c) => c.permission_decision.decision))}`);
}
process.exit(0);
