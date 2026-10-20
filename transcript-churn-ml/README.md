# Call-Transcript Topics to Churn, Where the Data Already Lives

[View Presentation](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/transcript-churn-ml/presentations/transcript-churn-ml.html)

Recorded sales and success calls already land in Snowflake. This module turns them into topics, price sentiment and churn
features without moving the text anywhere: segments are masked, redacted and embedded in incremental pipelines; business
topics are assigned in SQL and new ones discovered with UMAP + HDBSCAN in a stored procedure, versioned in the Model
Registry; call signals join product usage in the Feature Store; and survival models (lifelines, scikit-survival) train,
register, score from SQL and are monitored next to the data. A data-gravity ledger measures what the in-place path saves
against a round trip.

Scenario: a home-ownership engagement SaaS company that sells monthly homeowner reports and lead alerts to loan officers
and real-estate agents. Every row is synthetic.

## Audience

ML engineers, data scientists, analytics engineers and data engineers who run topic modeling, LLM labeling or churn
models today, partly on Snowflake and partly on an external ML platform.

## Topics Covered

- Segmenting transcripts into analysis units; masking policies and `AI_REDACT` before anything is embedded
- Incremental pipelines: dynamic tables, a stream + MERGE, AI functions that process each row once
- `AI_EMBED`, SQL vector similarity against business exemplars, and the embedding-model column for planned re-embeds
- UMAP + HDBSCAN topic discovery in a warehouse stored procedure, compared with k-means
- A custom clusterer in the Model Registry (array input, `MODEL(...)!PREDICT` from SQL), versions matched by member overlap
- `AI_COMPLETE` structured output on cluster representatives, with a review queue
- A price-sentiment cascade: keyword prefilter, `AI_SENTIMENT` aspects, `AI_CLASSIFY` driver
- A semantic view over topics, sentiment and deal outcomes
- Feature Store entities and managed feature views, point-in-time Datasets
- Logistic vs Cox vs gradient-boosted survival under Experiment Tracking, registry versions with `explain`, model monitor
- A data-gravity ledger (round trip vs in place) and AI cost read back from usage history

## Contents

| File | Description |
|------|-------------|
| `presentations/transcript-churn-ml.html` | Slide deck (16 slides) |
| `presentations/transcript-churn-ml-speaker-notes.md` | Per-slide speaker notes with talking points, presenter notes, and references |
| `demo_script.md` | Timed run of show: the 15-minute app path first, then the 25-minute notebook deep dive |
| `demo.sh` | One script for setup, the headless build, the notebooks, the story app and teardown |
| `lab/app_setup.sql` | Presenter objects: the live January step, account risk and drivers, semantic view, search service, agent |
| `app/` | Streamlit story app (`CHURN_STORY_APP`, container runtime): seven pages, one live step |
| `pyproject.toml`, `uv.lock` | Local Python environment (notebooks, headless build, Snowflake CLI), managed by uv |
| `lab/setup.sql` | Database, warehouse and all synthetic data (SQL `GENERATOR`) |
| `lab/cleanup.sql` | Tear everything down to start fresh |
| `lab/transcript-churn-01-segments-governance.ipynb` | Segments, masking, redaction, embeddings, the new month |
| `lab/transcript-churn-02-topics-registry.ipynb` | Seeded topics, HDBSCAN discovery, the clusterer in the registry, LLM naming |
| `lab/transcript-churn-03-insights-semantic-view.ipynb` | Price-sentiment cascade, topics on won and lost deals, semantic view |
| `lab/transcript-churn-04-churn-feature-store.ipynb` | Feature Store, survival models, Experiment Tracking, registry, SQL scoring, monitor |
| `lab/transcript-churn-05-ledger-cost.ipynb` | Data-gravity ledger and AI cost |

## Hands-On Lab

Five notebooks, about 25 minutes each to walk through; the headless build runs all five in about 20-25 minutes. Each
notebook rehydrates from the previous one's tables, so any of them can be re-run on its own, in order.

### Prerequisites

- A role that can create a database and a warehouse (`SYSADMIN`), and `SNOWFLAKE.CORTEX_USER` (granted to `PUBLIC` by default)
- Cortex AI functions available in your region, or cross-region inference enabled (`CORTEX_ENABLED_CROSS_REGION`), for
  `AI_REDACT`, `AI_EMBED` (`snowflake-arctic-embed-l-v2.0`), `AI_SENTIMENT`, `AI_CLASSIFY` and `AI_COMPLETE` (`claude-sonnet-4-5`)
