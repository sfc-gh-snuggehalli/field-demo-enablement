// Framework-neutral Fetch-API handlers: dispatch(Request) => Promise<Response>.
// Express (server/express.ts) and Next.js (app-runtime/app/api/[...path]/route.ts) are
// thin adapters over this one function.
import type { ChatRequest, ConversationRecord, PublicConfig } from "../shared/protocol";
import { AgentUnavailableError, agentSpec, resumeRun, runAgent } from "./agent";
import { agentClient } from "./auth";
import { config } from "./config";
import { historyStore, validId } from "./history";
import { bindMcp, hasMcpCredential, setMcpCredential } from "./mcp";
import { resolveUser, type ResolvedUser } from "./identity";
import { log, logPrompts, requestId } from "./log";
import { rateLimit } from "./ratelimit";
import { cancelRun, createRun, getRun, sseResponse, type Run } from "./runs";
import { persistRun, runStore } from "./runstore";
import { fileResponse } from "./files";
import { runStudio, studioApprove, studioFile } from "./studio";

/** Headers on every API response (HTML pages get CSP from server/security.ts). */
const API_HEADERS = { "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer", "Cache-Control": "no-store" };

const json = (body: unknown, status = 200, extra: Record<string, string> = {}) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...API_HEADERS, ...extra } });
const notFound = () => json({ error: "not found" }, 404);

const g = globalThis as unknown as { __acmeDraining?: boolean };
export const setDraining = (v: boolean) => void (g.__acmeDraining = v);

export function publicConfig(user: ResolvedUser): PublicConfig {
  const cfg = config();
  return {
    brand: cfg.brand,
    user: { name: user.name, source: user.source },
    powerModeEnabled: cfg.powerModeEnabled,
    studioEnabled: !!cfg.cocoRunnerUrl,
    historyStore: cfg.historyStore,
    agent: `${cfg.agentDatabase}.${cfg.agentSchema}.${cfg.agentName}`,
    powerAgent: `${cfg.agentDatabase}.${cfg.agentSchema}.${cfg.powerAgentName}`,
  };
}

async function body<T>(req: Request): Promise<T> {
  return (await req.json()) as T;
}

/** Owner-scoped run lookup: this process first, then the persisted record (restart / other
 *  instance), which is resumed from the upstream run stream. */
async function findRun(id: string, owner: string, after: number, callerToken?: string): Promise<Run | undefined> {
  const local = getRun(id, owner);
  if (local) return local;
  const rec = await runStore().get(id).catch(() => undefined);
  if (!rec || rec.owner !== owner || !rec.upstreamRunId) return undefined;
  return getRun(id, owner) ?? resumeRun(rec, after, callerToken);
}

export async function dispatch(req: Request): Promise<Response> {
  const started = Date.now();
  const rid = requestId(req.headers.get("x-request-id"));
  const url = new URL(req.url);
  const path = url.pathname.replace(/\/+$/, "");
  const method = req.method.toUpperCase();
  let owner = "anonymous";
  let res: Response;
  try {
    res = await route(req, url, path, method, rid, (o) => (owner = o));
  } catch (e: any) {
    log("error", "handler error", { rid, path, method, error: e?.message });
    res = json({ error: "server error", requestId: rid }, 500);
  }
  res.headers.set("X-Request-Id", rid);
  if (path !== "/api/health") log("info", "request", { rid, method, path: path.replace(/[0-9a-f-]{36}/g, ":id"), status: res.status, ms: Date.now() - started, user: owner });
  return res;
}

