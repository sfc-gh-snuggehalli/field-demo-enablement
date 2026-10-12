// Power Mode deliverables -> downloads via GET /api/files/<conversation>/<name>.
// The sandbox filesystem is not reachable from the proxy, so deliverables are recovered from the
// event stream:
//  - `write` tool calls: the file content is in the tool_use arguments (kept once the result
//    reports success);
//  - files created any other way (matplotlib savefig, pandas to_csv, shell redirection): after
//    the turn, the proxy asks the agent, on the same thread, to print the file as base64 in
//    chunks (`base64 -w0 <path> | cut -cA-B`). The sandbox replaces large outputs with a short
//    "Output too large" preview, so the chunk size halves on that reply. Decoded bytes are
//    checked against the file type's magic bytes before they are offered.
// State is per owner + conversation (a permission prompt splits a tool call across /api/chat
// turns). Each chunk is a bash call, so it goes through the normal approval prompt.
import { putFile } from "./files";
import type { Run } from "./runs";

type Status = "pending" | "fetching" | "delivered" | "failed";
interface Item {
  path: string;
  status: Status;
  b64: string;
  chunk: number;
  asks: number;
}
interface Conv {
  items: Map<string, Item>;
  calls: Map<string, { kind: "write"; path: string; content: string } | { kind: "chunk"; path: string; from: number }>;
  at: number;
}
const g = globalThis as unknown as { __acmeDeliverables?: Map<string, Conv> };
const convs = (g.__acmeDeliverables ??= new Map());

const EXT = "csv|png|svg|xlsx|pdf|json|html";
const PATH = new RegExp(`((?:/workspace/|\\./|output/)[\\w./-]*?\\.(?:${EXT}))\\b`, "gi");
const FIRST_CHUNK = Number(process.env.DELIVERABLE_CHUNK || 24_000);
const MIN_CHUNK = 1_500;
const MAX_ASKS = 40;

const norm = (p: string) => (p.startsWith("/") ? p : `/workspace/${p.replace(/^\.\//, "")}`).replace(/\/+/g, "/");
const base = (p: string) => p.split("/").pop() ?? p;

function conv(run: Run): Conv {
  const key = `${run.owner}\u0000${run.conversationId}`;
  let c = convs.get(key);
  if (!c) {
    c = { items: new Map(), calls: new Map(), at: Date.now() };
    convs.set(key, c);
    if (convs.size > 1000) for (const [k, v] of convs) if (Date.now() - v.at > 6 * 3600_000) convs.delete(k);
  }
  c.at = Date.now();
  return c;
}

function note(c: Conv, path: string) {
  const p = norm(path);
  if (!c.items.has(p)) c.items.set(p, { path: p, status: "pending", b64: "", chunk: FIRST_CHUNK, asks: 0 });
}

/** Valid file of this type? (Rejects truncated or mangled base64.) */
export function looksValid(name: string, buf: Buffer): boolean {
  if (/\.png$/i.test(name)) return buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  if (/\.pdf$/i.test(name)) return buf.subarray(0, 5).toString() === "%PDF-";
  if (/\.xlsx$/i.test(name)) return buf.subarray(0, 2).toString() === "PK";
  const t = buf.toString("utf8");
  if (/\.svg$/i.test(name)) return /<svg[\s\S]*<\/svg>\s*$/i.test(t);
  return !t.includes("\uFFFD");
}

function offer(run: Run, path: string, content: string | Buffer) {
  const f = putFile(run.owner, run.conversationId, path, content);
  if (f) run.pendingFiles = [...(run.pendingFiles ?? []).filter((x) => x.name !== f.name), f];
}

const CHUNK_CMD = /base64\s+-w0\s+(\S+)\s*\|\s*cut\s+-c(\d+)-(\d+)/;
const toolText = (data: any) => (data.content ?? []).map((c: any) => c?.text ?? (typeof c?.json === "string" ? c.json : "")).join("");

/** Feed every relayed event of a run (cheap no-op for non-sandbox tools). */
export function observe(run: Run, event: string, data: any): void {
  if (event !== "response.tool_use" && event !== "response.tool_result") return;
  if (data?.name !== "write" && data?.name !== "bash") return;
  const c = conv(run);
  if (event === "response.tool_use") {
    const id = String(data.tool_use_id);
    if (data.name === "write") {
      const path = data.input?.file_path ?? data.input?.path;
      const content = data.input?.content;
      if (typeof content !== "string" || !path) return;
      c.calls.set(id, { kind: "write", path: norm(String(path)), content });
      // A script that saves files: those files are deliverables too.
      if (/\.py$/.test(String(path))) for (const m of content.matchAll(PATH)) note(c, m[1]);
      return;
    }
    const cmd = String(data.input?.command ?? "");
    const chunk = cmd.match(CHUNK_CMD);
    if (chunk) return void c.calls.set(id, { kind: "chunk", path: norm(chunk[1]), from: Number(chunk[2]) });
    if (!/^\s*(cat|ls|head|tail|wc|file|base64)\b/.test(cmd)) for (const m of cmd.matchAll(PATH)) if (/[>]|savefig|to_csv|to_excel|-o\s|write/.test(cmd) || /\.py\b/.test(cmd)) note(c, m[1]);
    return;
  }
  const call = c.calls.get(String(data.tool_use_id));
  if (!call) return;
  c.calls.delete(String(data.tool_use_id));
  const failed = data.status === "error";
  if (call.kind === "write") {
    if (failed) return;
    if (!/\.py$/.test(call.path)) {
      offer(run, call.path, call.content);
      c.items.set(call.path, { path: call.path, status: "delivered", b64: "", chunk: 0, asks: 0 });
    }
    return;
  }
  const item = c.items.get(call.path);
  if (!item || item.status === "delivered") return;
  const out = toolText(data);
  if (failed || /No such file|cannot open/i.test(out)) return void (item.status = "failed");
  if (/Output too large/i.test(out)) {
    item.chunk = Math.floor(item.chunk / 2);
    if (item.chunk < MIN_CHUNK) item.status = "failed";
    return;
  }
  // Sandbox results read "Bash command `...` with description `...` returned output: <stdout>".
  const stdout = out.includes("returned output:") ? out.slice(out.lastIndexOf("returned output:") + 16) : out;
  const piece = stdout.replace(/\s+/g, "");
  if (!/^[A-Za-z0-9+/=]*$/.test(piece) || call.from !== item.b64.length + 1) return void (item.status = "failed");
  item.b64 += piece;
  if (piece.length < item.chunk) {
    const buf = Buffer.from(item.b64, "base64");
    item.status = looksValid(item.path, buf) ? "delivered" : "failed";
    if (item.status === "delivered") offer(run, item.path, buf);
  }
}

/** Next follow-up message for undelivered files, or undefined. */
export function followUp(run: Run): string | undefined {
  const c = conv(run);
  const next = [...c.items.values()].find((i) => (i.status === "pending" || i.status === "fetching") && i.asks < MAX_ASKS);
  for (const i of c.items.values()) if (i.status !== "delivered" && i.asks >= MAX_ASKS) i.status = "failed";
  if (!next) return undefined;
  next.status = "fetching";
  next.asks++;
  const from = next.b64.length + 1;
  return `To hand ${base(next.path)} to the user, run exactly this one bash command and nothing else, then stop: base64 -w0 ${next.path} | cut -c${from}-${from + next.chunk - 1}`;
}

export function resetDeliverables(): void {
  convs.clear();
}
