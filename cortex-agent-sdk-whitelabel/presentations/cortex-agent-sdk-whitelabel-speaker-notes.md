# Speaker Notes — Building Agentic AI Applications on the Cortex Agent SDK

## Slide 1: Overview

### Talking Points
- Today is about *how*: a fully branded, CoWork-style agent app built on the Cortex Agent SDK and governed Cortex Agents.
- The app you'll see (ACME Assist) was generated from one meta-prompt in Cortex Code with a high-reasoning model.
- Four numbers frame it: one prompt, two brands from one codebase, a dozen client-side browser tools, three deploy targets.

### Internal Context
- ACME Retail is a fictional brand; Northwind is the second sample theme.
- Everything is reproducible from `lab/setup.sql` + `PROMPT.md`.

### References
- npm: `@snowflake/cortex-agent-sdk` · PyPI: `snowflake-cortex-agent-sdk`
- https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/cortex-code-agent-sdk

## Slide 2: The Problem

### Talking Points
- The ask is always the same four things: their brand, their apps, their controls, and a timeline measured in days.
- Hand-building streaming chat, tool loops, approvals, resume, charts and three deploy paths is a quarter of engineering.
- The split that makes it fast: agents reason and access data; the SDK gives a typed client; Cortex Code writes the app.

### Internal Context
- Keep this anchored on outcomes. Don't position against any other Snowflake surface.

### References
- Cortex Agents overview docs.

## Slide 3: Architecture

### Talking Points
- Three layers: a thin React client, a proxy that owns credentials and runs, and Cortex Agents in Snowflake.
- The browser sidebar is just an iframe of the customer's own app, reached through a postMessage bridge.
- The trick that makes "agent drives my app" possible is client-side tool execution, coming up on slide 7.

### Internal Context
- Proxy-owned runs are what make reload/reattach work; normal streams don't carry a run id.

### References
- Agent Run API: tool_use / tool_result / permission_decision content items.

## Slide 4: The SDK Surface

### Talking Points
- `CortexAgentClient` with PAT, OAuth or a callable token provider (used for the rotating SPCS token).
- `agent`, `threads`, `runs`, plus `/code` for Cortex Code sessions.
- Real lesson from the build: named-agent runs don't accept extra per-request tools. So the proxy describes the named agent once and runs its spec via `agent.stream` with browser tools merged in. Governance still lives in the agent object.

### Internal Context
- Verified live on 0.0.1: generic tools without tool_resources yield `client_side_execute: true`; in a thread you only send the tool_result plus `parent_message_id`.

### References
- Package README and `dist/resources/*.d.ts`.

## Slide 5: Meta-Prompt Pattern

### Talking Points
- Don't ask the model for code first. Ask it for the questions it needs answered, then have it write the spec.
- `META_PROMPT.md` shows the seed and the 11 clarifying questions; `PROMPT.md` is the result.
- What makes it one-shot-able: file layout, read-the-types instruction, a Step 0 spike on the riskiest API, acceptance criteria, hard rules.

### Internal Context
- Built with Opus 5.5 in Cortex Code at high reasoning effort.

### References
- `META_PROMPT.md`, `PROMPT.md`.

## Slide 6: Branding by Config

### Talking Points
- One `brand.config.ts` drives every color, logo and the thinking animation via CSS variables.
- Show the swap live: `VITE_BRAND=northwind npm run dev`, and both the chat and the embedded app re-skin.

### Internal Context
- Assets are original SVGs in `public/brand/<id>/`.

### References
- `app/src/brand/brand.config.ts`.

## Slide 7: Client-Side Browser Tools

### Talking Points
- Declare each browser tool as a `generic` tool with no server binding. The agent asks the client to run it.
- Walk the three scenarios; scenario 3 shows an approval card before the write.
- Guardrails: allowlisted URLs, testid targeting, get-page-before-click, confirm-marked elements.

### Internal Context
- The seed data is relative: `npm run gen:seed` anchors "today" on the day you generate it (or `SEED_ANCHOR_DATE`). The proxy reads MAX(order_date) from Snowflake at startup and tells the agent "Data current as of <date>", so date filters line up.
- All three scenarios pass in `npm run test:scenarios` against the live agent.

### References
- `app/src/agent/tools/browser.ts`, `app/src/browser/bridge.ts`.

## Slide 8: Power Mode

### Talking Points
- Swap to a second agent that has `code_toolset_all`: the Cortex Code sandbox as a tool.
- Keep `always_ask`; every write arrives as an approval card.
- Demo: CSV of failed orders and a chart by reason, returned as downloads.

### Internal Context
- Approval options observed: "Allow this command", "Allow all <tool> for this session", "Deny". The UI shows per-action options only.
- Preview feature; caller's rights required.

### References
- Coding Agent docs; Cortex Agent code execution tool docs.

## Slide 9: Studio Mode

### Talking Points
- For richer artifacts (XLSX, PDF, Streamlit) a runner container drives Cortex Code sessions through the SDK's `/code` entry point.
- `canUseTool` turns tool calls into the same approval cards.

### Internal Context
- The runner image needs the `cortex` CLI supplied at build time.

### References
- `app/coco-runner/`.

## Slide 10: Deploy Options

### Talking Points
- Same handlers in Express and Next.js. Docker for local, SPCS for full control, App Runtime for the simplest managed path.
- App Runtime: `npm run deploy:sar`, Snowflake sign-in, `*.snowflakecomputing.app` URL.

### Internal Context
- Needs Snowflake CLI with app.yml v2 support (3.29 verified). Single instance because runs buffer in-process.

### References
- `snowflake-apps` bundled skill.

## Slide 11: Production Checklist

### Talking Points
- Secrets server-side, one identity resolver, caller's rights, owner-scoped runs and history, resumable streams, version pinning.

### Internal Context
- `npm run check:identity` covers 401s, header identity and cross-user isolation.

### References
- `app/README.md`.

## Slide 12: Takeaways

### Talking Points
- Build on the SDK, generate then verify, ship in Snowflake.
- Next step for the customer: run setup, open the meta-prompt with their own brand and domain.

### Internal Context
- Clean up with `lab/cleanup.sql`.

### References
- Module README.
