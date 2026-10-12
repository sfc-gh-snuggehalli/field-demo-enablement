// Lazy chunk: Tools modal (MCP servers + skills) driven by the plugin registry.
import { useState } from "react";
import { deleteMcpCredential, listItems, removeItem, saveMcpCredential, toggleItem, upsertItem, useExtensions, type McpItem, type SkillItem } from "./registry";

export default function ToolsModal({ onClose }: { onClose: () => void }) {
  useExtensions();
  const [tab, setTab] = useState<"mcp" | "skill">("skill");
  const [mcp, setMcp] = useState({ name: "", url: "", authHeader: "" });
  const [skill, setSkill] = useState({ name: "", description: "", instructions: "" });
  const [test, setTest] = useState<string>("");
  const mcps = listItems<McpItem>("mcp");
  const skills = listItems<SkillItem>("skill");
  const validUrl = /^https?:\/\/\S+$/.test(mcp.url);

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" role="dialog" aria-modal="true" aria-label="Tools" onClick={(e) => e.stopPropagation()} data-testid="tools-modal">
        <div className="modal-head">
          <div className="tabs" role="tablist">
            <button role="tab" aria-selected={tab === "skill"} className={tab === "skill" ? "on" : ""} onClick={() => setTab("skill")} data-testid="tab-skills">Skills</button>
            <button role="tab" aria-selected={tab === "mcp"} className={tab === "mcp" ? "on" : ""} onClick={() => setTab("mcp")} data-testid="tab-mcp">MCP servers</button>
          </div>
          <button className="icon-btn" aria-label="Close" onClick={onClose} data-testid="tools-close">×</button>
        </div>
        {tab === "skill" ? (
          <div className="modal-body">
            <p className="muted">Selected skills inject their instructions into the agent request.</p>
            <ul className="ext-list">
              {skills.map((k) => (
                <li key={k.id}>
                  <label>
                    <input type="checkbox" checked={k.enabled} onChange={() => toggleItem("skill", k.id)} data-testid={`skill-${k.id}`} /> <strong>{k.name}</strong>
                  </label>
                  <div className="muted">{k.description}</div>
                  <button className="link-btn" onClick={() => removeItem("skill", k.id)} aria-label={`Remove ${k.name}`}>Remove</button>
                </li>
              ))}
            </ul>
            <form className="ext-form" onSubmit={(e) => { e.preventDefault(); if (!skill.name || !skill.instructions) return; upsertItem("skill", { id: `sk-${Date.now()}`, enabled: true, ...skill } as SkillItem); setSkill({ name: "", description: "", instructions: "" }); }}>
              <input placeholder="Skill name" aria-label="Skill name" value={skill.name} onChange={(e) => setSkill({ ...skill, name: e.target.value })} />
              <input placeholder="Description" aria-label="Skill description" value={skill.description} onChange={(e) => setSkill({ ...skill, description: e.target.value })} />
              <textarea placeholder="Instructions (markdown)" aria-label="Skill instructions" rows={4} value={skill.instructions} onChange={(e) => setSkill({ ...skill, instructions: e.target.value })} />
              <button className="btn primary" type="submit">Add skill</button>
            </form>
          </div>
        ) : (
          <div className="modal-body">
            <p className="muted">MCP servers are called by the ACME proxy (auth headers stay server-side) and exposed to the agent as tools.</p>
            <ul className="ext-list">
              {mcps.length === 0 && <li className="muted">No MCP servers yet.</li>}
              {mcps.map((c) => (
                <li key={c.id}>
                  <label>
                    <input type="checkbox" checked={c.enabled} onChange={() => toggleItem("mcp", c.id)} data-testid={`mcp-${c.name}`} /> <strong>{c.name}</strong> <span className="muted">{c.url}</span>{c.hasAuth ? <span className="muted small"> · auth stored on server</span> : null}
                  </label>
                  <button className="link-btn" onClick={() => { void deleteMcpCredential(c.id); removeItem("mcp", c.id); }}>Remove</button>
                </li>
              ))}
            </ul>
            <form className="ext-form" onSubmit={async (e) => { e.preventDefault(); if (!mcp.name || !validUrl) return; const id = `mcp-${Date.now()}`; const hasAuth = !!mcp.authHeader.trim() && (await saveMcpCredential(id, mcp.authHeader)); upsertItem("mcp", { id, enabled: true, name: mcp.name, url: mcp.url, hasAuth } as McpItem); setMcp({ name: "", url: "", authHeader: "" }); }}>
              <input placeholder="Name" aria-label="MCP name" data-testid="mcp-name" value={mcp.name} onChange={(e) => setMcp({ ...mcp, name: e.target.value })} />
              <input placeholder="https://… (Streamable HTTP endpoint)" aria-label="MCP URL" data-testid="mcp-url" value={mcp.url} onChange={(e) => setMcp({ ...mcp, url: e.target.value })} />
              <input placeholder="Auth header, e.g. Authorization: Bearer …" aria-label="MCP auth header" value={mcp.authHeader} onChange={(e) => setMcp({ ...mcp, authHeader: e.target.value })} />
              <div className="row">
                <button className="btn primary" type="submit" disabled={!mcp.name || !validUrl} data-testid="mcp-add">Add MCP server</button>
                <button className="btn" type="button" disabled={!validUrl} onClick={async () => { setTest("Testing…"); const r = await fetch("/api/mcp/test", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(mcp) }).then((x) => x.json()).catch((e) => ({ errors: [e.message] })); setTest(r.errors?.length ? `Error: ${r.errors.join("; ")}` : `${r.tools.length} tools: ${r.tools.join(", ")}`); }}>Test</button>
              </div>
              {test && <div className="muted">{test}</div>}
            </form>
          </div>
        )}
      </div>
    </div>
  );
}
