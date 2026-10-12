// App side of the postMessage bridge: the simulator answers browser-tool ops from the chat.
import { inlineApp, notifyHost, serveBridge } from "../../browser/bridge";

// Inline mode renders the app inside the chat document, so DOM queries are scoped to the
// app root and the URL comes from the in-memory router rather than window.location.
let root: ParentNode = document;
let currentUrl: () => string = () => location.pathname + location.search;
let inlineMode = false;

const MAX_TREE_CHARS = 16000; // ~4k tokens

function byTestid(id: string): HTMLElement | null {
  return root.querySelector(`[data-testid="${CSS.escape(id)}"]`);
}

function find(selector?: string): HTMLElement | null {
  if (!selector) return (root === document ? document.body : root) as HTMLElement;
  return byTestid(selector) ?? (root.querySelector(selector) as HTMLElement | null);
}

function labelOf(el: HTMLElement): string {
  const aria = el.getAttribute("aria-label");
  if (aria) return aria;
  if (el.id) {
    const l = root.querySelector(`label[for="${CSS.escape(el.id)}"]`);
    if (l) return l.textContent?.trim() ?? "";
  }
  const wrap = el.closest("label");
  if (wrap && wrap !== el) return wrap.textContent?.trim().slice(0, 60) ?? "";
  return "";
}

function roleOf(el: HTMLElement): string {
  const r = el.getAttribute("role");
  if (r) return r;
  const tag = el.tagName.toLowerCase();
  return ({ a: "link", button: "button", select: "combobox", input: "textbox", textarea: "textbox", table: "table", tr: "row", h1: "heading", h2: "heading", h3: "heading", nav: "navigation" } as Record<string, string>)[tag] ?? tag;
}

const visible = (el: HTMLElement) => !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length);

/** Simplified accessibility tree: interactive or test-addressable elements only. */
function pageTree() {
  const out: Array<Record<string, unknown>> = [];
  let size = 0;
  const els = root.querySelectorAll<HTMLElement>("[data-testid], a, button, select, input, textarea, h1, h2, h3");
  for (const el of els) {
    if (!visible(el)) continue;
    if (el.tagName === "TR" && out.filter((o) => o.role === "row").length > 40) continue;
    const node: Record<string, unknown> = { role: roleOf(el) };
    const label = labelOf(el);
    if (label) node.label = label;
    if (el.dataset.testid) node.testid = el.dataset.testid;
    if (el.dataset.agentConfirm === "true") node.confirm = true;
    const text = (el.tagName === "SELECT" ? "" : el.innerText || "").trim().replace(/\s+/g, " ").slice(0, el.tagName === "TABLE" ? 0 : 120);
    if (text) node.text = text;
    if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) node.value = el.value;
    if (el instanceof HTMLSelectElement) {
      node.value = el.value;
      node.options = [...el.options].map((o) => o.value);
    }
    const s = JSON.stringify(node).length;
    if (size + s > MAX_TREE_CHARS) {
      out.push({ truncated: true });
      break;
    }
    size += s;
    out.push(node);
  }
  return out;
}

let pointer: HTMLDivElement | null = null;
function pointAt(el: HTMLElement) {
  el.scrollIntoView({ block: "center", behavior: "smooth" });
  const r = el.getBoundingClientRect();
  pointer ??= Object.assign(document.createElement("div"), { className: "agent-pointer" });
  if (!pointer.isConnected) document.body.appendChild(pointer);
  pointer.style.left = `${r.left + r.width / 2}px`;
  pointer.style.top = `${r.top + r.height / 2}px`;
  el.classList.add("agent-highlight");
  setTimeout(() => el.classList.remove("agent-highlight"), 4000);
}

/** Sets a value on a React-controlled input/select so React sees the change. */
function setNativeValue(el: HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement, value: string) {
  const proto = el instanceof HTMLSelectElement ? HTMLSelectElement.prototype : el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, "value")!.set!.call(el, value);
  el.dispatchEvent(new Event("input", { bubbles: true }));
  el.dispatchEvent(new Event("change", { bubbles: true }));
}

