// Security headers for HTML responses. CSP allows only this origin (no CDNs, no third-party
// scripts, styles, fonts or connections); frame-src is 'self' plus the registered app origins
// (src/config/app.config.ts apps are same-origin paths today; extra origins come from
// FRAME_ORIGINS, space-separated https origins). Mirrored in app-runtime/next.config.mjs.
export function frameOrigins(env = process.env): string[] {
  return (env.FRAME_ORIGINS ?? "")
    .split(/\s+/)
    .filter((o) => /^https:\/\/[A-Za-z0-9.-]+(:\d+)?$/.test(o));
}

export function csp(opts: { dev?: boolean; inlineScripts?: boolean } = {}, env = process.env): string {
  const script = ["'self'", ...(opts.inlineScripts ? ["'unsafe-inline'"] : []), ...(opts.dev ? ["'unsafe-eval'"] : [])];
  return [
    "default-src 'self'",
    `script-src ${script.join(" ")}`,
    // React style attributes and vega-embed inject inline styles.
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob:",
    "font-src 'self' data:",
    `connect-src 'self'${opts.dev ? " ws:" : ""}`,
    `frame-src ${["'self'", ...frameOrigins(env)].join(" ")}`,
    "frame-ancestors 'self'",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
  ].join("; ");
}

export function securityHeaders(opts: { dev?: boolean; inlineScripts?: boolean } = {}): Record<string, string> {
  return {
    "Content-Security-Policy": csp(opts),
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "X-Frame-Options": "SAMEORIGIN",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
    "Cross-Origin-Opener-Policy": "same-origin",
  };
}
