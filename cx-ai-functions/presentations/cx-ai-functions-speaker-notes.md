# Speaker Notes: AI Functions — Customer Experience Telemetry

## Account Context Summary

Generic demo scenario (synthetic, brand-free): a B2C + B2B home-valuation /
proptech company runs a customer-facing GPT chat assistant and a support line. A small,
fast-growing data team wants to understand which conversations are meaningful, what customers
ask about, and how they feel — without standing up ML infrastructure. This module shows how
Snowflake AI Functions convert raw chat threads and call transcripts into structured
customer-experience telemetry in SQL, and how AI Function Studio optimizes a custom function.
Governed metrics (semantic view + Cortex Agent) and app UX telemetry ingestion are part of this
same module — the second notebook and the Governed Metrics / CX Agent slides.

---

## Slide 1: Overview

**Talking Points:**
- Frame the outcome first: raw conversations become sentiment + topic telemetry with functions you call in plain SQL.
- Emphasize the four stats — one SQL call from text to sentiment, zero models to host, one pipeline for chat and voice, and it all runs governed next to your data.
- This is not a data-science project; it's a query pattern any analyst on the team can own.

**Presenter Notes:**
- The hook that lands with small data teams is "no infra": no endpoints, no model hosting, no MLOps.
- Requires the `SNOWFLAKE.CORTEX_USER` database role. Call that out early so the lab doesn't stall on privileges.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql-privileges-and-access

---

## Slide 2: The Problem

**Talking Points:**
- Walk the four cards: volume of conversations, no structured read, buried churn signals, and ML being too heavy for a small team.
- Land the warning box: the richest CX signal is unstructured and invisible to analytics today.

**Presenter Notes:**
- This is the emotional hook — let the customer name their own version of "we can't read all of it." Most have exactly this pain.
- Note the contrast: alternatives require exporting text to a third-party NLP/LLM service, which raises data-movement and governance concerns that Snowflake avoids.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql

---

## Slide 3: Architecture

**Talking Points:**
- Orient the room before the function-by-function detail: three text sources (CHAT_THREADS, CALL_TRANSCRIPTS, SUPPORT_TICKETS) flow through one AI Functions layer and land back as enriched CX telemetry columns in the warehouse.
- The built-in functions handle the common cases; AI Function Studio covers custom AI_COMPLETE functions in the same layer.
- Call out both ends: app UX telemetry (chat + thumbs up/down) feeds in at the top via a stage, and the enriched telemetry at the bottom is exactly what the semantic view and agent (later in this deck) consume.

**Presenter Notes:**
- This is the "text in, governed telemetry out, no models to deploy" mental model — every later slide fills in one function in this diagram.
- The semantic view + Analyst + agent are now part of this same module (the old Conversational-BI module folded in); use the last box to tee up the Governed Metrics and CX Agent slides later.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-function-studio

---

## Slide 4: The Pipeline

**Talking Points:**
- Show the shape before the detail: ingest → sentiment → topics → extract → themes → at-risk.
- Each step is a single AI Function over a conversation table; the output is a governed telemetry table.

**Presenter Notes:**
- Set expectations: functions run row-by-row (AI_SENTIMENT/CLASSIFY/EXTRACT/FILTER) except the aggregate functions (AI_AGG/AI_SUMMARIZE_AGG), which are set-based.
- Recommend a warehouse no larger than MEDIUM for AI functions — larger doesn't speed them up and just costs more.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql

---

## Slide 5: App UX Telemetry

**Talking Points:**
- This answers the most common question: "how does my app's data actually get into Snowflake?" Chat threads and thumbs up/down land as JSON in a stage, then flow to curated tables.
- Two patterns, both shown live: raw `VARIANT` landing (`COPY INTO`, schema-on-read) and curated typed tables (`LATERAL FLATTEN`). Raw is the durable landing zone; curated is what you serve.
- In production the manual `COPY` becomes Snowpipe or Snowpipe Streaming; the FLATTEN can be a Dynamic Table or Task.

**Presenter Notes:**
- The customer points their own app at the stage with this JSON shape and nothing downstream changes — that's the reusable-template message.
- Thumbs up/down rolls up to `ANALYTICS.CUSTOMER_FEEDBACK`, which the semantic view exposes as `thumbs_down_rate` — connecting app UX to a governed metric the agent can answer.

**References:**
- https://docs.snowflake.com/en/user-guide/data-load-overview
- https://docs.snowflake.com/en/user-guide/data-load-snowpipe-streaming-overview

---

## Slide 6: Sentiment

**Talking Points:**
- `AI_SENTIMENT(text[, categories])` returns overall sentiment plus per-category (aspect) sentiment in one call.
- Categories are the "aspects" you care about — valuation accuracy, pricing, onboarding — up to ten.

