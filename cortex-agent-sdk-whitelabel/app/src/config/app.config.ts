// App configuration (not branding): models in the composer and apps registered in the
// browser sidebar. URLs are same-origin paths so they work under Vite, Express, SPCS and
// App Runtime.

// Every id must be an agent-allowed model in the account (the API error lists them).
// "auto" lets Cortex pick the orchestration model per request.
// `group` renders as an <optgroup> in the composer.
export const MODELS: { id: string; label: string; group: string }[] = [
  { id: "auto", label: "Auto (recommended)", group: "Default" },
  { id: "claude-sonnet-4-5", label: "Claude Sonnet 4.5", group: "Anthropic" },
  { id: "claude-sonnet-5-5", label: "Claude Sonnet 5.5", group: "Anthropic" },
  { id: "claude-opus-5-5", label: "Claude Opus 5.5", group: "Anthropic" },
  { id: "claude-haiku-4-5", label: "Claude Haiku 4.5", group: "Anthropic" },
  { id: "openai-gpt-5", label: "OpenAI GPT-5", group: "OpenAI" },
  { id: "openai-gpt-5-mini", label: "OpenAI GPT-5 mini", group: "OpenAI" },
  { id: "gemini-3.1-pro", label: "Gemini 3.1 Pro", group: "Google" },
  { id: "gemini-3.5-flash", label: "Gemini 3.5 Flash", group: "Google" },
  { id: "grok-4.6", label: "Grok 4.6", group: "xAI" },
  { id: "kimi-k3", label: "Kimi K3", group: "Open-weight" },
];
export const DEFAULT_MODEL = "auto";

export interface RegisteredApp {
  id: string;
  name: string;
  url: string;
  icon: string; // emoji-free short glyph rendered in a badge
}

export const APPS: RegisteredApp[] = [
  { id: "storeops", name: "Store Ops", url: "/apps/storeops", icon: "SO" },
  { id: "storeops-risk", name: "Risk Dashboard", url: "/apps/storeops/risk", icon: "RK" },
  { id: "storeops-exceptions", name: "Exceptions Queue", url: "/apps/storeops/exceptions", icon: "EX" },
];

/** Allowlist: the browser tools may only navigate within registered app paths (same origin). */
export function isAllowedAppUrl(url: string, origin: string): boolean {
  try {
    const u = new URL(url, origin);
    return u.origin === origin && APPS.some((a) => u.pathname === a.url || u.pathname.startsWith(a.url.split("/").slice(0, 3).join("/") + "/"));
  } catch {
    return false;
  }
}
