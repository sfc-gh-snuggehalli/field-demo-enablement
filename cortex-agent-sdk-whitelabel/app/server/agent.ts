// Agent runs. The named agents (ACME_ASSIST_AGENT / ACME_POWER_AGENT) are the source of
// truth for models, instructions, tools, tool_resources and the orchestration budget. Finding
// from the spike (README): the named-agent endpoint (client.agent.runData / streamData) rejects
// extra per-request tools ("Tool names ... are not allowed") and has no `models` override, so
// the proxy hydrates the named agent's spec (client.agent.describe -> agent_spec, cached with a
// TTL and revalidated on created_on / spec hash), then runs it through the lite endpoint with
// the client-side browser tools, MCP tools, skills, user context and data date merged in.
//
// Runs start in Agent API background mode (client.agent.run({ stream: false, background: true }))
// and are read through client.runs.stream(runId, { startingAfter }). Each upstream event's
// sequence_number maps to a proxy seq, and the run metadata is persisted (server/runstore.ts),
// so a reattach after a restart, or on another instance, resumes from Snowflake's run stream.
// Stop cancels upstream with client.runs.cancel. AGENT_BACKGROUND_RUNS=false restores the
// foreground stream (resumable only within one process).
import { createHash } from "node:crypto";
import type { CortexAgentClient } from "@snowflake/cortex-agent-sdk";
import { browserToolGuidance, browserToolSpecs } from "../src/agent/tools/browser";
import type { ChatRequest, UserContentItem } from "../shared/protocol";
import { ProxyEvent } from "../shared/protocol";
import { agentClient } from "./auth";
import { config } from "./config";
import { dataDate } from "./datadate";
import { log } from "./log";
import { bindMcp, type McpBinding } from "./mcp";
import { sql } from "./sqlapi";
import { createRun, emit, finish, type Run } from "./runs";
import { persistRun, type RunRecord } from "./runstore";
import { backoffMs } from "./http";
import { followUp, observe } from "./deliverables";

export interface AgentSpec {
  models?: { orchestration?: string };
  instructions?: Record<string, unknown>;
  tools?: unknown[];
  tool_resources?: Record<string, unknown>;
  orchestration?: unknown;
}

/** Describe failed: surfaced to the browser as a 503 with this message. */
export class AgentUnavailableError extends Error {
  constructor(name: string, cause: unknown) {
    super(`Agent ${name} is unavailable (describe failed: ${(cause as any)?.status ?? ""} ${(cause as any)?.message ?? cause})`.replace(/\s+/g, " "));
    this.name = "AgentUnavailableError";
  }
}

const backgroundRuns = () => process.env.AGENT_BACKGROUND_RUNS !== "false";
const specTtlMs = () => Number(process.env.AGENT_SPEC_TTL_MS || 5 * 60 * 1000);

interface CachedSpec {
  at: number;
  spec: AgentSpec;
  createdOn: string;
  hash: string;
}
const specCache = ((globalThis as any).__acmeSpecs ??= new Map<string, CachedSpec>()) as Map<string, CachedSpec>;

export const specHash = (raw: unknown) => createHash("sha256").update(typeof raw === "string" ? raw : JSON.stringify(raw)).digest("hex").slice(0, 16);

/** Cached named-agent spec, keyed by database.schema.name. Within the TTL the cache is served;
 *  after it, describe runs again and the entry is replaced; a changed created_on (CREATE OR
 *  REPLACE) or spec hash (ALTER) is logged as an invalidation. Describe failure throws
 *  AgentUnavailableError (no stale fallback: a dropped or revoked agent must not keep serving). */
export async function agentSpec(client: CortexAgentClient, name: string, opts: { force?: boolean } = {}): Promise<AgentSpec> {
  const cfg = config();
  const key = `${cfg.agentDatabase}.${cfg.agentSchema}.${name}`.toUpperCase();
  const hit = specCache.get(key);
  if (hit && !opts.force && Date.now() - hit.at < specTtlMs()) return hit.spec;
  let body: any;
  try {
    const res = await client.agent.describe({ database: cfg.agentDatabase, schema: cfg.agentSchema, name }, { retryPolicy: { maxRetries: Number(process.env.UPSTREAM_RETRIES ?? 3) }, timeout: 15_000 });
    body = res.responseBody;
  } catch (e) {
    specCache.delete(key);
    log("error", "agent describe failed", { agent: key, status: (e as any)?.status, error: (e as any)?.message });
    throw new AgentUnavailableError(name, e);
  }
  const raw = body?.agent_spec;
  const spec: AgentSpec = typeof raw === "string" ? JSON.parse(raw) : raw;
  if (!spec || typeof spec !== "object") throw new AgentUnavailableError(name, new Error("empty agent_spec"));
  const next: CachedSpec = { at: Date.now(), spec, createdOn: String(body.created_on ?? ""), hash: specHash(raw) };
  if (hit && (hit.createdOn !== next.createdOn || hit.hash !== next.hash)) log("info", "agent spec changed; cache invalidated", { agent: key, createdOn: next.createdOn, hash: next.hash });
  specCache.set(key, next);
  return spec;
}

