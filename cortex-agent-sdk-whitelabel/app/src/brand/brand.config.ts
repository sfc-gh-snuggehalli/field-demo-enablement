// brand.config.ts — the single place that controls branding. Re-brand by adding an entry
// here plus assets in public/brand/<brandId>/, then set VITE_BRAND / NEXT_PUBLIC_BRAND.
// Shared code: no import.meta.env and no asset imports (assets are URLs under /brand).

export interface Palette {
  primary: string;
  secondary: string;
  accent: string;
  accentLight: string;
  accentLight2: string;
  accentTint: string;
  accentTint2: string;
  background: string;
  surface: string;
  card: string;
  border: string;
  text: string;
  textMuted: string;
  textMuted2: string;
  success: string;
  warning: string;
  danger: string;
  power: string;
}

export interface BrandMark {
  viewBox: string;
  /** Static body of the mark (filled with primary/text). */
  basePath: string;
  /** The detachable accent stroke (the ACME chevron) that animates. */
  accentPath: string;
  accentWidth: number;
  /** Center the accent orbits around while thinking. */
  orbit: { cx: number; cy: number; r: number };
}

export interface BrandConfig {
  id: string;
  productName: string;
  productPrefix: string; // "ACME"
  productSuffix: string; // "Assist" (rendered in accent)
  companyName: string;
  logo: { light: string; dark: string; mark: string };
  favicon: string;
  font: string;
  theme: Palette;
  darkTheme: Palette;
  mark: BrandMark;
  animation: { name: string; orbitMs: number; trail: [string, string] };
  emptyPrompt: string;
  powerModeAllowed: boolean;
}

const acmeMark: BrandMark = {
  viewBox: "0 0 64 64",
  basePath: "M6 56 L27 8 H37 L58 56 H46 L32 22 L18 56 Z",
  accentPath: "M20 46 L32 35 L44 46",
  accentWidth: 7,
  orbit: { cx: 32, cy: 36, r: 22 },
};

const FONT = "Inter, system-ui, -apple-system, 'Segoe UI', sans-serif";

export const BRANDS: Record<string, BrandConfig> = {
  acme: {
    id: "acme",
    productName: "ACME Assist",
    productPrefix: "ACME",
    productSuffix: "Assist",
    companyName: "ACME Retail",
    logo: { light: "/brand/acme/logo.svg", dark: "/brand/acme/logo-dark.svg", mark: "/brand/acme/mark.svg" },
    favicon: "/brand/acme/mark.svg",
    font: FONT,
    theme: {
      primary: "#1F2A44", secondary: "#5B6478", accent: "#E4572E", accentLight: "#F28C6B", accentLight2: "#F7B39C",
      accentTint: "#FDEEE8", accentTint2: "#FADBCF", background: "#FFFFFF", surface: "#F6F7F9", card: "#FFFFFF",
      border: "#E6E8EC", text: "#1F2A44", textMuted: "#5B6478", textMuted2: "#A3AAB8", success: "#2E9E5B",
      warning: "#D98E04", danger: "#C2410C", power: "#6D28D9",
    },
    darkTheme: {
      primary: "#F4F5F7", secondary: "#A3AAB8", accent: "#F06A43", accentLight: "#F28C6B", accentLight2: "#F7B39C",
      accentTint: "#3A2622", accentTint2: "#4A2C24", background: "#141B2D", surface: "#1C2540", card: "#222C4A",
      border: "#2E3A5C", text: "#F4F5F7", textMuted: "#A3AAB8", textMuted2: "#6F7891", success: "#43B873",
      warning: "#E9A23B", danger: "#F87171", power: "#A78BFA",
    },
    mark: acmeMark,
    animation: { name: "spark-and-settle", orbitMs: 1600, trail: ["#F28C6B", "#F7B39C"] },
    emptyPrompt: "What can ACME Assist help with?",
    powerModeAllowed: true,
  },
  northwind: {
    id: "northwind",
    productName: "Northwind Assist",
    productPrefix: "Northwind",
    productSuffix: "Assist",
    companyName: "Northwind Traders",
    logo: { light: "/brand/northwind/logo.svg", dark: "/brand/northwind/logo-dark.svg", mark: "/brand/northwind/mark.svg" },
    favicon: "/brand/northwind/mark.svg",
    font: FONT,
    theme: {
      primary: "#1E293B", secondary: "#475569", accent: "#0F766E", accentLight: "#14B8A6", accentLight2: "#5EEAD4",
      accentTint: "#E6F4F2", accentTint2: "#CCEBE7", background: "#FFFFFF", surface: "#F1F5F9", card: "#FFFFFF",
      border: "#E2E8F0", text: "#1E293B", textMuted: "#475569", textMuted2: "#94A3B8", success: "#15803D",
      warning: "#B45309", danger: "#B91C1C", power: "#7C3AED",
    },
    darkTheme: {
      primary: "#E2E8F0", secondary: "#94A3B8", accent: "#2DD4BF", accentLight: "#14B8A6", accentLight2: "#5EEAD4",
      accentTint: "#123432", accentTint2: "#164340", background: "#0F172A", surface: "#1E293B", card: "#24324A",
      border: "#334155", text: "#E2E8F0", textMuted: "#94A3B8", textMuted2: "#64748B", success: "#4ADE80",
      warning: "#FBBF24", danger: "#F87171", power: "#C4B5FD",
    },
    mark: {
      viewBox: "0 0 64 64",
      basePath: "M10 56 V8 H21 L43 40 V8 H54 V56 H43 L21 24 V56 Z",
      accentPath: "M40 54 L49 46 L58 54",
      accentWidth: 7,
      orbit: { cx: 32, cy: 32, r: 24 },
    },
    animation: { name: "spark-and-settle", orbitMs: 1800, trail: ["#14B8A6", "#5EEAD4"] },
    emptyPrompt: "What can Northwind Assist help with?",
    powerModeAllowed: true,
  },
};

let defaultBrand = "acme";

/** Vite: setDefaultBrand(import.meta.env.VITE_BRAND); Next.js: setDefaultBrand(process.env.NEXT_PUBLIC_BRAND). */
export function setDefaultBrand(id: string | undefined): void {
  if (id && BRANDS[id]) defaultBrand = id;
}

export function getBrand(id?: string): BrandConfig {
  return BRANDS[id ?? defaultBrand] ?? BRANDS.acme;
}
