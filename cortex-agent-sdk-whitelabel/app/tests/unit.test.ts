// Unit tests (no Snowflake): npm test
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { after, describe, it } from "node:test";
import { buildBody, mergeTools, specHash, type AgentSpec } from "../server/agent";
import { safeName, putFile, fileResponse } from "../server/files";
import { backoffMs, fetchRetry } from "../server/http";
import { requestId } from "../server/log";
import { bindMcp, hasMcpCredential, setMcpCredential } from "../server/mcp";
import { rateLimit, resetRateLimits } from "../server/ratelimit";
import { createRun, emit, finish, sseResponse } from "../server/runs";
import { csp, frameOrigins } from "../server/security";
import type { ChatRequest } from "../shared/protocol";

const tool = (name: string, type = "generic") => ({ tool_spec: { type, name, description: name } });

const SPEC: AgentSpec = {
  models: { orchestration: "claude-sonnet-4-5" },
  instructions: { orchestration: "You are ACME Assist. Be concise.", response: "Use tables.", sample_questions: [{ question: "x" }] } as any,
  tools: [tool("acme_analyst", "cortex_analyst_text_to_sql"), tool("acme_search", "cortex_search")],
  tool_resources: { acme_analyst: { semantic_view: "ACME_ASSIST_DEMO.DATA.ACME_SEMANTIC_VIEW" }, acme_search: { name: "X" } },
  orchestration: { budget: { seconds: 300, tokens: 400000 } },
};
const REQ: ChatRequest = { conversationId: "c1", mode: "assist", content: [{ type: "text", text: "hi" }], user: { name: "Alice Ng", email: "alice@acme.test" }, threadId: "t1" };