export function invalidateAgentSpec(name?: string): void {
  if (!name) return specCache.clear();
  for (const k of specCache.keys()) if (k.endsWith(`.${name.toUpperCase()}`)) specCache.delete(k);
}

function userContextBlock(req: ChatRequest, signedIn: string | null): string {
  const lines: string[] = [];
  if (signedIn) lines.push(`Signed-in Snowflake user: ${signedIn}`);
  if (req.user?.name) lines.push(`User name: ${req.user.name}`);
  if (req.user?.email) lines.push(`User email: ${req.user.email}`);
  if (!lines.length) return "";
  return `\n\n## User context\n${lines.join("\n")}\nWhen the user says "me" (for example "assign to me"), use this person's name.`;
}

function skillsBlock(req: ChatRequest): string {
  if (!req.skills?.length) return "";
  return "\n\n## Active skills\n" + req.skills.map((s) => `### ${s.name}\n${s.instructions}`).join("\n\n");
}

const toolName = (t: any): string | undefined => t?.tool_spec?.name ?? t?.name;

/** Named-agent tools first, then request tools whose names are not taken. A request tool can
 *  never shadow an agent tool (and so can never pick up its tool_resources). */
export function mergeTools(specTools: unknown[], extra: unknown[]): { tools: unknown[]; dropped: string[] } {
  const seen = new Set<string>();
  const tools: unknown[] = [];
  const dropped: string[] = [];
  for (const t of [...specTools, ...extra]) {
    const n = toolName(t);
    if (n && seen.has(n)) {
      dropped.push(n);
      continue;
    }
    if (n) seen.add(n);
    tools.push(t);
  }
  return { tools, dropped };
}

/** Lite-run body for one turn: the named agent's spec with request additions merged in.
 *  Pure (tested in tests/merge.test.ts). `dataAsOf` is MAX(order_date) (server/datadate.ts). */
export function buildBody(spec: AgentSpec, req: ChatRequest, extraTools: unknown[], signedIn: string | null, dataAsOf = new Date().toISOString().slice(0, 10)) {
  const instructions: Record<string, unknown> = { ...(spec.instructions ?? {}) };
  delete instructions.sample_questions;
  const withBrowser = req.browserTools !== false;
  instructions.orchestration =
    String(instructions.orchestration ?? "") +
    `\n\n## Data freshness\nData current as of ${dataAsOf} (the latest order date). Resolve "today", "this week" and other relative dates against ${dataAsOf}.` +
    (withBrowser ? browserToolGuidance(dataAsOf) : "") +
    skillsBlock(req) +
    userContextBlock(req, signedIn);
  if (req.mode === "power") {
    instructions.orchestration += `\n\n## Deliverables (Power Mode)\nFor every deliverable, first compute the data (SQL or bash), then save it under /workspace/output/: CSV for tabular data (write the CSV text itself with the write tool). Charts may be made with matplotlib (dpi=80, figsize about 8x5) saved under /workspace/output/ as .png; the proxy then asks you to print them as base64 so the user can download them. Keep each file under 1 MB.`;
  }
  const { tools, dropped } = mergeTools(spec.tools ?? [], [...(withBrowser ? browserToolSpecs() : []), ...extraTools]);
  if (dropped.length) log("warn", "dropped duplicate request tools", { tools: dropped });
  const body: Record<string, unknown> = {
    models: { ...(spec.models ?? {}), orchestration: req.model || spec.models?.orchestration || "auto" },
    instructions,
    tools,
    tool_resources: spec.tool_resources ?? {},
    messages: [{ role: "user", content: req.content }],
    thread_id: req.threadId,
    parent_message_id: req.parentMessageId ?? "0",
  };
  if (spec.orchestration) body.orchestration = spec.orchestration;
  // Power Mode: skills backed by a stage path are attached the way code_toolset_all expects.
  const stageSkills = (req.skills ?? []).filter((s: any) => s.stagePath).map((s: any) => ({ name: s.name, source: { type: "STAGE", path: s.stagePath } }));
  if (req.mode === "power" && stageSkills.length) body.skills = stageSkills;
  return body;
}

