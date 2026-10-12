// Studio mode: relays a turn to the CoCo runner (coco-runner/, @snowflake/cortex-agent-sdk/code)
// and maps its SSE messages onto run events. The proxy adds the owner hash; the runner
// owns the session and guards file paths.
import type { ChatRequest } from "../shared/protocol";
import { ProxyEvent } from "../shared/protocol";
import { config } from "./config";
import { ownerHash } from "./identity";
import { emit, finish, type Run } from "./runs";

export async function runStudio(run: Run, req: ChatRequest, owner: string): Promise<void> {
  const base = config().cocoRunnerUrl!;
  const prompt = req.content.filter((c) => c.type === "text").map((c: any) => c.text).join("\n");
  run.onCancel = async () => void (await fetch(`${base}/turns/${run.id}/interrupt`, { method: "POST" }).catch(() => undefined));
  emit(run, ProxyEvent.Run, { runId: run.id, mode: "studio" });
  try {
    const res = await fetch(`${base}/turns`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ turnId: run.id, owner: ownerHash(owner), conversationId: req.conversationId, prompt, resume: req.studioSessionId, user: req.user }),
      signal: run.abort.signal,
    });
    if (!res.ok || !res.body) throw new Error(`Studio runner ${res.status}`);
    const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();
    let buf = "";
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      buf += value;
      let i: number;
      while ((i = buf.indexOf("\n\n")) >= 0) {
        const block = buf.slice(0, i);
        buf = buf.slice(i + 2);
        const ev = block.match(/^event: (.*)$/m)?.[1];
        const data = block.match(/^data: (.*)$/m)?.[1];
        if (ev && data) emit(run, ev, JSON.parse(data));
      }
    }
    finish(run, "completed");
  } catch (e: any) {
    if (run.status !== "running") return;
    emit(run, ProxyEvent.Error, { message: e.message });
    finish(run, "error");
  }
}

export async function studioApprove(body: { turnId: string; id: string; decision: "allow" | "deny" }): Promise<Response> {
  const r = await fetch(`${config().cocoRunnerUrl}/approvals`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  return new Response(await r.text(), { status: r.status, headers: { "Content-Type": "application/json" } });
}

export async function studioFile(owner: string, conversation: string, file: string): Promise<Response> {
  const r = await fetch(`${config().cocoRunnerUrl}/files/${ownerHash(owner)}/${encodeURIComponent(conversation)}/${encodeURIComponent(file)}`);
  return new Response(r.body, { status: r.status, headers: { "Content-Type": r.headers.get("content-type") ?? "application/octet-stream", "Content-Disposition": `attachment; filename="${file.replace(/"/g, "")}"` } });
}
