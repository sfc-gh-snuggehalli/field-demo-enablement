# AI Functions: Customer Experience Telemetry

[View Presentation](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/cx-ai-functions/presentations/cx-ai-functions.html)

Turn raw chat threads, call transcripts, and support tickets into structured sentiment
and topic telemetry — entirely in SQL with Snowflake AI Functions, no ML infrastructure.
Built around a generic B2C + B2B home-valuation (proptech) scenario: a customer-facing GPT
assistant and support line generate thousands of conversations a day, and the team needs to
know what customers ask about, how they feel, and who is at risk of churning.

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

## Contents

| File | Description |
|------|-------------|
| `presentations/cx-ai-functions.html` | Slide deck (12 slides) |
| `presentations/cx-ai-functions-speaker-notes.md` | Per-slide speaker notes with talking points, internal context, and references |
| `lab/setup.sql` | SQL setup (database, schema, warehouse, structured `CUSTOMERS`) |
| `lab/data_gen.py` | Snowpark loader for the unstructured text tables |
| `lab/cx-ai-functions-lab.ipynb` | Hands-on lab notebook (~30 min) |

## Hands-On Lab

Run each AI Function over synthetic conversation data, then assemble a governed
`CX_TELEMETRY` table that combines sentiment and topic per thread.

### Prerequisites

- A role granted the `SNOWFLAKE.CORTEX_USER` database role (required for all `AI_*` functions)
- Privileges to create a database and a warehouse (or access to existing ones)
- Python with `snowflake-snowpark-python` and `pandas` to run `data_gen.py` locally
  (or run it from a Snowflake Notebook cell)

### Setup

Run in this order:

1. `lab/setup.sql` — creates `FIELD_CX_DEMO`, schema `AI_FUNCTIONS`, warehouse
   `CX_AI_FUNCTIONS_WH`, and the structured `CUSTOMERS` table (500 rows).
2. `python lab/data_gen.py` — loads `CHAT_THREADS`, `CALL_TRANSCRIPTS`, and `SUPPORT_TICKETS`
   via `write_pandas`.
3. Open `lab/cx-ai-functions-lab.ipynb` in Snowflake Notebooks.

### Run in Snowflake (Workspaces / Git) — recommended for demos

The cleanest way to demo is to run everything inside Snowsight so `get_active_session()` handles
auth (no local OAuth / connection setup needed):

1. Snowsight → **Projects → Workspaces → Create Workspace from Git repository**, pointing at
   `https://github.com/sfc-gh-snuggehalli/field-demo-enablement`.
2. Open `cx-ai-functions/lab/setup.sql` and run it.
3. Run `lab/data_gen.py` as a notebook cell (it uses `get_active_session()` in-notebook — no
   `--connection` needed).
4. Open `lab/cx-ai-functions-lab.ipynb` and walk the sections; the AI functions run live.

Running locally instead? Use `snow sql -f lab/setup.sql` and
`python lab/data_gen.py --connection <name>`, with a connection whose role can create the objects
and use a warehouse.

### Lab Sections

1. Connect & explore the raw conversations
2. Sentiment with `AI_SENTIMENT`
3. Topic modeling with `AI_CLASSIFY`
4. Structured fields with `AI_EXTRACT`
5. Theme discovery with `AI_AGG` / `AI_SUMMARIZE_AGG`
6. At-risk detection with `AI_FILTER`
7. Assemble the `CX_TELEMETRY` table
8. Optimize a custom function with AI Function Studio

## Key Concepts

- **Built-ins first:** purpose-built functions cover most CX telemetry; reach for a custom
  `AI_COMPLETE` function + AI Function Studio only for domain-specific labels or rubrics.
- **Aggregate functions beat context limits:** `AI_AGG` / `AI_SUMMARIZE_AGG` process datasets
  larger than the model context window and support `GROUP BY`.
- **Governed, in-place:** text never leaves Snowflake; results land next to billing and
  engagement data for the Conversational BI module to analyze.

## References

- [Cortex AISQL functions](https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql)
- [AI_SENTIMENT](https://docs.snowflake.com/en/sql-reference/functions/ai_sentiment)
- [AI_CLASSIFY](https://docs.snowflake.com/en/sql-reference/functions/ai_classify)
- [AI_EXTRACT](https://docs.snowflake.com/en/sql-reference/functions/ai_extract)
- [AI_AGG](https://docs.snowflake.com/en/sql-reference/functions/ai_agg) · [AI_SUMMARIZE_AGG](https://docs.snowflake.com/en/sql-reference/functions/ai_summarize_agg)
- [AI_FILTER](https://docs.snowflake.com/en/sql-reference/functions/ai_filter)
- [Cortex AI Function Studio](https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-function-studio)
