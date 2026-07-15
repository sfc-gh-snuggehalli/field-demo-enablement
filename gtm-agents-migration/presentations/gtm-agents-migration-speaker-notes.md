# Speaker Notes: Migrating GTM AI to Cortex Agents + CoWork

## Account Context Summary

Client-agnostic scenario: a B2B sales-intelligence / go-to-market (GTM) SaaS company whose sales org sends
high email volume. Today they score every rep email with AI and mine winning patterns using Claude Code over
the Snowflake-managed MCP server (the "external brain"). Their top sensitivities are cost/budget, governance,
and connector reliability. This demo migrates that workload to an in-data-plane multi-agent Cortex Agents +
CoWork architecture and proves lower latency, lower cost, stronger governance, and built-in observability.
All objects live in database `GTMAGENTS`, schema `DEMO`, warehouse `GTMAGENTS_WH`, role `GTMAGENTS_ROLE`.

> Model note: the plan named `claude-3-5-haiku` as the cheap scorer, but it is not available in this region,
> so the lab uses `llama3.1-8b` (cheap) escalating to `mistral-large2` on low confidence. Swap in your
> region's cheapest capable model when re-skinning.

---

## Slide 1: Hero

**Talking Points:**
- Frame the arc in one sentence: we are moving the AI "brain" from outside Snowflake (Claude Code + MCP) to inside the data plane (Cortex Agents + CoWork) over the exact same governed data and tools.
- The four stats are the promises we will substantiate live: ~69% lower per-request latency, ~26% less volume treated via a targeting gate, a 3-specialist + 1-supervisor architecture, and 100% server-side traces.

**Presenter Notes:**
- These numbers are produced by the lab, not slideware: latency comes from `REQUEST_LOG` (MCP ~1150ms vs Agents ~360ms), the volume cut from `COST_COMPARISON`. If you re-run with different data they will shift slightly — that is expected and a strength.
- Prerequisite for the live demo: run `lab/setup.sql` and the four notebooks first; the Streamlit app reads their output.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork

---

## Slide 2: The Problem

**Talking Points:**
- The BEFORE state works — that is important to acknowledge. The issue is the compounding "external-brain tax": latency on every call, cost blindness, a governance gap, and fragile connector plumbing.
- Anchor each card to the customer's stated sensitivities: cost/budget (card 2), governance (card 3), connector reliability (card 4).

**Presenter Notes:**
- Common question: "Isn't MCP the modern way to do this?" — Yes, MCP is valuable and we keep it; the point is where the *reasoning loop* runs. When the brain is external, budgets/quotas/traces can't be native.
- The connector-reliability card previews the real gotchas we hit on Slide 4 — foreshadow them here.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp

---

## Slide 3: Architecture

**Talking Points:**
- The key insight: Part 0 builds the governed tools once (Cortex Analyst semantic view, Cortex Search, governed UDF). BOTH front doors — the MCP server and the supervisor+specialists — consume the *same* tools.
- So migration is not a data rebuild. It is swapping the front door / relocating the reasoning loop. Business definitions never drift because the semantic view is shared.

**Presenter Notes:**
- Walk the diagram top-down: entry points (Claude external vs CoWork in-plane) → brains (MCP server vs supervisor) → shared governed tools.
- Emphasize that the AFTER supervisor (highlighted node) and the BEFORE MCP server point at identical underlying objects. This is what makes the comparison fair on Slide 10.

**References:**
- https://docs.snowflake.com/en/user-guide/views-semantic/overview
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-manage

---

## Slide 4: Before — Snowflake-managed MCP server

**Talking Points:**
- Show how little it takes to expose governed tools: `CREATE MCP SERVER ... FROM SPECIFICATION` lists the tools; OAuth is Snowflake's built-in service (no dynamic client registration).
- Access to the server is not access to the tools — each underlying object is granted separately. That is the least-privilege story.

**Presenter Notes:**
- The warning box is the live-demo survival kit. The two that bite everyone: (1) redirect URI must exactly match what Claude shows; (2) the OAuth session uses the user's DEFAULT_ROLE and fails if DEFAULT_WAREHOUSE is null — the classic "can't list tools / no warehouse" error.
- Underscore gotcha: use the hyphenated org-account URL and an underscore-free DB name (`GTMAGENTS`). The Claude connect itself is manual (your personal Claude account) — the notebook has the exact click-path and demo prompts.
- Non-TLS localhost redirect URIs are rejected unless `OAUTH_ALLOW_NON_TLS_REDIRECT_URI=TRUE`; Claude Desktop needs this, claude.ai does not.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp
- https://docs.snowflake.com/en/sql-reference/sql/create-security-integration-oauth-snowflake

---

## Slide 5: After — a supervisor over three specialists

**Talking Points:**
- The AFTER brain is a supervisor agent that routes each sub-task to a specialist: Scoring (cheap model + escalate), Recommendation (Cortex Analyst), Coaching (Cortex Search + rewrite).
- There is no native "supervisor" object — it is the documented agent-to-agent pattern: each specialist is wrapped in an owner's-rights procedure calling `DATA_AGENT_RUN`, bound to the supervisor as a `generic` tool.

**Presenter Notes:**
- The cost-control heart is here: the Scoring agent runs `llama3.1-8b` and escalates to `mistral-large2` only when confidence is low; every decision is written to `ROUTING_LOG`. A hard `orchestration.budget` (tokens/seconds) caps each run.
- Custom-tool contract gotcha: the bound procedure MUST return a single cell (1 row × 1 col). The wrappers return a STRING; the scoring proc returns a VARIANT object — both are single cells. A `RETURNS TABLE` proc or UDTF fails here.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/data_agent_run-snowflake-cortex
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-manage