/** Tools the proxy executes itself when the API hands them back with client_side_execute:
 *  MCP tools, plus the coding agent's `snowflake_sql_execute` (Power Mode), which the
 *  proxy runs read-only through the SQL API with SQL_READONLY_ROLE (caller's rights token
 *  when CALLERS_RIGHTS=true). */
interface ProxyTools {
  owns(name: string): boolean;
  call(name: string, input: any): Promise<unknown>;
}

const READ_ONLY_SQL = /^\s*(select|with|show|describe|desc|explain)\b/i;

function proxyTools(mcp: McpBinding, callerToken?: string): ProxyTools {
  return {
    owns: (n) => mcp.owns(n) || n === "snowflake_sql_execute",
    async call(n, input) {
      if (n !== "snowflake_sql_execute") return mcp.call(n, input);
      const statement = String(input?.sql ?? input?.query ?? "").trim().replace(/;\s*$/, "");
      if (!READ_ONLY_SQL.test(statement) || statement.includes(";")) return { error: "Only single read-only statements (SELECT/WITH/SHOW/DESCRIBE) are allowed." };
      const rows = await sql(statement, [], { role: config().sqlReadonlyRole ?? config().role, callerToken });
      return { row_count: rows.length, rows: rows.slice(0, 1000), truncated: rows.length > 1000 };
    },
  };
}

const record = (run: Run): Omit<RunRecord, "updated"> => ({
  runId: run.id,
  owner: run.owner,
  conversationId: run.conversationId,
  threadId: run.threadId,
  agent: run.agent,
  upstreamRunId: run.upstreamRunId,
  seqBase: run.seqBase,
  lastSeq: run.nextSeq - 1,
  status: run.status,
});

function wireCancel(run: Run, client: CortexAgentClient) {
  run.onCancel = async () => {
    if (!run.upstreamRunId) return;
    try {
      const r = await client.runs.cancel(run.upstreamRunId, { retryPolicy: { maxRetries: 2 } });
      log("info", "upstream run cancelled", { runId: run.id, upstreamRunId: run.upstreamRunId, status: r.response.status });
    } catch (e: any) {
      log("warn", "upstream cancel failed", { runId: run.id, upstreamRunId: run.upstreamRunId, status: e?.status, error: e?.message });
    }
  };
}

/** Runs one agent turn (plus proxy-side MCP / SQL tool loops) into `run`. */
export async function runAgent(run: Run, req: ChatRequest, signedIn: string | null, callerToken?: string): Promise<void> {
  const cfg = config();
  const client = agentClient(callerToken);
  const name = req.mode === "power" && cfg.powerModeEnabled ? cfg.powerAgentName : cfg.agentName;
  run.agent = name;
  wireCancel(run, client);
  try {
    const [spec, mcp, asOf] = await Promise.all([agentSpec(client, name), bindMcp(req.mcp, run.owner), dataDate()]);
    for (const e of mcp.errors) emit(run, "response.status", { status: "mcp_error", message: `MCP unavailable: ${e}` });
    let threadId = req.threadId;
    if (!threadId) {
      const t = await client.threads.create({ origin_application: "acme_assist" } as any, { retryPolicy: { maxRetries: 2 } });
      threadId = String((t.responseBody as any).thread_id);
    }
    run.threadId = threadId;
    emit(run, ProxyEvent.Run, { runId: run.id, threadId, agent: name });
    let turn: ChatRequest = { ...req, threadId };
    for (let hop = 0; hop < 8; hop++) {
      const next = await streamOnce(run, client, buildBody(spec, turn, mcp.specs, signedIn, asOf), proxyTools(mcp, callerToken));
      if (!next || run.status !== "running") break;
      turn = { ...turn, content: next.content, parentMessageId: next.parentMessageId };
    }
    if (run.status === "running") finish(run, "completed");
  } catch (e: any) {
    if (run.status === "running") {
      log("error", "agent run failed", { runId: run.id, agent: name, error: e?.message });
      emit(run, ProxyEvent.Error, { message: e?.message ?? String(e) });
      finish(run, "error");
    }
  } finally {
    await persistRun(record(run));
  }
}

interface Pending {
  tool_use_id: string;
  name: string;
  input: unknown;
}

/** Reads the upstream run stream into `run`, mapping sequence_number k to seqBase + k, and
 *  reconnects with startingAfter on network drops. Returns the assistant message id and the
 *  client-side tool calls seen. */
