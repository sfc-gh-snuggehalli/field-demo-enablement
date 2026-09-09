# Cortex Search: BYO Embeddings & Cost Optimization

[View Presentation](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/cortex-search-cost/presentations/cortex-search-cost.html)

Validate the cost behavior of Cortex Search with user-provided (BYO) embeddings. This module proves that BYO vectors incur zero EMBED_TEXT cost, demonstrates incremental refresh mechanics, breaks down the serving cost formula, and walks through optimization levers (AUTO_SUSPEND, TARGET_LAG, corpus pruning, vector dimension reduction).

## Audience

Data engineers, platform teams, and solutions architects evaluating Cortex Search cost at scale -- especially teams that pre-compute embeddings externally and want to understand what Snowflake charges for indexing and serving.

## Topics Covered

- Multi-index Cortex Search with BYO (user-provided) vector embeddings
- Incremental refresh with PRIMARY KEY (what triggers it, what breaks it)
- Serving cost anatomy: the 6.3 cr/GB/mo formula and how vectors dominate
- Cost monitoring with CORTEX_SEARCH_DAILY_USAGE_HISTORY
- Optimization levers: AUTO_SUSPEND, TARGET_LAG, FULL_INDEX_BUILD_INTERVAL_DAYS, corpus pruning

## Contents

| File | Description |
|------|-------------|
| `presentations/cortex-search-cost.html` | Slide deck (9 slides) |
| `presentations/cortex-search-cost-speaker-notes.md` | Per-slide speaker notes with talking points, presenter notes, and references |
| `lab/setup.sql` | SQL setup script (database, warehouse, document metadata, 5,000 chunks + embeddings) |
| `lab/cleanup.sql` | Tear everything down to start fresh |
| `lab/data_gen.py` | Optional Python path for chunk generation (equivalent to setup.sql section 4; run in a notebook cell) |
| `lab/cortex-search-cost-lab.ipynb` | Hands-on lab notebook (30-45 min) |

## Hands-On Lab

Create a Cortex Search Service with BYO embeddings on ~5,000 synthetic document chunks, measure serving cost, add 500 new chunks incrementally, verify zero embedding cost and delta-only refresh, then test optimization levers.

### Prerequisites

- A Snowflake account (any edition) in a region that supports Cortex Search
- A role with CREATE DATABASE, CREATE WAREHOUSE privileges (e.g. SYSADMIN)
- The SNOWFLAKE.CORTEX_USER database role granted to your role

### Setup

Run `lab/setup.sql` in your Snowflake account. This creates everything the lab needs:

- Database `CORTEX_SEARCH_COST_DEMO` with schema `DEMO`
- Warehouse `CORTEX_SEARCH_COST_WH` (MEDIUM)
- `DOCUMENTS` table (500 rows of document metadata)
- `DOCUMENT_CHUNKS` table (5,000 rows with 768-dim BYO embeddings)

Then open `lab/cortex-search-cost-lab.ipynb` and walk the sections.

> `lab/data_gen.py` is an optional Python equivalent of setup.sql's chunk-generation block
> (pandas + `write_pandas`). Run it in a notebook cell where `get_active_session()` works --
> the local Python connector cannot drive `oauth_authorization_code` without a client_id.

### Lab Sections

1. **Connect & Explore** -- verify the data loaded correctly
2. **Create the Search Service** -- multi-index DDL with BYO vectors + PRIMARY KEY + `query_model`
3. **Baseline Cost Measurement** -- query CORTEX_SEARCH_DAILY_USAGE_HISTORY, estimate serving cost
4. **Validate Incremental Refresh** -- INSERT 500 new chunks, trigger refresh, verify delta-only processing with `CORTEX_SEARCH_REFRESH_HISTORY`
5. **Optimization Levers** -- AUTO_SUSPEND, TARGET_LAG, FULL_INDEX_BUILD_INTERVAL_DAYS, corpus pruning projection
6. **Cost Monitoring Dashboard Queries** -- production-ready monitoring queries + production-scale projections

### Run in Snowflake (Workspaces / Git) -- recommended for demos

Run everything inside Snowsight so `get_active_session()` handles auth (no local OAuth / connection
setup needed):

1. Snowsight -> **Projects -> Workspaces -> Create Workspace from Git repository**, pointing at
   `https://github.com/sfc-gh-snuggehalli/field-demo-enablement`.
2. Open `cortex-search-cost/lab/setup.sql` and run it (creates everything, including chunks + embeddings).
3. Open `lab/cortex-search-cost-lab.ipynb` and walk the sections.

Running locally instead? Use `snow sql -f lab/setup.sql` with a connection whose **role can create
the objects** and use a warehouse. If a referenced warehouse already exists under a different owner,
grant your role `USAGE, OPERATE` on it.

## Key Concepts

- **BYO Embeddings:** Specifying a bare VECTOR column in `VECTOR INDEXES` means Snowflake indexes it as-is with zero EMBED_TEXT cost. Adding `(query_model='...')` lets Snowflake embed query *text* at search time while still using your vectors at index time.
- **Incremental Refresh:** With PRIMARY KEY + REFRESH_MODE = INCREMENTAL, only changed/new rows are processed per refresh cycle. Verify with `CORTEX_SEARCH_REFRESH_HISTORY` (`REFRESH_ACTION`, `numInsertedRows`).
- **FULL_INDEX_BUILD_INTERVAL_DAYS:** Controls periodic index compaction frequency. Does NOT re-embed unchanged data.
- **Serving Cost:** Proportional to indexed data size (rows x (dims x 4B + payload)), charged at 6.3 cr/GB/mo while serving is active.
- **AUTO_SUSPEND:** Automatically suspends serving compute after idle period (min 30 min). Auto-resumes on next query.

## References

- [Understanding cost for Cortex Search Services](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-costs)
- [CREATE CORTEX SEARCH SERVICE](https://docs.snowflake.com/en/sql-reference/sql/create-cortex-search)
- [ALTER CORTEX SEARCH SERVICE](https://docs.snowflake.com/en/sql-reference/sql/alter-cortex-search)
- [CORTEX_SEARCH_DAILY_USAGE_HISTORY view](https://docs.snowflake.com/en/sql-reference/account-usage/cortex_search_daily_usage_history)
- [Cortex Search Overview](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview)