async function route(req: Request, url: URL, path: string, method: string, rid: string, setOwner: (o: string) => void): Promise<Response> {
  if (path === "/api/health") return json({ ok: true, draining: !!g.__acmeDraining }, g.__acmeDraining ? 503 : 200);

  const user = resolveUser(req);
  if (config().requireAuth && !user.name) return json({ error: "authentication required" }, 401);
  const owner = user.name ?? "anonymous";
  setOwner(owner);

  if (path === "/api/config" && method === "GET") return json(publicConfig(user));

  if (path === "/api/chat" && method === "POST") {
    if (g.__acmeDraining) return json({ error: "server is shutting down; retry" }, 503, { "Retry-After": "2" });
    const rl = rateLimit(owner);
    if (!rl.ok) return json({ error: "rate limited", retryAfterSeconds: rl.retryAfterS }, 429, { "Retry-After": String(rl.retryAfterS) });
    const chat = await body<ChatRequest>(req);
    if (!validId(chat.conversationId) || !Array.isArray(chat.content) || !chat.content.length) return json({ error: "bad request" }, 400);
    if (chat.mode === "studio" && !config().cocoRunnerUrl) return json({ error: "studio disabled" }, 400);
    if (chat.mode === "power" && !config().powerModeEnabled) chat.mode = "assist";
    // Legacy clients may still send MCP auth headers inline: store them, never forward them.
    chat.mcp = (chat.mcp ?? []).map(({ authHeader, ...c }) => {
      if (authHeader) setMcpCredential(owner, c.id, authHeader);
      return c;
    });
    if (logPrompts()) log("debug", "chat prompt", { rid, prompt: chat.content });
    if (chat.mode !== "studio") {
      // Fail fast with a clear 503 when the named agent cannot be described (dropped, no grant).
      const name = chat.mode === "power" ? config().powerAgentName : config().agentName;
      try {
        await agentSpec(agentClient(user.callerToken), name);
      } catch (e) {
        if (e instanceof AgentUnavailableError) return json({ error: e.message, requestId: rid }, 503);
        throw e;
      }
    }
    const run = createRun(owner, chat.conversationId);
    log("info", "run start", { rid, runId: run.id, mode: chat.mode, user: owner });
    void persistRun({ runId: run.id, owner, conversationId: chat.conversationId, seqBase: 0, lastSeq: 0, status: "running" });
    // The run lives on independently of this HTTP response.
    void (chat.mode === "studio" ? runStudio(run, chat, owner) : runAgent(run, chat, user.name, user.callerToken));
    return sseResponse(run, 0);
  }

  let m = path.match(/^\/api\/runs\/([0-9a-f-]{36})\/(events|cancel)$/);
  if (m) {
    const after = Number(url.searchParams.get("after") ?? 0) || 0;
    if (m[2] === "events" && method === "GET") {
      const run = await findRun(m[1], owner, after, user.callerToken);
      return run ? sseResponse(run, after) : notFound();
    }
    if (m[2] === "cancel" && method === "POST") {
      const run = getRun(m[1], owner);
      if (run) {
        await cancelRun(run);
        void persistRun({ runId: run.id, owner, conversationId: run.conversationId, threadId: run.threadId, agent: run.agent, upstreamRunId: run.upstreamRunId, seqBase: run.seqBase, lastSeq: run.nextSeq - 1, status: run.status });
        return json({ ok: true, status: run.status });
      }
      // Not in this process: cancel upstream from the persisted record.
      const rec = await runStore().get(m[1]).catch(() => undefined);
      if (!rec || rec.owner !== owner) return notFound();
      if (rec.upstreamRunId && rec.status === "running") await agentClient(user.callerToken).runs.cancel(rec.upstreamRunId).catch(() => undefined);
      await persistRun({ ...rec, status: "cancelled" });
      return json({ ok: true, status: "cancelled" });
    }
  }

  if (path === "/api/conversations" && method === "GET") return json(await historyStore().list(owner));
  m = path.match(/^\/api\/conversations\/([A-Za-z0-9_-]{1,64})$/);
  if (m) {
    const store = historyStore();
    if (method === "GET") {
      const rec = await store.get(owner, m[1]);
      return rec ? json(rec) : notFound();
    }
    if (method === "PUT") {
      const rec = await body<ConversationRecord>(req);
      return json(await store.put(owner, { ...rec, id: m[1], title: String(rec.title ?? "").slice(0, 200) }));
    }
    if (method === "DELETE") {
      await store.remove(owner, m[1]);
      return json({ ok: true });
    }
  }

  if (path === "/api/mcp/test" && method === "POST") {
    const conn = await body<any>(req);
    const b = await bindMcp([{ ...conn, id: conn.id || "test", enabled: true }], owner);
    return json({ tools: b.specs.map((s: any) => s.tool_spec.name), errors: b.errors });
  }

  // MCP auth header: write-only. PUT stores it for this user, GET only says whether one is set.
  m = path.match(/^\/api\/mcp\/credentials\/([A-Za-z0-9_-]{1,64})$/);
  if (m) {
    if (method === "PUT") {
      const b = await body<{ authHeader?: string }>(req);
      if (!setMcpCredential(owner, m[1], String(b.authHeader ?? ""))) return json({ error: "bad request" }, 400);
      return json({ ok: true, hasAuth: hasMcpCredential(owner, m[1]) });
    }
    if (method === "DELETE") {
      setMcpCredential(owner, m[1], "");
      return json({ ok: true, hasAuth: false });
    }
    if (method === "GET") return json({ hasAuth: hasMcpCredential(owner, m[1]) });
  }

  if (path === "/api/studio/approve" && method === "POST") {
    if (!config().cocoRunnerUrl) return notFound();
    const b = await body<{ runId: string; id: string; decision: "allow" | "deny" }>(req);
    if (!getRun(b.runId, owner)) return notFound();
    return studioApprove({ turnId: b.runId, id: b.id, decision: b.decision });
  }

  m = path.match(/^\/api\/files\/([A-Za-z0-9_-]{1,64})\/([^/]{1,200})$/);
  if (m && method === "GET") {
    const name = decodeURIComponent(m[2]);
    const local = fileResponse(owner, m[1], name);
    if (local) return local;
    if (config().cocoRunnerUrl) return studioFile(owner, m[1], name);
  }

  return notFound();
}
