# Demo Script: Multi-Agent Orchestration over MCP

About 20 minutes for a technical audience (architects, data and platform engineers), plus Q&A. The [Cuts](#cuts) bring it to 15. It interleaves the deck (`presentations/multi-agent-mcp.html`) with the Claude-style app (`./demo.sh app`). Slide-by-slide detail lives in `presentations/multi-agent-mcp-speaker-notes.md`; this file is the run of show.

The audience should leave with three points:

1. **One governed front door.** Any MCP client gets one tool, `northwind_assistant`. What sits behind it (two specialists, or one agent with inherited tools) is invisible to the client.
2. **The model picks the tool; Snowflake decides the answer.** Grants, caller's-rights execution and a row access policy decide what each person gets. No prompt asks a model to refuse.
3. **Two architectures, a real trade-off.** Hub and spoke gives per-domain ownership and an explicit, auditable denial. An agent toolset gives one run, native charts and lower latency, but denials are silent.

How to read the beats: **Say** is spoken (paraphrase freely), **Do** is a click or keystroke, **Show** is where to point, **If** is the fallback.

## Pre-flight

### The day before

- `./demo.sh build --yes` has run on the demo account and every CHECK line passed (README, Quick start).
- Rehearse once end to end, and screenshot each expected result: the persona compare, the `NOT_ENTITLED` inspector, and the both-architecture chart compare. They are your fallback if the network or an agent run fails live.
- The host-model PAT lasts 7 days. If it expires before the talk, run `./demo.sh pat` to reissue it. `./demo.sh app` stops with that hint once it has expired.
- Confirm the venue network is allowed by the account's network policy. A PAT on a person user only authenticates under a network policy; if the venue is blocked, tether to an allowed network.

### 30 minutes before

- Optional headless check, no model involved: `./demo.sh smoke` and `./demo.sh smoke --server toolset`.
- Start the app: `./demo.sh app`, then open http://localhost:8501. The sidebar shows **Connected: 1 tool(s) via tools/list** and no PAT warning.
- Warm both servers: as the Global sales exec, ask one sample question on **Hub and spoke**, then on **Agent toolset**. This primes the cached MCP clients and `tools/list`.
- Click **New conversation** for each persona you will use in Chat, so the room sees a clean thread.
- Tab 1: the deck at slide 1. Tab 2: the app. Tab 3: Snowsight at **AI & ML » Agents » ORCHESTRATOR_AGENT » Monitoring**.

### Screen setup

- Browser at 125-150% zoom; the app sidebar must be readable from the back row.
- Hide bookmarks, notifications and the terminal running `./demo.sh app`.
- App start state: **Chat** tab, **Hub and spoke**, **Global sales exec**.

## Run of show

| # | Segment | Where | Minutes | Ends at |
|---|---|---|---|---|
| 0 | Frame it | Deck, slides 1-4 | 3 | 3:00 |
| 1 | One connector, one tool | App | 2 | 5:00 |
| 2 | The model picks the tool; Snowflake decides the answer | App | 3 | 8:00 |
| 3 | Same question, three personas | App | 2.5 | 10:30 |
| 4 | Denial is enforced by grants, not prompts | App, then slide 5 | 2 | 12:30 |
| 5 | Cross-domain and follow-up (cuttable) | App | 1.5 | 14:00 |
| 6 | Agent toolset: same connector, different architecture | Slide 8, app, slides 9 and 11 | 4 | 18:00 |
| 7 | Swap the client | App sidebar, Snowsight | 1 | 19:00 |
| 8 | Close | Slide 12 | 1 | 20:00 |

Slides 6, 7 and 10 are covered live in the app; skip them, or flash them only if someone asks.

## 0. Frame it (deck, slides 1-4, 3 min)

**Slide 2. Say:** "Your users already live in an AI assistant: Claude, ChatGPT, Cursor. They want to ask it about the business. You want the answers to respect exactly the same access rules as your dashboards. And you don't want to rebuild governance in every client."

**Slide 3. Say:** "One Snowflake-managed MCP server, one tool. Behind it, an orchestrator agent delegates to a sales or a support specialist through caller's-rights bridge procedures. Every hop runs as the person who asked."

**Slide 4. Say:** "The app you're about to see plays the part of Claude Desktop. A Claude model, `claude-sonnet-4-6`, decides when to call a tool. There are two identities, just as in Claude. The model call runs as me: that plays the LLM vendor. The tool call is signed in as the persona I pick. That second identity is the one Snowflake governs, and Snowflake can't tell this app apart from Claude Desktop: it's the same JSON-RPC traffic."

**Do:** Switch to the app tab.

## 1. One connector, one tool (2 min)

**Do:** Point at the sidebar.

**Show:** The server `MULTI_AGENT_MCP_DEMO.APP.ORCHESTRATOR_MCP` and **Connected: 1 tool(s) via tools/list**.

**Do:** Expand **Tool: northwind_assistant**.

**Say:** "This is everything the client knows: a name, a description and an input schema. One `text` field, plus optional `thread_id` and `parent_message_id` for server-side threads. No SQL tool, on purpose. Every client gets the same single front door."

**Do:** Switch **Signed in as** through all three personas.

**Show:** The tool list stays identical. The default role changes each time.

**Say:** "Same tool for everyone. The client has no idea there are two specialist agents behind it. That's the point: the routing and the rules sit on the server."

**Do:** Leave it on **EMEA seller**.

## 2. The model picks the tool; Snowflake decides the answer (3 min)

**Do:** As the EMEA seller, click the sample **"What were total new bookings in FY25-Q4 by theater?"**

**Fill while it runs (about 35 seconds):** "Claude saw one tool and decided this question needs it. The app sends a `tools/call` signed with the EMEA seller's key pair. The MCP server starts `ORCHESTRATOR_AGENT` as that user. The orchestrator decides this is a sales question and calls its `ask_sales` tool. That's a stored procedure with caller's rights, so it starts `SALES_AGENT` as the EMEA seller, not as some service account. Two agent runs, one question."

**Show:** The answer: **EMEA $38.4M only**.

**Say:** "Global question, regional answer. Nobody told the model this person is in EMEA."

**Do:** Open the **Tool call: northwind_assistant** expander and walk it top to bottom:

1. **"Claude wrote these tool arguments"**: "The model rewrote my question into a self-contained message, as the tool description asks."
2. **The MCP JSON-RPC line**: "Real protocol traffic: HTTP status, an event-stream response with one SSE event, round-trip time."
3. **Inside Snowflake**: "The orchestrator delegated to `ask_sales`, and the specialist answered. Below that is what it returned, then the thread and run IDs."

**Say:** "Why EMEA only? The specialist's Cortex Analyst query ran as the caller, and a row access policy on the bookings table filtered it. The policy has no idea an AI was involved. It does what it does for every query."

**If** the run fails or times out: show the rehearsal screenshot. "This is the run from rehearsal; the flow is identical." Carry on to segment 3.

## 3. Same question, three personas (2.5 min)

**Do:** **Compare** tab, **Three personas on Hub and spoke**, question **"What were total new bookings in FY25-Q4 by theater?"**, **Run side by side**.

**Fill while it runs (about 35-60 seconds, in parallel; the columns appear together when the slowest finishes):** "Three users, three tool calls, three orchestrator runs, all in parallel. Same server, same tool, same prompt. The only variable is who is signed in."

**Show:** The three columns:

| Persona | Expected answer |
|---|---|
| Global sales exec | Americas $59.6M, EMEA $38.4M, APAC $22.1M, total $120.0M |
| EMEA seller | EMEA $38.4M only |
| Support rep | "This type of question is not available at your access level..." |

**Say:** "Global sees everything. EMEA sees its theater. Support is refused outright. Now the interesting question: who refused?"

## 4. Denial is enforced by grants, not prompts (2 min)

**Do:** In the **Support rep** column, open the tool-call expander. Its label reads **"(a specialist denied access)"**.

**Show:** Under **Inside Snowflake**, the red line: **`ORCHESTRATOR_AGENT → ask_sales → specialist denied: NOT_ENTITLED (error 399513)`**.

**Say:** "Neither model was asked to refuse. The orchestrator tried to delegate to sales. The bridge ran the nested agent call with caller's rights, as the support role, and the support role has no USAGE on the sales agent. Snowflake rejected the call with error 399513. The refusal you saw is the orchestrator reporting a denial, not a model deciding to be cautious."

**Say:** "That matters for prompt injection. You can talk a model into many things. You can't talk it into a grant it doesn't have."

**Optional, slide 5:** the four layers of grants: agent USAGE, the caller's-rights bridge, SELECT on the semantic view and table, and the fail-closed row access policy.

**Optional honest detail:** "You'll sometimes see it try `ask_sales` twice, though its instructions say not to retry. The boundary held both times."

## 5. Cross-domain and follow-up (1.5 min, cuttable)

**Do:** Back to **Chat**, still **EMEA seller**. Click **"What was total new bookings in FY25-Q4, and how do I fix a 401 error from the API?"**

**Fill while it runs (longer: up to three agent runs):** "One question, two domains. The orchestrator splits it: sales for the number, support for the how-to."

**Show:** The EMEA seller gets the EMEA number and a refusal for the support part.

**Do:** Click **"Break that down by territory."**

**Say:** "A follow-up with no subject. The host model keeps the conversation and rewrites the question; the orchestrator rewrites it again for the specialist. The tool also accepts a `thread_id`, so a client could keep the thread server-side instead."

## 6. Agent toolset: same connector, different architecture (4 min)

**Slide 8. Say:** "Everything so far was hub and spoke. Snowflake now has a second way to build one front door: agent toolsets. `TOOLSET_AGENT` holds no tools of its own. At run time Snowflake reads the sales and support agents' specifications and adds their tools to this one agent. One orchestrator, one context, one run. The specialists' own instructions, models and budgets never run."

**Do:** App sidebar, switch **Architecture behind the connector** to **Agent toolset**.

**Show:** The server changes to `TOOLSET_MCP`; still 1 tool, still `northwind_assistant`.

**Say:** "Same tool name, same description. Only the server URL changed."

### 6a. Native chart, one run

**Do:** Sidebar persona **Global sales exec**. **Compare**, **Both architectures as Global sales exec**, question **"Show new bookings by fiscal quarter and theater as a chart"**, **Run side by side**.

**Fill while it runs (about 60 seconds; both columns appear together when the slower run finishes):** "When this comes back, look at the timing under each answer. On the toolset side, the agent that runs the query also draws the chart. On the hub side, the specialist's chart doesn't survive the hop: the bridge relays text, and the orchestrator re-draws a chart from the relayed table."

**Show:** A native chart on the toolset side and a re-drawn chart on the hub side. Point at the **"Ns end to end"** caption under each: about 22 s against about 60 s.

**Say:** "Over MCP the chart arrives as a Vega-Lite spec inside the tool's JSON, so the client has to draw it. This app does. Snowsight and CoWork render it natively. I haven't verified whether Claude Desktop does, so I won't claim it."

### 6b. The access boundary holds, but denial goes silent

**Do:** Sidebar persona **Support rep**. **Compare**, **Both architectures as Support rep**, question **"What were total new bookings in FY25-Q4 by theater?"**, **Run side by side**.

**Show:** The hub's inspector shows an explicit `NOT_ENTITLED`. The toolset's shows the yellow note that no inherited domain tool was available.

**Say:** "Both refuse. The difference is how. USAGE on a referenced agent is checked as the caller. The support rep has no USAGE on the sales agent, so for this run the sales tools simply don't exist. No error, no marker, no trace of a skipped tool. The refusal wording lives in the toolset agent's instructions. The boundary is still grants; the observability is weaker."

**Optional, as the EMEA seller:** "The row access policy still applies, because the inherited Analyst tool runs its SQL as the caller. The EMEA seller's chart covers EMEA only. It may say the other theaters are 'missing': an agent can't tell rows a policy hid from rows that don't exist."

### 6c. Measured, and when to use which

**Slide 9. Say:** "On this demo's evaluation the toolset scored higher: answer correctness 1.00 against 0.87. That's five questions over two tools, so it's directional, not proof. The real test is to keep adding tools until selection accuracy drops. The documented limits are 25 referenced agents and depth 5. Any tool-count rule of thumb you've heard is not documented."

**Slide 11. Say:**

- "**Hub and spoke** when domains need their own instructions, model, budget or owning team; when tool count would crowd one context; or when you want an explicit, auditable denial."
- "**Agent toolset** when one agent can hold all the tools and still pick well, and you want native charts, one run and lower latency."
- "Either way, the MCP front door and the grants underneath are identical."

## 7. Swap the client (1 min)

**Do:** Back to the app; point at the server name in the sidebar.

**Say:** "This is a URL: `https://<account>/api/v2/databases/MULTI_AGENT_MCP_DEMO/schemas/APP/mcp-servers/ORCHESTRATOR_MCP`. Point Claude Desktop, ChatGPT or Cursor at it. The user signs in with OAuth instead of the key pair this app uses, and the session runs as their default role. Everything you just saw stays the same, because none of the governance lives in the client."

**Do:** Snowsight tab: **ORCHESTRATOR_AGENT » Monitoring**.

**Show:** Today's runs, each attributed to the persona user who made it.

**Say:** "Every run is attributed to the person, not to a shared bot account. That's your audit trail, whichever client they used."

## 8. Close (slide 12, 1 min)

**Say:** "Three things. One governed front door for every MCP client. The model picks the tool; Snowflake decides the answer, with grants and policies you already have. And a real choice of architecture behind the same connector: hub and spoke for ownership and explicit denials, toolsets for one run and native charts. To run it yourself: `./demo.sh setup`, `./demo.sh build --yes`, then `./demo.sh app`."

## Cuts

Cut from the top of this list first:

1. **Segment 5** (cross-domain and follow-up): saves 1.5 min. Mention it in one sentence during segment 4.
2. **Slide 4**: saves 1 min. Say the two-identities line during segment 1 instead.
3. **6b's optional EMEA beat**: saves 1 min.
4. **Snowsight Monitoring in segment 7**: saves 30 s. Say it, don't show it.
5. **Segment 3's live run**: show the rehearsal screenshot of the three columns instead. Saves about 1 min of waiting.

Never cut segment 4. It is the proof that governance is not prompt-based.

## Recovery tips

| Symptom | Likely cause | Recovery |
|---|---|---|
| `./demo.sh app` stops with a PAT hint | The 7-day host-model PAT expired | `./demo.sh pat`, then restart the app |
| Sidebar: "Not connected" | `.env` or the persona keys are missing, or the network is blocked | Re-run `./demo.sh setup`; switch networks. Meanwhile, present from screenshots |
| Sidebar: "No host-model PAT" | The app was started without the PAT file | `./demo.sh pat`, then restart the app |
| The model call fails with 401 | PAT expired, or a network the account's network policy does not allow | `./demo.sh pat`; check the network policy. Present from screenshots meanwhile |
| Answer: "[stopped: the model kept calling tools after 5 model calls]" | The host loop's model-call cap | Click **New conversation** and re-ask, or move on with the screenshot |
| A run takes much longer than 60 s | Agent latency on the day | Keep narrating the flow; past about 90 s, use the screenshot |
| Personas reach nothing | An MCP server was re-created and lost its grants | Re-run `./demo.sh build --yes` after the talk; use screenshots now |

## Q&A prep

**"Does the model vendor see my data?"** The host model never queries governed tables, and its identity has no access to them. It does receive the answer text the persona was entitled to, as any assistant does with a tool result. With Claude, that answer goes to Anthropic; here the host model is on Cortex, so it stays in Snowflake.

**"Why key pair here and OAuth in Claude?"** The demo needs to sign in as three people without a browser flow, so each persona is a service user with a key pair. Key-pair JWT worked on the MCP endpoint in testing, though the MCP docs only name OAuth and PAT. A real client uses OAuth.

**"Can a user bypass the agent and query the data directly?"** Not through this server: it exposes one tool and no SQL tool. Any other path into Snowflake still goes through the same grants and row access policy.

**"Why a separate MCP server for the toolset instead of a second tool?"** So a host model never has to choose between two overlapping tools. One connector, one architecture.

**"How many tools can a toolset hold?"** The documented limits are 25 referenced agents per run and depth 5, not a tool count. All inherited tools share one context, so selection accuracy is the real ceiling. Measure it with an evaluation as you add tools.

**"Do the evaluations test the access boundary?"** No. Evaluations run as the role that starts them and don't impersonate personas, so they score routing and answers. The boundary is tested as the persona users: notebook Section 4, `./demo.sh smoke`, or the app.

**"What does the support rep's refusal look like in traces?"** Hub: a `NOT_ENTITLED` delegation in the orchestrator's trace. Toolset: nothing, because the sales tools were never in the run.

## After the talk

- Click **New conversation** for each persona before handing the laptop over.
- When you're done with the demo for good: `./demo.sh teardown --yes`.
