// Lazy chunk: Settings dialog. Persists to localStorage (acme.settings) and applies live.
import { useState } from "react";
import type { PublicConfig } from "../../shared/protocol";
import type { BrandConfig } from "../brand/brand.config";
import { EMAIL_RE, resetSettings, updateSettings, useSettings } from "./settings";

export default function SettingsDialog({ brand, cfg, onClose }: { brand: BrandConfig; cfg: PublicConfig | null; onClose: () => void }) {
  const s = useSettings();
  const [email, setEmail] = useState(s.email);
  const emailOk = email === "" || EMAIL_RE.test(email);
  const signedIn = cfg?.user.source === "snowflake" || cfg?.user.source === "sso" ? cfg.user.name : null;
  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" role="dialog" aria-modal="true" aria-label="Settings" onClick={(e) => e.stopPropagation()} data-testid="settings-dialog">
        <div className="modal-head">
          <h2>Settings</h2>
          <button className="icon-btn" aria-label="Close" onClick={onClose} data-testid="settings-close">×</button>
        </div>
        <div className="modal-body form">
          <fieldset>
            <legend>Theme</legend>
            {(["light", "dark", "system"] as const).map((t) => (
              <label key={t} className="radio">
                <input type="radio" name="theme" checked={s.theme === t} onChange={() => updateSettings({ theme: t })} data-testid={`theme-${t}`} /> {t[0].toUpperCase() + t.slice(1)}
              </label>
            ))}
          </fieldset>
          <label className="check">
            <input type="checkbox" checked={s.showDetails} onChange={(e) => updateSettings({ showDetails: e.target.checked })} data-testid="setting-show-details" /> Show thinking &amp; tool details
          </label>
          {signedIn && (
            <div className="field">
              <span className="label">Signed in as</span>
              <input readOnly value={signedIn} aria-label="Signed in as" data-testid="signed-in-as" />
            </div>
          )}
          <label className="field">
            <span className="label">Name</span>
            <input value={s.name} onChange={(e) => updateSettings({ name: e.target.value })} data-testid="setting-name" placeholder={signedIn ?? "Your name"} />
          </label>
          <label className="field">
            <span className="label">Email</span>
            <input value={email} onChange={(e) => { setEmail(e.target.value); if (e.target.value === "" || EMAIL_RE.test(e.target.value)) updateSettings({ email: e.target.value }); }} aria-invalid={!emailOk} data-testid="setting-email" placeholder="name@acme.example" />
            {!emailOk && <span className="error">Enter a valid email address.</span>}
          </label>
          <p className="muted small">Name and email are sent to {brand.productName} as context (for example, "assign to me"). They are not used for authentication.</p>
          <p className="muted small" data-testid="history-note">Conversation history is stored {cfg?.historyStore === "snowflake" ? "in Snowflake (ACME_ASSIST_DEMO.APP.CONVERSATIONS), scoped to your user" : "in this browser and on the app server for this user"}.</p>
          <p className="muted small">Brand ({brand.productName}, logo) is set by the administrator.</p>
          <button className="btn" onClick={() => { resetSettings(); setEmail(""); }} data-testid="settings-reset">Reset to defaults</button>
        </div>
      </div>
    </div>
  );
}
