// postMessage bridge between the chat (host) and same-origin sidebar apps (the Store Ops
// simulator implements the app side). No direct DOM access into the iframe.

export const BRIDGE_NS = "acme.bridge";

export interface BridgeRequest {
  ns: typeof BRIDGE_NS;
  kind: "request";
  id: string;
  op: string;
  args: Record<string, unknown>;
}
export interface BridgeResponse {
  ns: typeof BRIDGE_NS;
  kind: "response";
  id: string;
  ok: boolean;
  result?: unknown;
  error?: string;
}
/** App -> host notifications: page ready/changed, user selected a record as context. */
export interface BridgeNotice {
  ns: typeof BRIDGE_NS;
  kind: "ready" | "context";
  url: string;
  title: string;
  record?: { type: "region" | "store" | "sku" | "order" | "exception"; id: string; summary: string };
}

export type BridgeMessage = BridgeRequest | BridgeResponse | BridgeNotice;

export const isBridge = (d: unknown): d is BridgeMessage => !!d && typeof d === "object" && (d as any).ns === BRIDGE_NS;

/** Host side: send an op to the iframe and await its response. */
export function callApp(frame: HTMLIFrameElement, op: string, args: Record<string, unknown> = {}, timeoutMs = 8000): Promise<any> {
  const win = frame.contentWindow;
  if (!win) return Promise.reject(new Error("sidebar app not loaded"));
  const id = Math.random().toString(36).slice(2);
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => {
      window.removeEventListener("message", onMsg);
      reject(new Error(`app did not answer ${op}`));
    }, timeoutMs);
    function onMsg(e: MessageEvent) {
      if (e.origin !== location.origin || !isBridge(e.data) || e.data.kind !== "response" || e.data.id !== id) return;
      clearTimeout(t);
      window.removeEventListener("message", onMsg);
      e.data.ok ? resolve(e.data.result) : reject(new Error(e.data.error));
    }
    window.addEventListener("message", onMsg);
    win.postMessage({ ns: BRIDGE_NS, kind: "request", id, op, args } satisfies BridgeRequest, location.origin);
  });
}

type Handlers = Record<string, (args: any) => unknown | Promise<unknown>>;

/**
 * In-process transport, used when the app is rendered inline in the sidebar (no iframe).
 * App Runtime's ingress sends X-Frame-Options: DENY, so same-origin iframes cannot load there.
 */
let inline: Handlers | null = null;
const inlineSubs = new Set<() => void>();
export const inlineApp = {
  get handlers() {
    return inline;
  },
  register(h: Handlers): () => void {
    inline = h;
    inlineSubs.forEach((f) => f());
    return () => {
      if (inline === h) inline = null;
    };
  },
  onRegister(f: () => void): () => void {
    inlineSubs.add(f);
    return () => inlineSubs.delete(f);
  },
};

export async function callInline(op: string, args: Record<string, unknown> = {}): Promise<any> {
  const h = inline?.[op];
  if (!h) throw new Error(inline ? `unknown op ${op}` : "sidebar app not loaded");
  return h(args);
}

/** App side: answer host requests. */
export function serveBridge(handlers: Record<string, (args: any) => unknown | Promise<unknown>>): () => void {
  async function onMsg(e: MessageEvent) {
    if (e.origin !== location.origin || !isBridge(e.data) || e.data.kind !== "request") return;
    const { id, op, args } = e.data;
    const reply = (r: Omit<BridgeResponse, "ns" | "kind" | "id">) => (e.source as Window)?.postMessage({ ns: BRIDGE_NS, kind: "response", id, ...r }, location.origin);
    try {
      const h = handlers[op];
      if (!h) throw new Error(`unknown op ${op}`);
      reply({ ok: true, result: await h(args) });
    } catch (err: any) {
      reply({ ok: false, error: err?.message ?? String(err) });
    }
  }
  window.addEventListener("message", onMsg);
  return () => window.removeEventListener("message", onMsg);
}

export function notifyHost(n: Omit<BridgeNotice, "ns">): void {
  if (inline) window.postMessage({ ns: BRIDGE_NS, ...n }, location.origin);
  else if (window.parent !== window) window.parent.postMessage({ ns: BRIDGE_NS, ...n }, location.origin);
}
