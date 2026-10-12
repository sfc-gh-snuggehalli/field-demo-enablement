// User-added MCP servers (name, URL, auth header). The proxy speaks MCP Streamable HTTP
// (JSON-RPC over POST) to list tools, exposes them to the agent as client-side `generic`
// tools named mcp__<server>__<tool>, and executes those calls itself, so MCP auth headers
// never reach the model. The browser sends an auth header once (PUT /api/mcp/credentials/:id);
// the proxy keeps it in memory per owner + connection id and never echoes it back. Chat
// requests carry only { id, name, url, enabled }. (In-memory: after a restart, re-enter the
// header; MCP_CREDENTIALS_TTL_MS bounds how long one is kept.)
import type { McpConnection } from "../shared/protocol";

export const MCP_PREFIX = "mcp__";

interface McpTool {
  name: string;
  description?: string;
  inputSchema?: Record<string, unknown>;
}

interface Cred {
  header: string;
  at: number;
}
const g = globalThis as unknown as { __acmeMcpCreds?: Map<string, Cred> };
const creds = (g.__acmeMcpCreds ??= new Map());
const credKey = (owner: string, id: string) => `${owner.toLowerCase()}\u0000${id}`;
const credTtl = () => Number(process.env.MCP_CREDENTIALS_TTL_MS || 12 * 3600 * 1000);
const CONN_ID = /^[A-Za-z0-9_-]{1,64}$/;

export function setMcpCredential(owner: string, id: string, header: string): boolean {
  if (!CONN_ID.test(id) || header.length > 4096 || /[\r\n]/.test(header)) return false;
  if (!header.trim()) creds.delete(credKey(owner, id));
  else creds.set(credKey(owner, id), { header: header.trim(), at: Date.now() });
  return true;
}

export function hasMcpCredential(owner: string, id: string): boolean {
  const c = creds.get(credKey(owner, id));
  if (c && Date.now() - c.at > credTtl()) creds.delete(credKey(owner, id));
  return creds.has(credKey(owner, id));
}

function credentialFor(owner: string | undefined, id: string): string | undefined {
  return owner && hasMcpCredential(owner, id) ? creds.get(credKey(owner, id))!.header : undefined;
}

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "").slice(0, 24) || "server";

async function rpc(conn: McpConnection, method: string, params: unknown, session?: string): Promise<{ result: any; session?: string }> {
  const headers: Record<string, string> = { "Content-Type": "application/json", Accept: "application/json, text/event-stream" };
  if (conn.authHeader) {
    const i = conn.authHeader.indexOf(":");
    if (i > 0) headers[conn.authHeader.slice(0, i).trim()] = conn.authHeader.slice(i + 1).trim();
    else headers.Authorization = conn.authHeader;
  }
  if (session) headers["Mcp-Session-Id"] = session;
  const res = await fetch(conn.url, { method: "POST", headers, body: JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method, params }), signal: AbortSignal.timeout(15000) });
  const text = await res.text();
  const json = text.trim().startsWith("{") ? JSON.parse(text) : JSON.parse(text.split("\n").filter((l) => l.startsWith("data:")).pop()!.slice(5));
  if (json.error) throw new Error(json.error.message ?? "MCP error");
  return { result: json.result, session: res.headers.get("mcp-session-id") ?? session };
}

async function open(conn: McpConnection): Promise<string | undefined> {
  const { session } = await rpc(conn, "initialize", { protocolVersion: "2025-03-26", capabilities: {}, clientInfo: { name: "acme-assist", version: "0.1.0" } });
  return session;
}

export interface McpBinding {
  specs: unknown[];
  call: (toolName: string, input: unknown) => Promise<unknown>;
  owns: (toolName: string) => boolean;
  errors: string[];
}

/** `owner` resolves stored auth headers; a header in the request itself (Test button) wins. */
export async function bindMcp(conns: McpConnection[] = [], owner?: string): Promise<McpBinding> {
  const enabled = conns
    .filter((c) => c.enabled && /^https?:\/\//.test(c.url))
    .map((c) => ({ ...c, authHeader: c.authHeader || credentialFor(owner, c.id) }));
  const map = new Map<string, { conn: McpConnection; tool: string }>();
  const specs: unknown[] = [];
  const errors: string[] = [];
  for (const conn of enabled) {
    try {
      const session = await open(conn);
      const { result } = await rpc(conn, "tools/list", {}, session);
      for (const t of (result?.tools ?? []) as McpTool[]) {
        const name = `${MCP_PREFIX}${slug(conn.name)}__${slug(t.name)}`.slice(0, 64);
        map.set(name, { conn, tool: t.name });
        specs.push({ tool_spec: { type: "generic", name, description: `[MCP ${conn.name}] ${t.description ?? t.name}`, input_schema: t.inputSchema ?? { type: "object", properties: {} } } });
      }
    } catch (e: any) {
      errors.push(`${conn.name}: ${e.message}`);
    }
  }
  return {
    specs,
    errors,
    owns: (n) => map.has(n),
    async call(n, input) {
      const m = map.get(n)!;
      const session = await open(m.conn);
      const { result } = await rpc(m.conn, "tools/call", { name: m.tool, arguments: input ?? {} }, session);
      return result;
    },
  };
}
