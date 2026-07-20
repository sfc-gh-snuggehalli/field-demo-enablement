# Semantic Views & the AI-BI Stack on Snowflake

[View Presentation](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/sms-marketing-ai/presentations/sms-marketing-ai.html)

Define a business metric **once**, as a native governed object, and reuse it identically across
Cortex Analyst, Cortex Agents, Cortex Search grounding, raw SQL, and BI tools. The demo is
grounded in an SMS/MMS marketing platform for e-commerce brands: shoppers opt in by keyword,
brands send broadcast and automated "flow" campaigns, and store orders are attributed back to the
send that drove them. A native **semantic view** is the centerpiece; Cortex Analyst, Cortex
Search, and a Cortex Agent are layered on top — all reusing the same KPI definitions.

## Audience

Field sales engineers, marketing/analytics teams, and data engineers evaluating a governed
metric layer and AI-BI stack on Snowflake.

## Topics Covered

- Native semantic views: tables, relationships, facts, dimensions, base and derived metrics,
  synonyms, sample values, and verified queries
- Three ways to create a semantic view: programmatic DDL/YAML, CoCo-assisted / dbt-generated, and
  the no-code Snowsight wizard
- Cortex Analyst over the semantic view (governed text-to-SQL)
- Cortex Search over a document corpus (grounded, cited retrieval; PARSE_DOCUMENT path included)
- A Cortex Agent blending the semantic view (via Analyst) and Cortex Search as tools
- Positioning: define once, layered-not-versus (dbt / semantic view / BI), governed by default,
  open & portable, AI-native

## Contents

| File | Description |
|------|-------------|
| `presentations/sms-marketing-ai.html` | Slide deck (12 slides) |
| `presentations/sms-marketing-ai-speaker-notes.md` | Per-slide speaker notes with talking points, presenter notes, and references |
| `demo_script.md` | Run-of-show live talk track mapped to the five positioning points |
| `lab/setup.sql` | Idempotent setup: data + semantic view + Cortex Search + Cortex Agent |
| `lab/cleanup.sql` | Tear everything down to start fresh |
| `lab/sms-marketing-ai-lab.ipynb` | Hands-on lab notebook (~30 min) |
| `app/streamlit_app.py` | Optional Streamlit-in-Snowflake chat app over the agent |
| `agent_optimization/` | /agent-optimization system-of-record: baseline + optimized agent specs, `optimization_log.md`, and `eval_questions.md` |

## Hands-On Lab

Walk the full AI-BI stack on one governed object: explore the star schema, inspect and query the
semantic view, see all three creation paths, run Cortex Analyst-style questions, run Cortex
Search, and blend both with the Cortex Agent.

### Prerequisites

- A role that can `CREATE DATABASE`/`WAREHOUSE` and use Cortex (SYSADMIN works). The role needs
  the `SNOWFLAKE.CORTEX_USER` database role to build the Search service and run the Agent.
- Cortex Analyst, Cortex Search, and Cortex Agents available in your region. If a model is not
  local, enable cross-region inference:
  `ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';`

### Setup

Run `lab/setup.sql` in your Snowflake account. This creates:

- Database `SMS_MARKETING_DEMO`, schema `CORE`, warehouse `SMS_MARKETING_WH` (MEDIUM)
- Star-schema data via SQL GENERATOR (~18 months): `DIM_BRAND`, `DIM_SUBSCRIBER`,
  `DIM_CAMPAIGN`, `FACT_MESSAGE` (~70k sends), `FACT_ORDER` (~20k attributed orders)
- A governed document corpus `SMS_DOC_CHUNKS` (briefs, copy library, TCPA/consent, deliverability,
  support macros) + an internal stage `SMS_DOCS` for real PDFs
- Semantic view `SMS_MARKETING_SV` — 7 KPIs defined once, with synonyms, sample values, and
  verified queries
- Cortex Search service `SMS_DOCS_SEARCH` over the document corpus
- Cortex Agent `SMS_MARKETING_AGENT` using the semantic view (via Analyst) and Search as tools

### Lab Sections

1. Connect & explore the star-schema data
2. The semantic view — inspect it and query metrics directly with `SEMANTIC_VIEW(...)`
3. Three ways to build it — DDL, YAML/dbt generation, and the no-code Snowsight wizard
4. Cortex Analyst — five marketer questions as governed SQL
5. Cortex Search — grounded, cited retrieval over the document corpus
6. Cortex Agent — blend structured KPIs and unstructured knowledge
7. Programmatically build & optimize the agent — deploy a weak baseline, then apply the
   /agent-optimization best practices (tool descriptions, orchestration vs response, boundaries,
   sample questions) to deploy the optimized agent; before→after
