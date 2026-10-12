import { lazy, Suspense, useEffect, useState } from "react";
import type { BrandConfig } from "../brand/brand.config";
import { ThinkingLogo, type ThinkingState } from "../brand/Logo";
import { DataTable } from "../render/DataTable";
import { useSettings } from "../settings/settings";
import { decideApproval } from "./session";
import type { Approval, Step, UIMessage } from "./types";

const Markdown = lazy(() => import("../render/Markdown"));
const VegaChart = lazy(() => import("../render/VegaChart"));

const working = (m: UIMessage) => ["submitting", "thinking", "streaming"].includes(m.status);

export function logoState(m: UIMessage | undefined): ThinkingState {
  if (!m) return "idle";
  if (m.status === "submitting") return "submitting";
  if (m.status === "thinking") return "thinking";
  if (m.status === "streaming") return "streaming";
  return "done";
}

function useTick(active: boolean) {
  const [, set] = useState(0);
  useEffect(() => {
    if (!active) return;
    const t = setInterval(() => set((n) => n + 1), 1000);
    return () => clearInterval(t);
  }, [active]);
}

const stepIcon: Record<Step["state"], string> = { running: "◌", done: "✓", error: "!", denied: "⊘" };

/** Status and reconnect lines are orchestration chatter; tool steps and failures are what users act on. */
const isNoise = (s: Step) => (s.kind === "status" || s.kind === "reconnect") && s.state !== "error";
const keySteps = (steps: Step[]) => steps.filter((s) => !isNoise(s));
const count = (n: number) => `${n} step${n === 1 ? "" : "s"}`;

/** One compact live line while a run is in progress; click opens the accordion. */
function LiveLine({ m, onOpen }: { m: UIMessage; onOpen: () => void }) {
  useTick(true);
  const current = [...m.steps].reverse().find((s) => s.state === "running") ?? m.steps.at(-1);
  const secs = Math.max(0, Math.round((Date.now() - m.started) / 1000));
  const label = current?.label ?? (m.status === "submitting" ? "Sending" : m.status === "streaming" ? "Writing answer" : "Thinking");
  return (
    <button className="live-line" onClick={onOpen} data-testid="live-line" aria-live="polite">
      <span className="pulse" aria-hidden />
      <span className="live-label">{label}</span>
      <span className="muted">· {secs}s · {count(keySteps(m.steps).length)}</span>
    </button>
  );
}

function ApprovalCard({ a, convId, msgId }: { a: Approval; convId: string; msgId: string }) {
  return (
    <div className={`approval ${a.state}`} role="group" aria-label="Approval required" data-testid={`approval-${a.toolUseId}`}>
      <div className="approval-title">{a.state === "pending" ? "Approval needed" : `Decision: ${a.decision}`} · {a.title}</div>
      {a.preview && <pre className="approval-preview">{a.preview}</pre>}
      {a.state === "pending" && (
        <div className="approval-actions">
          {a.options.map((o) => (
            <button key={o} className={/deny|reject/i.test(o) ? "btn" : "btn primary"} data-testid={`approval-${/deny|reject/i.test(o) ? "deny" : "allow"}`} onClick={() => decideApproval(convId, msgId, a, o)}>
              {o}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

export function MessageView({ m, convId, brand, dark, onRegenerate }: { m: UIMessage; convId: string; brand: BrandConfig; dark: boolean; onRegenerate?: () => void }) {
  const { showDetails } = useSettings();
  const [actOpen, setActOpen] = useState(showDetails);
  const [thinkOpen, setThinkOpen] = useState(showDetails);
  const [allSteps, setAllSteps] = useState(false);
  useEffect(() => {
    setActOpen(showDetails);
    setThinkOpen(showDetails);
  }, [showDetails]);

  if (m.role === "user") {
    return (
      <div className="msg user" data-testid="msg-user">
        {m.context && <div className="ctx-chip">{m.context}</div>}
        <div className="bubble">{m.text}</div>
      </div>
    );
  }

  const busy = working(m);
  return (
    <div className={`msg assistant ${m.mode === "power" ? "power" : ""}`} data-testid="msg-assistant" data-status={m.status}>
      <div className="msg-avatar">
        <ThinkingLogo brand={brand} state={logoState(m)} size={30} />
      </div>
      <div className="msg-body">
        {m.mode && m.mode !== "assist" && <span className={`mode-badge ${m.mode}`}>{m.mode === "power" ? "Power Mode · Preview" : "Studio"}</span>}
        {m.skills?.length ? (
          <div className="chips">
            {m.skills.map((s) => <span key={s} className="chip" title="Bundled Cortex Code skill attached">${s}</span>)}
          </div>
        ) : null}
        {/* Approval cards are never collapsed. */}
        {m.approvals.map((a) => <ApprovalCard key={a.id} a={a} convId={convId} msgId={m.id} />)}

        {busy ? <LiveLine m={m} onOpen={() => setActOpen(true)} /> : null}

        {m.thinking ? (
          <details className="acc" open={thinkOpen} onToggle={(e) => setThinkOpen((e.target as HTMLDetailsElement).open)}>
            <summary>Thinking</summary>
            <div className="acc-body thinking-text">{m.thinking}</div>
          </details>
        ) : null}
        {m.steps.length ? (
          <details className="acc" open={actOpen} onToggle={(e) => setActOpen((e.target as HTMLDetailsElement).open)} data-testid="activity">
            <summary>Activity · {count(keySteps(m.steps).length)}</summary>
            <ol className="acc-body steps">
              {(showDetails || allSteps ? m.steps : keySteps(m.steps)).map((s) => (
                <li key={s.id} className={`step ${s.state} k-${s.kind}`} data-testid={`step-${s.kind}`}>
                  <span className="step-icon" aria-label={s.state}>{stepIcon[s.state]}</span>
                  <span>{s.label}</span>
                  {s.sql && <pre className="code">{s.sql}</pre>}
                  {s.detail && s.kind !== "sql" && <pre className="code small">{s.detail}</pre>}
                </li>
              ))}
              {!showDetails && keySteps(m.steps).length < m.steps.length && (
                <li>
                  <button className="steps-more" data-testid="steps-toggle" onClick={() => setAllSteps((v) => !v)}>
                    {allSteps ? "Hide status updates" : `Show all ${m.steps.length} updates`}
                  </button>
                </li>
              )}
            </ol>
          </details>
        ) : null}

        {m.text ? (
          <Suspense fallback={<div className="md plain">{m.text}</div>}>
            <Markdown text={m.text} />
          </Suspense>
        ) : null}
        {m.tables.map((t) => <DataTable key={t.id} columns={t.columns} rows={t.rows} title="Analyst result" />)}
        {m.charts.map((c) => (
          <Suspense key={c.id} fallback={<div className="chart-card muted">Loading chart…</div>}>
            <VegaChart spec={c.spec} brand={brand} dark={dark} />
          </Suspense>
        ))}
        {m.files.length ? (
          <div className="chips">
            {m.files.map((f) => (
              <a key={f.url + f.name} className="chip file" href={f.url} download={f.name}>⬇ {f.name}</a>
            ))}
          </div>
        ) : null}
        {m.status === "error" && <div className="error" role="alert">{m.error}</div>}
        {m.status === "cancelled" && <div className="muted">Stopped.</div>}
        {!busy && m.text && (
          <div className="msg-actions">
            <button className="link-btn" onClick={() => navigator.clipboard.writeText(m.text)} data-testid="copy">Copy</button>
            {onRegenerate && <button className="link-btn" onClick={onRegenerate} data-testid="regenerate">Regenerate</button>}
          </div>
        )}
      </div>
    </div>
  );
}
