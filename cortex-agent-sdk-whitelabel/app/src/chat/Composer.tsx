import { useRef, useState, type KeyboardEvent } from "react";
import type { BrandConfig } from "../brand/brand.config";
import { MODELS } from "../config/app.config";
import { listItems, useExtensions, type SkillItem } from "../plugins/registry";
import { updateSettings, useSettings } from "../settings/settings";

export function Composer({ brand, busy, onSend, onStop, onTools, powerAvailable, studioAvailable, context, clearContext, docked }: {
  brand: BrandConfig;
  busy: boolean;
  onSend: (text: string) => void;
  onStop: () => void;
  onTools: () => void;
  powerAvailable: boolean;
  studioAvailable: boolean;
  context?: string;
  clearContext: () => void;
  docked: boolean;
}) {
  const s = useSettings();
  useExtensions();
  const [text, setText] = useState("");
  const ref = useRef<HTMLTextAreaElement>(null);
  const activeSkills = listItems<SkillItem>("skill").filter((x) => x.enabled);
  const activeMcp = listItems("mcp").filter((x) => x.enabled);
  const submit = () => {
    const t = text.trim();
    if (!t || busy) return;
    onSend(t);
    setText("");
  };
  const onKey = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      submit();
    }
  };
  return (
    <div className={`composer ${docked ? "docked" : "hero"} ${s.powerMode && powerAvailable ? "power-on" : ""}`} data-testid="composer">
      {context && (
        <div className="ctx-chip">
          Context: {context}
          <button className="link-btn" aria-label="Remove context" onClick={clearContext}>×</button>
        </div>
      )}
      <textarea ref={ref} data-testid="composer-input" aria-label="Message" placeholder={brand.emptyPrompt} value={text} onChange={(e) => setText(e.target.value)} onKeyDown={onKey} rows={docked ? 1 : 3} />
      <div className="composer-row">
        <button className="btn ghost" onClick={onTools} data-testid="tools-menu" aria-label="Tools, MCP servers and skills">+ Tools</button>
        {activeSkills.map((k) => <span key={k.id} className="chip">{k.name}</span>)}
        {activeMcp.length ? <span className="chip">{activeMcp.length} MCP</span> : null}
        <span className="spacer" />
        {powerAvailable && (
          <label className={`toggle ${s.powerMode ? "on power" : ""}`} data-testid="power-toggle">
            <input type="checkbox" checked={s.powerMode} onChange={(e) => updateSettings({ powerMode: e.target.checked, studioMode: false })} /> Power Mode <span className="preview-tag">Preview</span>
          </label>
        )}
        {studioAvailable && (
          <label className={`toggle ${s.studioMode ? "on" : ""}`} data-testid="studio-toggle">
            <input type="checkbox" checked={s.studioMode} onChange={(e) => updateSettings({ studioMode: e.target.checked, powerMode: false })} /> Studio
          </label>
        )}
        <select aria-label="Model" data-testid="model-select" value={s.model} onChange={(e) => updateSettings({ model: e.target.value })}>
          {[...new Set(MODELS.map((m) => m.group))].map((g) => (
            <optgroup key={g} label={g}>
              {MODELS.filter((m) => m.group === g).map((m) => <option key={m.id} value={m.id}>{m.label}</option>)}
            </optgroup>
          ))}
        </select>
        {busy ? (
          <button className="btn" onClick={onStop} data-testid="stop" aria-label="Stop">Stop</button>
        ) : (
          <button className="btn primary" onClick={submit} disabled={!text.trim()} data-testid="send" aria-label="Send">Send</button>
        )}
      </div>
    </div>
  );
}
