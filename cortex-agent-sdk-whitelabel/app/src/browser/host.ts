// Host-side controller for the browser sidebar. A module singleton so the agent tool
// executor (outside React) and the sidebar component share one state.
import { useSyncExternalStore } from "react";
import { APPS, isAllowedAppUrl } from "../config/app.config";
import { callInline, inlineApp, isBridge, type BridgeNotice } from "./bridge";

export interface BrowserState {
  open: boolean;
  url: string;
  title: string;
  loading: boolean;
  cursor?: { label: string; at: number };
}

type Ctx = BridgeNotice["record"];

class BrowserHost {
  state: BrowserState = { open: false, url: APPS[0].url, title: "", loading: false };
  /** Bumped to remount the inline app (refresh, or first navigation to a new URL). */
  mount = { url: APPS[0].url, key: 0 };
  private subs = new Set<() => void>();
  private waiters: Array<(n: BridgeNotice) => void> = [];
  onContext?: (record: NonNullable<Ctx>, url: string) => void;

  constructor() {
    if (typeof window === "undefined") return;
    window.addEventListener("message", (e) => {
      if (e.origin !== location.origin || !isBridge(e.data)) return;
      const d = e.data;
      if (d.kind === "ready") {
        this.set({ url: d.url, title: d.title, loading: false });
        const w = this.waiters;
        this.waiters = [];
        w.forEach((f) => f(d));
      } else if (d.kind === "context" && d.record) this.onContext?.(d.record, d.url);
    });
  }

  subscribe = (f: () => void) => (this.subs.add(f), () => this.subs.delete(f));
  set(patch: Partial<BrowserState>) {
    this.state = { ...this.state, ...patch };
    this.subs.forEach((f) => f());
  }
  setOpen(open: boolean) {
    this.set({ open });
  }
  pointer(label: string) {
    this.set({ cursor: { label, at: Date.now() } });
  }

  private waitReady(timeoutMs = 10000): Promise<BridgeNotice> {
    return new Promise((resolve, reject) => {
      const t = setTimeout(() => reject(new Error("page did not load")), timeoutMs);
      this.waiters.push((n) => (clearTimeout(t), resolve(n)));
    });
  }

  /** Opens the drawer and waits for the inline app to register its bridge handlers. */
  private async ensureApp(): Promise<void> {
    if (!this.state.open) this.setOpen(true);
    if (inlineApp.handlers) return;
    await new Promise<void>((resolve, reject) => {
      const t = setTimeout(() => (off(), reject(new Error("sidebar app did not load"))), 10000);
      const off = inlineApp.onRegister(() => (clearTimeout(t), off(), resolve()));
    });
  }

  private remount(url: string) {
    this.mount = { url, key: this.mount.key + 1 };
    this.subs.forEach((f) => f());
  }

  async navigate(url: string): Promise<{ url: string; title: string }> {
    if (!isAllowedAppUrl(url, location.origin)) throw new Error(`URL not allowed (must be a registered ACME app): ${url}`);
    const path = new URL(url, location.origin);
    const target = path.pathname + path.search;
    const wasLoaded = this.state.open && !!inlineApp.handlers;
    this.set({ loading: true });
    const ready = this.waitReady();
    if (wasLoaded && target === this.state.url) {
      this.set({ loading: false });
      return { url: target, title: this.state.title };
    }
    if (wasLoaded) await callInline("navigate", { url: target });
    else this.remount(target);
    await this.ensureApp();
    const n = await ready.catch(() => ({ url: target, title: this.state.title }) as BridgeNotice);
    this.set({ loading: false });
    return { url: n.url, title: n.title };
  }

  async history(dir: "back" | "forward" | "refresh"): Promise<{ url: string }> {
    await this.ensureApp();
    const ready = this.waitReady();
    if (dir === "refresh") this.remount(this.state.url);
    else await callInline("history", { dir });
    const n = await ready.catch(() => ({ url: this.state.url }) as BridgeNotice);
    return { url: n.url };
  }

  async call(op: string, args: Record<string, unknown> = {}): Promise<any> {
    await this.ensureApp();
    if (this.state.loading) await this.waitReady().catch(() => undefined);
    return callInline(op, args);
  }
}

export const browserHost = new BrowserHost();

export function useBrowser(): BrowserState {
  return useSyncExternalStore(browserHost.subscribe, () => browserHost.state);
}