**Presenter Notes:**
- Returns an OBJECT; parse with `:categories`. Each category is positive/negative/neutral/mixed/unknown ("unknown" = not mentioned).
- It's the successor to `ENTITY_SENTIMENT`. Supports several languages; categories can be given in English regardless of text language.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_sentiment

---

## Slide 7: Topic Modeling

**Talking Points:**
- `AI_CLASSIFY(input, categories[, config])` maps each conversation to your support taxonomy; `:labels` holds the result.
- Use `output_mode: 'multi'` when a thread spans topics; add label descriptions and few-shot examples to raise accuracy.

**Presenter Notes:**
- This is "supervised" topic modeling — you supply the categories. For emergent/unknown themes, pair with AI_AGG on the next slides ("unsupervised" discovery).
- Keep categories mutually exclusive and descriptive; >~20 categories starts degrading accuracy. Labels are case-sensitive.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_classify

---

## Slide 8: Extraction

**Talking Points:**
- `AI_EXTRACT(text => ..., responseFormat => {...})` pulls named fields from free text; result is under `:response`.
- Ask one clear question per field, in plain English.

**Presenter Notes:**
- Same function extracts from documents via `file => TO_FILE(...)` — good expansion story into invoices/contracts later.
- Optional `scores => TRUE` returns confidence per field for human-in-the-loop thresholds. Client-side encrypted stages are not supported.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_extract

---

## Slide 9: Theme Discovery

**Talking Points:**
- `AI_AGG(expr, instruction)` reduces a whole column of text with a natural-language instruction; `AI_SUMMARIZE_AGG(expr)` gives a general summary.
- Both support `GROUP BY`, so you get per-topic or per-segment themes.

**Presenter Notes:**
- Key differentiator: these handle datasets larger than the model context window and are optimized for set-based aggregation (roughly 2x AI_COMPLETE throughput at scale).
- This is the "unsupervised topic modeling" answer to the customer's ask — surface dominant themes without predefining them.
- Give a declarative instruction ("Summarize the complaints"), not a question ("Can you summarize?").

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_agg
- https://docs.snowflake.com/en/sql-reference/functions/ai_summarize_agg

---

## Slide 10: At-Risk Detection

**Talking Points:**
- `AI_FILTER` evaluates a natural-language predicate and returns BOOLEAN, so it drops straight into `WHERE`.
- Concatenate an instruction with the transcript to flag frustration / cancellation intent.

**Presenter Notes:**
- The revenue move: join survivors to billing/MRR so the CX team prioritizes saves by dollar value, not just recency.
- NULLs on unprocessable rows won't fail the query — mention error-handling behavior if asked.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_filter

---

## Slide 11: Voice & Calls

**Talking Points:**
- `AI_TRANSCRIBE(TO_FILE(...))` turns call recordings into text; from there it's the exact same sentiment/topic/filter pipeline.
- Chat, in-app, and phone converge into one telemetry table.

**Presenter Notes:**
- In the lab, `CALL_TRANSCRIPTS` is shipped as text so nobody needs to stage audio — call this out so the audience isn't confused about the transcribe step.
- Good place to note multimodal reach: the same AI-function family also covers images and documents.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_transcribe

---

## Slide 12: AI Function Studio

**Talking Points:**
- Built-ins cover most CX telemetry. When the customer needs a domain-specific label or scoring rubric, build a custom function on `AI_COMPLETE` and tune it in AI Function Studio.
- Studio lets you compare prompts and models on a labeled sample and review accuracy vs cost before productionizing.
- The lab builds a concrete example: `ROUTE_ESCALATION`, a custom function that labels each conversation LOW / MEDIUM / HIGH escalation priority.

**How to demo it (two ways):**
- **Snowsight UI (best for a room):** Snowsight → **AI & ML → Cortex AI Function Studio**. (1) **Create** — pick model `llama3.1-8b`, paste the escalation rubric as the system prompt, `{TRANSCRIPT}` as the input; (2) **Evaluate** — select the `ESCALATION_EVAL` labeled table, metric `exact_match`, show the baseline score and the per-row failure list; (3) **Optimize** — add `mistral-large2` and `claude-sonnet-4-6`, run, and land on the **accuracy-vs-cost Pareto chart** — "same task, cheaper model, equal accuracy."
- **SQL / notebook (repeatable):** Section 8 of the lab runs the exact same three stored procedures (`CREATE_AI_FUNCTION` → `EVALUATE_AI_FUNCTION` → `OPTIMIZE_AI_FUNCTION`). The function created in SQL also shows up in the Studio UI, so you can start in the notebook and finish in the UI.
- Pre-built for you in this account: `FIELD_CX_DEMO.AI_FUNCTIONS.ROUTE_ESCALATION` + `ESCALATION_EVAL` (24 labeled rows). Baseline `exact_match` = **0.96** (23/24) on `llama3.1-8b`.