async function pumpUpstream(run: Run, client: CortexAgentClient, upstreamRunId: string, startingAfter: number): Promise<{ assistantMessageId?: string; pending: Pending[]; ended: boolean }> {
  let last = startingAfter;
  let assistantMessageId: string | undefined;
  const pending: Pending[] = [];
  for (let attempt = 0; attempt < 6; attempt++) {
    try {
      const stream = client.runs.stream(upstreamRunId, { startingAfter: last, signal: run.abort.signal, streamReadTimeoutMs: 180_000 });
      for await (const ev of stream as AsyncIterable<any>) {
        if (run.status !== "running") return { pending, ended: false };
        const { event, sequence_number, ...data } = ev;
        if (typeof sequence_number === "number") last = sequence_number;
        if (event === "metadata" && data.metadata?.role === "assistant") assistantMessageId = String(data.metadata.message_id);
        if (event === "response.tool_use" && data.client_side_execute) pending.push({ tool_use_id: data.tool_use_id, name: data.name, input: data.input });
        emit(run, event, data, typeof sequence_number === "number" ? run.seqBase + sequence_number : undefined);
        observe(run, event, data);
        if (event === "response.tool_use" && data.permission?.options?.length) run.awaitingApproval = true;
        if (event === "error") throw Object.assign(new Error(data.message ?? "Agent error"), { fatal: true });
        if (last % 50 === 0) void persistRun(record(run));
      }
      return { assistantMessageId, pending, ended: true };
    } catch (e: any) {
      if (e?.fatal || run.abort.signal.aborted || run.status !== "running") throw e;
      if (e?.status && e.status < 500 && e.status !== 429) throw e;
      log("warn", "upstream run stream dropped; reconnecting", { runId: run.id, upstreamRunId, after: last, attempt: attempt + 1, error: e?.message });
      await new Promise((r) => setTimeout(r, backoffMs(attempt, 500)));
    }
  }
  throw new Error("Lost the upstream run stream");
}

/** Streams one Agent API call. Returns a follow-up turn when every pending client-side
 *  tool call was a tool the proxy executes itself (MCP / read-only SQL). */
async function streamOnce(run: Run, client: CortexAgentClient, body: Record<string, unknown>, tools: ProxyTools): Promise<{ content: UserContentItem[]; parentMessageId: string } | undefined> {
  let assistantMessageId: string | undefined;
  let pending: Pending[] = [];
  if (backgroundRuns()) {
    const kick: any = await client.agent.run({ ...body, stream: false, background: true } as any, { signal: run.abort.signal, retryPolicy: { maxRetries: 0 } });
    run.upstreamRunId = String(kick.runId);
    // Upstream sequence_number k becomes proxy seq seqBase + k.
    run.seqBase = run.nextSeq - 1;
    await persistRun(record(run));
    ({ assistantMessageId, pending } = await pumpUpstream(run, client, run.upstreamRunId, 0));
    flushFiles(run);
  } else {
    const stream = client.agent.stream(body as any, { signal: run.abort.signal });
    for await (const ev of stream as AsyncIterable<any>) {
      if (run.status !== "running") return undefined;
      const { event, ...data } = ev;
      if (event === "metadata" && data.metadata?.role === "assistant") assistantMessageId = String(data.metadata.message_id);
      const upstreamRunId = data.metadata?.run_id ?? data.run_id;
      if (upstreamRunId && !run.upstreamRunId) run.upstreamRunId = String(upstreamRunId);
      if (event === "response.tool_use" && data.client_side_execute) pending.push({ tool_use_id: data.tool_use_id, name: data.name, input: data.input });
      emit(run, event, data);
      observe(run, event, data);
      if (event === "response.tool_use" && data.permission?.options?.length) run.awaitingApproval = true;
      if (event === "error") throw new Error(data.message ?? "Agent error");
    }
    flushFiles(run);
  }
  if (run.status !== "running") return undefined;
  const hop = await proxyToolHop(run, pending, assistantMessageId, tools);
  if (hop || pending.length || !assistantMessageId || run.awaitingApproval) return hop;
  return deliveryHop(run, assistantMessageId);
}

/** Power Mode: files the agent created outside the write tool are fetched with one follow-up
 *  turn per chunk on the same thread (server/deliverables.ts). */
function deliveryHop(run: Run, parentMessageId: string): { content: UserContentItem[]; parentMessageId: string } | undefined {
  if (run.agent !== config().powerAgentName) return undefined;
  const text = followUp(run);
  if (!text) return undefined;
  emit(run, "response.status", { status: "proxy_followup", message: "Preparing download" });
  return { parentMessageId, content: [{ type: "text", text }] };
}

function flushFiles(run: Run) {
  if (!run.pendingFiles?.length) return;
  emit(run, ProxyEvent.StudioFiles, { files: run.pendingFiles });
  run.pendingFiles = [];
}

