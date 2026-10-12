# ACME Assist

A branded chat app for **ACME Retail** store, regional and fulfillment teams, built on the
**Snowflake Cortex Agent SDK** (`@snowflake/cortex-agent-sdk@0.0.1`, pinned). It fronts the
`ACME_ASSIST_AGENT` Cortex Agent, drives the **ACME Store Ops** simulator in a built-in browser
sidebar through client-side tools, and re-brands from configuration alone (ACME and Northwind
themes ship).

```
React + Vite UI (src/)  ──/api──▶  framework-neutral handlers (server/handlers.ts)
   │  browser tools run here           │  Express adapter (server/express.ts)
   │  (src/agent/tools/browser.ts)     │  or Next.js route (app-runtime/app/api/[...path])
   ▼                                   ▼
ACME Store Ops (/apps/storeops)     Cortex Agent API via the SDK (PAT locally,
 postMessage bridge                  /snowflake/session/token in SPCS / App Runtime)
```

No Snowflake credentials ever reach the browser bundle: the proxy holds them and relays SSE.

## Quick start (local)

Requirements: Node >= 22.22, the Snowflake objects from `../lab/setup.sql` (+ `seed_data.sql`,
`history.sql`), and a PAT for a user with `ACME_DEMO_ROLE`.

```bash
cd app
npm install
cp .env.example .env        # set SNOWFLAKE_ACCOUNT and SNOWFLAKE_PAT_FILE (a path, not the secret)
npm run dev                 # Vite on http://localhost:5173 + proxy on :8080
```

Production-style single process: `npm run build && npm start` → http://localhost:8080.

## npm scripts

| Script | What it does |
|---|---|
| `dev` | Vite (5173) + Express proxy (8080, `tsx watch`) together |
| `build` | Vite build, then `scripts/chunk-report.mjs` (fails if the initial chunk is over budget) |
| `start` | Express serving `dist/` and `/api` on `PORT` (8080) |
| `typecheck` | client, server, `coco-runner/`, `app-runtime/` |
| `gen:seed` | `scripts/gen-seed.mjs`: deterministic seed JSON for the simulator **and** `../lab/seed_data.sql` |
| `gen:skills` | Generates `AGENTS.md`, `.snowflake/cortex/skills/acme-project/SKILL.md`, `coco-runner/skills.json` from `shared/skills.ts` |
| `spike` | Step-0 client-side tool spike (see findings below) |
| `test:scenarios` | The three section-5b scenarios against the real agent, with a seed-data sidebar model |
| `check:identity` | 401s, ingress/SSO identity, cross-user run and history isolation (no Snowflake needed) |
| `test` | Unit tests (`node:test`, no Snowflake): spec merge, seq mapping, rate limit, retry, CSP, MCP credentials, files, chunked deliverables |
| `test:resume` | Live: restart-resume, Stop (live and after restart), SIGTERM drain, 429, describe 503, headers, log hygiene |
| `test:mcp` | Live: local MCP server + proxy + agent end to end; auth header stored server-side, never echoed |
| `test:history` | Live: `HISTORY_STORE=snowflake`, alice vs bob isolation, delete |
| `test:power` | Live: Power Mode CSV + chart scenario, approvals driven programmatically, downloads via `/api/files` |
| `test:studio` | Live: local `coco-runner` + `cortex` CLI, XLSX of orders by status via `/api/files` |
| `test:next` | Live: Next.js `next dev`, stream + reattach, resume after a dev-server restart |
| `sync` | Copies `src/ server/ shared/` → `app-runtime/acme/`, `public/` → `app-runtime/public/` |
| `deploy:spcs` | `snowflake/spcs/deploy.sh` (manual; see SPCS) |
| `deploy:sar` | `sync`, then `snow app deploy --verbose` in `app-runtime/` (manual; confirm the connection first) |

## Step 0 spike: client-side tools (findings)

`npm run spike` runs both paths against the live account. Results with SDK 0.0.1:

1. **Named-agent endpoint does not accept per-request tools.** `client.agent.runData(target, { tools: [...] })`
   silently ignores extra tools; with `tool_choice` it fails with
   `Tool names get_store_weather are not allowed`. `DataAgentRunRequest` (the typed body) has no
   `tools`, `models` or `instructions` fields either.
2. **The lite endpoint does.** `client.agent.stream({ models, instructions, tools, tool_resources, messages })`
   with a `generic` tool and no `tool_resources` entry emits
   `response.tool_use` with `client_side_execute: true`.
3. **Round trip in a thread.** Create a thread (`client.threads.create`), send `thread_id` +
   `parent_message_id: "0"` on turn 1, then send **only** a user message containing the
   `tool_result` item with `parent_message_id` = the assistant `message_id` from the
   `metadata` event. The agent answers from the tool result. No need to resend history.

Design consequence: the proxy **hydrates the named agent's spec** once
(`client.agent.describe(...).responseBody.agent_spec`, cached per agent with `AGENT_SPEC_TTL_MS`,
default 5 minutes; a changed `created_on` or spec hash is logged as an invalidation; describe has
no ETag in 0.0.1) and runs it through the lite
endpoint with the browser tools, MCP tools, skills, user context and the selected model merged
in (`server/agent.ts`). The named agent stays the source of truth for instructions, tools and
`tool_resources`; nothing is duplicated in code. Merge rules (`buildBody`, unit-tested): the
agent's models, `tool_resources` and `orchestration` budget are passed through; the agent's tools
come first and a request tool with a taken name is dropped; data date, browser guidance, skills and
user context are **appended** to the agent's orchestration instructions. If describe fails,
`/api/chat` returns **503** with the reason (no stale spec is served).

### Other SDK / API observations (0.0.1)

- Events are flat: `ev.event` plus payload fields on the same object (`ev.text`, `ev.tool_use_id`,
  `ev.client_side_execute`, `ev.permission`, `ev.result_set`, `ev.chart_spec`). Events seen:
  `response.status`, `response.thinking.delta`, `response.thinking`, `response.text.delta`,
  `response.text`, `response.tool_use`, `response.tool_result.status`, `response.tool_result`,
  `response.table`, `response.chart`, `response.suggested_queries`, `metadata`, `response`, `error`.
- `metadata` carries `{ role, message_id }`; **no `run_id` is emitted on foreground streams**.
  **Background runs do work on the lite endpoint with client-side tools** (`scripts/bg-probe.ts`,
  live): `client.agent.run({ ...body, stream: false, background: true })` returns an `AsyncRun`
  (`runId` like `<thread_id>-<user_message_id>`, `initialStatus: "in_progress"`, ~0.9 s);
  `client.runs.stream(runId, { startingAfter })` replays and tails events that carry
  `sequence_number` (1-based, contiguous), including `response.tool_use` with
  `client_side_execute: true`; the tool_result round trip in the thread works the same way;
  `client.runs.cancel(runId)` returns 200 with `metadata.assistant_message_id`. Background mode
  requires a `thread_id` (`400 thread_id must be provided when using background mode`).
- int64 ids (`message_id`, `thread_id`) are parsed as strings by the SDK; sending them back as strings works.
- Power Mode (`code_toolset_all`): permission prompts arrive as `response.tool_use` with
  `permission.options` = `["Allow this command", "Allow all <tool> for this session", "Deny"]`;
  the reply is a `permission_decision` item with the chosen option string. The UI shows only the
  per-action options (never "Allow all"). The sandbox's `snowflake_sql_execute` comes back as a
  **client-side** tool (`client_side_execute: true`); the proxy executes it read-only through the SQL API.
- Sandbox files are not surfaced as asset events. Power Mode asks the agent to write deliverables
  with the `write` tool; the UI offers each successful `write` as a download chip (CSV, SVG chart).
- `@snowflake/cortex-agent-sdk/code` `query()` options used by Studio: `mode: "cli"`, `cwd`, `resume`,
  `canUseTool`, `appendSystemPrompt`, `allowedTools`, `connection`, `abortController`;
  messages: `system` (with `session_id`), `assistant` (`text` / `thinking` / `tool_use` blocks),
  `user` (`tool_result` blocks), `result`.

## Features