**Presenter Notes:**
- Position Studio as the "optimization" chapter, not the starting point — don't lead with custom functions when a built-in exists.
- Great trust-builder: showing measured accuracy/cost trade-offs turns a hand-wave into evidence.
- Optimize runs 10+ minutes — run it live only if you can talk through the Pareto concept while it works, otherwise run it beforehand and show the stored results (`SHOW RUN METRICS`).
- The baseline is already high (0.96) because the sample transcripts are clear-cut — pivot the story to **cost**: can a cheaper model match it? That's the Pareto payoff.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-function-studio
- https://docs.snowflake.com/en/sql-reference/functions/ai_complete

---

## Slide 13: Built-in vs Custom

**Talking Points:**
- Use the table as a cheat sheet: match each CX need to the right function, and reserve Studio for custom labels/rubrics.

**Presenter Notes:**
- If asked "why not just one AI_COMPLETE prompt for everything?": the purpose-built functions are cheaper, more accurate, and simpler to maintain; aggregates also bypass context-window limits.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql

---

## Slide 14: Where AI functions plug in

**Talking Points:**
- Reframe AI functions as reusable building blocks, not a dead-end SQL feature: build a label once as a UDF, reuse it three ways.
- **Agent custom tool** — an AI-function UDF (e.g. `CLASSIFY_ESCALATION`) is registered as a *generic tool* in a Cortex Agent spec; the agent's LLM calls it via tool-use when the question needs it.
- **Inside Cortex Analyst** — the UDF becomes a computed column in a semantic view, so a business user's natural-language question returns AI-derived labels transparently.
- **Cortex Search enrichment** — `AI_EXTRACT` / `AI_EMBED` pre-process documents (structured fields + embeddings) before indexing, and expose filterable attributes.

**Presenter Notes:**
- This slide bridges the CX telemetry story to the broader Cortex stack; it sets up the extensions notebook (`cx-ai-functions-extensions.ipynb`).
- The cost caveat matters: a view re-runs inference on every query — recommend materializing the column (task or Dynamic Table) for interactive Analyst/agent use so inference runs once per row.
- Tool-use bills twice — the agent's orchestration tokens plus the UDF's inference tokens; tie this back to the estimator slide.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview

---

## Slide 15: Governed metrics

**Talking Points:**
- One semantic view (`ANALYTICS.CX_ANALYTICS_SV`) defines churn, MRR, engagement, and the app-fed `thumbs_down_rate` once; `SEMANTIC_VIEW()` queries it with no JOINs.
- The same definition powers Cortex Analyst NL→SQL, the agent, and BI tools like Sigma — change it once, it changes everywhere.

**Presenter Notes:**
- `churn_rate` and `thumbs_down_rate` are derived metrics (scalar expressions of other metrics) — defined once, reused everywhere.
- This is the old Conversational-BI module folded in; the objects are created by setup.sql and queried live in the extensions notebook.

**References:**
- https://docs.snowflake.com/en/user-guide/views-semantic/overview
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst

---

## Slide 16: The CX Intelligence agent

**Talking Points:**
- One agent (`CX_INTELLIGENCE_AGENT`) combines Cortex Analyst (semantic view), Cortex Search (chat telemetry), and the escalation UDF tool.
- Ask "which churn-risk customers had negative support chats?" or "what's our thumbs-down rate by plan?" — the agent routes to the right tool automatically.

**Presenter Notes:**
- Analyst answers metric questions from the governed view; Search answers "what did customers say"; the UDF returns escalation urgency. Extend with more custom tools or MCP.
- Chat with it in Snowsight (AI & ML → Agents → "CX Intelligence"); the extensions notebook confirms it with SHOW AGENTS.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents

---

## Slide 17: Cost & Usage

**Talking Points:**
- Set the mental model: AI Functions bill by **tokens processed** (input + output), or pages for document functions — not by warehouse size. A row-wise function over 1M rows is ~1M model calls.
- Name the runaway causes directly: running a row-wise function over a full 1M+ row table with no `WHERE`/`LIMIT`, verbose prompts, and oversized models.
- Walk the monitoring query: `SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY` is the single source of truth for credits by function, model, user, and query (2-5 min latency).
- Land the best-practices box: prototype on a sampled/`LIMIT` subset, pre-filter rows, pick the smallest model that passes eval, keep prompts tight, prefer aggregates at scale, and don't oversize the warehouse.

