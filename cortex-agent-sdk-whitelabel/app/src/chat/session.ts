// Client side of an agent turn: POST /api/chat (SSE), reattach via
// GET /api/runs/:id/events?after=<seq> on disconnect (4 retries, backoff), then run the
// client-side tool loop: browser tools execute against the sidebar, permission prompts and
// data-agent-confirm actions become approval cards, and results go back as tool_result /
// permission_decision items on the same thread.
import type { ChatMode, ChatRequest, RunEnvelope, UserContentItem } from "../../shared/protocol";
import { executeBrowserTool, type ToolCall } from "../agent/executor";
import { BROWSER_TOOL_NAMES, browserToolLabel } from "../agent/tools/browser";
import { requestContributions } from "../plugins/registry";
import { getSettings } from "../settings/settings";
import { getConversation, updateConversation, updateMessage } from "./store";
import type { Approval, PendingTool, Step, UIMessage } from "./types";

const controllers = new Map<string, AbortController>();
const approvalWaiters = new Map<string, (decision: string) => void>();
const sid = () => Math.random().toString(36).slice(2, 10);

export function emptyAssistant(mode: ChatMode): UIMessage {
  return { id: sid(), role: "assistant", text: "", steps: [], tables: [], charts: [], approvals: [], files: [], status: "submitting", started: Date.now(), mode };
}

// ---------------------------------------------------------------- event -> UI mapping

function upsertStep(m: UIMessage, step: Partial<Step> & { id: string }): UIMessage {
  const i = m.steps.findIndex((s) => s.id === step.id);
  if (i < 0) return { ...m, steps: [...m.steps, { kind: "tool", label: "", state: "running", at: Date.now(), ...step } as Step] };
  const steps = m.steps.slice();
  steps[i] = { ...steps[i], ...step };
  return { ...m, steps };
}

function describeToolUse(d: any): Pick<Step, "kind" | "label" | "detail" | "sql"> {
  const name: string = d.name ?? "";
  const type: string = d.type ?? "";
  if (BROWSER_TOOL_NAMES.has(name)) return { kind: "browser", label: browserToolLabel(name, d.input) };
  if (name.startsWith("mcp__")) return { kind: "mcp", label: `Calling ${name.replace(/^mcp__/, "").replace("__", " · ")}` };
  if (name === "system_execute_sql" || d.input?.sql) return { kind: "sql", label: "Running SQL", sql: d.input?.sql };
  if (/analyst/.test(type) || /analyst|semantic/.test(name)) return { kind: "analyst", label: `Querying ${name}` };
  if (/chart/.test(type) || /chart/.test(name)) return { kind: "chart", label: "Building chart" };
  if (/search/.test(type)) return { kind: "search", label: `Searching ${name}` };
  if (/code|sandbox|bash|write|edit|read|grep|glob/.test(type + name)) {
    const i = d.input ?? {};
    return { kind: "sandbox", label: i.command ? `$ ${String(i.command).slice(0, 120)}` : i.file_path || i.path ? `${name} ${i.file_path ?? i.path}` : `Sandbox: ${name}`, detail: JSON.stringify(i, null, 2).slice(0, 4000) };
  }
  return { kind: "tool", label: `Using ${name || type}` };
}

function approvalPreview(input: Record<string, any> = {}): string {
  if (input.command) return `$ ${input.command}`;
  if (input.old_string !== undefined || input.new_string !== undefined) return `--- ${input.file_path ?? ""}\n- ${String(input.old_string ?? "").split("\n").join("\n- ")}\n+ ${String(input.new_string ?? "").split("\n").join("\n+ ")}`;
  if (input.content !== undefined) return `+++ ${input.file_path ?? input.path ?? ""}\n${String(input.content).slice(0, 2000)}`;
  return JSON.stringify(input, null, 2).slice(0, 2000);
}

function resultSetToTable(id: string, rs: any) {
  const cols = (rs?.resultSetMetaData?.rowType ?? []).map((c: any) => ({ name: c.name, type: c.type }));
  return { id, columns: cols, rows: rs?.data ?? [] };
}