const settle = () => new Promise((r) => setTimeout(r, 120));

function need(testid: string): HTMLElement {
  const el = byTestid(testid);
  if (!el) throw new Error(`no element with data-testid="${testid}". Call browser_get_page to list testids.`);
  return el;
}

let title = "";

export function startAgentBridge(nav: {
  navigate: (url: string) => void;
  history: (dir: "back" | "forward") => void;
  inline?: { root: HTMLElement; url: () => string };
}) {
  inlineMode = !!nav.inline;
  root = nav.inline?.root ?? document;
  currentUrl = nav.inline?.url ?? (() => location.pathname + location.search);
  const handlers: Record<string, (args: any) => unknown> = {
    navigate: ({ url }) => (nav.navigate(String(url)), { ok: true }),
    history: ({ dir }) => (nav.history(dir), { ok: true }),
    get_page: () => ({ url: currentUrl(), title: inlineMode ? title : document.title, tree: pageTree() }),
    get_text: ({ selector }) => {
      const el = find(selector);
      if (!el) throw new Error(`nothing matches ${selector}`);
      return { text: el.innerText.slice(0, 12000) };
    },
    describe: ({ testid }) => {
      const el = need(String(testid));
      return { label: labelOf(el) || el.innerText.trim().slice(0, 80), confirm: el.dataset.agentConfirm === "true" };
    },
    click: async ({ testid }) => {
      const el = need(String(testid));
      pointAt(el);
      el.click();
      await settle();
      return { ok: true, url: currentUrl() };
    },
    fill: async ({ testid, value }) => {
      const el = need(String(testid)) as HTMLInputElement;
      pointAt(el);
      setNativeValue(el, String(value));
      await settle();
      return { ok: true };
    },
    select: async ({ testid, value }) => {
      const el = need(String(testid)) as HTMLSelectElement;
      if (!(el instanceof HTMLSelectElement)) throw new Error(`${testid} is not a select`);
      const opt = [...el.options].find((o) => o.value === value || o.text.toLowerCase() === String(value).toLowerCase());
      if (!opt) throw new Error(`option ${value} not in ${[...el.options].map((o) => o.value).join(", ")}`);
      pointAt(el);
      setNativeValue(el, opt.value);
      await settle();
      return { ok: true, url: currentUrl() };
    },
    get_table: ({ testid }) => {
      const t = need(String(testid));
      const headers = [...t.querySelectorAll("thead th")].map((th) => (th as HTMLElement).innerText.replace(/[▲▼]/g, "").trim());
      const rows = [...t.querySelectorAll("tbody tr")].map((tr) => {
        const cells = [...tr.querySelectorAll("td")].map((td) => (td as HTMLElement).innerText.trim());
        return { testid: (tr as HTMLElement).dataset.testid, ...Object.fromEntries(headers.map((h, i) => [h || `col${i}`, cells[i]])) };
      });
      return { rowCount: rows.length, rows: rows.slice(0, 200) };
    },
    highlight: ({ testid }) => (pointAt(need(String(testid))), { ok: true }),
    screenshot: () => ({ ok: false, error: "Screenshots are not supported by the simulator; use browser_get_page or browser_get_table." }),
  };
  if (!nav.inline) return serveBridge(handlers);
  const off = inlineApp.register(handlers);
  return () => {
    off();
    root = document;
    inlineMode = false;
  };
}

export function announce(t: string) {
  title = t;
  if (!inlineMode) document.title = t;
  notifyHost({ kind: "ready", url: currentUrl(), title: t });
}

export function shareContext(record: { type: "region" | "store" | "sku" | "order" | "exception"; id: string; summary: string }) {
  notifyHost({ kind: "context", url: currentUrl().split("?")[0], title, record });
}
