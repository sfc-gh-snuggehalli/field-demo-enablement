// ACME Studio runner: Cortex Code driven headlessly through @snowflake/cortex-agent-sdk/code
// (query() with resume + canUseTool, CLI mode). One session per conversation, continued
// across turns. Internal/trusted users only; one container per deployment.
//
//   POST /turns                  { turnId, owner, conversationId, prompt, resume?, user? } -> SSE
//   POST /turns/:id/interrupt
//   POST /approvals              { turnId, id, decision: "allow" | "deny" }
//   GET  /files/:owner/:conv/:file
//   GET  /health
import { createReadStream, existsSync, mkdirSync, readdirSync, readFileSync, realpathSync, statSync } from "node:fs";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { basename, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { query, type CanUseTool, type PermissionResult } from "@snowflake/cortex-agent-sdk/code";

const PORT = Number(process.env.PORT || 8790);
const WORK_ROOT = resolve(process.env.WORK_ROOT || "/work");
const here = fileURLToPath(new URL(".", import.meta.url));
const skillsFile = [resolve(here, "../skills.json"), resolve(here, "skills.json")].find(existsSync)!;
const SKILLS: { intents: Array<{ id: string; pattern: string; skills: string[]; note?: string }>; bundledSkills: string[] } = JSON.parse(readFileSync(skillsFile, "utf8"));

const OWNER_RE = /^[a-f0-9]{8,64}$/;
const CONV_RE = /^[A-Za-z0-9_-]{1,64}$/;
const READ_ONLY_TOOLS = new Set(["read", "grep", "glob", "Read", "Grep", "Glob", "LS", "ls"]);
const WRITE_TOOLS = /^(bash|write|edit|notebook_edit|notebook_execute|Bash|Write|Edit|MultiEdit|NotebookEdit)$/;
const SQL_TOOL = /sql/i;
const READ_SQL = /^\s*(select|show|describe|desc|with|explain|list)\b/i;
const SESSION_SQL = /^\s*use\s+(role|warehouse|secondary\s+roles|database|schema)\b/i;
/** Every statement is a read or a session USE (comments stripped). Splits on `;` outside quotes. */
export function isReadOnlySql(q: string): boolean {
  const body = q.replace(/--[^\n]*|\/\*[\s\S]*?\*\//g, " ");
  const stmts: string[] = [];
  let cur = "";
  let quote: string | null = null;
  for (const ch of body) {
    if (quote) {
      if (ch === quote) quote = null;
    } else if (ch === "'" || ch === '"') quote = ch;
    else if (ch === ";") {
      stmts.push(cur);
      cur = "";
      continue;
    }
    cur += ch;
  }
  stmts.push(cur);
  const real = stmts.map((x) => x.trim()).filter(Boolean);
  return real.length > 0 && real.every((x) => READ_SQL.test(x) || SESSION_SQL.test(x)) && real.some((x) => READ_SQL.test(x));
}

interface Turn {
  send: (event: string, data: unknown) => void;
  approvals: Map<string, (r: PermissionResult) => void>;
  abort: AbortController;
  interrupt?: () => Promise<void>;
}
const turns = new Map<string, Turn>();

function workDir(owner: string, conv: string): string {
  if (!OWNER_RE.test(owner) || !CONV_RE.test(conv)) throw new Error("bad owner or conversation id");
  const dir = join(WORK_ROOT, owner, conv);
  mkdirSync(join(dir, "output"), { recursive: true });
  return dir;
}

function matchSkills(prompt: string) {
  const skills: string[] = [];
  const notes: string[] = [];
  for (const i of SKILLS.intents) {
    if (!new RegExp(i.pattern, "i").test(prompt)) continue;
    for (const s of i.skills) if (!skills.includes(s)) skills.push(s);
    if (i.note) notes.push(`${i.id}: ${i.note}`);
  }
  return { skills, notes };
}

function systemPrompt(user: { name?: string; email?: string } | undefined, notes: string[]): string {
  return [
    "You are ACME Studio, generating documents and apps from ACME Retail store-operations data.",
    `Data: ACME_ASSIST_DEMO.DATA (REGIONS, PRODUCTS, INVENTORY, DAILY_SALES, ORDERS, FULFILLMENT_EXCEPTIONS, REGION_RISK). Query it read-only with role ${process.env.STUDIO_ROLE || "ACME_STUDIO_ROLE"}; never write to Snowflake.`,
    "Write every deliverable into ./output/ (XLSX via openpyxl, PDF via reportlab + matplotlib, Streamlit apps as ./output/<app>/streamlit_app.py). Name the files in your answer.",
    "Only deploy a Streamlit app (snow streamlit deploy) after the user explicitly confirms in chat.",
    `Bundled Cortex Code skills available (use only these, never install catalog skills): ${SKILLS.bundledSkills.map((s) => `$${s}`).join(", ")}.`,
    ...notes.map((n) => `Library note — ${n}`),
    user?.name ? `The user is ${user.name}${user.email ? ` <${user.email}>` : ""}.` : "",
  ].filter(Boolean).join("\n");
}

function preview(tool: string, input: Record<string, any>): string {
  if (input.command) return `$ ${input.command}`;
  if (input.old_string !== undefined) return `--- ${input.file_path}\n- ${input.old_string}\n+ ${input.new_string}`;
  if (input.content !== undefined) return `+++ ${input.file_path}\n${String(input.content).slice(0, 2000)}`;
  return `${tool} ${JSON.stringify(input).slice(0, 1500)}`;
}

function permissionGate(turn: Turn): CanUseTool {
  return async (toolName, input, ctx) => {
    if (process.env.STUDIO_DEBUG) console.error("gate", toolName, JSON.stringify(input).slice(0, 200));
    if (READ_ONLY_TOOLS.has(toolName)) return { behavior: "allow" };
    if (SQL_TOOL.test(toolName)) {
      // CLI >= 1.2 permission requests carry { action, resource } (resource = the SQL text).
      const q = String((input as any).query ?? (input as any).sql ?? (input as any).statement ?? (input as any).resource ?? "");
      return isReadOnlySql(q) ? { behavior: "allow" } : { behavior: "deny", message: "Studio is read-only: write SQL is not allowed." };
    }
    if (!WRITE_TOOLS.test(toolName)) return { behavior: "deny", message: `${toolName} is not enabled in Studio.` };
    const id = ctx.toolUseID || Math.random().toString(36).slice(2);
    turn.send("acme.approval", { id, tool: toolName, title: `Allow ${toolName}?`, input, preview: preview(toolName, input as any) });
    return new Promise<PermissionResult>((resolveDecision) => {
      turn.approvals.set(id, resolveDecision);
      ctx.signal?.addEventListener("abort", () => resolveDecision({ behavior: "deny", message: "interrupted" }));
    });
  };
}

function toolLabel(name: string, input: Record<string, any>): string {
  if (input.command) return `$ ${String(input.command).slice(0, 120)}`;
  if (input.file_path) return `${name} ${input.file_path}`;
  if (input.query || input.sql) return `SQL: ${String(input.query ?? input.sql).slice(0, 100)}`;
  return name;
}

async function runTurn(req: IncomingMessage, res: ServerResponse, body: any) {
  const { turnId, owner, conversationId, prompt, resume, user } = body;
  const cwd = workDir(owner, conversationId);
  res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-cache", Connection: "keep-alive" });
  const send = (event: string, data: unknown) => res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  const turn: Turn = { send, approvals: new Map(), abort: new AbortController() };
  turns.set(turnId, turn);
  req.on("close", () => turn.abort.abort());
  const { skills, notes } = matchSkills(prompt);
  send("acme.studio.skills", { skills });
  const mention = skills.length ? `${skills.map((s) => `$${s}`).join(" ")} ` : "";
  const before = new Set(readdirSync(join(cwd, "output")));
  try {
    const q = query({
      prompt: mention + prompt,
      options: {
        mode: "cli",
        cwd,
        resume: resume || undefined,
        canUseTool: permissionGate(turn),
        appendSystemPrompt: systemPrompt(user, notes),
        // No allowedTools: Cortex Code CLI >= 1.2 treats --allowed-tools as a whitelist that
        // hard-denies everything else before canUseTool runs. permissionGate() is the policy.
        connection: process.env.SNOWFLAKE_CONNECTION || undefined,
        abortController: turn.abort,
      },
    });
    turn.interrupt = () => q.interrupt();
    let sessionId: string | undefined;
    for await (const m of q as AsyncIterable<any>) {
      if (m.session_id && m.session_id !== sessionId) send("acme.studio.session", { sessionId: (sessionId = m.session_id) });
      if (m.type === "assistant") {
        for (const b of m.message?.content ?? m.content ?? []) {
          if (b.type === "text") send("acme.studio.text", { text: b.text });
          else if (b.type === "thinking") send("acme.studio.thinking", { text: b.thinking });
          else if (b.type === "tool_use") send("acme.studio.tool", { id: b.id, name: b.name, label: toolLabel(b.name, b.input ?? {}), detail: JSON.stringify(b.input ?? {}, null, 2).slice(0, 3000) });
        }
      } else if (m.type === "user") {
        for (const b of m.message?.content ?? []) if (b.type === "tool_result") send("acme.studio.tool_result", { id: b.tool_use_id, ok: !b.is_error, denied: /denied|not allowed|interrupted/i.test(JSON.stringify(b.content ?? "")), ...(b.is_error || process.env.STUDIO_DEBUG ? { detail: JSON.stringify(b.content ?? "").slice(0, 300) } : {}) });
      } else if (m.type === "result") {
        if (m.is_error) send("acme.error", { message: m.result ?? m.subtype ?? "Studio error" });
        break;
      }
    }
  } catch (e: any) {
    send("acme.error", { message: e?.message ?? String(e) });
  } finally {
    const files = readdirSync(join(cwd, "output"))
      .filter((f) => statSync(join(cwd, "output", f)).isFile())
      .map((f) => ({ name: f, url: `/api/files/${conversationId}/${encodeURIComponent(f)}`, size: statSync(join(cwd, "output", f)).size, new: !before.has(f) }));
    if (files.length) send("acme.studio.files", { files: files.filter((f) => f.new).length ? files.filter((f) => f.new) : files });
    turns.delete(turnId);
    res.end();
  }
}

function serveFile(res: ServerResponse, owner: string, conv: string, file: string) {
  const dir = join(workDir(owner, conv), "output");
  const p = resolve(dir, basename(file));
  if (!existsSync(p)) return void res.writeHead(404).end();
  const real = realpathSync(p);
  if (!real.startsWith(realpathSync(dir) + sep)) return void res.writeHead(403).end(); // path traversal / symlink guard
  res.writeHead(200, { "Content-Type": "application/octet-stream" });
  createReadStream(real).pipe(res);
}

async function readJson(req: IncomingMessage): Promise<any> {
  let s = "";
  for await (const c of req) s += c;
  return JSON.parse(s || "{}");
}

createServer(async (req, res) => {
  try {
    const url = new URL(req.url ?? "/", "http://runner");
    if (url.pathname === "/health") return void res.end('{"ok":true}');
    if (req.method === "POST" && url.pathname === "/turns") return await runTurn(req, res, await readJson(req));
    let m = url.pathname.match(/^\/turns\/([\w-]+)\/interrupt$/);
    if (req.method === "POST" && m) {
      await turns.get(m[1])?.interrupt?.();
      return void res.end('{"ok":true}');
    }
    if (req.method === "POST" && url.pathname === "/approvals") {
      const b = await readJson(req);
      const r = turns.get(b.turnId)?.approvals.get(b.id);
      if (!r) return void res.writeHead(404).end('{"error":"no pending approval"}');
      r(b.decision === "allow" ? { behavior: "allow" } : { behavior: "deny", message: "denied by user" });
      return void res.end('{"ok":true}');
    }
    m = url.pathname.match(/^\/files\/([a-f0-9]+)\/([\w-]+)\/(.+)$/);
    if (req.method === "GET" && m) return serveFile(res, m[1], m[2], decodeURIComponent(m[3]));
    res.writeHead(404).end();
  } catch (e: any) {
    if (!res.headersSent) res.writeHead(400, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: e.message }));
  }
}).listen(PORT, () => console.log(`ACME Studio runner on :${PORT} (work root ${WORK_ROOT})`));
