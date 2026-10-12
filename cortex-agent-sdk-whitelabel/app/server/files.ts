// Power Mode deliverables. When the coding agent's `write` tool succeeds, the proxy keeps a copy
// of the file (owner + conversation scoped, under FILES_DIR, default .data/files) and emits an
// acme.studio.files event pointing at GET /api/files/<conversation>/<name>, the same endpoint
// Studio uses. Names are reduced to a safe basename; files over 1 MB are not kept.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { ownerHash } from "./identity";

const MAX_BYTES = 1024 * 1024;
const CONV = /^[A-Za-z0-9_-]{1,64}$/;

export const safeName = (p: string) =>
  String(p)
    .split(/[\\/]/)
    .pop()!
    .replace(/[^A-Za-z0-9._-]/g, "_")
    .replace(/^\.+/, "")
    .slice(0, 120);

const dir = (owner: string, conv: string) => resolve(process.env.FILES_DIR || ".data/files", ownerHash(owner), conv);

export const contentType = (name: string) =>
  /\.png$/i.test(name) ? "image/png" : /\.svg$/i.test(name) ? "image/svg+xml" : /\.csv$/i.test(name) ? "text/csv; charset=utf-8" : /\.json$/i.test(name) ? "application/json" : /\.xlsx$/i.test(name) ? "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" : /\.pdf$/i.test(name) ? "application/pdf" : "text/plain; charset=utf-8";

export function putFile(owner: string, conv: string, path: string, content: string | Buffer): { name: string; url: string; size: number } | undefined {
  const name = safeName(path);
  if (!name || !CONV.test(conv) || Buffer.byteLength(content) > MAX_BYTES) return undefined;
  try {
    mkdirSync(dir(owner, conv), { recursive: true });
    writeFileSync(resolve(dir(owner, conv), name), content);
  } catch {
    return undefined; // read-only filesystem: the inline copy in the UI still works
  }
  return { name, url: `/api/files/${conv}/${encodeURIComponent(name)}`, size: Buffer.byteLength(content) };
}

export function fileResponse(owner: string, conv: string, file: string): Response | undefined {
  const name = safeName(file);
  if (!name || name !== file || !CONV.test(conv)) return undefined;
  const p = resolve(dir(owner, conv), name);
  if (!existsSync(p)) return undefined;
  return new Response(readFileSync(p), { headers: { "Content-Type": contentType(name), "Content-Disposition": `attachment; filename="${name}"`, "X-Content-Type-Options": "nosniff", "Cache-Control": "no-store", "Content-Security-Policy": "sandbox; default-src 'none'" } });
}