---

## Slide 6: Targeted analysis — the AI_FILTER gate

**Talking Points:**
- The biggest cost lever is simply not scoring everything. `AI_FILTER` pre-selects the emails worth full treatment (generic, low-effort, no CTA) and skips the rest.
- In the lab this cuts treated volume ~26% versus analyze-all, with proportional credit savings — a number the buyer can map directly to their monthly bill.

**Presenter Notes:**
- `AI_FILTER(PROMPT('...{0}...', col))` returns a boolean per row; wrap in `COUNT_IF` to size the gate. It is itself an AI function, so keep the gate prompt cheap and the treated set is where the expensive work goes.
- Tie this back to the customer's "cost/budget" sensitivity — this is the slide budget owners remember.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_filter
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql

---

## Slide 7: CoWork — no external connector

**Talking Points:**
- Because the supervisor is a standard Cortex Agent, it appears automatically in Snowflake CoWork. Business users pick it and ask NL questions — zero connector setup, full in-plane governance.
- Contrast the two-column setup effort: external MCP connector (URL, client id/secret, OAuth, IP allow-lists) vs "pick the agent and ask."

**Presenter Notes:**
- Reassure the audience we are not throwing MCP away: you can add the supervisor to the MCP server as a `CORTEX_AGENT_RUN` tool so external clients still reach it — now governed in-plane.
- Good live moment: open CoWork, pick `GTM Supervisor`, ask "Which region and quality tier drive the highest win rate?"

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/integrate-tools

---

## Slide 8: Evals — measured, not assumed

**Talking Points:**
- Trust requires measurement. The harness computes scoring accuracy vs labels, run-to-run consistency, and predicted coached win-rate lift, persisting every run to `EVAL_RUNS`.
- Honesty sells: the cheap model's standalone accuracy is modest — which is exactly why we escalate and why evals belong in the pipeline.

**Presenter Notes:**
- Ground truth uses the unambiguous quality tiers (tier 3 = good, tier 1 = poor). Consistency is high because the model is deterministic at temperature 0.
- For a fully managed loop, register the scorer as a Cortex AI Function and use `EVALUATE_AI_FUNCTION` / `OPTIMIZE_AI_FUNCTION` to find the cheapest model that holds accuracy on the Pareto frontier — long-running, so run it live, not inline.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql

---

## Slide 9: Observability

**Talking Points:**
- This is the capability the external brain structurally cannot provide: every agent run emits server-side spans into `SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS` — tool calls, model, tokens, latency.
- The Streamlit command center turns those spans plus the logging tables into four operational views: Live Traces, Cost & Budget, Eval Dashboard, Recommendations.

**Presenter Notes:**
- Read events with `TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(db, schema, agent, 'CORTEX AGENT'))`. The role needs MONITOR on the agent + the `CORTEX_USER` database role; unredacted content needs a separate account privilege.
- Span names you will actually see include `ToolCall-ScoringSpecialist`, `SqlExecution`, and reasoning steps — point them out live to prove it is real, not mocked.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-monitor
- https://docs.snowflake.com/en/sql-reference/functions/get_ai_observability_events-snowflake-local

---

## Slide 10: Comparison

**Talking Points:**
- Put the two brains side by side across the dimensions the customer cares about: latency, cost model, budgets/quotas, chargeback/tagging, traces, and data egress.
- The latency and cost cells are sourced live from `REQUEST_LOG` and `COST_COMPARISON` — call that out so the room knows the badges are backed by data.

**Presenter Notes:**
- If asked "why is the external path slower?" — it pays a network hop to the client provider plus client-side LLM planning on every call; the in-plane path runs the same tools next to the data.
- The governance rows are the enterprise clincher: budgets, quotas, tagging, and server-side traces are native only when the brain is in-plane.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents
- https://docs.snowflake.com/en/sql-reference/account-usage/cortex_functions_usage_history

---

## Slide 11: When to use which

**Talking Points:**
- This is not "MCP is bad." Use the MCP server when users already live in an external client and you want governed tools with minimal setup.
- Use Cortex Agents + CoWork when you need orchestration, cost control, budgets, server-side traces, and business-user NL access. Use both by exposing the supervisor through the MCP server.

**Presenter Notes:**
- Decision signal is where the reasoning loop and the users live, not a feature checklist. Many customers land on "both."
- Reinforce the reuse story: one governed object set, two front doors.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork

---

## Slide 12: Next Steps

**Talking Points:**
- Give the audience the exact runway: setup.sql → gtm-01 → gtm-02 → gtm-03 → gtm-04 → deploy the Streamlit app.
- The strongest close is the live A/B: ask the same question in Claude (before) and CoWork (after) and let the latency, cost, and governance gap speak.

**Presenter Notes:**
- Best demo path: Snowsight → Projects → Workspaces → Create Workspace from Git repo, so `get_active_session()` works with no local auth. Deploy the app via Snowsight → Projects → Streamlit.
- Leave-behind message: the migration is not a rewrite; it is relocating the reasoning loop into the data plane, where cost, governance, and observability come for free.

**References:**
- https://docs.snowflake.com/en/user-guide/ui-snowsight/notebooks
- https://docs.snowflake.com/en/developer-guide/streamlit/about-streamlit
