// Conversation store: localStorage is the offline cache, the proxy (/api/conversations)
// is the source of truth when reachable; the newer `updated` wins. Saves are debounced.
import { useSyncExternalStore } from "react";
import type { ConversationRecord } from "../../shared/protocol";
import type { Conversation, UIMessage } from "./types";

const KEY = "acme.conversations";
const ACTIVE = "acme.active";

interface State {
  list: Conversation[];
  activeId: string | null;
}

let state: State = { list: loadLocal(), activeId: localStorage.getItem(ACTIVE) };
const subs = new Set<() => void>();
const timers = new Map<string, ReturnType<typeof setTimeout>>();

function loadLocal(): Conversation[] {
  try {
    return JSON.parse(localStorage.getItem(KEY) || "[]");
  } catch {
    return [];
  }
}

function commit(next: State) {
  state = next;
  localStorage.setItem(KEY, JSON.stringify(state.list.slice(0, 50)));
  if (state.activeId) localStorage.setItem(ACTIVE, state.activeId);
  else localStorage.removeItem(ACTIVE);
  subs.forEach((f) => f());
}

export const newId = () => crypto.randomUUID().replace(/-/g, "").slice(0, 24);

export function useStore(): State {
  return useSyncExternalStore((f) => (subs.add(f), () => subs.delete(f)), () => state);
}
export const getState = () => state;
export const getConversation = (id: string) => state.list.find((c) => c.id === id);

export function setActive(id: string | null) {
  commit({ ...state, activeId: id });
}

export function createConversation(brand: string): Conversation {
  const now = new Date().toISOString();
  const c: Conversation = { id: newId(), title: "New chat", brand, messages: [], wire: {}, created: now, updated: now };
  commit({ list: [c, ...state.list], activeId: c.id });
  return c;
}

export function updateConversation(id: string, fn: (c: Conversation) => Conversation, persist = true) {
  const list = state.list.map((c) => (c.id === id ? { ...fn(c), updated: new Date().toISOString() } : c));
  commit({ ...state, list });
  if (persist) scheduleSave(id);
}

export function updateMessage(convId: string, msgId: string, fn: (m: UIMessage) => UIMessage) {
  updateConversation(convId, (c) => ({ ...c, messages: c.messages.map((m) => (m.id === msgId ? fn(m) : m)) }), false);
}

export async function deleteConversation(id: string) {
  commit({ list: state.list.filter((c) => c.id !== id), activeId: state.activeId === id ? null : state.activeId });
  await fetch(`/api/conversations/${id}`, { method: "DELETE" }).catch(() => undefined);
}

function scheduleSave(id: string) {
  clearTimeout(timers.get(id));
  timers.set(
    id,
    setTimeout(() => {
      const c = getConversation(id);
      if (!c) return;
      const rec: ConversationRecord = { id: c.id, title: c.title, brand: c.brand, ui: c.messages, wire: c.wire, studioSessionId: c.wire.studioSessionId, created: c.created, updated: c.updated };
      fetch(`/api/conversations/${id}`, { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify(rec) }).catch(() => undefined);
    }, 800),
  );
}

export function saveNow(id: string) {
  scheduleSave(id);
}

/** Pull the server list and merge: server wins when its `updated` is newer. */
export async function syncFromServer(): Promise<void> {
  const res = await fetch("/api/conversations").catch(() => undefined);
  if (!res?.ok) return;
  const metas: Array<Omit<ConversationRecord, "ui" | "wire">> = await res.json();
  const local = new Map(state.list.map((c) => [c.id, c]));
  const merged: Conversation[] = [...state.list];
  for (const m of metas) {
    const l = local.get(m.id);
    if (l && l.updated >= m.updated) continue;
    const full = await fetch(`/api/conversations/${m.id}`).then((r) => (r.ok ? (r.json() as Promise<ConversationRecord>) : undefined)).catch(() => undefined);
    if (!full) continue;
    const conv: Conversation = { id: full.id, title: full.title, brand: full.brand, messages: (full.ui as UIMessage[]) ?? [], wire: (full.wire as any) ?? {}, created: full.created, updated: full.updated };
    const i = merged.findIndex((c) => c.id === m.id);
    if (i >= 0) merged[i] = conv;
    else merged.push(conv);
  }
  merged.sort((a, b) => b.updated.localeCompare(a.updated));
  commit({ ...state, list: merged });
}
