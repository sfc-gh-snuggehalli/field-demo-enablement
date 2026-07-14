# AI Functions: Customer Experience Telemetry

[View Presentation](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/cx-ai-functions/presentations/cx-ai-functions.html)

Turn raw chat threads, call transcripts, and support tickets into structured sentiment
and topic telemetry — entirely in SQL with Snowflake AI Functions, no ML infrastructure —
then govern it with a semantic view and a Cortex Agent. Built around a generic B2C + B2B
home-valuation (proptech) scenario: a customer-facing GPT assistant and support line generate
thousands of conversations a day, and the team needs to know what customers ask about, how
they feel, and who is at risk of churning.

This module also shows **how your app's own UX data flows into Snowflake** — chat threads and
thumbs up/down land in a stage as JSON, get loaded into a raw `VARIANT` table, and are curated
into typed tables that feed the AI functions and a governed `thumbs_down_rate` metric. (This
module absorbs what was previously a separate Conversational-BI module.)

## Audience

Sales Engineers and field teams demonstrating Snowflake Cortex AI Functions to data and
product teams evaluating customer-experience analytics.

## Topics Covered

- Per-aspect and overall sentiment (`AI_SENTIMENT`)
- Topic modeling / classification (`AI_CLASSIFY`)
- Structured extraction from free text (`AI_EXTRACT`)
- Theme discovery across large corpora (`AI_AGG`, `AI_SUMMARIZE_AGG`)
- Natural-language filtering for at-risk conversations (`AI_FILTER`)
- Voice via `AI_TRANSCRIBE`
- Optimizing a custom function with AI Function Studio
- Estimating token cost before a bulk run (`AI_COUNT_TOKENS`) and tying it to real credits/$
- App UX telemetry ingestion: stage → raw `VARIANT` (`COPY INTO`) → curated tables (`LATERAL FLATTEN`), plus thumbs up/down feedback
- Governed metrics with a semantic view (`CX_ANALYTICS_SV`), Cortex Analyst, Cortex Search, and the `CX_INTELLIGENCE_AGENT`
- Extending AI functions: custom Agent tool, Cortex Analyst computed columns, Cortex Search enrichment
- Cost management, best practices, per-user quotas, and killing runaway queries

## Contents

| File | Description |
|------|-------------|
| `presentations/cx-ai-functions.html` | Slide deck (20 slides) |
| `presentations/cx-ai-functions-speaker-notes.md` | Per-slide speaker notes with talking points, internal context, and references |
| `lab/setup.sql` | One-step SQL setup — schemas `AI_FUNCTIONS` + `ANALYTICS`, warehouse, **all** structured + unstructured data, app-telemetry ingestion (stage → raw → curated), semantic view, Cortex Search, agent |
| `lab/cleanup.sql` | Tear everything down to start fresh (drops the database + warehouse) |
| `lab/cx-ai-functions-lab.ipynb` | Notebook 1 — run the AI-function pipeline (+ a read-only tour of the app-telemetry setup loaded) + AI Function Studio |
| `lab/cx-ai-functions-extensions.ipynb` | Notebook 2 — integrate: semantic view / Cortex Analyst / Cortex Search / Agent (runs live) + cost & guardrails |

## Hands-On Lab

Run each AI Function over synthetic conversation data, then assemble a governed
`CX_TELEMETRY` table that combines sentiment and topic per thread.

### Prerequisites

- A role granted the `SNOWFLAKE.CORTEX_USER` database role (required for all `AI_*` functions)
- Privileges to create a database and a warehouse (or access to existing ones)
- Privileges to create a semantic view, a Cortex Search service, and an agent on the schema

### Setup

One setup step, then two notebooks — nothing else generates data, so every object is valid and
populated the moment setup finishes:

1. **Setup** — run `lab/setup.sql`. It creates `FIELD_CX_DEMO`, schemas `AI_FUNCTIONS` +
   `ANALYTICS`, warehouse `CX_AI_FUNCTIONS_WH`, **all** structured data, the unstructured text
   tables (`CHAT_THREADS` / `CALL_TRANSCRIPTS` / `SUPPORT_TICKETS`) via SQL `GENERATOR`, runs the
   full app-telemetry ingestion (stage → `RAW_APP_EVENTS` → curated `APP_*` tables), builds
   `CUSTOMER_FEEDBACK` from the real thumbs data, then creates the `CX_ANALYTICS_SV` semantic view,
   the `CHAT_SEARCH` service, and the `CX_INTELLIGENCE_AGENT` **over data that already exists** — so
   search returns hits, `thumbs_down_rate` is non-zero, and the agent answers immediately, with no
   re-create.
2. **Run the AI functions** — open `lab/cx-ai-functions-lab.ipynb`.
3. **Integrate** — open `lab/cx-ai-functions-extensions.ipynb`.

### Run in Snowflake (Workspaces / Git) — recommended for demos

The cleanest way to demo is to run everything inside Snowsight so `get_active_session()` handles
auth (no local OAuth / connection setup needed):

1. Snowsight → **Projects → Workspaces → Create Workspace from Git repository**, pointing at
   `https://github.com/sfc-gh-snuggehalli/field-demo-enablement`.
2. Open `cx-ai-functions/lab/setup.sql` and run it — this creates and fully populates everything.
3. Open `lab/cx-ai-functions-lab.ipynb` and walk the sections; the AI functions run live.
4. Open `lab/cx-ai-functions-extensions.ipynb` for the integrations + cost/guardrails.