8. Positioning recap + export the view to YAML for Git

### No-code path — build the semantic view in the Snowsight wizard

You can build the same semantic view without writing DDL:

1. Snowsight → **AI & ML → Cortex Analyst**.
2. **Create → Semantic View**; choose database `SMS_MARKETING_DEMO`, schema `CORE`.
3. Add the five tables (`DIM_BRAND`, `DIM_SUBSCRIBER`, `DIM_CAMPAIGN`, `FACT_MESSAGE`,
   `FACT_ORDER`); confirm the auto-detected joins (foreign keys → primary keys).
4. Promote columns to **dimensions** (region, channel, campaign_type, theme, months) and define
   **metrics** (attributed_revenue, revenue_per_send, ctr, opt_in_growth, subscriber_ltv,
   list_churn_rate, consent_rate).
5. Add **synonyms** and **sample values** so Analyst understands business language.
6. Add a few **verified queries** from real questions, then **Save**.
7. Chat with the agent at **AI & ML → Agents → SMS_MARKETING_AGENT** (or Snowflake Intelligence).

### Run in Snowflake (Workspaces / Git) — recommended for demos

Run everything inside Snowsight so `get_active_session()` handles auth (no local OAuth / connection
setup needed):

1. Snowsight → **Projects → Workspaces → Create Workspace from Git repository**, pointing at
   `https://github.com/sfc-gh-snuggehalli/field-demo-enablement`.
2. Open `sms-marketing-ai/lab/setup.sql` and run it.
3. Open `lab/sms-marketing-ai-lab.ipynb` and walk the sections.
4. Finish by chatting with `SMS_MARKETING_AGENT` in **AI & ML → Agents**.

Running locally instead? Use `snow sql -f lab/setup.sql` with a connection whose **role can create
the objects** and use a warehouse. If `SMS_MARKETING_WH` already exists under a different owner,
grant your role `USAGE, OPERATE` on it first.

To deploy the optional chat app: create a Streamlit-in-Snowflake app from `app/streamlit_app.py`
in `SMS_MARKETING_DEMO.CORE`. Grant its owner role `USAGE` on the agent, semantic view, and Search
service, plus `SELECT` on the base tables.

## Key Concepts

- **Define once, reuse everywhere** — a metric like `attributed_revenue` has one definition in the
  semantic view; Analyst, Agents, Search grounding, SQL, and BI all read it.
- **Base vs derived metrics** — derived metrics (e.g. `revenue_per_send`, `consent_rate`) reference
  base metrics, so they compose across logical tables without re-implementing aggregations.
- **Layered, not versus** — dbt (code-first system of record) + semantic view (native governed
  metric layer) + BI tools (render layer).
- **Governed by default** — RBAC, row-access, masking, tagging, and lineage on the base tables are
  inherited by every consumer.
- **Open & portable** — OSI-format, exportable to YAML (`SYSTEM$READ_YAML_FROM_SEMANTIC_VIEW`) into
  Git alongside dbt; importable via `SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML`.
- **Agent optimization** — tool descriptions are the highest-leverage factor in agent quality; the
  demo builds a weak baseline and an optimized agent (clear names, when-to-use / when-NOT-to-use
  boundaries, separated orchestration vs response instructions, sample questions), with a versioned
  system-of-record in `agent_optimization/`.

## References

- [Overview of semantic views](https://docs.snowflake.com/en/user-guide/views-semantic/overview)
- [CREATE SEMANTIC VIEW](https://docs.snowflake.com/en/sql-reference/sql/create-semantic-view)
- [Querying semantic views (SEMANTIC_VIEW)](https://docs.snowflake.com/en/user-guide/views-semantic/querying)
- [YAML vs DDL authoring](https://docs.snowflake.com/en/user-guide/views-semantic/yaml-vs-ddl)
- [Cortex Analyst](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst)
- [CREATE CORTEX SEARCH SERVICE](https://docs.snowflake.com/en/sql-reference/sql/create-cortex-search)
- [Cortex Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents)
- [CREATE AGENT](https://docs.snowflake.com/en/sql-reference/sql/create-agent)
- [Best Practices for Building Cortex Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-best-practices)
