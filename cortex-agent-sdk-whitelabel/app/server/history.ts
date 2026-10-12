// Conversation history. HISTORY_STORE=local keeps a JSON file per owner under .data/;
// HISTORY_STORE=snowflake uses ACME_ASSIST_DEMO.APP.CONVERSATIONS (see snowflake/history.sql)
// through the SQL API with bind parameters. Every query is filtered by the resolved owner.
import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import type { ConversationRecord } from "../shared/protocol";
import { config } from "./config";
import { ownerHash } from "./identity";
import { sql } from "./sqlapi";

export interface HistoryStore {
  list(owner: string): Promise<Omit<ConversationRecord, "ui" | "wire">[]>;
  get(owner: string, id: string): Promise<ConversationRecord | undefined>;
  put(owner: string, rec: ConversationRecord): Promise<ConversationRecord>;
  remove(owner: string, id: string): Promise<void>;
}

const ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
export const validId = (id: string) => ID_RE.test(id);

class LocalStore implements HistoryStore {
  private file(owner: string) {
    const dir = resolve(process.env.HISTORY_DIR || ".data/conversations");
    mkdirSync(dir, { recursive: true });
    return resolve(dir, `${ownerHash(owner)}.json`);
  }
  private load(owner: string): Record<string, ConversationRecord> {
    const f = this.file(owner);
    return existsSync(f) ? JSON.parse(readFileSync(f, "utf8")) : {};
  }
  private save(owner: string, all: Record<string, ConversationRecord>) {
    writeFileSync(this.file(owner), JSON.stringify(all));
  }
  async list(owner: string) {
    return Object.values(this.load(owner))
      .map(({ ui: _u, wire: _w, ...meta }) => meta)
      .sort((a, b) => b.updated.localeCompare(a.updated));
  }
  async get(owner: string, id: string) {
    return this.load(owner)[id];
  }
  async put(owner: string, rec: ConversationRecord) {
    const all = this.load(owner);
    const prev = all[rec.id];
    // Server wins on `updated`: ignore stale writes.
    if (prev && prev.updated > rec.updated) return prev;
    all[rec.id] = { ...rec, created: prev?.created ?? rec.created };
    this.save(owner, all);
    return all[rec.id];
  }
  async remove(owner: string, id: string) {
    const all = this.load(owner);
    delete all[id];
    this.save(owner, all);
  }
}

class SnowflakeStore implements HistoryStore {
  private t = config().historyTable;
  private role = config().historyRole;
  private q(statement: string, binds: (string | null)[]) {
    return sql(statement, binds, { role: this.role });
  }
  async list(owner: string) {
    const rows = await this.q(`SELECT conversation_id, title, brand, studio_session_id, TO_VARCHAR(created_at, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM') AS created, TO_VARCHAR(updated_at, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM') AS updated FROM ${this.t} WHERE owner_user = ? ORDER BY updated_at DESC LIMIT 200`, [owner]);
    return rows.map((r: any) => ({ id: r.conversation_id, title: r.title ?? "", brand: r.brand ?? "", studioSessionId: r.studio_session_id ?? undefined, created: new Date(r.created).toISOString(), updated: new Date(r.updated).toISOString() }));
  }
  async get(owner: string, id: string) {
    const rows = await this.q(`SELECT conversation_id, title, brand, studio_session_id, ui_messages, wire_history, TO_VARCHAR(created_at, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM') AS created, TO_VARCHAR(updated_at, 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM') AS updated FROM ${this.t} WHERE owner_user = ? AND conversation_id = ?`, [owner, id]);
    const r: any = rows[0];
    if (!r) return undefined;
    const parse = (v: unknown) => (typeof v === "string" ? JSON.parse(v) : v);
    return { id: r.conversation_id, title: r.title ?? "", brand: r.brand ?? "", studioSessionId: r.studio_session_id ?? undefined, ui: parse(r.ui_messages), wire: parse(r.wire_history), created: new Date(r.created).toISOString(), updated: new Date(r.updated).toISOString() };
  }
  async put(owner: string, rec: ConversationRecord) {
    await this.q(
      `MERGE INTO ${this.t} t USING (SELECT ? AS owner_user, ? AS conversation_id) s
         ON t.owner_user = s.owner_user AND t.conversation_id = s.conversation_id
       WHEN MATCHED AND t.updated_at <= TO_TIMESTAMP_LTZ(?) THEN UPDATE SET title = ?, brand = ?, ui_messages = PARSE_JSON(?), wire_history = PARSE_JSON(?), studio_session_id = ?, updated_at = TO_TIMESTAMP_LTZ(?)
       WHEN NOT MATCHED THEN INSERT (conversation_id, owner_user, title, brand, ui_messages, wire_history, studio_session_id, created_at, updated_at)
         VALUES (?, ?, ?, ?, PARSE_JSON(?), PARSE_JSON(?), ?, TO_TIMESTAMP_LTZ(?), TO_TIMESTAMP_LTZ(?))`,
      [owner, rec.id, rec.updated, rec.title, rec.brand, JSON.stringify(rec.ui ?? null), JSON.stringify(rec.wire ?? null), rec.studioSessionId ?? null, rec.updated,
       rec.id, owner, rec.title, rec.brand, JSON.stringify(rec.ui ?? null), JSON.stringify(rec.wire ?? null), rec.studioSessionId ?? null, rec.created, rec.updated],
    );
    return (await this.get(owner, rec.id)) ?? rec;
  }
  async remove(owner: string, id: string) {
    await this.q(`DELETE FROM ${this.t} WHERE owner_user = ? AND conversation_id = ?`, [owner, id]);
  }
}

let store: HistoryStore | undefined;
export function historyStore(): HistoryStore {
  return (store ??= config().historyStore === "snowflake" ? new SnowflakeStore() : new LocalStore());
}
