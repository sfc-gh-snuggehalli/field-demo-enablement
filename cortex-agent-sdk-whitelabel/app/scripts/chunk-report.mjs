// Prints JS chunk sizes (raw + gzip) after `vite build` and flags the initial chunk budget
// (300 KB raw / 90 KB gzip). The initial chunk is the one referenced by dist/index.html.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { gzipSync } from "node:zlib";

const dir = "dist/assets";
const html = readFileSync("dist/index.html", "utf8");
const initial = new Set([...html.matchAll(/assets\/([^"']+\.js)/g)].map((m) => m[1]));
const rows = readdirSync(dir)
  .filter((f) => f.endsWith(".js"))
  .map((f) => {
    const buf = readFileSync(join(dir, f));
    return { file: f, raw: statSync(join(dir, f)).size, gzip: gzipSync(buf).length, initial: initial.has(f) };
  })
  .sort((a, b) => Number(b.initial) - Number(a.initial) || b.raw - a.raw);
const kb = (n) => `${(n / 1024).toFixed(1)} KB`;
console.log("\nJS chunks:");
for (const r of rows) console.log(`${r.initial ? "* initial" : "  lazy   "}  ${r.file.padEnd(36)} ${kb(r.raw).padStart(10)}  gzip ${kb(r.gzip).padStart(9)}`);
const init = rows.filter((r) => r.initial);
const raw = init.reduce((s, r) => s + r.raw, 0);
const gz = init.reduce((s, r) => s + r.gzip, 0);
const ok = raw < 300 * 1024 && gz < 90 * 1024;
console.log(`\nInitial JS: ${kb(raw)} raw / ${kb(gz)} gzip — budget 300 KB / 90 KB: ${ok ? "PASS" : "FAIL"}`);
if (!ok) process.exitCode = 1;
