# Proactive Retail Intelligence with Snowflake Cortex

[View Presentation](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/proactive-retail-intelligence/presentations/proactive-retail-intelligence.html)

How to turn an embedded, reactive analytics assistant into a **proactive** one — it leads
with unprompted, explained observations and still answers ad-hoc questions on live data —
**without paying a language model to scan the whole data estate**. The pattern: cheap
in-warehouse ML (`ANOMALY_DETECTION`, `TOP_INSIGHTS`) detects and explains; a Cortex Agent
narrates only the small flagged slice.

## Audience

Data & analytics engineers, ML/platform teams, and product leaders at analytics SaaS
providers who want to adopt Snowflake Cortex incrementally and understand the cost/latency
trade-offs of an "always-watching" assistant.

## Topics Covered

- Multi-series anomaly detection with `SNOWFLAKE.ML.ANOMALY_DETECTION`
- Key-driver ("why") analysis with `SNOWFLAKE.ML.TOP_INSIGHTS`
- Semantic views + Cortex Analyst for governed, ad-hoc questions
- Cortex Search over free-text return reasons
- A custom "briefing" tool and an **optimized** Cortex Agent orchestrating every layer
- Snowflake CoWork / Snowflake Intelligence and the REST `agent:run` embed path
- The cost pattern: ML scans in-warehouse, the LLM only narrates

## Contents

| File | Description |
|------|-------------|
| `presentations/proactive-retail-intelligence.html` | Slide deck (12 slides) |
| `presentations/proactive-retail-intelligence-speaker-notes.md` | Per-slide speaker notes with talking points, presenter notes, and references |
| `lab/setup.sql` | SQL setup script (database, warehouse, sample data, ML models, semantic view, search) |
| `lab/cleanup.sql` | Tear everything down to start fresh |
| `lab/proactive-retail-intelligence-lab.ipynb` | Hands-on lab notebook (~45 min) |
| `agent_optimization/` | Baseline vs. optimized agent specs and a diff summary |

## Hands-On Lab

The notebook tours the proactive layer built by `setup.sql`, then builds the custom briefing
tool and the optimized Cortex Agent, and finishes in Snowflake CoWork / Snowflake
Intelligence. ML detection and driver analysis run in-warehouse; the language model only ever
reads the flagged slice.

### Prerequisites

- A Snowflake account with **Cortex ML Functions**, **Cortex Analyst**, **Cortex Search**,
  and **Cortex Agents / Snowflake CoWork** available in your region.
- A role that can `CREATE DATABASE` / `CREATE WAREHOUSE` and create
  `SNOWFLAKE.ML.ANOMALY_DETECTION` / `TOP_INSIGHTS` models (e.g. `SYSADMIN`).
- Privileges to `CREATE AGENT` in the target schema, and USAGE on the custom tool function.

### Setup

Run `lab/setup.sql` in your Snowflake account. This creates:

- Database `PROACTIVE_RETAIL_DEMO` (schemas `RAW`, `ANALYTICS`) and warehouse
  `PROACTIVE_RETAIL_WH` (MEDIUM).
- Sample data: retailers, ~60 stores, ~400 days of daily store metrics, ~50k return records
  (with an injected anomaly), and free-text return reasons.
- `SNOWFLAKE.ML.ANOMALY_DETECTION` model + `STORE_ANOMALY_FINDINGS` table + enriched view.
- `SNOWFLAKE.ML.TOP_INSIGHTS` model + `RETURN_DRIVERS` table.
- `RETAIL_RETURNS_SV` semantic view and `RETURN_REASONS_SEARCH` Cortex Search service.
- A (suspended) `REFRESH_ANOMALY_FINDINGS_TASK` scheduled task.

### Lab Sections

1. **Connect & Explore** — tour the raw retail data.
2. **Detect Anomalies Without an LLM** — read the ML-flagged store anomalies.
3. **Explain the "Why"** — review the Top Insights drivers.
4. **Ad-Hoc on Live Data** — query the semantic view the way Cortex Analyst does.
5. **Build the Briefing Tool** — a single-cell JSON function over findings + drivers.
6. **Create the Cortex Agent** — baseline spec, then the optimized spec (Section 6b).
7. **Deliver the Agent** — chat with the agent in CoWork / Snowflake Intelligence and via REST.

### Run in Snowflake (Workspaces / Git) — recommended for demos

Run everything inside Snowsight so `get_active_session()` handles auth (no local OAuth /
connection setup needed):

1. Snowsight → **Projects → Workspaces → Create Workspace from Git repository**, pointing at
   `https://github.com/sfc-gh-snuggehalli/field-demo-enablement`.
2. Open `proactive-retail-intelligence/lab/setup.sql` and run it.
3. Open `lab/proactive-retail-intelligence-lab.ipynb` and walk the sections.
4. Finish in **AI & ML → Agents** chatting with **Proactive Retail Assistant**.

Running locally instead? Use `snow sql -f lab/setup.sql` with a connection whose **role can
create the objects** and use a warehouse. If `PROACTIVE_RETAIL_WH` already exists under a
different owner, grant your role `USAGE, OPERATE` on it first (otherwise Cortex Search reports
the warehouse as missing).

## Key Concepts

- **ML scans, LLM narrates** — detection/explanation are set-based SQL; token cost scales with
  what's *interesting*, not what's *stored*.
- **Precompute findings** — a scheduled task keeps a small findings table fresh so the
  assistant is always current.
- **One agent, two surfaces** — the same agent object serves CoWork / Intelligence and the
  embedded product via REST `agent:run`.
- **Tool descriptions are load-bearing** — "when NOT to use it" is the highest-leverage
  optimization for correct tool selection.

## References

- [Anomaly Detection](https://docs.snowflake.com/en/user-guide/ml-functions/anomaly-detection)
- [Top Insights](https://docs.snowflake.com/en/user-guide/ml-functions/top-insights)
- [Semantic views (SQL)](https://docs.snowflake.com/en/user-guide/views-semantic/sql)
- [Cortex Analyst](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst)
- [Cortex Search](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview)
- [Build agents (CoWork)](https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/build-agents)
- [Cortex Agents REST API](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-rest-api)