describe("agent spec merge (C)", () => {
  it("keeps named-agent tools first, appends client tools, no duplicate names", () => {
    const body: any = buildBody(SPEC, REQ, [tool("mcp__weather__now"), tool("acme_analyst")], "ALICE", "2026-10-12");
    const names = body.tools.map((t: any) => t.tool_spec.name);
    assert.deepEqual(names.slice(0, 2), ["acme_analyst", "acme_search"]);
    assert.equal(new Set(names).size, names.length, "duplicate tool names");
    assert.ok(names.includes("browser_open_app"), "browser tools appended");
    assert.equal(names.at(-1), "mcp__weather__now");
    // The agent's own tool spec wins over a same-named request tool.
    assert.equal(body.tools[0].tool_spec.type, "cortex_analyst_text_to_sql");
  });
  it("appends user context, data date and skills to the agent's instructions instead of replacing them", () => {
    const body: any = buildBody(SPEC, { ...REQ, skills: [{ id: "s", name: "Recap", description: "", instructions: "Do a recap." }] }, [], "ALICE", "2026-10-12");
    const o: string = body.instructions.orchestration;
    assert.ok(o.startsWith("You are ACME Assist. Be concise."));
    assert.match(o, /Data current as of 2026-10-12/);
    assert.match(o, /Signed-in Snowflake user: ALICE/);
    assert.match(o, /User name: Alice Ng/);
    assert.match(o, /### Recap\nDo a recap\./);
    assert.equal(body.instructions.response, "Use tables.");
    assert.equal(body.instructions.sample_questions, undefined);
    assert.equal((SPEC.instructions as any).sample_questions.length, 1, "spec not mutated");
  });
  it("honors the named agent's models, tool_resources and orchestration budget", () => {
    const body: any = buildBody(SPEC, REQ, [], null, "2026-10-12");
    assert.equal(body.models.orchestration, "claude-sonnet-4-5");
    assert.deepEqual(body.tool_resources, SPEC.tool_resources);
    assert.deepEqual(body.orchestration, SPEC.orchestration);
    assert.equal(body.thread_id, "t1");
    assert.equal(body.parent_message_id, "0");
    assert.equal(buildBody(SPEC, { ...REQ, model: "claude-opus-4-5" }, [], null).models.orchestration, "claude-opus-4-5");
  });
  it("omits browser tools when the request opts out", () => {
    const body: any = buildBody(SPEC, { ...REQ, browserTools: false }, [], null);
    assert.ok(!body.tools.some((t: any) => t.tool_spec.name.startsWith("browser_")));
  });
  it("mergeTools reports dropped duplicates; specHash changes with the spec", () => {
    assert.deepEqual(mergeTools([tool("a")], [tool("a"), tool("b")]).dropped, ["a"]);
    assert.notEqual(specHash(SPEC), specHash({ ...SPEC, models: { orchestration: "other" } }));
  });
});

describe("run registry sequence mapping (B)", () => {
  it("pins upstream-mapped seqs, never goes backwards, replays after a cursor", async () => {
    const run = createRun("alice", "c1");
    emit(run, "acme.run", {});
    run.seqBase = run.nextSeq - 1; // 1
    emit(run, "response.text.delta", { text: "a" }, run.seqBase + 1);
    emit(run, "response.text.delta", { text: "b" }, run.seqBase + 2);
    emit(run, "late", {}, 1); // stale pin -> next free
    assert.deepEqual(run.events.map((e) => e.seq), [1, 2, 3, 4]);
    finish(run, "completed");
    const text = await sseResponse(run, 2).text();
    assert.ok(!text.includes("id: 2\n") && text.includes("id: 3\n") && text.includes("event: acme.done"));
  });
});

describe("rate limit (D)", () => {
  it("token bucket per user with refill", () => {
    process.env.RATE_LIMIT_PER_MIN = "60";
    process.env.RATE_LIMIT_BURST = "2";
    resetRateLimits();
    const t = 1_000_000;
    assert.equal(rateLimit("u", t).ok, true);
    assert.equal(rateLimit("u", t).ok, true);
    const r = rateLimit("u", t);
    assert.equal(r.ok, false);
    assert.equal(rateLimit("other", t).ok, true, "per user");
    assert.equal(rateLimit("u", t + 1000).ok, true, "refills at 1/s");
    delete process.env.RATE_LIMIT_PER_MIN;
    delete process.env.RATE_LIMIT_BURST;
  });
});

describe("upstream retry (D)", () => {
  const hits: number[] = [];
  const srv = createServer((req, res) => {
    hits.push(Date.now());
    if (hits.length < 3) {
      res.writeHead(hits.length === 1 ? 429 : 503, { "Retry-After": "0" });
      return res.end("busy");
    }
    res.end("ok");
  });
  after(() => srv.close());
  it("retries 429/5xx with backoff, then succeeds", async () => {
    await new Promise<void>((r) => srv.listen(0, r));
    const port = (srv.address() as any).port;
    const res = await fetchRetry(`http://127.0.0.1:${port}/`, { method: "POST" }, { retries: 3, baseDelayMs: 5 });
    assert.equal(res.status, 200);
    assert.equal(hits.length, 3);
  });
  it("backoff grows and honors Retry-After", () => {
    assert.ok(backoffMs(3, 100) >= 800);
    assert.equal(backoffMs(0, 100, "2"), 2000);
  });
});

describe("logging + headers (D)", () => {
  it("request ids: reuse well-formed, mint otherwise", () => {
    assert.equal(requestId("abcdef12-req"), "abcdef12-req");
    assert.match(requestId("<script>"), /^[0-9a-f-]{36}$/);
  });
  it("CSP: self only, frame-src adds only https registered origins", () => {
    const env = { FRAME_ORIGINS: "https://storeops.acme.example http://evil.test javascript:alert(1)" } as any;
    assert.deepEqual(frameOrigins(env), ["https://storeops.acme.example"]);
    const c = csp({}, env);
    assert.match(c, /default-src 'self'/);
    assert.match(c, /script-src 'self';/);
    assert.match(c, /frame-src 'self' https:\/\/storeops\.acme\.example;/);
    assert.ok(!/unsafe-eval|https:\/\/(?!storeops)/.test(c));
  });
});

describe("MCP credentials (E)", () => {
  it("stored per owner, never in the binding output, rejected when malformed", async () => {
    assert.equal(setMcpCredential("alice", "mcp-1", "Authorization: Bearer s3cret"), true);
    assert.equal(setMcpCredential("alice", "mcp-1\n", "x"), false);
    assert.equal(setMcpCredential("alice", "mcp-2", "X: a\r\nInjected: b"), false);
    assert.equal(hasMcpCredential("alice", "mcp-1"), true);
    assert.equal(hasMcpCredential("bob", "mcp-1"), false);
    const b = await bindMcp([{ id: "mcp-1", name: "x", url: "http://127.0.0.1:9/mcp", enabled: true }], "alice");
    assert.ok(!JSON.stringify(b).includes("s3cret"));
    setMcpCredential("alice", "mcp-1", "");
    assert.equal(hasMcpCredential("alice", "mcp-1"), false);
  });
});

describe("power files", () => {
  it("safe names, owner scoped", async () => {
    process.env.FILES_DIR = `/tmp/acme-files-test-${process.pid}`;
    assert.equal(safeName("/workspace/output/../../etc/passwd"), "passwd");
    assert.equal(safeName("/workspace/output/failed orders.csv"), "failed_orders.csv");
    const f = putFile("alice", "conv1", "/workspace/output/a.csv", "x,y\n1,2\n")!;
    assert.equal(f.url, "/api/files/conv1/a.csv");
    assert.equal(await fileResponse("alice", "conv1", "a.csv")!.text(), "x,y\n1,2\n");
    assert.equal(fileResponse("bob", "conv1", "a.csv"), undefined);
    assert.equal(fileResponse("alice", "conv1", "../a.csv"), undefined);
  });
});

describe("power deliverables (chunked base64)", async () => {
  const { observe, followUp, looksValid, resetDeliverables } = await import("../server/deliverables");
  it("notes a savefig target, fetches it in chunks, halves on 'Output too large', validates PNG", () => {
    resetDeliverables();
    process.env.FILES_DIR = `/tmp/acme-files-test-${process.pid}`;
    const run = createRun("alice", "convP");
    const png = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(40_000, 7)]);
    const b64 = png.toString("base64");
    observe(run, "response.tool_use", { name: "write", tool_use_id: "w1", input: { path: "/workspace/output/chart.py", content: "plt.savefig('/workspace/output/chart.png', dpi=80)" } });
    observe(run, "response.tool_result", { name: "write", tool_use_id: "w1", status: "success", content: [] });
    let n = 0;
    for (let ask = followUp(run); ask; ask = followUp(run)) {
      const m = ask.match(/cut -c(\d+)-(\d+)/)!;
      const [a, b] = [Number(m[1]), Number(m[2])];
      observe(run, "response.tool_use", { name: "bash", tool_use_id: `b${n}`, input: { command: ask.slice(ask.indexOf("base64 -w0")) } });
      const out = b - a + 1 > 20_000 ? "Output too large to display inline (1 lines, 30 KB). Full output saved to: /x" : `Bash command \`base64 -w0 x | cut -c${a}-${b}\` with description \`Encode\` returned output: ${b64.slice(a - 1, b)}`;
      observe(run, "response.tool_result", { name: "bash", tool_use_id: `b${n++}`, status: "success", content: [{ type: "text", text: out }] });
      assert.ok(n < 20, "terminates");
    }
    assert.equal(run.pendingFiles?.[0]?.name, "chart.png");
    assert.ok(n >= 4, `chunked (${n} calls)`);
    assert.equal(looksValid("x.png", Buffer.from("garbage")), false);
  });
  it("write-tool deliverables are offered directly, .py scripts are not", () => {
    resetDeliverables();
    const run = createRun("alice", "convQ");
    observe(run, "response.tool_use", { name: "write", tool_use_id: "w2", input: { file_path: "/workspace/output/a.csv", content: "carrier,age\nUPS,3\n" } });
    observe(run, "response.tool_result", { name: "write", tool_use_id: "w2", status: "success", content: [] });
    assert.deepEqual(run.pendingFiles?.map((f) => f.name), ["a.csv"]);
    assert.equal(followUp(run), undefined);
  });
});