Running locally instead? Use `snow sql -f lab/setup.sql` with a connection whose role can create the
objects and use a warehouse — no Python or second data step required.

### Lab Sections

1. Connect & explore the raw conversations
1b. App UX telemetry — a read-only tour of how setup landed chat threads + thumbs up/down via stage → `VARIANT` → curated tables
2. Sentiment with `AI_SENTIMENT`
3. Topic modeling with `AI_CLASSIFY`
4. Structured fields with `AI_EXTRACT`
5. Theme discovery with `AI_AGG` / `AI_SUMMARIZE_AGG`
6. At-risk detection with `AI_FILTER`
7. Assemble the `CX_TELEMETRY` table
8. AI Function Studio — create → evaluate → optimize a custom escalation router (`ROUTE_ESCALATION`)
9. Cost, usage & guardrails — estimate token cost before a run (`AI_COUNT_TOKENS`), monitor spend, set per-user quotas, kill runaway queries

After the core lab, `lab/cx-ai-functions-extensions.ipynb` runs live against the semantic view
(`CX_ANALYTICS_SV`), Cortex Search service (`CHAT_SEARCH`), and agent (`CX_INTELLIGENCE_AGENT`)
created by setup.sql, and shows how the same AI-function UDFs plug into the broader Cortex stack —
as a **custom Agent tool**, a **computed column inside Cortex Analyst**, and an **`AI_EXTRACT` /
`AI_EMBED` enrichment pipeline for Cortex Search** — plus cost/spike prevention (spend alerts,
per-user budget enforcement, runaway-query cancellation, query tagging, and role-gated access).

### Demoing AI Function Studio (Section 8)

Section 8 builds a custom **escalation router** that labels each conversation `LOW` / `MEDIUM` /
`HIGH`, then runs the three stored procedures behind Cortex AI Function Studio:
`CREATE_AI_FUNCTION` → `EVALUATE_AI_FUNCTION` → `OPTIMIZE_AI_FUNCTION`. You can demo it two ways:

- **SQL / notebook:** run the Section 8 cells top to bottom (create the function, build the
  `ESCALATION_EVAL` labeled set, evaluate with `exact_match`, then optimize across models).
- **Snowsight UI:** Snowsight → **AI & ML → Cortex AI Function Studio** → open `ROUTE_ESCALATION`
  (created by the notebook) and run **Evaluate** / **Optimize** from the visual workflow — the
  Optimize step plots an accuracy-vs-cost Pareto chart across models.

> `OPTIMIZE_AI_FUNCTION` runs ~10+ minutes; run it live only if you can narrate the Pareto concept,
> or run it ahead of time and read results back with `SHOW RUN METRICS`.

## Key Concepts

- **Built-ins first:** purpose-built functions cover most CX telemetry; reach for a custom
  `AI_COMPLETE` function + AI Function Studio only for domain-specific labels or rubrics.
- **Aggregate functions beat context limits:** `AI_AGG` / `AI_SUMMARIZE_AGG` process datasets
  larger than the model context window and support `GROUP BY`.
- **App data has a clear on-ramp:** raw `VARIANT` landing (schema-on-read, captures everything) vs.
  curated typed tables (governed, joinable) — both coexist; Snowpipe/Snowpipe Streaming is the
  production continuous path.
- **Governed, in-place:** text never leaves Snowflake; results land next to billing and
  engagement data, and a semantic view + agent sit on top — all in one module.
- **Cost is token-based, not warehouse-based:** a row-wise function over 1M+ rows is ~1M model
  calls, so prototype on a subset, pre-filter rows, right-size the model, and don't oversize the
  warehouse. Monitor via `CORTEX_AI_FUNCTIONS_USAGE_HISTORY` and cap with per-user quotas.

## References

- [Cortex AISQL functions](https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql)
- [AI_SENTIMENT](https://docs.snowflake.com/en/sql-reference/functions/ai_sentiment)
- [AI_CLASSIFY](https://docs.snowflake.com/en/sql-reference/functions/ai_classify)
- [AI_EXTRACT](https://docs.snowflake.com/en/sql-reference/functions/ai_extract)
- [AI_AGG](https://docs.snowflake.com/en/sql-reference/functions/ai_agg) · [AI_SUMMARIZE_AGG](https://docs.snowflake.com/en/sql-reference/functions/ai_summarize_agg)
- [AI_FILTER](https://docs.snowflake.com/en/sql-reference/functions/ai_filter)
- [Cortex AI Function Studio](https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-function-studio)
- [Managing Cortex AI Function costs](https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-func-cost-management)
- [Per-user quotas](https://docs.snowflake.com/en/user-guide/budgets/per-user-quotas)
- [CORTEX_AI_FUNCTIONS_USAGE_HISTORY view](https://docs.snowflake.com/en/sql-reference/account-usage/cortex_ai_functions_usage_history)
- [AI_COUNT_TOKENS](https://docs.snowflake.com/en/sql-reference/functions/ai_count_tokens) · [CORTEX_FUNCTIONS_QUERY_USAGE_HISTORY view](https://docs.snowflake.com/en/sql-reference/account-usage/cortex_functions_query_usage_history)
- [Cortex Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents) · [Cortex Analyst](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst) · [Cortex Search](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview)