- Privileges to create models, a model monitor, an experiment and a Feature Store schema (`SYSADMIN` as owner of the database has them)
- [uv](https://docs.astral.sh/uv/) (`brew install uv`) and a Snowflake CLI connection (`snow connection add`, or any entry in `~/.snowflake/config.toml`) for the local quick start

### Quick start

```bash
./demo.sh setup -c <connection>   # Python env, lab/setup.sql (database, warehouse, synthetic data), .env
./demo.sh build --yes             # runs notebooks 01-05 headless and prints every CHECK line
./demo.sh notebook 2              # open any notebook (1-5) with the .venv kernel and the saved connection
./demo.sh teardown --yes          # drop everything
```

`setup` is safe to re-run. `build --from 3` resumes at notebook 03; `ledger --yes` re-runs notebook 05 only. With a
browser-based (OAuth) connection, each notebook opens one sign-in; use a key-pair or PAT connection for unattended runs.

### Present it: the story app and the agent

After the build, one command creates the presenter path:

```bash
./demo.sh app --yes        # lab/app_setup.sql, then deploys the Streamlit app; prints the app URL
./demo.sh app-reset        # before each show: January's calls wait for the app's live step
./demo.sh app-load         # optional: run the live step from the terminal (rehearsal or recovery)
```

- **`CHURN_STORY_APP`** (Streamlit, container runtime, no external packages) tells the story in seven pages. Page 3
  loads January's calls live and shows each pipeline step with its rows, AI calls and seconds (about 2 minutes).
- **`CHURN_INSIGHTS_AGENT`** appears in Snowflake Intelligence as *Call insights and churn risk*. It answers from the
  semantic view `ANALYTICS.CHURN_STORY_SV` and the search service `ANALYTICS.CALL_SEARCH`, which indexes redacted
  segments only.
- Re-run `./demo.sh app --yes` after rebuilding any notebook; `--app-only` redeploys just the app code.
- `demo_script.md` has the 15-minute run of show for this path.

#### Run the app locally

To test the app on your machine against the same Snowflake objects, run this from this folder (`transcript-churn-ml`).
Use the connection name saved in `.env` by `./demo.sh setup`:

```bash
cd app
SNOWFLAKE_DEFAULT_CONNECTION_NAME=<your-connection> \
  uv run --project .. --frozen --with 'streamlit[snowflake]>=1.50' \
  streamlit run streamlit_app.py --server.port 8502
```

Open http://localhost:8502 and press `Ctrl+C` to stop. `--with` adds Streamlit for this run only and leaves the lockfile
unchanged. Run `./demo.sh app` first: the app reads the objects that `lab/app_setup.sql` creates. Resetting or loading
January locally changes the same tables the deployed app uses.

### Set up with Cortex Code

Open this repository in Cortex Code and paste:

```text
Set up the Call-Transcript Topics to Churn lab in the transcript-churn-ml folder on my Snowflake account.
1. If uv is not installed, ask me before installing it (brew install uv).
2. Run ./demo.sh --help, then ./demo.sh setup. Add </dev/null to every demo.sh command
   so it never waits for typed input. When it stops and names a flag (such as
   -c <connection>), show me the options it printed (point out the connection marked
   is_default), ask me which to use, and re-run with that flag. If I have no Snowflake
   CLI connection, help me create one with snow connection add.
3. Judge progress by the lines starting with ==>, CHECK or ERROR: (SQL and notebook output go to .logs/).
   If it seems stuck on sign-in, tell me to finish the browser sign-in, then re-run the
   same command.
4. When setup prints Done, ask me before running ./demo.sh build --yes (it calls AI functions,
   trains and registers models and spends credits). When it finishes, show me every CHECK line it printed.
   If a notebook fails, show me its CHECK lines and the error, and offer ./demo.sh build --yes --from <n>.
Do not run teardown or ledger unless I ask.
```

### Manual setup

Run `lab/setup.sql` in your Snowflake account (Snowsight worksheet or `snow sql -f lab/setup.sql`). This creates:

- Database `TRANSCRIPT_CHURN_ML_DEMO` with schemas `RAW`, `CORE`, `ML`, `FEATURES`, `ANALYTICS`, and warehouse `TRANSCRIPT_CHURN_ML_WH` (MEDIUM, auto-suspend 60 s)
- `RAW.ACCOUNTS` (2,000), `RAW.USAGE_EVENTS` (monthly), `RAW.SUBSCRIPTIONS`, `RAW.CRM_OPPORTUNITIES`, `RAW.REPS`
- `RAW.CALLS` and `RAW.UTTERANCES` (November-December), `RAW.CALLS_NEW_MONTH` and `RAW.UTTERANCES_NEW_MONTH` (January, loaded by notebook 01)
- `ML.TOPIC_TAXONOMY` (eight business topics with exemplars), and the answer keys `RAW.SEED_TRUTH` and `RAW.SEED_ACCOUNTS` that the CHECKs grade against

Then run the notebooks in order, 01 to 05. Everything else (dynamic tables, the stream and procedures, the masking policy,
models, experiment, Feature Store, semantic view, monitor) is created by the notebooks.

### Lab Sections

1. **01 Segments and governance:** what landed, the masking policy, segments as an incremental dynamic table, `AI_REDACT`
   through a stream and MERGE (plus a known-name pass), `AI_EMBED` on redacted text only, a new month processing only new rows
2. **02 Topics and registry:** seeded assignment by vector similarity, UMAP + HDBSCAN discovery in a stored procedure,
   k-means comparison, the clusterer in the registry scored from SQL, `AI_COMPLETE` naming into a review queue, run 2 matched to run 1
3. **03 Insights:** the price-sentiment cascade, topics on won and lost deals, `CALL_INSIGHTS_SV`, both questions through the semantic view
4. **04 Churn:** entity and managed feature views, a point-in-time Dataset, six models in a stored procedure, Experiment Tracking,
   survival models in the registry with `explain`, SQL scoring at four dates, a model monitor
5. **05 Ledger and cost:** round trip vs in place under query tags, the ledger, `ACCOUNT_USAGE` queries for an existing loop,
   AI token estimates and usage history, spend-control reference SQL

### Run in Snowflake (Workspaces / Git) — recommended for demos

Run everything inside Snowsight so `get_active_session()` handles auth (no local OAuth / connection setup needed):

1. Snowsight → **Projects → Workspaces → Create Workspace from Git repository**, pointing at
   `https://github.com/sfc-gh-snuggehalli/field-demo-enablement`.
2. Open `transcript-churn-ml/lab/setup.sql` and run it.
3. Open the notebooks in order, 01 to 05. In each connect cell, set `DEMO_ACCOUNT` to your account name.
4. Finish in Snowsight: **AI & ML » Models** (`TOPIC_CLUSTERER`, `CHURN_SURVIVAL`), **AI & ML » Feature Store**,
   **AI & ML » Experiments**, and **AI & ML » Cortex Analyst** on `ANALYTICS.CALL_INSIGHTS_SV`.

## Key Concepts

- **Segment:** four consecutive turns of a real conversation (about 100-200 tokens); the unit topics and sentiment are computed on
- **Redact before embed:** embeddings and LLM prompts only ever see `CORE.SEGMENTS_REDACTED`; the raw column is masked
- **Seeded vs discovered topics:** business topics by similarity to exemplars; HDBSCAN on what is left, with noise left unassigned
- **Cluster stability:** a new clustering version is matched to the previous one by the Jaccard overlap of shared members
- **Cascade:** cheap filters first, an AI function only where signal is likely, an LLM per cluster rather than per row
- **Point-in-time features:** the same feature view definitions read at any date from a snapshot calendar
- **c-index:** the share of account pairs whose predicted risk orders their time to churn correctly (0.5 = random)
- **Data-gravity ledger:** rows that leave the platform and come back, per run, measured from query history

## References

- [AI_REDACT](https://docs.snowflake.com/en/sql-reference/functions/ai_redact)
- [AI_EMBED](https://docs.snowflake.com/en/sql-reference/functions/ai_embed)
- [AI_SENTIMENT](https://docs.snowflake.com/en/sql-reference/functions/ai_sentiment)
- [AI_CLASSIFY](https://docs.snowflake.com/en/sql-reference/functions/ai_classify)
- [AI_COMPLETE structured outputs](https://docs.snowflake.com/en/user-guide/snowflake-cortex/complete-structured-outputs)
- [AI_COUNT_TOKENS](https://docs.snowflake.com/en/sql-reference/functions/ai_count_tokens)
- [Dynamic tables](https://docs.snowflake.com/en/user-guide/dynamic-tables-about)
- [Masking policies](https://docs.snowflake.com/en/user-guide/security-column-ddm-intro)
- [Snowflake Model Registry: custom models](https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/custom-models)
- [Feature Store](https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/overview)
- [Experiment Tracking](https://docs.snowflake.com/en/developer-guide/snowflake-ml/experiments)
- [Model monitoring](https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/model-observability)
- [Semantic views](https://docs.snowflake.com/en/user-guide/views-semantic/overview)
- [Cortex AI functions cost management](https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-func-cost-management)
