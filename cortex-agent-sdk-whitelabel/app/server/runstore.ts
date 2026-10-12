// Durable run records, so a reattach can resume after a server restart (or on another
// instance) from Snowflake's own run stream (client.runs.stream(upstreamRunId, { startingAfter })).
// Only metadata is stored, never prompts or events:
//   { runId, upstreamRunId, owner, conversationId, threadId, agent, seqBase, lastSeq, status }
// `seqBase` maps upstream sequence_number k to proxy seq seqBase + k, so the client's
// `after=<seq>` cursor stays valid across processes.
//   RUN_STORE=local     JSON files under .data/runs/ (default; survives restarts of one host)
//   RUN_STORE=snowflake ACME_ASSIST_DEMO.APP.AGENT_RUNS (lab/history.sql), bind parameters,
//                       shared by every instance (required for max_instances > 1)
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { config } from "./config";
import { log } from "./log";
import { sql } from "./sqlapi";

export interface RunRecord {
  runId: string;
  owner: string;
  conversationId: string;
  threadId?: string;
  agent?: string;
  upstreamRunId?: string;
  seqBase: number;
  lastSeq: number;
  status: "running" | "completed" | "cancelled" | "error";
  updated: string;
}

export interface RunStore {
  put(rec: RunRecord): Promise<void>;
  get(runId: string): Promise<RunRecord | undefined>;
}

const RUN_ID = /^[0-9a-f-]{36}$/;
const RETENTION_MS = 24 * 3600 * 1000;

class LocalRunStore implements RunStore {
  private dir() {
    const d = resolve(process.env.RUN_STORE_DIR || ".data/runs");
    mkdirSync(d, { recursive: true });
    return d;
  }
  async put(rec: RunRecord) {
    if (!RUN_ID.test(rec.runId)) return;
    writeFileSync(resolve(this.dir(), `${rec.runId}.json`), JSON.stringify(rec));
    this.sweep();
  }
  async get(runId: string) {
    if (!RUN_ID.test(runId)) return undefined;
    const f = resolve(this.dir(), `${runId}.json`);
    return existsSync(f) ? (JSON.parse(readFileSync(f, "utf8")) as RunRecord) : undefined;
  }
  private lastSweep = 0;
  private sweep() {
    if (Date.now() - this.lastSweep < 600_000) return;
    this.lastSweep = Date.now();
    for (const f of readdirSync(this.dir())) {
      const p = resolve(this.dir(), f);
      if (Date.now() - statSync(p).mtimeMs > RETENTION_MS) rmSync(p, { force: true });
    }
  }
}

class SnowflakeRunStore implements RunStore {
  private t = process.env.RUN_TABLE || "ACME_ASSIST_DEMO.APP.AGENT_RUNS";
  private role = config().historyRole;
  async put(r: RunRecord) {
    await sql(
      `MERGE INTO ${this.t} t USING (SELECT ? AS run_id) s ON t.run_id = s.run_id
       WHEN MATCHED THEN UPDATE SET upstream_run_id = ?, thread_id = ?, seq_base = ?, last_seq = ?, status = ?, updated_at = CURRENT_TIMESTAMP()
       WHEN NOT MATCHED THEN INSERT (run_id, owner_user, conversation_id, thread_id, agent, upstream_run_id, seq_base, last_seq, status, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP())`,
      [r.runId, r.upstreamRunId ?? null, r.threadId ?? null, r.seqBase, r.lastSeq, r.status, r.runId, r.owner, r.conversationId, r.threadId ?? null, r.agent ?? null, r.upstreamRunId ?? null, r.seqBase, r.lastSeq, r.status],
      { role: this.role },
    );
  }
  async get(runId: string) {
    if (!RUN_ID.test(runId)) return undefined;
    const rows: any[] = await sql(`SELECT run_id, owner_user, conversation_id, thread_id, agent, upstream_run_id, seq_base, last_seq, status, TO_VARCHAR(updated_at) AS updated FROM ${this.t} WHERE run_id = ?`, [runId], { role: this.role });
    const x = rows[0];
    if (!x) return undefined;
    return { runId: x.run_id, owner: x.owner_user, conversationId: x.conversation_id, threadId: x.thread_id ?? undefined, agent: x.agent ?? undefined, upstreamRunId: x.upstream_run_id ?? undefined, seqBase: Number(x.seq_base), lastSeq: Number(x.last_seq), status: x.status, updated: x.updated };
  }
}

let store: RunStore | undefined;
export function runStore(): RunStore {
  return (store ??= process.env.RUN_STORE === "snowflake" ? new SnowflakeRunStore() : new LocalRunStore());
}

/** Best-effort write: a failed persist only costs cross-restart resumability. */
export async function persistRun(rec: Omit<RunRecord, "updated">): Promise<void> {
  try {
    await runStore().put({ ...rec, updated: new Date().toISOString() });
  } catch (e: any) {
    log("warn", "run persist failed", { runId: rec.runId, error: e?.message });
  }
}
