# Speaker Notes: AI Functions — Customer Experience Telemetry

## Account Context Summary

Generic field-enablement scenario (synthetic, brand-free): a B2C + B2B home-valuation /
proptech company runs a customer-facing GPT chat assistant and a support line. A small,
fast-growing data team wants to understand which conversations are meaningful, what customers
ask about, and how they feel — without standing up ML infrastructure. This module shows how
Snowflake AI Functions convert raw chat threads and call transcripts into structured
customer-experience telemetry in SQL, and how AI Function Studio optimizes a custom function.
Pairs with the "Conversational BI" module, which analyzes this telemetry alongside churn/revenue.

---

## Slide 1: Overview

**Talking Points:**
- Frame the outcome first: raw conversations become sentiment + topic telemetry with functions you call in plain SQL.
- Emphasize the four stats — one SQL call from text to sentiment, zero models to host, one pipeline for chat and voice, and it all runs governed next to your data.
- This is not a data-science project; it's a query pattern any analyst on the team can own.

**Internal Context:**
- Audience is SEs/field. The hook that lands with small data teams is "no infra": no endpoints, no model hosting, no MLOps.
- Requires the `SNOWFLAKE.CORTEX_USER` database role. Call that out early so the lab doesn't stall on privileges.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql-privileges-and-access

---

## Slide 2: The Problem

**Talking Points:**
- Walk the four cards: volume of conversations, no structured read, buried churn signals, and ML being too heavy for a small team.
- Land the warning box: the richest CX signal is unstructured and invisible to analytics today.

**Internal Context:**
- This is the emotional hook — let the customer name their own version of "we can't read all of it." Most have exactly this pain.
- Competitive angle: alternatives require exporting text to a third-party NLP/LLM service, which raises data-movement and governance objections that Snowflake avoids.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql

---

## Slide 3: Architecture

**Talking Points:**
- Orient the room before the function-by-function detail: three text sources (CHAT_THREADS, CALL_TRANSCRIPTS, SUPPORT_TICKETS) flow through one AI Functions layer and land back as enriched CX telemetry columns in the warehouse.
- The built-in functions handle the common cases; AI Function Studio covers custom AI_COMPLETE functions in the same layer.
- Call out the downstream arrow: that enriched telemetry is exactly what the Conversational BI module's semantic view and agent consume.

**Internal Context:**
- This is the "text in, governed telemetry out, no models to deploy" mental model — every later slide fills in one function in this diagram.
- The last box (Conversational BI) is the cross-module bridge; use it to set up the paired demo without diving in yet.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-function-studio

---

## Slide 4: The Pipeline

**Talking Points:**
- Show the shape before the detail: ingest → sentiment → topics → extract → themes → at-risk.
- Each step is a single AI Function over a conversation table; the output is a governed telemetry table.

**Internal Context:**
- Set expectations: functions run row-by-row (AI_SENTIMENT/CLASSIFY/EXTRACT/FILTER) except the aggregate functions (AI_AGG/AI_SUMMARIZE_AGG), which are set-based.
- Recommend a warehouse no larger than MEDIUM for AI functions — larger doesn't speed them up and just costs more.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql

---

## Slide 5: Sentiment

**Talking Points:**
- `AI_SENTIMENT(text[, categories])` returns overall sentiment plus per-category (aspect) sentiment in one call.
- Categories are the "aspects" you care about — valuation accuracy, pricing, onboarding — up to ten.

**Internal Context:**
- Returns an OBJECT; parse with `:categories`. Each category is positive/negative/neutral/mixed/unknown ("unknown" = not mentioned).
- It's the successor to `ENTITY_SENTIMENT`. Supports several languages; categories can be given in English regardless of text language.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_sentiment

---

## Slide 6: Topic Modeling

**Talking Points:**
- `AI_CLASSIFY(input, categories[, config])` maps each conversation to your support taxonomy; `:labels` holds the result.
- Use `output_mode: 'multi'` when a thread spans topics; add label descriptions and few-shot examples to raise accuracy.

