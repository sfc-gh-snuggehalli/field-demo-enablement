export type StepState = "running" | "done" | "error" | "denied";

export interface Step {
  id: string;
  kind: "status" | "analyst" | "sql" | "browser" | "sandbox" | "mcp" | "chart" | "search" | "tool" | "reconnect" | "studio";
  label: string;
  detail?: string;
  sql?: string;
  state: StepState;
  toolUseId?: string;
  /** Power Mode: file written by the sandbox `write` tool (offered as a download on success). */
  file?: { name: string; content: string };
  at: number;
}

export interface Approval {
  id: string;
  toolUseId: string;
  source: "agent" | "client" | "studio";
  title: string;
  preview?: string;
  options: string[];
  state: "pending" | "decided";
  decision?: string;
}

export interface ResultTable {
  id: string;
  columns: { name: string; type?: string }[];
  rows: unknown[][];
  title?: string;
}

export interface FileChip {
  name: string;
  url: string;
  size?: number;
}

export interface PendingTool {
  tool_use_id: string;
  name: string;
  input: Record<string, any>;
  permission?: { options: string[] };
  type?: string;
}

export interface UIMessage {
  id: string;
  role: "user" | "assistant";
  text: string;
  thinking?: string;
  steps: Step[];
  tables: ResultTable[];
  charts: { id: string; spec: string }[];
  approvals: Approval[];
  files: FileChip[];
  skills?: string[];
  mode?: "assist" | "power" | "studio";
  status: "submitting" | "thinking" | "streaming" | "done" | "error" | "cancelled";
  error?: string;
  started: number;
  ended?: number;
  /** Client-side tool calls / permission prompts still to answer (survives reload). */
  pending?: PendingTool[];
  serverToolResults?: unknown[];
  context?: string;
}

export interface WireState {
  threadId?: string;
  parentMessageId?: string;
  runId?: string;
  lastSeq?: number;
  runActive?: boolean;
  studioSessionId?: string;
}

export interface Conversation {
  id: string;
  title: string;
  brand: string;
  messages: UIMessage[];
  wire: WireState;
  created: string;
  updated: string;
}