async function proxyToolHop(run: Run, pending: Pending[], assistantMessageId: string | undefined, tools: ProxyTools) {
  const mine = pending.filter((p) => tools.owns(p.name));
  if (!mine.length) return undefined;
  const items: UserContentItem[] = [];
  for (const p of mine) {
    emit(run, "response.status", { status: "proxy_tool", message: p.name === "snowflake_sql_execute" ? "Running read-only SQL" : `Calling ${p.name}` });
    try {
      const result: any = await tools.call(p.name, p.input);
      emit(run, "response.tool_result", { tool_use_id: p.tool_use_id, name: p.name, status: result?.error ? "error" : "success", content: [{ type: "json", json: result }] });
      items.push({ type: "tool_result", tool_result: { tool_use_id: p.tool_use_id, name: p.name, content: [{ type: "json", json: result }] } });
    } catch (e: any) {
      items.push({ type: "tool_result", tool_result: { tool_use_id: p.tool_use_id, name: p.name, status: "error", content: [{ type: "text", text: `${p.name} failed: ${e.message}` }] } });
      emit(run, "response.tool_result", { tool_use_id: p.tool_use_id, name: p.name, status: "error", content: [{ type: "json", json: { error: e.message } }] });
    }
  }
  if (mine.length === pending.length && assistantMessageId) return { content: items, parentMessageId: assistantMessageId };
  // Mixed with browser tools: the client sends these alongside its own tool_results.
  emit(run, ProxyEvent.ServerToolResults, { items });
  return undefined;
}

/** Rebuilds a run this process does not hold (restart / other instance) from its persisted
 *  record by replaying Snowflake's run stream after the client's cursor. Browser tools and
 *  approvals then flow as usual (the client answers with a new /api/chat turn). A pending
 *  proxy-executed tool (read-only SQL) is executed and continued; MCP calls cannot be, because
 *  the MCP binding lived in the old process, so the run ends with a retry hint instead. */
export async function resumeRun(rec: RunRecord, after: number, callerToken?: string): Promise<Run> {
  const run = createRun(rec.owner, rec.conversationId, rec.runId);
  run.threadId = rec.threadId;
  run.agent = rec.agent;
  run.upstreamRunId = rec.upstreamRunId;
  run.seqBase = rec.seqBase;
  run.nextSeq = Math.max(after, 0) + 1;
  const client = agentClient(callerToken);
  wireCancel(run, client);
  log("info", "resuming run from upstream", { runId: run.id, upstreamRunId: rec.upstreamRunId, after, seqBase: rec.seqBase });
  void (async () => {
    try {
      if (!rec.upstreamRunId) throw new Error("This run cannot be resumed (no upstream run id).");
      if (after < rec.seqBase) emit(run, ProxyEvent.Run, { runId: run.id, threadId: rec.threadId, agent: rec.agent });
      // No proxy-only events here: seqs after seqBase belong to the upstream mapping.
      const { assistantMessageId, pending } = await pumpUpstream(run, client, rec.upstreamRunId, Math.max(0, after - rec.seqBase));
      flushFiles(run);
      const sqlOnly = pending.length > 0 && pending.every((p) => p.name === "snowflake_sql_execute");
      if (pending.some((p) => p.name.startsWith("mcp__"))) {
        emit(run, ProxyEvent.Error, { message: "The server restarted during an MCP tool call. Send the message again to retry." });
        return finish(run, "error");
      }
      if (sqlOnly && assistantMessageId && rec.threadId) {
        const next = await proxyToolHop(run, pending, assistantMessageId, proxyTools({ specs: [], errors: [], owns: () => false, call: async () => undefined }, callerToken));
        if (next) {
          const name = rec.agent ?? config().agentName;
          const spec = await agentSpec(client, name);
          const req: ChatRequest = { conversationId: rec.conversationId, mode: name === config().powerAgentName ? "power" : "assist", threadId: rec.threadId, parentMessageId: next.parentMessageId, content: next.content, browserTools: false };
          await streamOnce(run, client, buildBody(spec, req, [], rec.owner, await dataDate()), proxyTools({ specs: [], errors: [], owns: () => false, call: async () => undefined }));
        }
      }
      if (run.status === "running") finish(run, "completed");
    } catch (e: any) {
      if (run.status === "running") {
        emit(run, ProxyEvent.Error, { message: e?.status === 404 ? "This run has expired upstream." : e?.message ?? String(e) });
        finish(run, "error");
      }
    } finally {
      await persistRun(record(run));
    }
  })();
  return run;
}