**Internal Context:**
- This is "supervised" topic modeling — you supply the categories. For emergent/unknown themes, pair with AI_AGG on the next slides ("unsupervised" discovery).
- Keep categories mutually exclusive and descriptive; >~20 categories starts degrading accuracy. Labels are case-sensitive.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_classify

---

## Slide 7: Extraction

**Talking Points:**
- `AI_EXTRACT(text => ..., responseFormat => {...})` pulls named fields from free text; result is under `:response`.
- Ask one clear question per field, in plain English.

**Internal Context:**
- Same function extracts from documents via `file => TO_FILE(...)` — good expansion story into invoices/contracts later.
- Optional `scores => TRUE` returns confidence per field for human-in-the-loop thresholds. Client-side encrypted stages are not supported.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_extract

---

## Slide 8: Theme Discovery

**Talking Points:**
- `AI_AGG(expr, instruction)` reduces a whole column of text with a natural-language instruction; `AI_SUMMARIZE_AGG(expr)` gives a general summary.
- Both support `GROUP BY`, so you get per-topic or per-segment themes.

**Internal Context:**
- Key differentiator: these handle datasets larger than the model context window and are optimized for set-based aggregation (roughly 2x AI_COMPLETE throughput at scale).
- This is the "unsupervised topic modeling" answer to the customer's ask — surface dominant themes without predefining them.
- Give a declarative instruction ("Summarize the complaints"), not a question ("Can you summarize?").

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_agg
- https://docs.snowflake.com/en/sql-reference/functions/ai_summarize_agg

---

## Slide 9: At-Risk Detection

**Talking Points:**
- `AI_FILTER` evaluates a natural-language predicate and returns BOOLEAN, so it drops straight into `WHERE`.
- Concatenate an instruction with the transcript to flag frustration / cancellation intent.

**Internal Context:**
- The revenue move: join survivors to billing/MRR so the CX team prioritizes saves by dollar value, not just recency.
- NULLs on unprocessable rows won't fail the query — mention error-handling behavior if asked.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_filter

---

## Slide 10: Voice & Calls

**Talking Points:**
- `AI_TRANSCRIBE(TO_FILE(...))` turns call recordings into text; from there it's the exact same sentiment/topic/filter pipeline.
- Chat, in-app, and phone converge into one telemetry table.

**Internal Context:**
- In the lab, `CALL_TRANSCRIPTS` is shipped as text so nobody needs to stage audio — call this out so the audience isn't confused about the transcribe step.
- Good place to note multimodal reach: the same AI-function family also covers images and documents.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_transcribe

---

## Slide 11: AI Function Studio

**Talking Points:**
- Built-ins cover most CX telemetry. When the customer needs a domain-specific label or scoring rubric, build a custom function on `AI_COMPLETE` and tune it in AI Function Studio.
- Studio lets you compare prompts and models on a labeled sample and review accuracy vs cost before productionizing.
- The lab builds a concrete example: `ROUTE_ESCALATION`, a custom function that labels each conversation LOW / MEDIUM / HIGH escalation priority.

**How to demo it (two ways):**
- **Snowsight UI (best for a room):** Snowsight → **AI & ML → Cortex AI Function Studio**. (1) **Create** — pick model `llama3.1-8b`, paste the escalation rubric as the system prompt, `{TRANSCRIPT}` as the input; (2) **Evaluate** — select the `ESCALATION_EVAL` labeled table, metric `exact_match`, show the baseline score and the per-row failure list; (3) **Optimize** — add `mistral-large2` and `claude-sonnet-4-6`, run, and land on the **accuracy-vs-cost Pareto chart** — "same task, cheaper model, equal accuracy."
- **SQL / notebook (repeatable):** Section 8 of the lab runs the exact same three stored procedures (`CREATE_AI_FUNCTION` → `EVALUATE_AI_FUNCTION` → `OPTIMIZE_AI_FUNCTION`). The function created in SQL also shows up in the Studio UI, so you can start in the notebook and finish in the UI.
- Pre-built for you in this account: `FIELD_CX_DEMO.AI_FUNCTIONS.ROUTE_ESCALATION` + `ESCALATION_EVAL` (24 labeled rows). Baseline `exact_match` = **0.96** (23/24) on `llama3.1-8b`.

