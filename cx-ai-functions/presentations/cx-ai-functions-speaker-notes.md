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

**Internal Context:**
- Position Studio as the "optimization" chapter, not the starting point — don't lead with custom functions when a built-in exists.
- Great trust-builder: showing measured accuracy/cost trade-offs turns a hand-wave into evidence.

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

## Slide 13: Next Steps

**Talking Points:**
- Four concrete actions: run the lab, point the same SQL at real chat/call data, trend the telemetry in BI, and feed at-risk signals to churn.
- Close on the one-liner: CX telemetry is now a SQL query, not an ML project.

**Internal Context:**
- Natural bridge to the Conversational BI module — that demo consumes this telemetry inside a semantic view + agent.
- Leave-behind: this repo's deck + lab so champions can re-run it internally.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql
