# ACME Assist — Branded Agentic Chat App on the Cortex Agent SDK

## Goal
Build a branded, CoWork-style chat application for **ACME Retail** that fronts the **ACME Assist** agent. Store, regional, and fulfillment teams use it to ask questions of their operational data and to drive ACME's internal web apps. It must carry ACME's own branding throughout: logo, colors, and an animated "thinking" logo. The whole experience is themeable from configuration, so the same codebase can ship under another brand without code changes.

## Tech Stack
- **Frontend:** React + TypeScript, built with Vite (primary). The same client also runs inside a Next.js App Runtime wrapper (section 17).
- **Agent:** Snowflake Cortex Agents via the Cortex Agent SDK (`npm install @snowflake/cortex-agent-sdk@0.0.1`, pinned; requires Node >= 22.22).
  - Before writing integration code, read the installed package's `README.md` and type definitions in `node_modules/@snowflake/cortex-agent-sdk/dist` (especially `resources/agent.d.ts`, `resources/runs.d.ts`, `generated/events.d.ts`, `cortexcode/session.d.ts`) and use its actual API. Do not guess method names.
  - Verified against 0.0.1 (confirm before use):
    - `new CortexAgentClient({ account, auth })`, where `auth` is a PAT string, `PatAuth`, `OAuthAuth`, or `CallableAuth` (lazy token, used for the rotating SPCS token).
    - Named agents: `client.agent.streamData({ database, schema, name }, body)` returns an `AgentRunStream` (async iterable of SSE events).
    - Existing runs: `client.runs.stream(runId, { startingAfter })`, `client.runs.resume(runId)`, `client.runs.cancel(runId)`.
    - Threads: `client.threads.*`. Multi-turn helper: `Conversation`.
    - Client-side tools: `ToolUse` carries `client_side_execute: boolean` and optional `permission`. Replies use `tool_result` and `permission_decision` content items (`{ tool_use_id, decision, reason? }`).
    - Cortex Code sessions: `@snowflake/cortex-agent-sdk/code` exposes `query()` / `createSession()` with `canUseTool` and `resume` (CLI mode). `/code/api` is the browser-safe API mode; `/code/node` exposes `snowflakeConnectionProvider()`.
- **Backend:** Framework-neutral Fetch-API handlers (`server/handlers.ts`), served by a thin Express adapter (or Next.js route handlers in App Runtime). The backend holds Snowflake credentials (PAT or key-pair) and proxies agent calls. **No Snowflake credentials in the browser bundle.**
- Styling: CSS variables driven by a theme config (no hard-coded brand colors in components).

## 1. Branding
- A single `brand.config.ts` controls:
  - Product name (default "ACME Assist") and company name ("ACME Retail")
  - Logo (light + dark variants) and favicon
  - Color palette (primary, secondary, accent, background, surface, text) and font family
  - Animated logo config (see below)
- Ship the default **ACME theme** plus a second sample theme, **Northwind**, to prove that re-branding works by swapping config only, with no code changes.
- Keep brand assets in `public/brand/<brandId>/` (referenced by URL so both Vite and Next.js serve them) and brand code in `src/brand/`.

### 1a. ACME brand reference
| Token | Value | Usage |
|---|---|---|
| `primary` (ACME Ink) | `#1F2A44` | Wordmark, headings, primary text |
| `accent` (ACME Orange) | `#E4572E` | CTAs, links, active states, animation arc |
| `accentLight` | `#F28C6B` / `#F7B39C` | Hover states, gradients, chart series 2–3 |
| `accentTint` | `#FDEEE8` / `#FADBCF` | Selected rows, chips, info callouts |
| `background` | `#FFFFFF` | Page background |
| `surface` | `#F6F7F9` | Cards, sidebar, composer |
| `border` | `#E6E8EC` | Dividers, table borders |
| `textMuted` | `#5B6478` / `#A3AAB8` | Secondary text, placeholders |
| `success` | `#2E9E5B` | Healthy stock, on-time status |
| `warning` | `#D98E04` | Low cover, at-risk orders |

- **Font:** `Inter, system-ui, -apple-system, 'Segoe UI', sans-serif`. Headings use weight 600. Do not bundle font files; load nothing from third-party CDNs.
- **Logo:** create original SVG assets in `public/brand/acme/`:
  - `mark.svg`: a bold geometric "A" monogram in ink, whose crossbar is an orange chevron. Use it as the compact mark and the favicon.
  - `logo.svg`: the mark followed by an "ACME" wordmark in ink.
  - `logo-dark.svg`: the light-on-dark variant.
  - Product label: **ACME** in ink, with **Assist** in orange.
- **Visual motifs:**
  - The empty-chat hero shows a subtle diagonal stripe pattern in `accentTint` behind the composer, never behind message text.
  - Cards are white on `surface`, with 12px radius and generous whitespace.
- **Animated logo (section 2) in ACME colors:** "spark-and-settle."
  - The orange chevron detaches from the "A", orbits it as an arc trailed by two dots fading through `#F28C6B`, and pulses gently while the agent works.
  - On *done*, the chevron settles back into the crossbar with a brief orange glow.
- **Dark theme:** background `#141B2D`, surface `#1C2540`, text `#F4F5F7`, accent `#F06A43`, using `logo-dark.svg`.
- **Northwind sample theme:** teal `#0F766E` accent, slate `#1E293B` primary, its own simple "N" mark in `public/brand/northwind/`.

## 2. Animated "Thinking" Logo
- When the user submits a prompt (Enter or Send), show an animated version of the brand logo while the agent works. Make it an original design, not a copy of any existing product's animation.
- Implement it with SVG + CSS keyframes (no animation library, to keep the first load small; see section 15), with colors from the theme. Respect `prefers-reduced-motion` by falling back to a gentle pulse.
- Animation states: `idle` → `submitting` → `thinking` (tool calls in progress) → `streaming` → `done`. Hand off smoothly into the streamed response once the first token arrives.

## 3. Chat Experience (CoWork-like)
- Layout: left sidebar (conversation history, new chat), center chat pane, and an optional right browser sidebar (section 5).
- On an empty chat, show a centered composer ("What can ACME Assist help with?"). It docks to the bottom once a conversation starts.
- Stream responses rendered as Markdown (code blocks, tables).
- Show agent intermediate steps (tool calls, generated SQL, search results) in collapsible sections (section 10).
- Render charts and tables returned by the agent (section 13).
- Stop / regenerate / copy actions on messages.

## 4. Composer Controls & Extensibility
- **Model selector:** a config-driven dropdown in the composer (`auto` as the default, plus agent-allowed models such as `claude-sonnet-4-5`, `claude-opus-5-5`, `openai-gpt-5`, `gemini-3.1-pro`, `grok-4.6`, and the open-weight `kimi-k3`), grouped by provider with `<optgroup>`. A stored selection that is no longer in the list falls back to `auto`. The selected model is passed as `models.orchestration` on each request.
- **MCP servers:** a "+ / Tools" menu opens a **modal** to add, enable/disable, and remove MCP server connections (name, URL, auth header). Enabled MCPs are passed to the agent as tools.
- **Skills:** the same menu lists skills (name, description, instructions/markdown). Selecting a skill injects its instructions into the agent request. Ship three sample ACME skills: "Store Stockout Summary", "Fulfillment Exception Triage", and "Weekly Region Recap".
- Persist MCP, skill, and model selections in localStorage for the demo.
- Design these as a plugin registry interface so new extension types can be added later.

## 5. Built-in Browser Sidebar
- A collapsible **right-hand drawer** (toggled from the header) holds an embedded browser (iframe) with a URL bar, back/forward/refresh, and a list of registered "ACME apps" bookmarks.
- Apps are registered in config (name, URL, icon).
- Links in agent responses can open in the sidebar instead of a new tab.
- Build a **demo app** to prove this out: **ACME Store Ops**, a small React app served by the same dev server at `/apps/storeops`. It can `postMessage` the selected record (store, SKU, order, exception) back to the chat as context.

### 5a. Application Simulator — Sample Data
ACME Store Ops is a self-contained simulator backed by static seed data in `src/apps/storeops/data/` (JSON, deterministic, no Snowflake needed to render). It uses the **same records** as the Snowflake seed data in section 6, so agent answers and UI views agree.