**Internal Context:**
- Position Studio as the "optimization" chapter, not the starting point — don't lead with custom functions when a built-in exists.
- Great trust-builder: showing measured accuracy/cost trade-offs turns a hand-wave into evidence.
- Optimize runs 10+ minutes — run it live only if you can talk through the Pareto concept while it works, otherwise run it beforehand and show the stored results (`SHOW RUN METRICS`).
- The baseline is already high (0.96) because the sample transcripts are clear-cut — pivot the story to **cost**: can a cheaper model match it? That's the Pareto payoff.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-function-studio
- https://docs.snowflake.com/en/sql-reference/functions/ai_complete

---

## Slide 12: Built-in vs Custom

**Talking Points:**
- Use the table as a cheat sheet: match each CX need to the right function, and reserve Studio for custom labels/rubrics.

**Internal Context:**
- If asked "why not just one AI_COMPLETE prompt for everything?": the purpose-built functions are cheaper, more accurate, and simpler to maintain; aggregates also bypass context-window limits.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql

---

## Slide 13: Where AI functions plug in

**Talking Points:**
- Reframe AI functions as reusable building blocks, not a dead-end SQL feature: build a label once as a UDF, reuse it three ways.
- **Agent custom tool** — an AI-function UDF (e.g. `CLASSIFY_ESCALATION`) is registered as a *generic tool* in a Cortex Agent spec; the agent's LLM calls it via tool-use when the question needs it.
- **Inside Cortex Analyst** — the UDF becomes a computed column in a semantic view, so a business user's natural-language question returns AI-derived labels transparently.
- **Cortex Search enrichment** — `AI_EXTRACT` / `AI_EMBED` pre-process documents (structured fields + embeddings) before indexing, and expose filterable attributes.

**Internal Context:**
- This slide bridges the CX telemetry story to the broader Cortex stack; it sets up the extensions notebook (`cx-ai-functions-extensions.ipynb`).
- The cost caveat matters: a view re-runs inference on every query — recommend materializing the column (task or Dynamic Table) for interactive Analyst/agent use so inference runs once per row.
- Tool-use bills twice — the agent's orchestration tokens plus the UDF's inference tokens; tie this back to the estimator slide.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview

---

## Slide 14: Cost & Usage

**Talking Points:**
- Set the mental model: AI Functions bill by **tokens processed** (input + output), or pages for document functions — not by warehouse size. A row-wise function over 1M rows is ~1M model calls.
- Name the runaway causes directly: running a row-wise function over a full 1M+ row table with no `WHERE`/`LIMIT`, verbose prompts, and oversized models.
- Walk the monitoring query: `SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY` is the single source of truth for credits by function, model, user, and query (2-5 min latency).
- Land the best-practices box: prototype on a sampled/`LIMIT` subset, pre-filter rows, pick the smallest model that passes eval, keep prompts tight, prefer aggregates at scale, and don't oversize the warehouse.

**Internal Context:**
- This is the slide that answers the #1 field objection: "customers burn money running functions on 1M+ rows without knowing." Say that out loud — it builds trust.
- The warehouse point is counter-intuitive and worth repeating: a bigger warehouse does NOT speed AI functions up; it only adds compute cost on top of token cost. MEDIUM is plenty.
- `QUERY_TAG` is the cheap win for chargeback — encourage teams to tag AI workloads by project.
- `CORTEX_AI_FUNCTIONS_USAGE_HISTORY` requires access to the SNOWFLAKE database (IMPORTED PRIVILEGES / ACCOUNTADMIN). Flag that so the query doesn't stall in the demo.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-func-cost-management
- https://docs.snowflake.com/en/sql-reference/account-usage/cortex_ai_functions_usage_history

---