**Presenter Notes:**
- This is the slide that addresses the most common concern: teams can burn credits running functions on 1M+ rows without realizing it. Name it directly to set the right expectation.
- The warehouse point is counter-intuitive and worth repeating: a bigger warehouse does NOT speed AI functions up; it only adds compute cost on top of token cost. MEDIUM is plenty.
- `QUERY_TAG` is the cheap win for chargeback — encourage teams to tag AI workloads by project.
- `CORTEX_AI_FUNCTIONS_USAGE_HISTORY` requires access to the SNOWFLAKE database (IMPORTED PRIVILEGES / ACCOUNTADMIN). Flag that so the query doesn't stall in the demo.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-func-cost-management
- https://docs.snowflake.com/en/sql-reference/account-usage/cortex_ai_functions_usage_history

---

## Slide 18: Estimate cost before you run

**Talking Points:**
- The headline: you can price a full-table run *before* launching it — no need to run it and find out.
- `AI_COUNT_TOKENS('<function>', input)` returns the tokens a specific function will process (including its prompt template); `SNOWFLAKE.CORTEX.COUNT_TOKENS('<model>', text)` counts raw input-text tokens per model. Both are free and never invoke the model.
- Chain it: tokens → credits (× model's credits-per-million rate from the Service Consumption Table) → dollars (× your $/credit).
- Then reconcile against reality: back out the true credits-per-token from `CORTEX_FUNCTIONS_QUERY_USAGE_HISTORY` (it records TOKENS and TOKEN_CREDITS per query) and apply it to the full-table estimate.
- The lab's Section 9 has a reusable `estimate_cost()` helper — plug in any table/column/model.

**Presenter Notes:**
- This is the proactive companion to the cost slide: instead of monitoring spend after the fact, you forecast it. Useful for FinOps-minded stakeholders.
- Emphasize the ~13x model cost swing on the same data — model selection is the biggest lever, and the estimator quantifies it before you commit.
- `CORTEX_FUNCTIONS_QUERY_USAGE_HISTORY` lags (a few hours) and is empty on a fresh account — the notebook's estimator degrades gracefully and falls back to the rate table. Say this so a live run in a clean demo account doesn't look broken.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_count_tokens
- https://docs.snowflake.com/en/sql-reference/account-usage/cortex_functions_query_usage_history
- https://www.snowflake.com/legal-files/CreditConsumptionTable.pdf

---

## Slide 19: Guardrails & Quotas

**Talking Points:**
- Lead with **per-user quotas**: a first-class `SNOWFLAKE.CORE.QUOTA` object that enforces monthly/daily per-user credit limits and **auto-blocks** AI requests at the limit — no custom tasks, no scheduling.
- Emphasize the block behavior: enforcement evaluates within minutes, denies new AI requests with a clear "quota exhausted" error, and even terminates in-progress AI function calls; blocks clear automatically at the cycle reset.
- Show the two backup layers: an hourly `ALERT` on the usage view that emails admins on threshold breach, and a task that detects + cancels runaway queries.
- Show the manual escape hatch: `SELECT SYSTEM$CANCEL_QUERY('<query_id>')` kills a specific long-running query immediately.
- Note access control: revoke `SNOWFLAKE.CORTEX_USER` from `PUBLIC` and grant it via a dedicated role so limits can't be bypassed.

**Presenter Notes:**
- Quotas are the headline — they're the newest, cleanest answer and they auto-block. The alert + cancel-task pattern from the cost-management doc is the belt-and-suspenders story for accounts that want custom logic.
- Quota block enforcement covers AI domains only (AI functions, Cortex Agents, Snowflake CoWork, CoCo), not warehouse spend. Track warehouse spend in a separate quota.
- Cancelling a query stops further cost but does NOT refund credits already consumed — say this so nobody thinks cancel = free.
- Killing/cancelling and quotas require elevated privileges (OPERATE on the warehouse for cancel; ACCOUNTADMIN or a `QUOTA_CREATOR` custom role for quotas). Frame these as admin/governance setup, not analyst steps.

**References:**
- https://docs.snowflake.com/en/user-guide/budgets/per-user-quotas
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-func-cost-management
- https://docs.snowflake.com/en/sql-reference/functions/system_cancel_query

---

## Slide 20: Next Steps

**Talking Points:**
- Four concrete actions: run the lab, point the same SQL at real chat/call data, trend the telemetry in BI, and feed at-risk signals to churn.
- Close on the one-liner: CX telemetry is now a SQL query, not an ML project.

**Presenter Notes:**
- Before you leave, remind the room of the guardrails: quotas + alerts + cancel mean they can turn analysts loose without budget fear.
- Natural bridge to the second notebook (extensions), where the semantic view + agent analyze this telemetry alongside churn/revenue — same module, runs live.
- Leave-behind: this repo's deck + lab so the team can re-run it themselves.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql
