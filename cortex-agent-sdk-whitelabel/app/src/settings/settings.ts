// Per-user preferences, persisted in localStorage (acme.settings). Apply immediately.
import { useSyncExternalStore } from "react";
import type { ThemeMode } from "../brand/theme";
import { MODELS, DEFAULT_MODEL } from "../config/app.config";

export interface Settings {
  theme: ThemeMode;
  showDetails: boolean;
  name: string;
  email: string;
  model: string;
  powerMode: boolean;
  studioMode: boolean;
}

export const DEFAULT_SETTINGS: Settings = { theme: "system", showDetails: false, name: "", email: "", model: DEFAULT_MODEL, powerMode: false, studioMode: false };
const KEY = "acme.settings";
export const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

let state: Settings = load();
const subs = new Set<() => void>();

function load(): Settings {
  try {
    const s = { ...DEFAULT_SETTINGS, ...JSON.parse(localStorage.getItem(KEY) || "{}") };
    // A model removed from the list (or not allowed for agents) falls back to auto.
    if (!MODELS.some((m) => m.id === s.model)) s.model = DEFAULT_MODEL;
    return s;
  } catch {
    return { ...DEFAULT_SETTINGS };
  }
}

export function getSettings(): Settings {
  return state;
}

export function updateSettings(patch: Partial<Settings>): void {
  state = { ...state, ...patch };
  localStorage.setItem(KEY, JSON.stringify(state));
  subs.forEach((f) => f());
}

export function resetSettings(): void {
  state = { ...DEFAULT_SETTINGS };
  localStorage.removeItem(KEY);
  subs.forEach((f) => f());
}

export function useSettings(): Settings {
  return useSyncExternalStore((f) => (subs.add(f), () => subs.delete(f)), () => state);
}
