# Demo Script: Cortex AI Gateway for Medical Device Field Sales

About 30 minutes. Before you present, run `./demo.sh setup` and `./demo.sh traffic` once so the dashboards have history, and run the notebook once so the share-loss model has replaced the legacy scores. Run every command from the `ai-gateway-medtech` folder: `demo.sh` loads `.env` and runs inside the uv-managed `.venv`. Run the Trace Analyzer locally: gateway calls, including the optimizer's own calls, are traced only with a PAT from outside Snowflake (see the README section "Where to run the app").

## Pre-flight (10 min before)

- Terminal 1: `cd ai-gateway-medtech`, for the live prompt in section 2.
- Terminal 2: start the Trace Analyzer and leave it running: `./demo.sh app`
- Check the PAT hasn't expired: `demo.sh` warns in its last day and stops once it has. Reissue with `./demo.sh pat`. Send one prompt on the **Live prompt** page and confirm the waterfall appears.
- Run `./demo.sh traffic` so the Observe pages show the commercial team (reps, a territory manager, sales ops, market access, the AI platform team) instead of just you.
- At least 30 minutes before, make the territory-planning batch agent run away: `./demo.sh burst`. It spends about 6 credits over about 20 minutes as `GATEWAY_MEDTECH_TERRITORY_PLANNER` until the gateway returns HTTP 403. Confirm **Cost governance** shows 1 user blocked. The block lasts until 00:00 UTC, so run it on the day of the demo.
- CoCo Desktop: **Agent Settings > MCP > Snowflake Managed** lists Glean and the Snowflake server, both connected (authorized with your own accounts). Run one of the vetted Glean queries below once to warm the connection.
- Browser tab 1: Snowsight -> **AI & ML -> Cortex AI Gateway** (Traces), tab 2: **AI & ML -> AI Gateway -> MCP & Tools -> Activity**
- Browser tab 3: Trace Analyzer at http://localhost:8501, lookback 1 day
- Part 2 deck (`presentations/ai-gateway.html`) open at the Architecture slide. If the audience has not seen the agent build, start at the **Recap: The Agent** slide; the full build is the Part 1 deck (`presentations/agent-build.html`).

> **Glean safety.** The demo Glean tenant indexes internal content. Use only the vetted queries in section 3. Do not type ad-hoc Glean questions in front of the audience; ask the agent for Snowflake data instead.

## 1. Frame it (deck, 3 min)

Part 2 deck, slides 1-4 (overview, agent recap, why a control plane, architecture): one governed endpoint for every AI client, MCP for data and tools, telemetry you own. The use case: a field sales assistant that combines account numbers, the share-loss model and product knowledge.

## 2. Live prompt from an external agent (4 min)

```bash
./demo.sh ask "Which three Northeast accounts have the highest share-loss risk, which competitor is active there, and what does our clinical evidence say for the product at stake?"
```

- Point out the single tool call (`medtech_sales_agent`) and the `trace_id`. Behind the MCP server, the agent used the account health analyst for risk and competitors, then product knowledge search for the clinical evidence and battlecard, and cited the document titles.
- "Two gateway calls in one agent turn, one trace. The client never got a raw SQL tool, so it can't go around the semantic views."
- Note the guardrails in the answer: on-label evidence only, no superiority claim versus the competitor.
- If the notebook has not run yet, the agent says the scores are `LEGACY_SEED` and tied: that's the bridge to the share-loss model slide in the Part 1 deck ("the field's rule of thumb flags 186 of 300 accounts; the registered model ranks them").

## 3. Enterprise knowledge through Gateway Tools (5 min)

In **CoCo Desktop**, one prompt that uses both governed servers:

> "Using the Snowflake medtech sales agent, list the five accounts with the most consigned units near expiry. Then search Glean for our consignment and inventory rotation guidance and summarize it in three bullets."

Vetted Glean-only alternatives (safe on the demo tenant): "Search Glean for the AI Gateway Tools documentation and summarize what an admin controls", "Search Glean for MCP server setup guidance".

- "Same governed gateway, now for tools: the admin enabled Glean and the Snowflake server, restricted Glean to read-only tools, and each rep authorizes with their own identity. Glean results stay permission-aware."
- Tab 2, **Tools -> Activity -> Connections**: the tool calls from that prompt, grouped by prompt, with success or policy-violation status.
- "Teams, Outlook and SharePoint servers are in the catalog as Private Preview: the same pattern extends to where your reps already work."

## 4. Find it in Snowsight and the Trace Analyzer (3 min)

- Tab 1, AI Gateway traces: search the trace_id from section 2 and open the spans, model, tokens and captured messages. "It lives in an event table in this account."
- Trace Analyzer **Trace explorer**: the waterfall and the system prompt, input and output for each span. **Overview**: error rate and token charts include those calls.

