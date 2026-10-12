import { lazy, Suspense, useEffect, useMemo, useRef, useState } from "react";
import type { ChatMode, PublicConfig, UserContentItem } from "../../shared/protocol";
import { getBrand } from "../brand/brand.config";
import { BrandLogo, ProductLabel, ThinkingLogo } from "../brand/Logo";
import { applyTheme } from "../brand/theme";
import { BrowserSidebar } from "../browser/BrowserSidebar";
import { browserHost, useBrowser } from "../browser/host";
import { useSettings } from "../settings/settings";
import { Composer } from "./Composer";
import { logoState, MessageView } from "./MessageView";
import { emptyAssistant, isBusy, resumeConversation, sendTurn, stopTurn } from "./session";
import { createConversation, deleteConversation, setActive, syncFromServer, updateConversation, useStore } from "./store";
import type { UIMessage } from "./types";

const SettingsDialog = lazy(() => import("../settings/SettingsDialog"));
const ToolsModal = lazy(() => import("../plugins/ToolsModal"));

export default function ChatApp() {
  const brand = getBrand();
  const settings = useSettings();
  const { list, activeId } = useStore();
  const browser = useBrowser();
  const [cfg, setCfg] = useState<PublicConfig | null>(null);
  const [dark, setDark] = useState(false);
  const [modal, setModal] = useState<"settings" | "tools" | null>(null);
  const [context, setContext] = useState<string | undefined>();
  const scroller = useRef<HTMLDivElement>(null);
  const active = list.find((c) => c.id === activeId);
  const last = active?.messages.at(-1);
  const busy = !!active && (isBusy(active.id) || (last?.role === "assistant" && ["submitting", "thinking", "streaming"].includes(last.status)));

  // Theme: apply now and follow prefers-color-scheme live when "system".
  useEffect(() => {
    setDark(applyTheme(brand, settings.theme) === "dark");
    if (settings.theme !== "system") return;
    const mq = matchMedia("(prefers-color-scheme: dark)");
    const f = () => setDark(applyTheme(brand, "system") === "dark");
    mq.addEventListener("change", f);
    return () => mq.removeEventListener("change", f);
  }, [brand, settings.theme]);

  useEffect(() => {
    fetch("/api/config").then((r) => (r.ok ? r.json() : null)).then(setCfg).catch(() => setCfg(null));
    syncFromServer().catch(() => undefined);
    browserHost.onContext = (rec) => setContext(`${rec.type} ${rec.id} — ${rec.summary}`);
  }, []);

  // Reattach to an in-flight run (or re-ask pending tools) after a reload.
  useEffect(() => {
    if (activeId) void resumeConversation(activeId);
  }, [activeId]);

  useEffect(() => {
    scroller.current?.scrollTo({ top: scroller.current.scrollHeight });
  }, [last?.text, last?.steps.length, active?.messages.length]);

  const mode: ChatMode = settings.studioMode && cfg?.studioEnabled ? "studio" : settings.powerMode && cfg?.powerModeEnabled && brand.powerModeAllowed ? "power" : "assist";
  const signedIn = cfg && (cfg.user.source === "snowflake" || cfg.user.source === "sso") ? cfg.user.name : null;
  const displayName = signedIn ?? (settings.name || cfg?.user.name || "Guest");

  function send(text: string) {
    const conv = active ?? createConversation(brand.id);
    const ctx = context;
    const userMsg: UIMessage = { ...emptyAssistant(mode), role: "user", text, status: "done", context: ctx };
    const asst = emptyAssistant(mode);
    updateConversation(conv.id, (c) => ({ ...c, title: c.messages.length ? c.title : text.slice(0, 60), messages: [...c.messages, userMsg, asst] }));
    setContext(undefined);
    const content: UserContentItem[] = [{ type: "text", text: ctx ? `${text}\n\n(Context selected in ACME Store Ops: ${ctx})` : text }];
    void sendTurn(conv.id, asst.id, content, mode);
  }

  function regenerate() {
    const prevUser = [...(active?.messages ?? [])].reverse().find((m) => m.role === "user");
    if (prevUser) send(prevUser.text);
  }

  const items = useMemo(() => list.slice(0, 50), [list]);

  return (
    <div className={`shell ${browser.open ? "with-browser" : ""} ${mode === "power" ? "mode-power" : ""}`}>
      <nav className="sidebar" aria-label="Conversations">
        <div className="sidebar-brand">
          <BrandLogo brand={brand} dark={dark} height={26} />
        </div>
        <button className="btn primary block" onClick={() => setActive(null)} data-testid="new-chat">+ New chat</button>
        <ul className="conv-list">
          {items.map((c) => (
            <li key={c.id} className={c.id === activeId ? "on" : ""}>
              <button className="conv" onClick={() => setActive(c.id)} data-testid={`conv-${c.id}`}>{c.title}</button>
              <button className="icon-btn small" aria-label={`Delete ${c.title}`} onClick={() => deleteConversation(c.id)}>×</button>
            </li>
          ))}
        </ul>
        <div className="sidebar-foot">
          <div className="who">
            <div className="who-name" data-testid="user-name">{displayName}</div>
            <div className="muted small">{signedIn ? `Signed in (${cfg?.user.source})` : settings.email || brand.companyName}</div>
          </div>
          <button className="icon-btn" aria-label="Settings" onClick={() => setModal("settings")} data-testid="settings-open">⚙</button>
        </div>
      </nav>

      <main className="chat">
        <header className="chat-head">
          <ProductLabel brand={brand} />
          {mode === "power" && <span className="mode-badge power" data-testid="power-badge">Power Mode · Preview</span>}
          {mode === "studio" && <span className="mode-badge studio">Studio</span>}
          <span className="spacer" />
          <button className={`btn ghost ${browser.open ? "on" : ""}`} onClick={() => browserHost.setOpen(!browser.open)} data-testid="toggle-browser" aria-pressed={browser.open}>
            {browser.open ? "Hide apps" : "ACME apps"}
          </button>
        </header>

        {!active || active.messages.length === 0 ? (
          <div className="hero">
            <div className="hero-inner">
              <ThinkingLogo brand={brand} state="idle" size={64} />
              <h1>{brand.emptyPrompt}</h1>
              <div className="hero-stripes">
                <Composer brand={brand} busy={false} onSend={send} onStop={() => undefined} onTools={() => setModal("tools")} powerAvailable={!!cfg?.powerModeEnabled && brand.powerModeAllowed} studioAvailable={!!cfg?.studioEnabled} context={context} clearContext={() => setContext(undefined)} docked={false} />
              </div>
              <div className="suggestions">
                {["Which region is breaching its stockout threshold?", "Show me today's failed orders for the West region", "Assign the oldest Address mismatch exception to me"].map((q) => (
                  <button key={q} className="chip suggestion" onClick={() => send(q)}>{q}</button>
                ))}
              </div>
            </div>
          </div>
        ) : (
          <>
            <div className="messages" ref={scroller} data-testid="messages">
              {active.messages.map((m, i) => (
                <MessageView key={m.id} m={m} convId={active.id} brand={brand} dark={dark} onRegenerate={i === active.messages.length - 1 ? regenerate : undefined} />
              ))}
            </div>
            <div className="dock">
              {busy && <div className="dock-status"><ThinkingLogo brand={brand} state={logoState(last)} size={22} /></div>}
              <Composer brand={brand} busy={busy} onSend={send} onStop={() => active && stopTurn(active.id)} onTools={() => setModal("tools")} powerAvailable={!!cfg?.powerModeEnabled && brand.powerModeAllowed} studioAvailable={!!cfg?.studioEnabled} context={context} clearContext={() => setContext(undefined)} docked />
            </div>
          </>
        )}
      </main>

      {browser.open && <BrowserSidebar />}

      <Suspense fallback={null}>
        {modal === "settings" && <SettingsDialog brand={brand} cfg={cfg} onClose={() => setModal(null)} />}
        {modal === "tools" && <ToolsModal onClose={() => setModal(null)} />}
      </Suspense>
    </div>
  );
}