- **Branding** (`src/brand/brand.config.ts`, assets in `public/brand/<id>/`): name, logos,
  favicon, light + dark palettes, font, animated mark geometry. Components only use CSS variables.
- **Spark-and-settle thinking logo** (`src/brand/Logo.tsx`, keyframes in `src/styles.css`):
  `idle → submitting → thinking → streaming → done`; reduced-motion falls back to a pulse.
- **Chat**: history sidebar, centered hero composer that docks, streamed Markdown (lazy),
  Stop / Regenerate / Copy, compact live line (`Querying acme_analyst · 6s · 3 steps`),
  Thinking + `Activity · N steps` accordions (closed by default, open when "Show thinking & tool
  details" is on), approval cards always visible.
- **Composer**: model selector (`src/config/app.config.ts` → `models.orchestration`), `+ Tools`
  modal for MCP servers and skills (plugin registry in `src/plugins/registry.ts`), Power Mode toggle
  (hidden unless `POWER_MODE_ENABLED=true`), Studio toggle (hidden unless `COCO_RUNNER_URL`).
- **Browser sidebar** (`src/browser/`): iframe drawer, URL bar, back/forward/refresh, bookmarks,
  agent cursor; links to registered apps in answers open there; Store Ops can post the selected
  record back as chat context.
- **Browser tools** (`src/agent/tools/browser.ts`, one registry for the request and the UI):
  `browser_open_app`, `browser_navigate` (allowlisted), `browser_back/forward/refresh`,
  `browser_get_page`, `browser_get_text`, `browser_click`, `browser_fill`, `browser_select`,
  `browser_get_table`, `browser_highlight`, `browser_screenshot` (returns "not supported").
  Write actions on `data-agent-confirm="true"` elements need an approval card; Deny returns a
  "denied by user" `tool_result`.
- **Charts & tables**: `response.chart` Vega-Lite specs via `vega-embed` (lazy), full width
  (`fit-x` + `ResizeObserver`), themed, external data URLs blocked, PNG/SVG download;
  `response.table` result sets and Markdown tables in a scroll container with sticky header,
  row count, right-aligned numbers and CSV download.
- **Resumable runs** (`server/runs.ts`, `server/runstore.ts`, `server/agent.ts`): every turn starts
  as an Agent API **background run** and is read through `client.runs.stream(runId, { startingAfter })`.
  Upstream `sequence_number` k becomes proxy seq `seqBase + k`, and the run record
  `{ runId, upstreamRunId, owner, conversationId, threadId, agent, seqBase, lastSeq, status }` is
  persisted (`RUN_STORE=local` → `.data/runs/`, `RUN_STORE=snowflake` → `ACME_ASSIST_DEMO.APP.AGENT_RUNS`).
  The in-memory buffer stays the fast path; `GET /api/runs/:id/events?after=N` for a run this process
  does not hold (restart, other instance) rebuilds it from the record and replays Snowflake's run
  stream after the client's cursor (owner-checked, 404 for others). Stop finalizes the run and calls
  `client.runs.cancel(upstreamRunId)` (also from the record after a restart). Dropped upstream
  streams reconnect with `startingAfter`. 15 s keepalives; the client reattaches after reload
  (4 retries, backoff) and re-asks pending browser tools or approvals. `AGENT_BACKGROUND_RUNS=false`
  restores the foreground stream (then resumable only within one process). Limitation: if the
  process dies during a proxy-executed **MCP** call, the resumed run ends with a retry hint (the MCP
  binding lived in the old process); read-only SQL hops are continued.
- **History**: `HISTORY_STORE=local` (JSON per owner under `.data/`) or `snowflake`
  (`ACME_ASSIST_DEMO.APP.CONVERSATIONS`, bind parameters, filtered by owner, role `ACME_HISTORY_ROLE`).
  The client keeps localStorage as a cache; newer `updated` wins; debounced saves.
- **Identity** (`server/identity.ts` `resolveUser`): `Sf-Context-Current-User` (SPCS / App Runtime),
  `TRUSTED_USER_HEADER` only with `TRUST_PROXY_HEADER=true`, else `DEV_USER`; `REQUIRE_AUTH=true`
  returns 401 (health stays public). Settings name/email are sent as context only.

### Production hardening

| Concern | Behavior | Config |
|---|---|---|
| Request ids + logs | `X-Request-Id` (reused if well-formed) on every API response; one JSON line per request / run event (`server/log.ts`); prompts, tokens, auth headers never logged | `LOG_LEVEL`, `LOG_PROMPTS=false` |
| Rate limit | Per-user token bucket on `/api/chat`, 429 + `Retry-After` | `RATE_LIMIT_PER_MIN=20`, `RATE_LIMIT_BURST=10` (0 disables) |
| Upstream timeouts / retries | SQL API: per-attempt timeout, exponential backoff + jitter on 429/5xx/network, honors `Retry-After` (`server/http.ts`); describe / threads / cancel: SDK `retryPolicy` + 15 s timeout | `SQL_TIMEOUT_MS`, `UPSTREAM_RETRIES=3` |
| Graceful shutdown | SIGTERM/SIGINT: health 503, stop accepting, wait for live runs up to the drain window, end SSE streams (clients reattach; background runs continue upstream), exit 0 | `SHUTDOWN_DRAIN_MS=10000` |
| Security headers | CSP `default-src 'self'`, no third-party origins, `frame-src 'self'` + registered app origins, `frame-ancestors 'self'`, `object-src 'none'`; nosniff, no-referrer, COOP. Vega uses the AST interpreter, so no `unsafe-eval` (Next.js adds `'unsafe-inline'` scripts for its bootstrap; dev adds `unsafe-eval`) | `FRAME_ORIGINS` (https origins) |
| Data date | MAX(order_date) read once at startup through the SQL API (cached), injected as "Data current as of <date>"; falls back to today | `DATA_DATE_TABLE` |
| Secrets | `npm run build` output scanned: no PAT / key / bearer patterns in `dist/` | |

### Lazy loading and bundle size

`src/AppRoot.tsx` picks chat or simulator by pathname; `react-router` is only in the simulator
chunk. Markdown, Vega, Settings, Tools and Store Ops are separate chunks. Latest `npm run build`:

| Chunk | Raw | Gzip |
|---|---|---|
| **initial** `index-*.js` + runtime | **259.6 KB** | **81.3 KB** |
| `vega-*.js` (lazy) | 814.2 KB | 275.4 KB |
| `StoreOpsApp-*.js` (lazy, includes seed JSON) | 278.4 KB | 42.6 KB |
| `Markdown-*.js` (lazy) | 152.3 KB | 45.1 KB |
| `ToolsModal`, `SettingsDialog`, `VegaChart` (lazy) | 2–5 KB each | 1–1.5 KB |

Budget 300 KB / 90 KB: pass.

## Re-branding

1. Add an entry to `BRANDS` in `src/brand/brand.config.ts` (palette, dark palette, mark paths,
   animation trail colors, names).
2. Put `mark.svg`, `logo.svg`, `logo-dark.svg` in `public/brand/<id>/`.
3. Set `VITE_BRAND=<id>` (Vite/Express) or `NEXT_PUBLIC_BRAND=<id>` (App Runtime). No code changes.

## Adding MCP servers and skills

- **MCP**: `+ Tools → MCP servers` (name, Streamable-HTTP URL, optional auth header such as
  `Authorization: Bearer …`). The proxy lists the server's tools, exposes them to the agent as
  `mcp__<server>__<tool>` client-side tools, and executes the calls itself, so auth headers never
  reach the model. "Test" lists the tools. The auth header is sent **once** (`PUT /api/mcp/credentials/:id`), kept
  by the proxy in memory per user + connection (`MCP_CREDENTIALS_TTL_MS`, default 12 h) and never
  echoed back (`GET` returns only `{ hasAuth }`); localStorage keeps `{ id, name, url, enabled }`.
  Older builds' stored headers are migrated to the proxy and stripped on load. Re-enter the header
  after a server restart.
- **Skills**: `+ Tools → Skills` ships "Store Stockout Summary", "Fulfillment Exception Triage" and
  "Weekly Region Recap"; enabled skills' instructions are appended to the orchestration
  instructions. In Power Mode a skill with a `stagePath` is attached as a `code_toolset_all`
  stage skill (`skills: [{ name, source: { type: "STAGE", path } }]`, requires the
  `CORTEX_AGENT_ENABLE_COCO_STAGE_SKILL_MOUNTS` account parameter).
- New extension types: `registerExtensionType()` in `src/plugins/registry.ts`.

## Registering browser-sidebar apps

Add `{ id, name, url, icon }` to `APPS` in `src/config/app.config.ts`. Navigation is allowlisted
to same-origin registered app paths. Apps implement the `postMessage` bridge (`src/browser/bridge.ts`;
see `src/apps/storeops/agentBridge.ts`) and use stable `data-testid`s plus accessible labels.

## ACME Store Ops simulator

Routes: `/apps/storeops` (regions), `/apps/storeops/:regionId` (inventory + 30-day sales),
`/apps/storeops/:regionId/orders` (blotter; filters `order-filter-status|channel|date`),
`/apps/storeops/exceptions` (sort, assign with confirmation), `/apps/storeops/risk` (breaches,
margin by category/region). Data: `src/apps/storeops/data/*.json` from `npm run gen:seed`,
identical to `../lab/seed_data.sql`, so the agent and the UI agree (West 13.3% vs 6% threshold
and Northeast 6.7% vs 5% are the stockout breaches). Dates are relative: `npm run gen:seed` anchors "today"
on `SEED_ANCHOR_DATE` (default: today's UTC date when you run it), with a fixed PRNG seed so the
scenarios hold for any anchor (the generator asserts West + Northeast breach, West FAILED orders on
the anchor day, Address mismatch exceptions). Reload Snowflake with `snow sql -f ../lab/seed_data.sql`.
The proxy reads MAX(order_date) from `ORDERS` and tells the agent "Data current as of <date>".

## Snowflake objects and roles

`snowflake/setup.sql` and `snowflake/history.sql` point at the canonical `../lab/*.sql`
scripts (not copies). `ACME_DEMO_ROLE` needs `SNOWFLAKE.CORTEX_USER`, USAGE on `ACME_ASSIST_WH`,
the database and schema, SELECT on the tables and the semantic view, and USAGE on both agents.
History writes use `ACME_HISTORY_ROLE`.

## Power Mode (Preview)

Routes to `ACME_POWER_AGENT` (`code_toolset_all` + `acme_analyst`, `permission_policy: always_ask`).
Enable with `POWER_MODE_ENABLED=true`. Every sandbox action is an approval card (command or file
preview). Deliverables come back as downloads from `GET /api/files/<conversation>/<name>`
(owner-scoped, attachment, sandboxed CSP; `server/files.ts`, `server/deliverables.ts`): files the
agent writes with the `write` tool are kept from the tool arguments; files created otherwise
(matplotlib `savefig`, `to_csv`, redirection) are fetched by the proxy with follow-up turns on the
same thread that print them as base64 in chunks (`base64 -w0 <file> | cut -cA-B`; the sandbox
replaces large outputs with an "Output too large" preview, so the chunk halves), each chunk going
through the normal approval card, and checked against the file type's magic bytes. Constraints:
- The sandbox is scoped to the thread and suspends when idle; only files in a mounted workspace persist.
- Agents invoked with owner's rights drop code tools: call with caller's rights (`CALLERS_RIGHTS=true` in SPCS/App Runtime).
- The sandbox has no direct data access; data comes through the agent's SQL tools (the proxy runs
  `snowflake_sql_execute` read-only with `SQL_READONLY_ROLE`).
- Users need USAGE on the agent; configuring it needs MODIFY. `code_toolset_all` and `code_execution`
  are mutually exclusive.
- Browser tools still apply; the sandbox cannot reach the user's sidebar except through them.

## Studio (optional CoCo runner)

`coco-runner/` is a Node service using `@snowflake/cortex-agent-sdk/code` `query()` in CLI mode,
one session per conversation (`resume`), working in `WORK_ROOT/<owner-hash>/<conversation>`.
`canUseTool` is the whole policy (no `allowedTools`: Cortex Code CLI 1.2 treats `--allowed-tools`
as a whitelist and hard-denies every other tool before `canUseTool` runs). It auto-approves
read/grep/glob and read-only SQL (CLI 1.2 sends `{ action, resource }`; every statement must be a
read or a session `USE`), denies write SQL, and turns bash /
write / edit into `acme.approval` cards answered via `POST /api/studio/approve`. Files in `output/`
become download chips (`/api/files/<conversation>/<file>`, path-traversal guarded). Queries run
with `STUDIO_ROLE` (default `ACME_STUDIO_ROLE`; the local test uses `ACME_DEMO_ROLE`). Bundled skills
are matched from `coco-runner/skills.json` and pre-loaded with `$<skill>` mentions; attached skills
show as chips. Start: `STUDIO=http://coco-runner:8790 docker compose --profile coco up`.
The image needs the Cortex Code CLI (`cortex`) on PATH: supply a vetted tarball via
`coco-runner/vendor/` and `--build-arg CORTEX_CLI_TARBALL=...`. Internal/trusted users only;
credentials mounted read-only; usage bills as Cortex Code consumption.

## Docker

```bash
SNOWFLAKE_PAT_HOST_FILE=/path/to/token.pat docker compose up    # http://localhost:8080
```
The PAT is mounted read-only at `/run/secrets/snowflake_pat`; the rest comes from `.env`.

## SPCS (not run automatically)

1. As ACCOUNTADMIN: `snow sql -c <admin_conn> -f snowflake/spcs/setup.sql` (role `ACME_APP_ROLE`,
   repo `ACME_ASSIST_DEMO.APP.ACME_REPO`, pool `ACME_ASSIST_POOL` CPU_X64_XS 1/1, BIND SERVICE ENDPOINT).
2. With a connection using `ACME_APP_ROLE`: `CONNECTION=<conn> npm run deploy:spcs`
   (build `linux/amd64`, push, CREATE/ALTER SERVICE, print the ingress URL).
3. Grant `…ACME_ASSIST_SERVICE!ALL_ENDPOINTS_USAGE` to consumer roles.

In SPCS the app uses no PAT: `OAuthAuth` reads `/snowflake/session/token` per request against
`https://$SNOWFLAKE_HOST`; with `CALLERS_RIGHTS=true` it sends `<service token>.<Sf-Context-Current-User-Token>`
(`executeAsCaller: true` in `service.yaml`). Instances: see "Scaling out" below.

## App Runtime (Next.js variant)

`app-runtime/` is scaffolded from the bundled `snowflake-apps` Next.js template (Next 16):
`output: "standalone"`, pinned `turbopack.root` / `outputFileTracingRoot`, `compress: false`.
`app/[[...path]]/page.tsx` loads the shared `AppRoot` with `next/dynamic` (`ssr: false`);
`app/api/[...path]/route.ts` delegates to the same `dispatch()`. `npm run sync` copies shared code
into `app-runtime/acme/` (do not edit it).

```bash
cd app-runtime && npm install && npm run dev    # http://localhost:3000 (reads ../.env)
```
`app.yml` is `version: 2` with the template's build phases, label, icon, instance counts and
env vars. It was hand-written to match `snow app setup --app-name=acme_assist` output rather than
generated (setup was not run during this build). Prerequisite: `ACME_ASSIST_DEMO.APP` exists;
the owner role needs the `ACME_DEMO_ROLE` grants plus `SNOWFLAKE.CORTEX_USER`; viewers need USAGE
on the service. Deploy with `npm run deploy:sar` only after confirming the target connection.

### Scaling out

Runs no longer depend on one process: any instance can resume a run from Snowflake's run stream.
`app.yml` and the SPCS spec still ship with **max 1 instance** because the other per-process state
is not shared yet: set `RUN_STORE=snowflake` (create `AGENT_RUNS` from `../lab/history.sql`; this
store path is implemented but was not exercised live in this build), and note that MCP credentials,
rate-limit buckets and Power Mode downloads (`FILES_DIR`) are per instance. With a shared run store
and those trade-offs accepted, raise `max_instances`.

## Bundled CoCo skills

See `AGENTS.md` and `.snowflake/cortex/skills/acme-project/SKILL.md` (generated). Only bundled
Cortex Code skills are used; catalog skills are never installed.
