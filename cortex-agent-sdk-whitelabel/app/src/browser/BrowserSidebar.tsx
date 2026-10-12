import { lazy, Suspense, useEffect, useState, useSyncExternalStore } from "react";
import { APPS } from "../config/app.config";
import { browserHost, useBrowser } from "./host";

// Store Ops renders inline (same document, in-memory router). App Runtime's ingress sends
// X-Frame-Options: DENY, which blocks iframes even on the same origin.
const InlineStoreOps = lazy(() => import("../apps/storeops/StoreOpsApp").then((m) => ({ default: m.InlineStoreOps })));

/** Right-hand drawer with an inline app view, URL bar and app bookmarks. */
export function BrowserSidebar() {
  const st = useBrowser();
  const mount = useSyncExternalStore(browserHost.subscribe, () => browserHost.mount);
  const [draft, setDraft] = useState(st.url);
  useEffect(() => setDraft(st.url), [st.url]);
  const go = (url: string) => browserHost.navigate(url).catch((e) => alert(e.message));
  const cursorFresh = st.cursor && Date.now() - st.cursor.at < 2500;

  return (
    <aside className="browser" aria-label="Browser sidebar" data-testid="browser-sidebar">
      <div className="browser-bar">
        <button className="icon-btn" aria-label="Back" data-testid="browser-back" onClick={() => browserHost.history("back")}>‹</button>
        <button className="icon-btn" aria-label="Forward" data-testid="browser-forward" onClick={() => browserHost.history("forward")}>›</button>
        <button className="icon-btn" aria-label="Refresh" data-testid="browser-refresh" onClick={() => browserHost.history("refresh")}>↻</button>
        <form className="url-form" onSubmit={(e) => (e.preventDefault(), go(draft))}>
          <input aria-label="Address" data-testid="browser-url" value={draft} onChange={(e) => setDraft(e.target.value)} />
        </form>
        <button className="icon-btn" aria-label="Close browser" data-testid="browser-close" onClick={() => browserHost.setOpen(false)}>×</button>
      </div>
      <div className="bookmarks" role="toolbar" aria-label="ACME apps">
        {APPS.map((a) => (
          <button key={a.id} className="bookmark" data-testid={`bookmark-${a.id}`} onClick={() => go(a.url)} title={a.url}>
            <span className="bm-icon" aria-hidden>{a.icon}</span>
            {a.name}
          </button>
        ))}
      </div>
      <div className="browser-frame-wrap">
        {st.loading && <div className="browser-loading" aria-live="polite">Loading…</div>}
        {cursorFresh && (
          <div className="agent-cursor" key={st.cursor!.at} aria-live="polite">
            <span className="agent-cursor-dot" /> {st.cursor!.label}
          </div>
        )}
        <div className="browser-frame browser-inline">
          <Suspense fallback={<div className="browser-loading">Loading…</div>}>
            <InlineStoreOps key={mount.key} initialUrl={mount.url} />
          </Suspense>
        </div>
      </div>
    </aside>
  );
}
