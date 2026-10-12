// Thin Express adapter: /api/* -> dispatch(); in production also serves dist/ (SPA fallback
// covers the chat at / and the Store Ops simulator at /apps/storeops/*). Adds security headers
// and drains on SIGTERM/SIGINT: stop accepting, end open SSE streams (clients reattach; background
// runs continue upstream and resume from the persisted run record), then exit.
import express from "express";
import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { Readable } from "node:stream";
import { loadEnv } from "./env";

loadEnv();
const { dispatch, setDraining } = await import("./handlers");
const { config } = await import("./config");
const { log } = await import("./log");
const { closeAllStreams, liveRuns } = await import("./runs");
const { securityHeaders } = await import("./security");
const { dataDate } = await import("./datadate");

const app = express();
app.disable("x-powered-by");
const pageHeaders = securityHeaders({ dev: process.env.NODE_ENV !== "production" });
app.use((_req, res, next) => {
  for (const [k, v] of Object.entries(pageHeaders)) res.setHeader(k, v);
  next();
});

app.use("/api", async (req, res) => {
  const ctrl = new AbortController();
  res.on("close", () => ctrl.abort());
  const headers = new Headers();
  for (const [k, v] of Object.entries(req.headers)) if (typeof v === "string") headers.set(k, v);
  const hasBody = !["GET", "HEAD"].includes(req.method);
  const request = new Request(`http://${req.headers.host ?? "localhost"}${req.originalUrl}`, {
    method: req.method,
    headers,
    body: hasBody ? (Readable.toWeb(req) as ReadableStream) : undefined,
    // @ts-expect-error Node fetch requires duplex for streamed bodies
    duplex: hasBody ? "half" : undefined,
    signal: ctrl.signal,
  });
  const response = await dispatch(request);
  res.status(response.status);
  response.headers.forEach((v, k) => res.setHeader(k, v));
  if (!response.body) return res.end();
  res.flushHeaders();
  const reader = response.body.getReader();
  res.on("close", () => reader.cancel().catch(() => undefined));
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      res.write(value);
    }
  } catch {
    /* client went away; the run keeps going in the registry */
  }
  res.end();
});

const dist = resolve(process.cwd(), "dist");
if (existsSync(dist)) {
  app.use(express.static(dist, { index: false, maxAge: "1h" }));
  app.get(/^(?!\/api\/).*/, (_req, res) => res.sendFile(resolve(dist, "index.html")));
}

const port = config().port;
const server = app.listen(port, () => {
  log("info", "listening", { port, url: `http://localhost:${port}` });
  void dataDate();
});

let stopping = false;
function shutdown(signal: string) {
  if (stopping) return;
  stopping = true;
  setDraining(true);
  const drainMs = Number(process.env.SHUTDOWN_DRAIN_MS || 10_000);
  log("info", "shutdown: draining", { signal, liveRuns: liveRuns().length, drainMs });
  server.close(() => {
    log("info", "shutdown: closed");
    process.exit(0);
  });
  // Give in-flight runs a moment to finish, then end the remaining SSE streams.
  const started = Date.now();
  const tick = setInterval(() => {
    if (liveRuns().length === 0 || Date.now() - started > drainMs) {
      clearInterval(tick);
      const closed = closeAllStreams();
      log("info", "shutdown: streams closed", { closed });
      server.closeAllConnections?.();
      setTimeout(() => process.exit(0), 500).unref();
    }
  }, 200);
}
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
