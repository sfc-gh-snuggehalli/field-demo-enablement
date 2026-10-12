// Plugin registry: composer extensions (MCP servers, skills, ...) behind one interface so
// new extension types can be registered later. Items persist in localStorage for the demo.
import { useSyncExternalStore } from "react";
import type { McpConnection, SkillDef } from "../../shared/protocol";

export interface ExtensionItem {
  id: string;
  name: string;
  enabled: boolean;
}

export interface ExtensionType<T extends ExtensionItem> {
  id: string;
  label: string;
  storageKey: string;
  defaults: T[];
  /** Contribution to the chat request. */
  toRequest(enabled: T[]): Record<string, unknown>;
}

type AnyType = ExtensionType<any>;
const types = new Map<string, AnyType>();
const items = new Map<string, ExtensionItem[]>();
const subs = new Set<() => void>();
let version = 0;

export function registerExtensionType<T extends ExtensionItem>(t: ExtensionType<T>): void {
  types.set(t.id, t);
  let stored: T[] | undefined;
  try {
    stored = JSON.parse(localStorage.getItem(t.storageKey) || "null") ?? undefined;
  } catch {
    stored = undefined;
  }
  items.set(t.id, stored ?? t.defaults);
}

function save(typeId: string) {
  localStorage.setItem(types.get(typeId)!.storageKey, JSON.stringify(items.get(typeId)));
  version++;
  subs.forEach((f) => f());
}

export function listItems<T extends ExtensionItem>(typeId: string): T[] {
  return (items.get(typeId) ?? []) as T[];
}

export function upsertItem(typeId: string, item: ExtensionItem): void {
  const list = listItems(typeId).filter((i) => i.id !== item.id);
  items.set(typeId, [...list, item]);
  save(typeId);
}

export function removeItem(typeId: string, id: string): void {
  items.set(typeId, listItems(typeId).filter((i) => i.id !== id));
  save(typeId);
}

export function toggleItem(typeId: string, id: string, enabled?: boolean): void {
  items.set(typeId, listItems(typeId).map((i) => (i.id === id ? { ...i, enabled: enabled ?? !i.enabled } : i)));
  save(typeId);
}

/** Merged request contribution of every extension type. */
export function requestContributions(): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const t of types.values()) Object.assign(out, t.toRequest(listItems(t.id).filter((i) => i.enabled)));
  return out;
}

export function useExtensions(): number {
  return useSyncExternalStore((f) => (subs.add(f), () => subs.delete(f)), () => version);
}

export function extensionTypes(): AnyType[] {
  return [...types.values()];
}

// ---- Built-in extension types -------------------------------------------------------

/** Stored in localStorage without the auth header: that goes to the proxy once
 *  (PUT /api/mcp/credentials/:id) and is never read back. */
export type McpItem = Omit<McpConnection, "authHeader"> & { hasAuth?: boolean };

export async function saveMcpCredential(id: string, authHeader: string): Promise<boolean> {
  const r = await fetch(`/api/mcp/credentials/${encodeURIComponent(id)}`, { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ authHeader }) }).catch(() => undefined);
  return !!r?.ok;
}

export async function deleteMcpCredential(id: string): Promise<void> {
  await fetch(`/api/mcp/credentials/${encodeURIComponent(id)}`, { method: "DELETE" }).catch(() => undefined);
}
export type SkillItem = SkillDef & { enabled: boolean; stagePath?: string };

export const SAMPLE_SKILLS: SkillItem[] = [
  {
    id: "stockout-summary",
    name: "Store Stockout Summary",
    description: "Summarize stockouts by region and SKU with weeks of cover.",
    enabled: false,
    instructions: "Produce a stockout summary: for each region list SKUs with stockout_flag = true, on_hand, on_order and weeks_of_cover, ordered by region then daily_run_rate descending. Flag regions whose stockout rate exceeds stockout_threshold_pct. End with 3 recommended replenishment actions.",
  },
  {
    id: "exception-triage",
    name: "Fulfillment Exception Triage",
    description: "Prioritize open fulfillment exceptions by age and reason.",
    enabled: false,
    instructions: "Triage open fulfillment exceptions: group by reason, sort by age_hours descending, show unassigned ones first, and recommend an owner and next action per exception. If the browser tools are available, open /apps/storeops/exceptions and highlight the oldest unassigned row.",
  },
  {
    id: "weekly-recap",
    name: "Weekly Region Recap",
    description: "7-day recap per region: sales vs target, margin, stockouts.",
    enabled: false,
    instructions: "Write a weekly recap per region for the last 7 days of data: revenue and units, sales vs weekly_sales_target, gross margin %, stockout rate vs threshold and failed orders. Use one table, then two bullet highlights and one risk per region.",
  },
];

registerExtensionType<McpItem>({
  id: "mcp",
  label: "MCP servers",
  storageKey: "acme.mcp",
  defaults: [],
  toRequest: (enabled) => ({ mcp: enabled.map(({ id, name, url, enabled: on }) => ({ id, name, url, enabled: on })) }),
});

registerExtensionType<SkillItem>({
  id: "skill",
  label: "Skills",
  storageKey: "acme.skills",
  defaults: SAMPLE_SKILLS,
  toRequest: (enabled) => ({ skills: enabled.map(({ id, name, description, instructions, stagePath }) => ({ id, name, description, instructions, stagePath })) }),
});

// One-time migration: older builds kept MCP auth headers in localStorage. Hand them to the
// proxy and strip them from the browser.
{
  const legacy = listItems<McpItem & { authHeader?: string }>("mcp").filter((c) => c.authHeader);
  if (legacy.length) {
    for (const c of legacy) void saveMcpCredential(c.id, c.authHeader!);
    for (const { authHeader: _a, ...c } of legacy) upsertItem("mcp", { ...c, hasAuth: true } as McpItem);
  }
}
