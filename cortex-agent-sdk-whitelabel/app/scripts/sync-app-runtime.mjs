// npm run sync: copies the shared code into app-runtime/ (never edit app-runtime/acme/):
//   src/, server/, shared/ -> app-runtime/acme/   public/ -> app-runtime/public/
import { cpSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const dest = resolve(root, "app-runtime/acme");
rmSync(dest, { recursive: true, force: true });
mkdirSync(dest, { recursive: true });
// main.tsx and express/env are Vite/Express entry points, not shared code.
const skip = new Set(["src/main.tsx", "server/express.ts", "server/env.ts"].map((p) => resolve(root, p)));
for (const dir of ["src", "server", "shared"]) {
  cpSync(resolve(root, dir), resolve(dest, dir), { recursive: true, filter: (p) => !skip.has(p) });
}
const pub = resolve(root, "app-runtime/public");
mkdirSync(pub, { recursive: true });
if (existsSync(resolve(root, "public"))) cpSync(resolve(root, "public"), pub, { recursive: true });
console.log("synced src/ server/ shared/ -> app-runtime/acme/, public/ -> app-runtime/public/");