## 5. Close the loop, with AI and with evidence (8 min)

1. **Advisor**: show one rule finding (token bloat or latency, from the generator's verbose scenario), then click **Diagnose with AI**. `claude-sonnet-4-5` reads the telemetry profile and a few captured payloads and returns findings with a root cause, evidence spans and one config change. "The diagnosis itself went through the gateway: copy its trace id."
2. Click **Test this fix** on a finding. **Experiments** opens with the baseline (the flagged traffic's model and settings) and the candidate (only the proposed change). Keep the default 8 prompts, which span sales, share-loss, labeling, evidence, policy and definitions. Click **Run experiment** (about 1-2 minutes).
3. **Before / after** opens on the pair:
   - Lead with cost: credits per 1,000 requests and the projected monthly saving.
   - **Quality delta (95% CI)**: a paired bootstrap over the prompts, plus the rubric breakdown (correctness, completeness, conciseness, compliance). "We promote on the lower bound of the interval, not on a lucky average."
   - **Response side by side**: each answer shows the judge's one-line rationale and the judge's own trace id.
4. Optional, if time: **Experiments -> Prompt optimizer**. It reads the weakest answers and judge rationales, proposes system prompts, picks the best on a dev split and confirms it against the baseline on held-out prompts. In our validation run it held quality (0.99 -> 1.00) on the held-out prompts.
5. **Route by intent**: the cheapest model within 0.05 of the best quality for each intent, as a routing table to ship.
6. **Cost of optimization**: "Every diagnose, propose and judge call ran through the same gateway: traced, attributed and costed." Show the call counts by role, the experiment cost in credits and the payback in days. Then **Trace explorer -> Optimizer traces only**, and open a judge span to show the rubric prompt and the JSON verdict. "We ship the evidence, and the evidence has a receipt."
7. **Promote**: client config, the allowlist `ALTER AI GATEWAY`, and a per-user quota.

## 6. Govern spend (3 min)

On **Cost governance** (Govern group):

1. **Attribute**: spend by cost center: field sales, sales ops, commercial analytics, AI platform. Users carry a `COST_CENTER` tag, and the same tag scopes the 2,500-credit monthly `GATEWAY_BUDGET`.
2. **Cap**: `GATEWAY_MEDTECH_FIELD_QUOTA` is selected. Every field user gets 5 credits a day. The reps are a few percent in; the territory-planning batch agent got stuck in a loop and went past 100%. The block lands within minutes of the spend, not per request, so size limits with headroom. Switch to `GATEWAY_MEDTECH_ANALYST_QUOTA` to show a second tier (15/day): one limit per quota, a `QUOTA_TIER` tag picks the quota.
3. **Enforce**: blocked until 00:00 UTC. Open **Last gateway denial**: HTTP 403, code 391936, "exceeded the usage quota limit defined by your administrator". "The platform enforces it; the client didn't implement anything."
4. **Advisor** now leads with a HIGH finding for the blocked batch agent, which feeds back into the loop. "The reps on the same tier never noticed."

## 7. Governance close (deck, 2 min)

Part 2 deck, Governing Spend through Next Steps. USAGE vs MONITOR, the spec replaces as a whole, Tools admin is ACCOUNTADMIN. Then next steps: point Tools at your Glean tenant, connect your semantic layer, run the optimizer on your own eval set.

## Recovery tips

- No trace yet in the Trace Analyzer: traces normally land within a minute; refresh the Trace explorer.
- Gateway returns 401 locally: the PAT expired or a network policy blocked it (are you on the VPN?). Run `./demo.sh pat`.
- Experiments or Diagnose show HTTP 401 or no gateway trace: you are on the deployed Snowflake app. Switch to the local app.
- CoCo Desktop doesn't list Glean or the Snowflake server: check the server is enabled in Tools, your role has `SNOWFLAKE$OPS.MCP$USER` (`lab/tools_setup.sql`), and you authorized it yourself. "List tools fails" usually means your user has no `DEFAULT_WAREHOUSE`.
- Glean can't be added in Tools: the custom server URL must end in `/mcp` and support OAuth. If your Glean server URL does not, connect Glean to CoCo Desktop directly for the demo and say so.
- Diagnose returns no findings: there is too little traffic in the lookback window. Run `./demo.sh traffic` or widen the lookback.
- **Cost governance** shows no block: enforcement can take a few minutes after the burst. Re-run `./demo.sh burst`, or show the saved denial and block history.
- `unknown model`: that model isn't available on this account's Chat Completions API; Claude only works on `/v1/messages`.
