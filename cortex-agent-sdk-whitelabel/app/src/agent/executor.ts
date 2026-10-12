// Executes client-side browser tools (response.tool_use with client_side_execute: true)
// against the sidebar. Write-style actions on elements marked data-agent-confirm="true"
// need user approval first; Deny returns a "denied by user" tool_result.
import { APPS } from "../config/app.config";
import { browserHost } from "../browser/host";
import { BROWSER_TOOLS, browserToolLabel } from "./tools/browser";

export interface ToolCall {
  tool_use_id: string;
  name: string;
  input: Record<string, any>;
}

export interface ExecResult {
  status: "done" | "error" | "denied";
  json: unknown;
}

export type Confirm = (call: ToolCall, element: { label: string; testid: string }) => Promise<boolean>;

export async function executeBrowserTool(call: ToolCall, confirm: Confirm): Promise<ExecResult> {
  const { name, input = {} } = call;
  const def = BROWSER_TOOLS.find((t) => t.name === name);
  if (!def) return { status: "error", json: { error: `unknown tool ${name}` } };
  browserHost.pointer(browserToolLabel(name, input));
  try {
    switch (name) {
      case "browser_open_app": {
        const app = APPS.find((a) => a.id === input.appId) ?? APPS.find((a) => a.name.toLowerCase().includes(String(input.appId).toLowerCase()));
        if (!app) return { status: "error", json: { error: `unknown appId; registered: ${APPS.map((a) => a.id).join(", ")}` } };
        return { status: "done", json: await browserHost.navigate(app.url) };
      }
      case "browser_navigate":
        return { status: "done", json: await browserHost.navigate(String(input.url)) };
      case "browser_back":
        return { status: "done", json: await browserHost.history("back") };
      case "browser_forward":
        return { status: "done", json: await browserHost.history("forward") };
      case "browser_refresh":
        return { status: "done", json: await browserHost.history("refresh") };
      default: {
        if (def.write) {
          const el = await browserHost.call("describe", { testid: input.testid });
          if (el?.confirm) {
            const ok = await confirm(call, { label: el.label, testid: input.testid });
            if (!ok) return { status: "denied", json: { ok: false, error: "denied by user" } };
          }
        }
        const op = name.replace(/^browser_/, "");
        const result = await browserHost.call(op, input);
        if (result && typeof result === "object" && "url" in result) browserHost.set({ url: result.url });
        return { status: "done", json: result };
      }
    }
  } catch (e: any) {
    return { status: "error", json: { ok: false, error: e?.message ?? String(e) } };
  }
}