function applyEvent(convId: string, msgId: string, env: RunEnvelope) {
  const { event, data } = env;
  updateConversation(convId, (c) => ({ ...c, wire: { ...c.wire, lastSeq: env.seq, ...(event === "acme.run" ? { runId: data.runId, threadId: data.threadId ?? c.wire.threadId, runActive: true } : {}), ...(event === "metadata" && data.metadata?.role === "assistant" ? { parentMessageId: String(data.metadata.message_id) } : {}), ...(event === "acme.studio.session" ? { studioSessionId: data.sessionId } : {}) } }), false);
  updateMessage(convId, msgId, (m) => {
    switch (event) {
      case "response.status":
        if (m.steps.at(-1)?.label === data.message) return m;
        return upsertStep({ ...m, status: m.status === "submitting" ? "thinking" : m.status }, { id: `st-${env.seq}`, kind: "status", label: data.message ?? data.status, state: "done" });
      case "response.thinking.delta":
      case "acme.studio.thinking":
        return { ...m, status: m.status === "streaming" ? m.status : "thinking", thinking: (m.thinking ?? "") + (data.text ?? "") };
      case "response.text.delta":
      case "acme.studio.text":
        return { ...m, status: "streaming", text: m.text + (data.text ?? "") };
      case "response.tool_use": {
        const d = describeToolUse(data);
        const writePath = data.input?.file_path ?? data.input?.path;
        const file = data.name === "write" && typeof data.input?.content === "string" && writePath ? { name: String(writePath).split("/").pop()!, content: data.input.content as string } : undefined;
        let next = upsertStep({ ...m, status: m.status === "streaming" ? m.status : "thinking" }, { id: data.tool_use_id, toolUseId: data.tool_use_id, ...d, state: "running", file });
        const isClient = data.client_side_execute && !String(data.name).startsWith("mcp__") && data.name !== "snowflake_sql_execute";
        if (isClient || data.permission?.options?.length) {
          const p: PendingTool = { tool_use_id: data.tool_use_id, name: data.name, input: data.input ?? {}, permission: data.permission, type: data.type };
          next = { ...next, pending: [...(next.pending ?? []).filter((x) => x.tool_use_id !== p.tool_use_id), p] };
        }
        return next;
      }
      case "response.tool_result": {
        const json = data.content?.find((x: any) => x.json)?.json;
        const failed = data.status === "error" || json?.error;
        const step = m.steps.find((s) => s.id === data.tool_use_id);
        if (step?.file && !failed && !m.files.some((f) => f.name === step.file!.name)) {
          const type = /\.svg$/i.test(step.file.name) ? "image/svg+xml" : /\.csv$/i.test(step.file.name) ? "text/csv" : "text/plain";
          m = { ...m, files: [...m.files, { name: step.file.name, url: `data:${type};charset=utf-8,${encodeURIComponent(step.file.content)}`, size: step.file.content.length }] };
        }
        return upsertStep(m, { id: data.tool_use_id, state: failed ? "error" : "done", ...(json?.sql ? { sql: json.sql } : {}), ...(failed ? { detail: String(json?.error ?? "error") } : {}) });
      }
      case "response.table":
        return { ...m, tables: [...m.tables, resultSetToTable(`t-${env.seq}`, data.result_set)] };
      case "response.chart":
        return { ...m, charts: [...m.charts, { id: `c-${env.seq}`, spec: data.chart_spec }] };
      case "response.asset":
      case "acme.studio.files": {
        const files = (data.files ?? [data]).filter((f: any) => f?.url || f?.name).map((f: any) => ({ name: f.name ?? f.title ?? "file", url: f.url ?? f.download_url ?? "#", size: f.size }));
        // Server copies (/api/files/...) replace inline data: chips of the same name.
        return { ...m, files: [...m.files.filter((x) => !files.some((f: any) => f.name === x.name)), ...files] };
      }
      case "acme.studio.skills":
        return { ...m, skills: data.skills };
      case "acme.studio.tool":
        return upsertStep({ ...m, status: "thinking" }, { id: data.id, kind: "studio", label: data.label ?? data.name, detail: data.detail, state: "running" });
      case "acme.studio.tool_result":
        return upsertStep(m, { id: data.id, state: data.ok ? "done" : data.denied ? "denied" : "error" });
      case "acme.approval":
        if (m.approvals.some((a) => a.id === data.id)) return m;
        return { ...m, approvals: [...m.approvals, { id: data.id, toolUseId: data.id, source: "studio", title: data.title ?? `Allow ${data.tool}?`, preview: data.preview, options: ["Allow Once", "Deny"], state: "pending" }] };
      case "acme.server_tool_results":
        return { ...m, serverToolResults: [...(m.serverToolResults ?? []), ...data.items] };
      case "error":
      case "acme.error":
        return { ...m, status: "error", error: data.message ?? "Agent error" };
      case "acme.done":
        if (data.status === "cancelled") return { ...m, status: "cancelled", ended: Date.now(), steps: m.steps.map((s) => (s.state === "running" ? { ...s, state: "error" } : s)) };
        return m;
      default:
        return m;
    }
  });
}

// ---------------------------------------------------------------- SSE plumbing