## Slide 15: Estimate cost before you run

**Talking Points:**
- The headline: you can price a full-table run *before* launching it — no need to run it and find out.
- `AI_COUNT_TOKENS('<function>', input)` returns the tokens a specific function will process (including its prompt template); `SNOWFLAKE.CORTEX.COUNT_TOKENS('<model>', text)` counts raw input-text tokens per model. Both are free and never invoke the model.
- Chain it: tokens → credits (× model's credits-per-million rate from the Service Consumption Table) → dollars (× your $/credit).
- Then reconcile against reality: back out the true credits-per-token from `CORTEX_FUNCTIONS_QUERY_USAGE_HISTORY` (it records TOKENS and TOKEN_CREDITS per query) and apply it to the full-table estimate.
- The lab's Section 9 has a reusable `estimate_cost()` helper — plug in any table/column/model.

**Internal Context:**
- This is the proactive companion to the cost slide: instead of monitoring spend after the fact, you forecast it. Lands well with FinOps-minded buyers.
- Emphasize the ~13x model cost swing on the same data — model selection is the biggest lever, and the estimator quantifies it before you commit.
- `CORTEX_FUNCTIONS_QUERY_USAGE_HISTORY` lags (a few hours) and is empty on a fresh account — the notebook's estimator degrades gracefully and falls back to the rate table. Say this so a live run in a clean demo account doesn't look broken.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_count_tokens
- https://docs.snowflake.com/en/sql-reference/account-usage/cortex_functions_query_usage_history
- https://www.snowflake.com/legal-files/CreditConsumptionTable.pdf

---

## Slide 16: Guardrails & Quotas

**Talking Points:**
- Lead with **per-user quotas**: a first-class `SNOWFLAKE.CORE.QUOTA` object that enforces monthly/daily per-user credit limits and **auto-blocks** AI requests at the limit — no custom tasks, no scheduling.
- Emphasize the block behavior: enforcement evaluates within minutes, denies new AI requests with a clear "quota exhausted" error, and even terminates in-progress AI function calls; blocks clear automatically at the cycle reset.
- Show the two backup layers: an hourly `ALERT` on the usage view that emails admins on threshold breach, and a task that detects + cancels runaway queries.
- Show the manual escape hatch: `SELECT SYSTEM$CANCEL_QUERY('<query_id>')` kills a specific long-running query immediately.
- Note access control: revoke `SNOWFLAKE.CORTEX_USER` from `PUBLIC` and grant it via a dedicated role so limits can't be bypassed.

**Internal Context:**
- Quotas are the headline — they're the newest, cleanest answer and they auto-block. The alert + cancel-task pattern from the cost-management doc is the belt-and-suspenders story for accounts that want custom logic.
- Quota block enforcement covers AI domains only (AI functions, Cortex Agents, Snowflake CoWork, CoCo), not warehouse spend. Track warehouse spend in a separate quota.
- Cancelling a query stops further cost but does NOT refund credits already consumed — say this so nobody thinks cancel = free.
- Killing/cancelling and quotas require elevated privileges (OPERATE on the warehouse for cancel; ACCOUNTADMIN or a `QUOTA_CREATOR` custom role for quotas). Frame these as admin/governance setup, not analyst steps.

**References:**
- https://docs.snowflake.com/en/user-guide/budgets/per-user-quotas
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-func-cost-management
- https://docs.snowflake.com/en/sql-reference/functions/system_cancel_query

---

## Slide 17: Next Steps

**Talking Points:**
- Four concrete actions: run the lab, point the same SQL at real chat/call data, trend the telemetry in BI, and feed at-risk signals to churn.
- Close on the one-liner: CX telemetry is now a SQL query, not an ML project.

**Internal Context:**
- Before you leave, remind the room of the guardrails: quotas + alerts + cancel mean they can turn analysts loose without budget fear.
- Natural bridge to the Conversational BI module — that demo consumes this telemetry inside a semantic view + agent.
- Leave-behind: this repo's deck + lab so champions can re-run it internally.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql
