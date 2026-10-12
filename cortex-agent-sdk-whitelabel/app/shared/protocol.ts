// Wire protocol between the React client and the ACME proxy. Shared by server/ and src/.
// Shared-code rules: no import.meta.env, no asset imports, extensionless relative imports.

export type ChatMode = "assist" | "power" | "studio";

export interface McpConnection {
  id: string;
  name: string;
  url: string;
  authHeader?: string;
  enabled: boolean;
}

export interface SkillDef {
  id: string;
  name: string;
  description: string;
  instructions: string;
}

export interface UserContext {
  name?: string;
  email?: string;
}

/** Content item sent to the agent as part of a user message. */
export type UserContentItem =
  | { type: "text"; text: string }
  | { type: "tool_result"; tool_result: { tool_use_id: string; name: string; content: Array<{ type: "json"; json: unknown } | { type: "text"; text: string }>; status?: string } }
  | { type: "permission_decision"; permission_decision: { tool_use_id: string; decision: string; reason?: string } };

export interface ChatRequest {
  conversationId: string;
  mode: ChatMode;
  /** Agent API thread (created by the proxy on the first turn). */
  threadId?: string;
  parentMessageId?: string;
  /** The new user message content (text and/or tool_result / permission_decision items). */
  content: UserContentItem[];
  model?: string;
  skills?: SkillDef[];
  mcp?: McpConnection[];
  /** Include the client-side browser tools (src/agent/tools/browser.ts). */
  browserTools?: boolean;
  user?: UserContext;
  /** Studio: CoCo session to resume. */
  studioSessionId?: string;
}

/** Envelope for every SSE event the proxy relays. `seq` is the proxy's own sequence id. */
export interface RunEnvelope {
  seq: number;
  event: string;
  data: any;
}

/** Proxy-originated events (agent events are relayed with their native names). */
export const ProxyEvent = {
  Run: "acme.run", // { runId, threadId }
  Done: "acme.done", // { status: "completed" | "cancelled" | "error" }
  Error: "acme.error", // { message }
  ServerToolResults: "acme.server_tool_results", // { items: UserContentItem[] } (MCP calls run by the proxy)
  Approval: "acme.approval", // Studio: { id, tool, input, preview }
  StudioText: "acme.studio.text",
  StudioThinking: "acme.studio.thinking",
  StudioTool: "acme.studio.tool",
  StudioToolResult: "acme.studio.tool_result",
  StudioFiles: "acme.studio.files",
  StudioSkills: "acme.studio.skills",
  StudioSession: "acme.studio.session",
} as const;

export interface ConversationRecord {
  id: string;
  title: string;
  brand: string;
  ui: unknown; // UI messages
  wire: unknown; // { threadId, parentMessageId, runId, lastSeq }
  studioSessionId?: string;
  created: string;
  updated: string;
}

export interface PublicConfig {
  brand: string;
  user: { name: string | null; source: "snowflake" | "sso" | "dev" | "none" };
  powerModeEnabled: boolean;
  studioEnabled: boolean;
  historyStore: "local" | "snowflake";
  agent: string;
  powerAgent: string;
}