async function consume(res: Response, convId: string, msgId: string, signal: AbortSignal): Promise<string | undefined> {
  if (!res.ok || !res.body) {
    const err = await res.text().catch(() => "");
    applyEvent(convId, msgId, { seq: getConversation(convId)?.wire.lastSeq ?? 0, event: "acme.error", data: { message: `Request failed (${res.status}) ${err}` } });
    return "error";
  }
  const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();
  let buf = "";
  let done: string | undefined;
  try {
    while (!signal.aborted) {
      const { value, done: end } = await reader.read();
      if (end) break;
      buf += value;
      let i: number;
      while ((i = buf.indexOf("\n\n")) >= 0) {
        const block = buf.slice(0, i);
        buf = buf.slice(i + 2);
        const id = block.match(/^id: (\d+)$/m)?.[1];
        const event = block.match(/^event: (.*)$/m)?.[1];
        const data = block.match(/^data: (.*)$/m)?.[1];
        if (!id || !event || data === undefined) continue; // keepalive comment
        const env: RunEnvelope = { seq: Number(id), event, data: JSON.parse(data) };
        if (env.seq <= (getConversation(convId)?.wire.lastSeq ?? 0) && event !== "acme.run") continue;
        applyEvent(convId, msgId, env);
        if (event === "acme.done") done = env.data.status;
      }
    }
  } catch {
    /* network drop: caller reattaches */
  }
  return done;
}

async function reattach(convId: string, msgId: string, signal: AbortSignal): Promise<string | undefined> {
  for (let attempt = 0; attempt < 4 && !signal.aborted; attempt++) {
    const c = getConversation(convId);
    if (!c?.wire.runId) return undefined;
    if (attempt > 0) await new Promise((r) => setTimeout(r, 500 * 2 ** attempt));
    const res = await fetch(`/api/runs/${c.wire.runId}/events?after=${c.wire.lastSeq ?? 0}`, { signal }).catch(() => undefined);
    if (res?.status === 404) return "gone";
    if (!res) continue;
    updateMessage(convId, msgId, (m) => (m.steps.some((s) => s.kind === "reconnect" && s.at > Date.now() - 2000) ? m : upsertStep(m, { id: `rc-${Date.now()}`, kind: "reconnect", label: "Reconnected", state: "done" })));
    const done = await consume(res, convId, msgId, signal);
    if (done) return done;
  }
  return undefined;
}

// ---------------------------------------------------------------- public API

export interface TurnOptions {
  mode: ChatMode;
  browserTools?: boolean;
}

function baseRequest(convId: string, mode: ChatMode, content: UserContentItem[]): ChatRequest {
  const c = getConversation(convId)!;
  const s = getSettings();
  return {
    conversationId: convId,
    mode,
    threadId: c.wire.threadId,
    parentMessageId: c.wire.parentMessageId,
    content,
    model: s.model,
    user: { name: s.name || undefined, email: s.email || undefined },
    browserTools: true,
    studioSessionId: c.wire.studioSessionId,
    ...(requestContributions() as Partial<ChatRequest>),
  };
}

export async function sendTurn(convId: string, msgId: string, content: UserContentItem[], mode: ChatMode): Promise<void> {
  const ctrl = new AbortController();
  controllers.set(convId, ctrl);
  try {
    const res = await fetch("/api/chat", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(baseRequest(convId, mode, content)), signal: ctrl.signal });
    let done = await consume(res, convId, msgId, ctrl.signal);
    if (!done && !ctrl.signal.aborted) done = await reattach(convId, msgId, ctrl.signal);
    await afterRun(convId, msgId, mode, done, ctrl.signal);
  } catch (e: any) {
    if (!ctrl.signal.aborted) updateMessage(convId, msgId, (m) => ({ ...m, status: "error", error: e.message }));
  } finally {
    if (controllers.get(convId) === ctrl) {
      controllers.delete(convId);
      updateConversation(convId, (c) => c, false); // re-render: busy state changed
    }
  }
}

/** After a reload: reattach to an in-flight run, or re-ask pending tools/approvals. */
export async function resumeConversation(convId: string): Promise<void> {
  const c = getConversation(convId);
  const msg = c?.messages.at(-1);
  if (!c || !msg || msg.role !== "assistant" || controllers.has(convId)) return;
  if (["done", "error", "cancelled"].includes(msg.status) && !msg.pending?.length) return;
  const ctrl = new AbortController();
  controllers.set(convId, ctrl);
  try {
    const done = c.wire.runActive ? await reattach(convId, msg.id, ctrl.signal) : "completed";
    await afterRun(convId, msg.id, msg.mode ?? "assist", done, ctrl.signal);
  } finally {
    controllers.delete(convId);
    updateConversation(convId, (c) => c, false);
  }
}

