// Scaffolded from the bundled snowflake-apps Next.js template.
// `output: "standalone"` is required for App Runtime deployment.
// `turbopack.root` and `outputFileTracingRoot` are pinned to this directory because a
// parent package-lock.json exists (../package-lock.json); without the pin Next.js re-roots
// the project (404 on /, wrong chunk paths). Do NOT remove them.
// `compress: false` so SSE agent streams are not buffered by gzip.
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Local dev only: reuse ../.env (the Express build's config) if present. In App Runtime the
// variables come from app.yml environment_variables and auth from /snowflake/session/token.
const parentEnv = path.resolve(__dirname, "../.env");
if (existsSync(parentEnv) && !existsSync("/snowflake/session/token")) {
  for (const line of readFileSync(parentEnv, "utf8").split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m && !line.trim().startsWith("#") && process.env[m[1]] === undefined) process.env[m[1]] = m[2];
  }
  process.env.NEXT_PUBLIC_BRAND ??= process.env.VITE_BRAND;
}

// Security headers, mirroring server/security.ts. Next.js bootstraps with inline scripts, so
// script-src needs 'unsafe-inline' here (no third-party origins); dev adds 'unsafe-eval' for HMR.
const dev = process.env.NODE_ENV !== "production";
const frameOrigins = (process.env.FRAME_ORIGINS ?? "").split(/\s+/).filter((o) => /^https:\/\/[A-Za-z0-9.-]+(:\d+)?$/.test(o));
const csp = [
  "default-src 'self'",
  `script-src 'self' 'unsafe-inline'${dev ? " 'unsafe-eval'" : ""}`,
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob:",
  "font-src 'self' data:",
  `connect-src 'self'${dev ? " ws:" : ""}`,
  `frame-src ${["'self'", ...frameOrigins].join(" ")}`,
  "frame-ancestors 'self'",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
].join("; ");
const securityHeaders = [
  { key: "Content-Security-Policy", value: csp },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "no-referrer" },
  { key: "X-Frame-Options", value: "SAMEORIGIN" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
  { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
];

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "standalone",
  outputFileTracingRoot: __dirname,
  turbopack: { root: __dirname },
  compress: false,
  typescript: { ignoreBuildErrors: true },
  images: { unoptimized: true },
  poweredByHeader: false,
  async headers() {
    return [{ source: "/:path*", headers: securityHeaders }];
  },
  env: { NEXT_PUBLIC_BRAND: process.env.NEXT_PUBLIC_BRAND ?? "acme" },
};

export default nextConfig;
