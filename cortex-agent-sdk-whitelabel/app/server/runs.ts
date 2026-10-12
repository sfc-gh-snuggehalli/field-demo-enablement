// Resumable run registry. The proxy owns every agent run: events are buffered with
// sequence ids so a browser can disconnect and reattach (GET /api/runs/:id/events?after=N).
// Bounded, in-memory, kept on globalThis so Next.js route modules share one instance. This is
// the fast path; agent runs also start in Agent API background mode and their metadata is
// persisted (server/runstore.ts), so a run unknown to this process (restart, other instance)
// is resumed from Snowflake's run stream (server/agent.ts resumeRun).
import type { RunEnvelope } from "../shared/protocol";

export type RunStatus = "running" | "completed" | "cancelled" | "error";

export interface Run {
  id: string;
  owner: string;
  conversationId: string;
  events: RunEnvelope[];
  status: RunStatus;
  created: number;
  finished?: number;
  abort: AbortController;
  /** Upstream Agent API run id (background runs always have one). */
  upstreamRunId?: string;
  threadId?: string;
  agent?: string;
  /** Proxy seq of upstream sequence_number 0 for the current upstream run. */
  seqBase: number;
  /** Power Mode files captured during the current upstream run, announced when it ends. */
  pendingFiles?: Array<{ name: string; url: string; size: number }>;
  /** A permission prompt is outstanding (no proxy follow-up turns until the user answers). */
  awaitingApproval?: boolean;
  /** Next proxy seq to assign. */
  nextSeq: number;
  onCancel?: () => Promise<void>;
  listeners: Set<(e: RunEnvelope | null) => void>;
}

const MAX_RUNS = 200;
const MAX_EVENTS = 20000;
const RETENTION_MS = 10 * 60 * 1000;

interface Registry {
  runs: Map<string, Run>;
}
const g = globalThis as unknown as { __acmeRuns?: Registry };
const reg: Registry = (g.__acmeRuns ??= { runs: new Map() });

function sweep(): void {
  const now = Date.now();
  for (const [id, r] of reg.runs) if (r.finished && now - r.finished > RETENTION_MS) reg.runs.delete(id);
  if (reg.runs.size > MAX_RUNS) {
    const finished = [...reg.runs.values()].filter((r) => r.finished).sort((a, b) => a.finished! - b.finished!);
    for (const r of finished.slice(0, reg.runs.size - MAX_RUNS)) reg.runs.delete(r.id);
  }
}

export function createRun(owner: string, conversationId: string, id: string = crypto.randomUUID()): Run {
  sweep();
  const run: Run = { id, owner, conversationId, events: [], status: "running", created: Date.now(), abort: new AbortController(), listeners: new Set(), seqBase: 0, nextSeq: 1 };
  reg.runs.set(run.id, run);
  return run;
}

/** Owner-scoped lookup: other users get undefined (=> 404). */
export function getRun(id: string, owner: string): Run | undefined {
  const r = reg.runs.get(id);
  return r && r.owner === owner ? r : undefined;
}

/** Appends an event. `seq` pins the proxy sequence id (upstream-mapped events); otherwise the
 *  next free id is used. Ids never go backwards. */
export function emit(run: Run, event: string, data: unknown, seq?: number): void {
  if (run.events.length >= MAX_EVENTS) return;
  const s = seq !== undefined && seq >= run.nextSeq ? seq : run.nextSeq;
  run.nextSeq = s + 1;
  const env: RunEnvelope = { seq: s, event, data };
  run.events.push(env);
  for (const l of run.listeners) l(env);
}

export function finish(run: Run, status: RunStatus): void {
  if (run.status !== "running") return;
  run.status = status;
  run.finished = Date.now();
  emit(run, "acme.done", { status });
  for (const l of run.listeners) l(null);
  run.listeners.clear();
}

export async function cancelRun(run: Run): Promise<void> {
  if (run.status !== "running") return;
  // Finalize first: cancelling upstream ends the run stream normally, which would otherwise
  // race this into "completed".
  finish(run, "cancelled");
  run.abort.abort();
  try {
    await run.onCancel?.();
  } catch {
    /* upstream cancel is best-effort */
  }
}

export function liveRuns(): Run[] {
  return [...reg.runs.values()].filter((r) => r.status === "running");
}

/** Graceful shutdown: end every open SSE response (clients reattach elsewhere) without
 *  cancelling the runs; background runs keep going upstream. */
export function closeAllStreams(): number {
  let n = 0;
  for (const r of reg.runs.values()) {
    for (const l of r.listeners) {
      l(null);
      n++;
    }
    r.listeners.clear();
  }
  return n;
}

const enc = new TextEncoder();
const frame = (e: RunEnvelope) => enc.encode(`id: ${e.seq}\nevent: ${e.event}\ndata: ${JSON.stringify(e.data)}\n\n`);

/** SSE response that replays events after `after`, then tails until the run ends.
 *  Client disconnect only detaches the listener; it never aborts the run. */
export function sseResponse(run: Run, after = 0): Response {
  let cleanup = () => {};
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      const send = (e: RunEnvelope) => {
        try {
          controller.enqueue(frame(e));
        } catch {
          cleanup();
        }
      };
      for (const e of run.events) if (e.seq > after) send(e);
      if (run.status !== "running") return controller.close();
      const ka = setInterval(() => {
        try {
          controller.enqueue(enc.encode(`: keepalive ${Date.now()}\n\n`));
        } catch {
          cleanup();
        }
      }, 15000);
      const listener = (e: RunEnvelope | null) => {
        if (e) return send(e);
        cleanup();
        try {
          controller.close();
        } catch {
          /* already closed */
        }
      };
      run.listeners.add(listener);
      cleanup = () => {
        clearInterval(ka);
        run.listeners.delete(listener);
      };
    },
    cancel() {
      cleanup();
    },
  });
  return new Response(stream, {
    headers: { "Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-cache, no-transform", Connection: "keep-alive", "X-Accel-Buffering": "no", "X-Acme-Run-Id": run.id },
  });
}