async function afterRun(convId: string, msgId: string, mode: ChatMode, done: string | undefined, signal: AbortSignal) {
  updateConversation(convId, (c) => ({ ...c, wire: { ...c.wire, runActive: false } }));
  const msg = getConversation(convId)?.messages.find((m) => m.id === msgId);
  if (!msg || signal.aborted) return;
  if (done !== "completed" || !msg.pending?.length) {
    const ok = done === "completed" || done === "gone";
    updateMessage(convId, msgId, (m) => {
      if (m.status === "error" || m.status === "cancelled") return { ...m, ended: m.ended ?? Date.now(), pending: [] };
      return { ...m, status: ok ? "done" : "error", error: ok ? undefined : m.error ?? (done ? `Run ${done}` : "Connection lost"), ended: Date.now(), pending: [] };
    });
    updateConversation(convId, (c) => c);
    return;
  }
  const items: UserContentItem[] = [...((msg.serverToolResults as UserContentItem[]) ?? [])];
  for (const p of msg.pending) {
    if (signal.aborted) return;
    if (p.permission?.options?.length) {
      // Per-action approval only: never offer the session-wide "Allow all ..." options.
      const options = p.permission.options.filter((o) => !/allow all|always/i.test(o));
      const decision = await askApproval(convId, msgId, { id: `perm-${p.tool_use_id}`, toolUseId: p.tool_use_id, source: "agent", title: `${p.name} wants to run`, preview: approvalPreview(p.input), options: options.length ? options : p.permission.options, state: "pending" });
      items.push({ type: "permission_decision", permission_decision: { tool_use_id: p.tool_use_id, decision, ...(/deny/i.test(decision) ? { reason: "denied by user" } : {}) } });
      updateMessage(convId, msgId, (m) => upsertStep(m, { id: p.tool_use_id, state: /deny/i.test(decision) ? "denied" : "running" }));
      continue;
    }
    const call: ToolCall = { tool_use_id: p.tool_use_id, name: p.name, input: p.input };
    const r = await executeBrowserTool(call, async (_call, el) => /allow/i.test(await askApproval(convId, msgId, { id: `confirm-${p.tool_use_id}`, toolUseId: p.tool_use_id, source: "client", title: `Confirm: ${el.label || el.testid}`, preview: browserToolLabel(p.name, p.input), options: ["Allow Once", "Deny"], state: "pending" })));
    updateMessage(convId, msgId, (m) => upsertStep(m, { id: p.tool_use_id, state: r.status, ...(r.status === "error" ? { detail: JSON.stringify(r.json) } : {}) }));
    items.push({ type: "tool_result", tool_result: { tool_use_id: p.tool_use_id, name: p.name, ...(r.status === "done" ? {} : { status: "error" }), content: [{ type: "json", json: r.json }] } });
  }
  updateMessage(convId, msgId, (m) => ({ ...m, pending: [], serverToolResults: [], status: "thinking" }));
  await sendTurn(convId, msgId, items, mode);
}

function askApproval(convId: string, msgId: string, a: Approval): Promise<string> {
  updateMessage(convId, msgId, (m) => ({ ...m, approvals: [...m.approvals.filter((x) => x.id !== a.id), a] }));
  return new Promise((resolve) => approvalWaiters.set(a.id, resolve));
}

/** Called by approval cards. Studio approvals go to the runner via the proxy. */
export async function decideApproval(convId: string, msgId: string, a: Approval, decision: string) {
  updateMessage(convId, msgId, (m) => ({ ...m, approvals: m.approvals.map((x) => (x.id === a.id ? { ...x, state: "decided", decision } : x)) }));
  if (a.source === "studio") {
    const runId = getConversation(convId)?.wire.runId;
    await fetch("/api/studio/approve", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ runId, id: a.id, decision: /allow/i.test(decision) ? "allow" : "deny" }) });
    return;
  }
  const w = approvalWaiters.get(a.id);
  approvalWaiters.delete(a.id);
  if (w) w(decision);
  else void resumeConversation(convId); // after a reload: rebuild the loop, the card re-asks
}

export async function stopTurn(convId: string) {
  const c = getConversation(convId);
  controllers.get(convId)?.abort();
  controllers.delete(convId);
  if (c?.wire.runId) await fetch(`/api/runs/${c.wire.runId}/cancel`, { method: "POST" }).catch(() => undefined);
  const last = c?.messages.at(-1);
  if (last && last.role === "assistant") updateMessage(convId, last.id, (m) => ({ ...m, status: "cancelled", pending: [], ended: Date.now(), approvals: m.approvals.map((x) => ({ ...x, state: "decided", decision: x.decision ?? "Cancelled" })) }));
  updateConversation(convId, (cc) => ({ ...cc, wire: { ...cc.wire, runActive: false } }));
}

export const isBusy = (convId: string) => controllers.has(convId);
