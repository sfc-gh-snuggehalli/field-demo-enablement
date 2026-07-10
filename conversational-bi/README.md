# Conversational BI: Semantic Views + Cortex Analyst + Agent

[View Presentation](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/conversational-bi/presentations/conversational-bi.html)

Centralize churn, revenue, and engagement definitions in one governed semantic view, query
it in natural language with Cortex Analyst, and wrap it in a Cortex Agent that also searches
the customer-experience chat telemetry from the AI Functions module. Built around a generic
B2C + B2B home-valuation (proptech) scenario where two new data leaders need one source of
truth and self-serve analytics for business users.

## Audience

Sales Engineers and field teams working with BI and data-engineering teams that want to
centralize business logic in the warehouse and enable conversational, self-serve analytics.

## Topics Covered

- Semantic views: tables, relationships, facts, dimensions, metrics, derived metrics
- Querying with the `SEMANTIC_VIEW()` table function
- Cortex Analyst for governed natural-language → SQL
- Cortex Search over unstructured chat telemetry
- Cortex Agents combining structured + unstructured tools
- Agent extensions: custom tools, `data_to_chart`, and MCP connectors

## Contents

| File | Description |
|------|-------------|
| `presentations/conversational-bi.html` | Slide deck (11 slides) |
| `presentations/conversational-bi-speaker-notes.md` | Per-slide speaker notes with talking points, internal context, and references |
| `lab/setup.sql` | SQL setup (structured tables, semantic view, Cortex Search service, agent) |
| `lab/conversational-bi-lab.ipynb` | Hands-on lab notebook (~30 min) |

## Hands-On Lab

Inspect and query the semantic view, search the chat telemetry, and combine both in the
Cortex Agent.

### Prerequisites

- A role granted the `SNOWFLAKE.CORTEX_USER` database role
- Privileges: `CREATE SEMANTIC VIEW`, `CREATE CORTEX SEARCH SERVICE`, and `CREATE AGENT` on
  the schema, plus a warehouse
- Recommended: run the **AI Functions** module (`cx-ai-functions/lab`) first so
  `FIELD_CX_DEMO.AI_FUNCTIONS.CHAT_THREADS` exists for the search service and agent

### Setup

Run in this order:

1. (Recommended) `cx-ai-functions/lab/setup.sql` + `data_gen.py` — creates the chat telemetry.
2. `lab/setup.sql` — creates schema `ANALYTICS`, warehouse `CONVERSATIONAL_BI_WH`, the
   structured tables, the `CX_ANALYTICS_SV` semantic view, the `CHAT_SEARCH` service, and the
   `CX_INTELLIGENCE_AGENT` agent.
3. Open `lab/conversational-bi-lab.ipynb` in Snowflake Notebooks, or chat with the agent in
   Snowsight (**AI & ML → Agents**).

### Run in Snowflake (Workspaces / Git) — recommended for demos

Run everything inside Snowsight so `get_active_session()` handles auth (no local OAuth / connection
setup needed):

1. Snowsight → **Projects → Workspaces → Create Workspace from Git repository**, pointing at
   `https://github.com/sfc-gh-snuggehalli/field-demo-enablement`.
2. Run the AI Functions module first (`cx-ai-functions/lab/setup.sql`, then `data_gen.py` as a cell)
   so `AI_FUNCTIONS.CHAT_THREADS` exists.
3. Open `conversational-bi/lab/setup.sql` and run it (semantic view, search service, agent).
4. Open `lab/conversational-bi-lab.ipynb`, then finish in **AI & ML → Agents → CX Intelligence** —
   ask *"Which churn-risk customers had negative support chats?"* as the closing "wow" moment.

Note: if a warehouse referenced here already exists and is owned by a different role, grant your
role `USAGE, OPERATE` on it (`CREATE WAREHOUSE IF NOT EXISTS` won't re-own it), or Cortex Search
will report the warehouse as missing.

### Lab Sections

1. Connect & inspect the semantic view
2. Query governed metrics with `SEMANTIC_VIEW()`
3. Search the unstructured CX telemetry with Cortex Search
4. Combine both in the Cortex Agent

## Key Concepts

- **One definition, many consumers:** the semantic view is the contract that Analyst, agents,
  and BI tools all read — so "churn rate" means one thing.
- **Derived metrics:** `churn_rate` is a scalar expression of two metrics, defined once.
- **Structured + unstructured:** the agent joins governed metrics (Analyst) with chat
  telemetry (Search) to answer questions neither could alone.
- **Extensible:** custom tools and MCP connectors let the agent fit an existing Sigma /
  desktop-assistant workflow.

## References

- [Semantic views overview](https://docs.snowflake.com/en/user-guide/views-semantic/overview)
- [CREATE SEMANTIC VIEW](https://docs.snowflake.com/en/sql-reference/sql/create-semantic-view) · [SEMANTIC_VIEW()](https://docs.snowflake.com/en/sql-reference/constructs/semantic_view)
- [Cortex Analyst](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst)
- [CREATE CORTEX SEARCH SERVICE](https://docs.snowflake.com/en/sql-reference/sql/create-cortex-search)
- [Create and manage Cortex Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-manage) · [CREATE AGENT](https://docs.snowflake.com/en/sql-reference/sql/create-agent)
