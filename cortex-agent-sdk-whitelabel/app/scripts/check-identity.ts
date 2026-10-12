// npm run check:identity — exercises resolveUser() + owner scoping through dispatch()
// without Snowflake: 401s with REQUIRE_AUTH, ingress/SSO header identity, cross-user run
// isolation (other users get 404) and owner-scoped conversation history.
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

let failures = 0;
const check = (name: string, ok: boolean, info = "") => {
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${info ? `  (${info})` : ""}`);
  if (!ok) failures++;
};

Object.assign(process.env, {
  REQUIRE_AUTH: "true",
  DEV_USER: "",
  TRUST_PROXY_HEADER: "true",
  TRUSTED_USER_HEADER: "X-Forwarded-User",
  TRUST_SF_CONTEXT_HEADER: "true", // simulate Snowflake ingress locally
  HISTORY_STORE: "local",
  HISTORY_DIR: mkdtempSync(join(tmpdir(), "acme-hist-")),
});
const { dispatch } = await import("../server/handlers");
const { createRun, emit, finish } = await import("../server/runs");

const req = (path: string, headers: Record<string, string> = {}, init: RequestInit = {}) => dispatch(new Request(`http://local${path}`, { ...init, headers: { ...headers, ...(init.headers as any) } }));

check("health is public", (await req("/api/health")).status === 200);
check("config without user -> 401", (await req("/api/config")).status === 401);
check("conversations without user -> 401", (await req("/api/conversations")).status === 401);
check("chat without user -> 401", (await req("/api/chat", {}, { method: "POST", body: "{}" })).status === 401);

const sf = await req("/api/config", { "Sf-Context-Current-User": "ALICE" });
const sfBody: any = await sf.json();
check("Sf-Context-Current-User resolves", sf.status === 200 && sfBody.user.name === "ALICE" && sfBody.user.source === "snowflake", JSON.stringify(sfBody.user));
const sso: any = await (await req("/api/config", { "X-Forwarded-User": "bob@acme.example" })).json();
check("trusted SSO header resolves", sso.user?.name === "bob@acme.example" && sso.user.source === "sso", JSON.stringify(sso.user));
check("invalid header value rejected", (await req("/api/config", { "X-Forwarded-User": "bob; drop table" })).status === 401);

// Runs are owner-scoped.
const run = createRun("ALICE", "conv1");
emit(run, "response.text.delta", { text: "hi" });
finish(run, "completed");
check("owner can replay run", (await req(`/api/runs/${run.id}/events?after=0`, { "Sf-Context-Current-User": "ALICE" })).status === 200);
check("other user gets 404 on run", (await req(`/api/runs/${run.id}/events?after=0`, { "Sf-Context-Current-User": "MALLORY" })).status === 404);
check("other user cannot cancel run", (await req(`/api/runs/${run.id}/cancel`, { "Sf-Context-Current-User": "MALLORY" }, { method: "POST" })).status === 404);

// History is owner-scoped.
const now = new Date().toISOString();
const put = await req("/api/conversations/c1", { "Sf-Context-Current-User": "ALICE", "Content-Type": "application/json" }, { method: "PUT", body: JSON.stringify({ id: "c1", title: "Alice chat", brand: "acme", ui: [], wire: {}, created: now, updated: now }) });
check("owner can save conversation", put.status === 200);
const mine: any[] = await (await req("/api/conversations", { "Sf-Context-Current-User": "ALICE" })).json();
const theirs: any[] = await (await req("/api/conversations", { "Sf-Context-Current-User": "MALLORY" })).json();
check("owner lists own conversation", mine.some((c) => c.id === "c1"));
check("other user sees no conversations", theirs.length === 0);
check("other user gets 404 on conversation", (await req("/api/conversations/c1", { "Sf-Context-Current-User": "MALLORY" })).status === 404);

console.log(failures ? `\n${failures} check(s) failed` : "\nAll identity checks passed");
process.exit(failures ? 1 : 0);
