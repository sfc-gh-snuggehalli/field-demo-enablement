# Speaker Notes: Proactive Retail Intelligence with Snowflake Cortex

## Account Context Summary

Scenario: a multi-tenant retail analytics SaaS provider ingests point-of-sale and
returns/refunds data from several retail chains and sells them an embedded, in-app
assistant. The assistant today is **reactive** — it answers when a user asks. This deck
walks the architecture for making it **proactive**: it leads with unprompted, explained
observations ("return rates at three Midwest stores spiked overnight, here's why, here are
the next steps") and still answers ad-hoc questions on live account data — while keeping
the language model off the critical path for detection so cost scales with what's
*interesting*, not what's *stored*.

The demo objects live in `PROACTIVE_RETAIL_DEMO` (schemas `RAW` and `ANALYTICS`) on the
`PROACTIVE_RETAIL_WH` warehouse. Retailer names and stores are fictional personas. Run
`lab/setup.sql` first; the notebook builds the custom tool and the agent.

---

## Slide 1: Hero

**Talking Points:**
- Frame the shift: today's embedded assistant is reactive — it only answers when prompted. We want it to *lead* with observations and still converse.
- The four numbers set up the whole story: zero LLM calls to detect an anomaly, three Cortex layers (ML functions, Analyst, Agent), the LLM only ever reads one flagged slice, and Claude runs natively inside Cortex (no data leaves Snowflake).
- Promise the payoff up front: proactive *and* cheap are not in tension here.

**Presenter Notes:**
- Audience is data & analytics engineering and product leaders evaluating how to adopt Cortex without an open-ended inference bill.
- This is a starting point for a technical discussion, not a finished product — say so. The architecture is the deliverable.
- If asked "why not just use an LLM to watch everything?" — hold that; it's slide 10.

**References:**
- https://docs.snowflake.com/en/guides-overview-ai-features
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/overview

---

## Slide 2: The Problem

**Talking Points:**
- Four concrete pains: (1) the user has to already suspect something; (2) "scan everything with an LLM" doesn't scale in cost or latency; (3) threshold alerts fire without the "why"; (4) answers must reflect *this account's* live data, not a generic model's guess.
- The warning box states the goal in one sentence — lead with an explained observation, still answer anything ad-hoc, and keep the LLM on the small interesting slice.

**Presenter Notes:**
- Tie each pain to a later slide: detection → slide 4, the "why" → slide 5, live ad-hoc → slide 6, cost → slide 10.
- Common question: "Isn't a BI alert enough?" — alerts tell you a number moved; they don't attribute the move or converse about next steps.

**References:**
- https://docs.snowflake.com/en/user-guide/ml-functions/anomaly-detection
- https://docs.snowflake.com/en/user-guide/alerts

---

## Slide 3: Architecture

**Talking Points:**
- This is the centerpiece. Read it bottom-up: sources (store metrics, returns, reason text) → in-warehouse ML (ANOMALY_DETECTION, TOP_INSIGHTS) → serving objects (semantic view, Cortex Search, a custom briefing tool) → the Cortex Agent that narrates.
- The key architectural decision: detection and explanation happen in SQL on a schedule and precompute a *small* findings table. The agent orchestrates the tools; the language model reads only the flagged slice.
- Everything is one data plane — no copy of the estate, no external model endpoint.

**Presenter Notes:**
- Spend the most time here. If someone remembers one slide, make it this one.
- Clarify object placement: the ML models, findings/drivers tables, semantic view, and Search service are created in `setup.sql`; the custom tool and the agent are created in the notebook (they depend on the findings table already existing).
- "Where does Claude run?" — natively in Cortex; the agent's orchestration model is set to `auto`.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/build-agents
- https://docs.snowflake.com/en/user-guide/views-semantic/overview

---

## Slide 4: Proactive Scan

**Talking Points:**
- `SNOWFLAKE.ML.ANOMALY_DETECTION` trains one model across *every store's* return-rate series (multi-series via `SERIES_COLNAME`). No per-store modeling by hand.
- `DETECT_ANOMALIES` runs on the recent window and writes a compact findings table. A scheduled `TASK` re-runs it hourly — that's the proactive engine.
- Emphasize: no tokens were spent to find the anomaly. This is set-based SQL.

**Presenter Notes:**
- Training timestamps must be strictly earlier than the detection window — the lab splits at 14 days and detects on the recent window; the injected spike is in the last 10 days.
- Training the model takes ~1–2 minutes on MEDIUM; mention this so a live run doesn't feel stalled.
- A Cortex Alert is a valid alternative to a Task for firing on new findings — worth naming.

**References:**
- https://docs.snowflake.com/en/user-guide/ml-functions/anomaly-detection
- https://docs.snowflake.com/en/user-guide/tasks-intro

---

## Slide 5: The "Why"

**Talking Points:**
- Detection tells you *that* something moved; `SNOWFLAKE.ML.TOP_INSIGHTS` tells you *why*.
- We label the recent window as the test group and the prior baseline as control, set the metric to refunded dollars, and `GET_DRIVERS` ranks the dimension combinations driving the difference.
- The drivers (Electronics; stores 1003/1017/1042; Lakeshore Metro) are exactly the phrase the assistant needs: "concentrated in Electronics across three Midwest stores."

**Presenter Notes:**
- Cast `store_id` to STRING in the input view so Top Insights treats it as categorical, not continuous.
- `GET_DRIVERS` is called with `CALL`; capture the output via `RESULT_SCAN(LAST_QUERY_ID())` to persist it. This is done in setup so the agent can read a table, not re-run the call.
- This is contribution/key-driver analysis, not causal inference — say "drivers/associations," not "causes."

**References:**
- https://docs.snowflake.com/en/user-guide/ml-functions/top-insights
- https://docs.snowflake.com/en/sql-reference/functions/result_scan

---

## Slide 6: Ad-Hoc on Live Data

**Talking Points:**
- The proactive briefing is half the story; managers also ask follow-ups. A semantic view exposes the same tables as a governed model Cortex Analyst can query in natural language.
- "I'm visiting Store 1042 — what should I focus on?" compiles into governed SQL over the semantic view. Numbers are real; definitions (total refund, return rate) are defined once and reused.

**Presenter Notes:**
- The semantic view is a first-class schema object with its own privileges — grant `REFERENCES, SELECT` to the agent's role.
- Metrics/dimensions and synonyms in the view are what make Analyst accurate; point at the `COMMENT`s and `WITH SYNONYMS` in setup.sql.
- Add verified queries later to raise accuracy on the common questions.

**References:**
- https://docs.snowflake.com/en/user-guide/views-semantic/sql
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst

---

## Slide 7: Tool Orchestration

**Talking Points:**
- One agent, four tools: the custom briefing tool (`generic`), Cortex Analyst (`cortex_analyst_text_to_sql`), Cortex Search (`cortex_search`), and `data_to_chart`.
- The orchestration model (set to `auto`) reads the user's intent and picks the tool: briefing for "what changed," Analyst for store metrics, Search for reason text.
- The orchestration instruction is where you encode that routing — this is a big part of the optimization pass in the lab.

**Presenter Notes:**
- The custom tool must return a **single cell** (a JSON string), not a table, and its function must be granted USAGE to the agent's role and bound in the Snowsight agent UI.
- Tool *descriptions* are load-bearing: the agent chooses tools from them. The lab's optimized version rewrites these to say what each tool does, what data it reads, and when *not* to use it.
- `data_to_chart` needs no resources — it's a built-in.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/build-agents
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-manage

---

## Slide 8: Two Assistant Flows

**Talking Points:**
- Proactive flow: scheduled scan → precomputed findings + drivers → the briefing tool reads that small table → the agent narrates the unprompted observation with next steps.
- Reactive flow: the manager's follow-up routes to Analyst over the semantic view and answers from live data, optionally charted.
- Same agent object serves both. The bottom pipeline shows the proactive path end to end.

**Presenter Notes:**
- This slide answers "so what does the user actually see?" — walk it as a story: app opens → briefing appears → user asks a follow-up → live answer.
- Both flows share governance and definitions; the proactive layer is additive.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/overview
- https://docs.snowflake.com/en/user-guide/ml-functions/top-insights

---

## Slide 9: Snowflake CoWork

**Talking Points:**
- The same agent object surfaces in Snowflake CoWork for interactive chat (Snowsight → AI & ML → Agents) — no separate UI to build for internal exploration.
- For the embedded product, call the identical agent over the REST `agent:run` endpoint and stream the answer into the app's own chat surface.
- One agent definition, two delivery surfaces.

**Presenter Notes:**
- This is the demo's high point — end the live portion in the Agents UI chatting with the agent, then show the REST call as the embed path.
- `agent:run` authenticates with a PAT / OAuth token; a thread maintains conversation context across turns.
- CoWork auto-surfaces the agent's tools; you don't wire a bespoke UI for internal users.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-manage
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-rest-api

---

## Slide 10: Cost Control

**Talking Points:**
- The anti-pattern: send every store, every day, to an LLM on a schedule. Cost scales with the whole estate, latency grows, and most input is noise.
- This pattern: set-based ML functions scan every store in-warehouse; the LLM only reads the handful of flagged rows and their drivers. Token cost scales with what's interesting.
- The table makes it concrete across detection cost, freshness, explainability, and tokens per briefing.

**Presenter Notes:**
- This is the slide that answers the "why not just use an LLM for everything?" objection — hold it until here for maximum effect.
- Detection is a fixed warehouse cost regardless of estate size (set-based), decoupled from token pricing.
- Keep the framing honest: the LLM is still essential — for narration and conversation, not for scanning.

**References:**
- https://docs.snowflake.com/en/user-guide/ml-functions/anomaly-detection
- https://www.snowflake.com/legal-files/CreditConsumptionTable.pdf

---

## Slide 11: Reactive vs Proactive

**Talking Points:**
- Side-by-side of today's assistant vs. this build across five capabilities: surfacing issues unprompted, explaining the driver, live-data answers, the cost of always watching, and interactive + embedded delivery.
- The context box lands the close: same data, same governance, one agent object — the proactive layer is additive.

**Presenter Notes:**
- Use this to summarize before Next Steps; it maps directly to the earlier problem slide.
- If the customer already has a reactive assistant, this is the "incremental adoption" slide — nothing gets rebuilt, the proactive layer is added alongside.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/build-agents
- https://docs.snowflake.com/en/user-guide/views-semantic/overview

---

## Slide 12: Next Steps

**Talking Points:**
- Four actions: (1) run the lab; (2) point it at real returns/store-metrics data — only the ML functions and semantic view change; (3) schedule the scan (Task or Cortex Alert) so findings stay fresh; (4) embed the agent via `agent:run` and use CoWork for internal exploration.
- Closing line: detect and explain cheaply in the warehouse; let the language model narrate and converse over the slice that already matters.

**Presenter Notes:**
- The lab's optimization step (5b) is required — walk the before/after agent specs in `agent_optimization/` so the audience sees tuned tool descriptions and orchestration instructions.
- Recommend running the lab via Snowsight Workspaces from Git so `get_active_session()` works with no local auth.
- Leave them with the repo link and offer to scope a pilot against one real data feed.

**References:**
- https://docs.snowflake.com/en/user-guide/ui-snowsight/workspaces
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-manage
