import type { BrandConfig, Palette } from "./brand.config";

export type ThemeMode = "light" | "dark" | "system";

export function resolveMode(mode: ThemeMode): "light" | "dark" {
  if (mode !== "system") return mode;
  return typeof matchMedia !== "undefined" && matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

const kebab = (s: string) => s.replace(/[A-Z0-9]/g, (c) => "-" + c.toLowerCase()).replace(/-(\d)/g, "$1");

/** Writes the palette to CSS variables on :root. Components only use var(--...). */
export function applyTheme(brand: BrandConfig, mode: ThemeMode): "light" | "dark" {
  const resolved = resolveMode(mode);
  const p: Palette = resolved === "dark" ? brand.darkTheme : brand.theme;
  const root = document.documentElement;
  for (const [k, v] of Object.entries(p)) root.style.setProperty(`--${kebab(k)}`, v);
  root.style.setProperty("--trail-1", brand.animation.trail[0]);
  root.style.setProperty("--trail-2", brand.animation.trail[1]);
  root.style.setProperty("--orbit-ms", `${brand.animation.orbitMs}ms`);
  root.style.setProperty("--font", brand.font);
  root.dataset.theme = resolved;
  root.dataset.brand = brand.id;
  document.title = brand.productName;
  const fav = document.getElementById("brand-favicon") as HTMLLinkElement | null;
  if (fav) fav.href = brand.favicon;
  return resolved;
}

export function currentPalette(brand: BrandConfig): Palette {
  return document.documentElement.dataset.theme === "dark" ? brand.darkTheme : brand.theme;
}