| Route | Content |
|---|---|
| `/apps/storeops` | Region list (cards: name, store count, today's sales, stockout risk score) |
| `/apps/storeops/:regionId` | Store inventory table + 30-day sales line chart |
| `/apps/storeops/:regionId/orders` | Order blotter with filters (channel, status, date range) |
| `/apps/storeops/exceptions` | Fulfillment exceptions queue (reason, age, assignee) |
| `/apps/storeops/risk` | Risk dashboard: stockout risk, margin by category/region, threshold breaches |

Seed data (small but realistic):
- **regions.json** (4): `RG-001 West`, `RG-002 Central`, `RG-003 South`, `RG-004 Northeast`. Fields: id, name, manager, store_count, currency, weekly_sales_target, stockout_threshold_pct.
- **products.json** (~25 SKUs across Apparel, Footwear, Home, Electronics, Outdoor; e.g. `SKU-TRL-RUN-01 Trail Runner Shoe`, `SKU-HM-KTL-02 Electric Kettle`). Fields: sku, name, category, subcategory, brand, unit_cost, list_price.
- **inventory.json** (~60): region_id, sku, on_hand, on_order, daily_run_rate, weeks_of_cover, inventory_value, stockout_flag.
- **daily_sales.json**: 30 days of daily units and revenue per SKU and region, generated by a seeded script `scripts/gen-sales.ts`.
- **orders.json** (~150): order_id, region_id, sku, channel (`STORE|ONLINE|BOPIS`), qty, unit_price, order_date, promised_date, carrier, status (`NEW|PICKED|SHIPPED|FAILED|BACKORDERED`).
- **exceptions.json** (~12): exception_id, order_id, reason (`Address mismatch`, `Qty short`, `Late pick`, `Carrier delay`), age_hours, assignee, status.
- **risk.json**: per-region stockout rate, gross margin %, sales vs target, category exposure, and 2–3 deliberate threshold breaches (at least one region over its `stockout_threshold_pct`) so the agent has something to find.

Every interactive element must have a stable `data-testid` and an accessible label (e.g. `data-testid="order-filter-status"`, `data-testid="inventory-row-SKU-TRL-RUN-01"`) so the agent can target it reliably.

### 5b. Browser Navigation Tools for the Agent
Cortex Agents cannot drive a browser themselves, but the Agent Run API supports **client-side tool execution**, which is how the browser tools work:

1. Define each browser tool as a `generic` tool (`tool_spec` with name, description, `input_schema`) in the agent request. Leave out any server-side `tool_resources` (UDF/procedure), so the tool runs in the client.
2. When the stream emits a `response.tool_use` event with `client_side_execute: true`, the React app runs the tool against the sidebar.
3. The app sends the result back in the next request as a `tool_result` content item (matching `tool_use_id`), continuing the same thread (`thread_id` / `parent_message_id`). The agent then resumes reasoning.
4. If a `tool_use` event carries `permission.options` (e.g. `["Allow Once","Deny"]`), show an approval card in chat and reply with a `permission_decision` content item.

**Step 0, verify before building:** write a minimal spike (`scripts/spike-client-tool.ts`) using `@snowflake/cortex-agent-sdk`. It defines one generic tool, confirms the stream returns `client_side_execute: true`, and completes a round trip with a `tool_result`. Record findings in the README. If the SDK wraps this differently, follow the SDK's API. If client-side execution isn't available, fall back to the proxy running the tool loop and relaying calls to the browser over SSE.

The React app is the tool executor. The demo app runs same-origin, so tools act on it through a `postMessage` bridge (`src/browser/bridge.ts`) that the simulator implements. Never use raw cross-origin DOM access.

| Tool | Input | Returns |
|---|---|---|
| `browser_open_app` | `{ appId }` | url, title |
| `browser_navigate` | `{ url }` (must match a registered app origin — allowlist) | url, title |
| `browser_back` / `browser_forward` / `browser_refresh` | — | url |
| `browser_get_page` | — | url, title, simplified accessibility tree (role, label, testid, text, value) truncated to ~4k tokens |
| `browser_get_text` | `{ selector? }` (testid or CSS) | visible text |
| `browser_click` | `{ testid }` | ok, new url |
| `browser_fill` | `{ testid, value }` | ok |
| `browser_select` | `{ testid, value }` | ok |
| `browser_get_table` | `{ testid }` | rows as JSON |
| `browser_highlight` | `{ testid }` | ok — visually outlines the element |
| `browser_screenshot` (optional) | — | PNG data URL of the sidebar app view |

Behavior requirements:
- Each tool call shows in the activity section ("Opening Order Blotter…", "Filtering status = FAILED") and animates a cursor/highlight in the sidebar.
- If a browser tool is called while the sidebar is closed, open it automatically.
- Write-style actions (`click`, `fill`, `select`) on elements marked `data-agent-confirm="true"` (e.g. "Assign exception", "Cancel order") require user confirmation first. Use the API's `permission` / `permission_decision` flow if the agent emits one. Otherwise, the client enforces it with its own approval card and returns a "denied by user" `tool_result` on Deny.
- Tool definitions live in one registry (`src/agent/tools/browser.ts`) with JSON schemas, so the same registry feeds both the agent request and the UI.

Sample end-to-end scenarios (use as acceptance tests):
1. "Show me today's failed orders for the West region" → open app → navigate to RG-001 orders → set status filter = FAILED → read table → summarize in chat.
2. "Which region is breaching its stockout threshold?" → agent queries Snowflake (Cortex Analyst) **and** opens `/risk`, highlighting the breach row.
3. "Assign the oldest Address mismatch exception to me" → navigate to exceptions → sort by age → click assign → confirmation prompt → done.

## 6. Sample Cortex Agent
- Provide SQL setup scripts (`snowflake/setup.sql`) that create:
  - Database `ACME_ASSIST_DEMO`, schema `DATA`, with the **same seed records as section 5a**. Tables: REGIONS, PRODUCTS, INVENTORY, DAILY_SALES, ORDERS, FULFILLMENT_EXCEPTIONS, REGION_RISK. Load them from the JSON files via a script, so UI and agent data stay in sync.
  - A semantic view `ACME_SEMANTIC_VIEW` over that data for Cortex Analyst.
  - A Cortex Agent `ACME_ASSIST_AGENT` that uses the semantic view as a text-to-SQL tool, with retail-operations instructions. The instructions explain when to answer from data (Cortex Analyst) and when to **show** the user something in the sidebar app (browser tools from 5b), and require the agent to call `browser_get_page` before clicking.
- When building the semantic view and agent, use Cortex Code's built-in `agent-studio` skill. Use only built-in CoCo skills (no catalog or third-party skills).
- Document the role (`ACME_DEMO_ROLE`) and privileges required.

## 7. Power Mode (Cortex Code sandbox toolset)
An optional, admin-enabled mode that gives advanced users CoCo-style power, backed by Snowflake's managed `code_toolset_all` tool rather than a self-hosted CLI.

- **What it is:**
  - `code_toolset_all` adds the full Cortex Code sandbox toolset: bash, file read/write/edit, grep, glob, web search, SQL execution, and skills.
  - It runs in a Snowflake-managed sandbox.
  - It is a **Preview** feature; label it "Preview" in the UI.
- **Setup:** create a second agent, `ACME_POWER_AGENT`:
  ```yaml
  tools:
    - tool_spec: { type: code_toolset_all, name: coding_agent }
    - tool_spec: { type: cortex_analyst_text_to_sql, name: acme_analyst }
  tool_resources:
    coding_agent:
      permission_policy: { type: always_ask }
    acme_analyst:
      semantic_view: ACME_ASSIST_DEMO.DATA.ACME_SEMANTIC_VIEW
  ```
  - Before finalizing, check the exact `code_toolset_all` resource fields (workspace mounts, attached skills, disabled skills) against the "Coding Agent" docs page and the `agent-studio` skill.
  - `code_toolset_all` and `code_execution` are mutually exclusive; never put both in one agent.
- **UI:** a "Power Mode" toggle in the composer, hidden unless `brand.config.ts` or an admin flag enables it. It routes requests to `ACME_POWER_AGENT`. Show a distinct badge and accent color while it's active.
- **Approvals:**
  - Keep `permission_policy: always_ask`.
  - Every state-modifying sandbox action surfaces as a `tool_use` with `permission.options`, shown as an approval card (command or file-diff preview, Allow Once / Deny).
  - Never ship `always_allow` to end users.
- **Rendering:** show sandbox steps in the activity section (bash commands, file edits, SQL run). Offer generated workspace files (CSV, charts, reports) as downloadable attachments.
- **Skills:** the composer's Skills menu (section 4) can attach skills to Power Mode requests in the format `code_toolset_all` expects.
- **Browser tools still apply:** the 5b client-side browser tools can be included in Power Mode requests. The sandbox runs in Snowflake's cloud and **cannot** reach the user's sidebar or local machine; it only reaches the browser through those client-side tools.
- **Constraints to document:**
  - The sandbox is scoped to a thread and suspends when idle; only files in the mounted workspace stage persist.
  - Agents invoked with owner's rights drop code tools, so call the agent with caller's rights.
  - The sandbox has no direct data access; the agent queries data through its SQL tools.
  - Users need USAGE on the agent; configuring it requires MODIFY.
- **Sample scenario:** "Build me a CSV of all failed orders this week with carrier and age, and a bar chart by exception reason." The agent queries via Analyst/SQL, then writes the CSV and chart in the sandbox (with approval) and returns them as downloads.

## 8. Configuration & Running
- `.env.example` with:
  - Connection and auth: `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, auth (`SNOWFLAKE_PAT` / `SNOWFLAKE_PAT_FILE` or a private key path), `SNOWFLAKE_ROLE`, `SNOWFLAKE_WAREHOUSE`.
  - Agents: `AGENT_DATABASE=ACME_ASSIST_DEMO`, `AGENT_SCHEMA=DATA`, `AGENT_NAME=ACME_ASSIST_AGENT`, `POWER_AGENT_NAME=ACME_POWER_AGENT`, `POWER_MODE_ENABLED`, `VITE_BRAND=acme`.
  - Identity and history (section 15): `TRUST_PROXY_HEADER`, `TRUSTED_USER_HEADER`, `REQUIRE_AUTH`, `DEV_USER`, `CALLERS_RIGHTS`, `HISTORY_STORE`, `HISTORY_ROLE`, `HISTORY_TABLE`.
  - Studio: `COCO_RUNNER_URL`.
- `npm run dev` starts frontend + proxy together.
- The README covers setup, re-branding steps, adding MCPs/skills, and registering browser-sidebar apps.

## 9. Settings View
A settings dialog, opened from a gear button at the bottom of the conversation sidebar, holds per-user preferences. Persist them in `localStorage` (`acme.settings`). They apply immediately, with no reload.
- **Theme:** Light / Dark / System. System follows `prefers-color-scheme` and updates live. Each brand supplies a `theme` (light) and a `darkTheme` palette.
- **Show thinking & tool details:** when on, the accordions in section 10 start expanded. Default off.
- **Name and email:**
  - Shown in the sidebar footer and sent to the proxy as user context.
  - The proxy appends them to the agent's orchestration instructions, so "assign to me" resolves to a real person.
  - Validate the email format.
  - Display/context only, not authentication. In SPCS, prefill them from the ingress identity header.
- **Signed in as** (read-only): shown when an identity resolves from Snowflake ingress or a trusted SSO header (section 15). It takes precedence over the self-declared name.
- A note saying where conversation history is stored: this browser, or Snowflake.
- A reset-to-defaults button. Brand-locked items (logo, product name) are not user-editable.

## 10. Collapsible Activity (Accordions)
Everything that isn't the answer itself goes in accordion controls under the assistant message:
- **Thinking:** the model's reasoning text.
- **Activity / tool usage:** status updates, Analyst calls, generated SQL, browser actions, sandbox commands, and file writes. Each item shows its state (running / done / error / denied).

Both accordions are **closed by default**, and their summary reads "Activity · N steps". They open by default only when "Show thinking & tool details" is on, and users can toggle each one. Use native `<details>/<summary>`. **Approval cards are never collapsed**; they stay visible above the accordions.

## 11. Docker
- A multi-stage `Dockerfile`: build the Vite bundle, then run a slim Node 22 runtime that serves `dist/` and `/api` from one Express process on port 8080. It runs as a non-root user and has a `/api/health` healthcheck.
- A `docker-compose.yml` for local use:
  - Mount the PAT as a file (`SNOWFLAKE_PAT_FILE`), never as an image layer or build arg.
  - Read the rest of the config from `.env`.
  - Include an optional `coco` profile for section 14.
- `.dockerignore` excludes `node_modules`, `.env`, token files, and `app-runtime/`. The build stage copies `shared/`, and the runner image copies `skills.json`.

## 12. Snowpark Container Services (SPCS) Deployment
Scripts under `snowflake/spcs/`:
- `setup.sql`, run once as an admin, which:
  - creates service role `ACME_APP_ROLE`, an image repository, a compute pool (CPU_X64_XS, min 1 / max 1), and a warehouse grant
  - grants the `ACME_DEMO_ROLE` data privileges plus `SNOWFLAKE.CORTEX_USER`
  - grants `BIND SERVICE ENDPOINT` on the account
  - grants the service endpoint usage to consumer roles
- `service.yaml`: one container, a public endpoint on 8080, env (`AGENT_*`, `SEMANTIC_VIEW`, `SNOWFLAKE_WAREHOUSE`, `POWER_MODE_ENABLED`), and resource limits.
- `deploy.sh`:
  1. `docker build --platform linux/amd64`
  2. `snow spcs image-registry login`, then tag and push
  3. `CREATE SERVICE … FROM SPECIFICATION`, or `ALTER SERVICE` on redeploy
  4. print the ingress URL from `SHOW ENDPOINTS IN SERVICE`
- Inside SPCS, use no PAT:
  - Read the OAuth token from `/snowflake/session/token` per request (it rotates), via the SDK's `CallableAuth`/`OAuthAuth`, against `https://$SNOWFLAKE_HOST`.
  - The same auth helper serves the Agent API and the SQL API.
- Identify the user from the `Sf-Context-Current-User` ingress header. `CALLERS_RIGHTS=true` uses the `<service>.<caller>` token built from `Sf-Context-Current-User-Token`.
- Run a single instance, because resumable runs are buffered in-process.
- Document that the scripts are not run automatically, and which connection/role to use.

## 13. Charts & Tables Rendering
- Render natively from the agent's own output:
  - `data_to_chart` streams `response.chart` events carrying a **Vega-Lite spec**.
  - Analyst results arrive as `response.table` result sets.
  - Render with `vega-embed`.
- Charts:
  - full width of the chat column (`autosize: fit-x`, re-render via `ResizeObserver`)
  - themed from the brand palette, light and dark
  - external data URLs blocked
  - an error placeholder for invalid specs
- Tables:
  - every row in a scrollable container (sticky header, horizontal scroll, max height ~420px)
  - a row count
  - right-aligned numbers
- **Download CSV** per table and **Download PNG/SVG** per chart. Markdown tables get the same wrapper.

## 14. Optional Variation: CoCo Runner (Studio mode)
An optional, admin-enabled third mode, "Studio", for document and app generation. It runs Cortex Code headlessly in a separate container (`coco-runner/`).
- **Runner:**
  - A small Node service using `@snowflake/cortex-agent-sdk/code` (`query()` / `createSession()` with `resume`). It runs one session per conversation, continued across turns.
  - It works in `WORK_ROOT/<owner>/<conversation>`, where `<owner>` is a hash of the signed-in user.
  - It streams SDK messages (text, thinking, tool use/results, final result) as SSE events that the proxy maps onto the chat UI events.
  - It uses the resumable run registry (section 15) and loads the recommended bundled skills (section 16).
- **Approvals:**
  - The SDK `canUseTool` callback blocks on the user.
  - Read/grep/glob and read-only SQL are auto-approved.
  - Bash, file writes, and edits become approval cards (`acme.approval`, answered with `POST /api/studio/approve`). Write SQL is denied.
  - Headless `cortex exec --format json` cannot prompt, which is why the SDK with `canUseTool` is used.
- **Capabilities** (Python in the runner image: `openpyxl`, `reportlab`, `matplotlib`, `streamlit`):
  - XLSX, PDF reports, and Streamlit apps (optionally deployed with `snow streamlit deploy` after explicit confirmation)
  - data from Snowflake via the read-only `STUDIO_ROLE`
- **Output:**
  - Files written to `output/` appear as download chips via `/api/files/<conversation>/<file>`.
  - The proxy adds the owner hash, and the runner guards against path traversal.
- **Security and limits:** one container per deployment, for internal or trusted users only. Credentials are mounted read-only, and usage is billed as Cortex Code consumption on the hosting account.
- Hidden unless `COCO_RUNNER_URL` is set. Start it with `STUDIO=http://coco-runner:8790 docker compose --profile coco up`.

## 15. Experience Improvements
Each item below must also work unchanged in the App Runtime variant (section 17).
- **Resumable streams:**
  - The proxy owns each agent run: it registers it under a `runId`, buffers SSE events with sequence ids, and keeps it alive when the browser disconnects. The registry is bounded and in-memory, with ~10 minutes retention after the run finishes.
  - `GET /api/runs/:runId/events?after=<seq>` replays, then tails. `POST /api/runs/:runId/cancel` (Stop) is the only thing that aborts a run, and it also calls `client.runs.cancel`.
  - The client stores `runId` + last seq on the conversation and reattaches after a reload, re-asking any pending browser tool or approval. Show a "Reconnected" step.
  - Auto-reattach up to 4 retries with backoff.
  - Runs are owner-scoped (other users get 404).
  - Send SSE keepalives every 15 s.
- **Lighter first load:**
  - Code-split the markdown renderer, `vega`/`vega-embed`, the Settings/Tools modals, and the Store Ops simulator route.
  - `src/AppRoot.tsx` picks chat or simulator by pathname; use `react-router` only inside the simulator.
  - Target an initial JS chunk under 300 KB uncompressed / 90 KB gzip, and report chunk sizes in the README.
- **Compact live activity:** one live line while a run is in progress (pulse, current step, elapsed seconds, step count; e.g. "Querying acme_analyst · 6s · 3 steps"). Clicking it opens the accordion; it collapses into the summary when done.
- **Server-side conversation history:**
  - Persist conversations in `ACME_ASSIST_DEMO.APP.CONVERSATIONS`: id, owner, title, brand, UI messages and wire history (VARIANT), studio session id, and timestamps.
  - Every query filters by the resolved user and uses bind parameters.
  - Expose `GET/PUT/DELETE /api/conversations[/:id]`.
  - The client keeps localStorage as an offline cache; the server wins on `updated`. Save with a debounce after each turn.
  - `HISTORY_STORE=snowflake|local` switches the store (default `local`). The table and write role `ACME_HISTORY_ROLE` come from `snowflake/history.sql`.
- **Identity / SSO** via one `resolveUser(request)` function:
  - SPCS / App Runtime: the `Sf-Context-Current-User` header.
  - Behind an SSO proxy: `TRUSTED_USER_HEADER` (validated), honored only when `TRUST_PROXY_HEADER=true`.
  - Otherwise: `DEV_USER`.
  - `REQUIRE_AUTH=true` returns 401 without a user (`/api/health` stays public).
  - Ship `npm run check:identity` (401s, header identity, cross-user run isolation).
  - Expose the user via `/api/config`.

## 16. Recommended CoCo Bundled Skills
Use only Cortex Code's **bundled** skills; no catalog or third-party skills.
- **Building this project:**

  | Task | Bundled skill |
  |---|---|
  | Semantic view, Cortex Analyst, agent create/deploy/eval | `agent-studio` |
  | Any Snowflake SQL | `sql-author` |
  | Agent quality/debugging | `agent-optimization` |
  | App Runtime (Next.js) build/deploy/operate | `snowflake-apps` + `sar-actions-desktop` |
  | SPCS image/service deploy | `deploy-to-spcs` |
  | Grants, roles, caller's rights | `data-governance`, `access-troubleshooter` |
  | Streamlit generation (Studio) | `developing-with-streamlit-in-snowflake` |
  | Python / Snowpark in generated code | `snowpark-python` |
  | HTML reports (Studio) | `html-authoring`, `snowflake-publish-report` |
  | Cost of agents/Studio usage | `cost-intelligence` |

  - Ship `AGENTS.md` at the repo root, listing these with "invoke the matching bundled skill before doing that task".
  - Ship a project skill `.snowflake/cortex/skills/acme-project/SKILL.md` that routes each task type to a bundled skill and holds only project facts (object names, connection, brand rules).
- **Studio runner:**
  - Map intents to bundled skills: data/SQL → `sql-author`, streamlit → `developing-with-streamlit-in-snowflake`, HTML → `html-authoring`, publish → `snowflake-publish-report`, semantic view → `agent-studio`, Snowpark → `snowpark-python`, cost → `cost-intelligence`. XLSX/PDF use the runner's Python libraries.
  - List the skills in the appended system prompt, and pre-load matched skills with `$<skill>` mentions.
  - Never auto-install catalog skills.
  - Show attached skills as chips on the Studio message.
- Keep the list in `shared/skills.ts` (Studio intents as regex strings). `npm run gen:skills` generates `coco-runner/skills.json`, `AGENTS.md`, and the project `SKILL.md`. Never hand-edit generated files.

## 17. Snowflake App Runtime Deployment (Next.js variant)
`snow app deploy` builds and runs the app as an `APPLICATION SERVICE` with Snowflake sign-in at a `*.snowflakecomputing.app` URL. There is no Docker, registry, or compute pool to manage.
- **Scaffold** `app-runtime/` from the bundled `snowflake-apps` skill's Next.js template. Keep its `next.config.mjs` workspace-root pin (`output: "standalone"`, `turbopack.root`, `outputFileTracingRoot`); it is mandatory, because a parent `package-lock.json` exists.
- **One server implementation:**
  - `server/` exports framework-neutral handlers `(Request) => Promise<Response>`.
  - Express and Next.js route handlers (`export const dynamic = "force-dynamic"`) are thin adapters.
  - Run a single instance (`min_instances: 1`, `max_instances: 1`).
- **One UI:**
  - `app/[[...path]]/page.tsx` loads the shared `src/AppRoot.tsx` with `next/dynamic` and `ssr: false`.
  - Set the brand from `setDefaultBrand(NEXT_PUBLIC_BRAND)` (Vite: `VITE_BRAND`).
  - `npm run sync` copies `src/`, `server/`, and `shared/` into `app-runtime/acme/`, and `public/` into `app-runtime/public/`, before `dev` and `build`. Nobody edits `acme/` directly.
  - Shared code: no `import.meta.env`, no asset imports, extensionless relative imports.
  - `app/api/[...path]/route.ts` is a single catch-all (`runtime = "nodejs"`) delegating to `dispatch()`. Keep the registry on `globalThis`.
  - `next.config.mjs` adds `compress: false` so SSE isn't buffered.
  - The simulator keeps its `/apps/storeops/*` URLs.
- **Auth:**
  - App Runtime: the service token at `/snowflake/session/token`. Use caller's rights (`<service>.<caller>`) when `CALLERS_RIGHTS=true`.
  - Locally: the PAT.
- **Manifest:**
  - Generate it with `snow app setup --app-name=acme_assist`, targeting `ACME_ASSIST_DEMO.APP`.
  - Prefer `app.yml` `version: 2`, merging in the template's build phases. The standalone build copies `.next/static` and `public`.
  - Label "ACME Assist", a description, and `public/icon.svg`.
  - `environment_variables`: `SEMANTIC_VIEW`, `SNOWFLAKE_WAREHOUSE`, `POWER_MODE_ENABLED`, `SQL_READONLY_ROLE`, `CALLERS_RIGHTS`, `HISTORY_STORE`, `HISTORY_ROLE`, `NEXT_PUBLIC_BRAND`.
  - Prerequisite: `ACME_ASSIST_DEMO.APP` exists.
  - Grants: the owner role gets `ACME_DEMO_ROLE` grants plus `SNOWFLAKE.CORTEX_USER`; viewers get USAGE on the service.
- **Verify locally** with `npm run dev`: the homepage, `/api/config`, and a `_next/static` chunk return 200, and an answer streams and resumes.
- **Deploy:** `npm run deploy:sar` (sync, then `snow app deploy --verbose`), only after the user confirms the target connection.
- Studio stays a separate container; hide its toggle when `COCO_RUNNER_URL` is unset.

## Non-Goals (first version)
- Multi-tenant auth beyond Snowflake ingress identity and a trusted SSO proxy header.
- Per-tenant isolation for the CoCo runner.

## Acceptance Criteria
1. Swapping the brand (`VITE_BRAND=northwind`) fully re-skins the app: logo, colors, animation colors, and name.
2. Submitting a prompt triggers the spark-and-settle animation, then streams a response from `ACME_ASSIST_AGENT`.
3. The user can switch models, add/enable an MCP server, and apply a skill from the composer.
4. The browser sidebar opens ACME Store Ops and navigates between registered apps.
5. No Snowflake secrets are exposed client-side.
6. The three scenarios in 5b complete end-to-end, with tool steps visible in chat and actions visible in the sidebar.
7. Simulator numbers (inventory, sales, breaches) match what the agent returns from Snowflake.
8. The client-side tool spike passes, and its findings are documented.
9. Power Mode's sample scenario produces a downloadable CSV and chart, with each sandbox action approved through an approval card. With Power Mode disabled, the toggle is hidden.
10. Settings persist across reloads. Theme switches light/dark/system instantly for both brands. Name/email reach the agent as context.
11. Accordions start closed (or open when the setting is on), and approval cards always stay visible.
12. `docker compose up` serves the working app on http://localhost:8080. The SPCS scripts build, push, and create the service, and the app works through the ingress URL using the service OAuth token.
13. Charts render full-width and themed; tables show all rows with scroll and CSV download.
14. With the `coco` profile, Studio produces a downloadable XLSX, a PDF report, and a Streamlit app from ACME data.
15. Reloading mid-answer reattaches to the same run and finishes it; Stop cancels it server-side.
16. The initial JS chunk is under 300 KB (90 KB gzip). Chart, markdown, modal, and simulator code load lazily.
17. While working, a single compact live line shows the current step, elapsed time, and step count.
18. With `HISTORY_STORE=snowflake`, conversations follow the user to another browser, and users never see each other's history.
19. In SPCS/App Runtime, the signed-in Snowflake user is shown and used for history; `REQUIRE_AUTH=true` rejects unauthenticated requests.
20. `AGENTS.md` and the project skill route tasks to bundled CoCo skills; Studio runs show which bundled skills were attached.
21. `app-runtime/` runs locally with `npm run dev`. After `snow app deploy`, it serves the same chat and Store Ops app from a `*.snowflakecomputing.app` URL, using the same server handlers as the Express build.
