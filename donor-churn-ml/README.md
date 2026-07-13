# Donor Lapse/Churn Intelligence: Snowflake ML → Agent

[View Presentation](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/donor-churn-ml/presentations/donor-churn-ml.html)

An end-to-end demo of the **complete Snowflake ML lifecycle** for a generic **nonprofit
fundraising CRM** scenario: predict which donors are likely to **lapse** (stop giving),
explain every score, and let a fundraising manager act on it in natural language — all
inside one governed Snowflake account, no data movement. The demo exercises Feature Store,
Datasets, Cortex ML Functions, Snowpark ML modeling + HPO, ML Jobs on Container Runtime,
Model Registry, Model Explainability, Model Serving, and ML Observability, then culminates
in a **Cortex Agent that calls the deployed model as a tool** plus a Streamlit chat app.

> Client-agnostic by design. Swap the entity (donor → customer / patient / subscriber) and
> the same lifecycle demonstrates churn, propensity, or risk for any account.

## Audience

Mixed **Sales Engineers + customer ML platform teams**. The narrative maps to two common
initiatives: an ML Ops & Platform build (churn models, Registry, Serving, Observability)
and a GTM / executive chatbot (Cortex Analyst + Snowflake Intelligence + Streamlit).

## Topics Covered

- Feature Store: entities, Feature Views, point-in-time correct retrieval
- Datasets: immutable, versioned training snapshots
- Cortex ML Functions: Forecasting, Anomaly Detection, Classification, Top Insights
- Snowpark ML modeling (XGBoost) + distributed hyperparameter optimization
- ML Jobs / Container Runtime for scalable remote (GPU-optional) training
- Optional: orchestrating the pipeline as a Task Graph (DAG) — ML-Job training + retries + run history
- Model Registry: versioning, metrics, signatures, DEFAULT promotion, lineage
- Model Explainability: Shapley risk drivers per donor
- Model Serving: batch scoring + single-donor real-time inference (Warehouse / SPCS)
- ML Observability: drift + performance monitoring, segmentation, alerting
- Cortex Analyst semantic view + a model-as-a-tool Cortex Agent + Streamlit chat

## Contents

| File | Description |
|------|-------------|
| `presentations/donor-churn-ml.html` | Slide deck (17 slides) |
| `presentations/donor-churn-ml-speaker-notes.md` | Per-slide speaker notes with talking points, internal context, and references |
| `lab/setup.sql` | Database, four schemas, warehouses, synthetic data, Cortex ML Functions, Analyst semantic view |
| `lab/donor-churn-ml-lab.ipynb` | Hands-on lab notebook (~30–45 min) — builds the full ML lifecycle + agent |
| `app/streamlit_app.py` | Streamlit-in-Snowflake chat UI over the deployed agent |

## Hands-On Lab

Build the whole lifecycle live: register features, materialize a versioned dataset, run
no-code Cortex ML Functions, train and tune an XGBoost model, run it as a remote ML Job,
register/serve/monitor it, wrap it in SQL tool functions, and register a Cortex Agent that
retrieves donors via Cortex Analyst and scores them with the deployed model — then chat
with it.

### Prerequisites

- A role that can `CREATE DATABASE / SCHEMA / WAREHOUSE`, `CREATE SEMANTIC VIEW`, and has
  `CREATE SNOWFLAKE.ML.CLASSIFICATION / .FORECAST / .ANOMALY_DETECTION` on the `MODELS` schema.
- The `SNOWFLAKE.CORTEX_USER` database role (for `AI_COMPLETE` and the agent).
- `snowflake-ml-python >= 1.26` in the notebook runtime.
- For ML Jobs / SPCS serving: privilege to `CREATE COMPUTE POOL` and `CREATE MODEL / MODEL MONITOR / AGENT`.
- For the optional Task Graph extension (§14): `CREATE TASK` / `EXECUTE TASK` and the `DONOR_CHURN_ML_POOL` compute pool.
- For the Streamlit app: `USAGE` on the agent and on the `TOP_CHURN_RISK` function.

### Setup

Run `lab/setup.sql` in your Snowflake account. This creates:

- Database `DONOR_CHURN_ML_DEMO` with schemas `RAW`, `FEATURES`, `MODELS`, `ANALYTICS`
- Warehouses `DONOR_CHURN_ML_WH` (MEDIUM) and `DONOR_CHURN_ML_SOWH` (Snowpark-optimized)
- Synthetic tables `DONORS` (~50K), `DONATIONS` (~600K), `ENGAGEMENTS` (~950K)
- Point-in-time `DONOR_TRAINING_BASE` view + weekly `DONATION_VOLUME_TS`
- Cortex ML Function objects: `DONATION_VOLUME_FORECAST`, `DONATION_VOLUME_ANOMALY`, `LAPSE_BASELINE_MODEL`
- Cortex Analyst semantic view `ANALYTICS.DONOR_CHURN_SV`

> The Model Registry model, Model Monitor, the `PREDICT_DONOR_CHURN` / `TOP_CHURN_RISK`
> tool functions, and the Cortex Agent are created **by the notebook**, because they depend
> on the trained/deployed model. Run order: `setup.sql` → notebook sections 2–13 (+ optional 14) → Streamlit app.

### Lab Sections

1. Connect & explore the synthetic donor dataset
2. Feature Store — donor entity + RFM/engagement/wealth Feature Views (point-in-time)
3. Datasets — versioned training set from the Feature Store
4. Cortex ML Functions — Forecast, Anomaly Detection, Classification baseline
5. Snowpark ML — XGBoost lapse classifier + distributed HPO
6. ML Jobs — remote training on a Container Runtime compute pool
7. Model Registry — log, version, promote to DEFAULT
8. Explainability — Shapley risk drivers
9. Model Serving — batch + single-donor scoring
10. ML Observability — model monitor (segmented by region) + alert
11. Tool wrappers — `TOP_CHURN_RISK` / `PREDICT_DONOR_CHURN`
12. Cortex Agent — Analyst + model-as-a-tool
13. The "wow" moment + summary
14. *(Optional extension)* Orchestrate training as a Task Graph (DAG) — `snowflake.core` task API chains prep → **ML Job** train+register → score → refresh monitor; view the graph in Snowsight

### Run in Snowflake (Workspaces / Git) — recommended for demos

Run everything inside Snowsight so `get_active_session()` handles auth (no local OAuth /
connection setup needed):

1. Snowsight → **Projects → Workspaces → Create Workspace from Git repository**, pointing at
   `https://github.com/sfc-gh-snuggehalli/field-demo-enablement`.
2. Open `donor-churn-ml/lab/setup.sql` and run it.
3. Open `lab/donor-churn-ml-lab.ipynb` and walk sections 2–13 (creates the model, registry,
   monitor, tool functions, and agent). Section 14 is an optional add-on that orchestrates the
   pipeline as a scheduled Task Graph (DAG).
4. Deploy `app/streamlit_app.py` as a Streamlit-in-Snowflake app, or chat in Snowsight
   **AI & ML → Agents**, and ask the "wow" question.

Running locally instead? Use `snow sql -f lab/setup.sql` with a connection whose **role can
create the objects** and use a warehouse. If a referenced warehouse already exists under a
different owner, grant your role `USAGE, OPERATE` on it.

## Key Concepts

- **Point-in-time correctness** — features are computed as-of a snapshot date; the lapse
  label comes from the *following* 12-month window, so there is no leakage.
- **One governed platform** — features, datasets, models, monitors, and the agent all live
  in one account with a single RBAC and lineage model; donor PII never leaves Snowflake.
- **Heuristics → ML bridge** — Cortex ML Functions give analysts value in SQL; the same team
  graduates to Snowpark ML for custom control, HPO, and per-donor explainability.
- **Model as a tool** — a Cortex Agent plans across Cortex Analyst (retrieval) and a custom
  tool backed by the deployed model (scoring + explanation) to produce ranked, explained actions.

## References

- [Snowflake ML overview](https://docs.snowflake.com/en/developer-guide/snowflake-ml/overview)
- [Feature Store](https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/overview)
- [Datasets](https://docs.snowflake.com/en/developer-guide/snowflake-ml/dataset)
- [ML Functions: Classification](https://docs.snowflake.com/en/user-guide/ml-functions/classification) · [Anomaly Detection](https://docs.snowflake.com/en/user-guide/ml-functions/anomaly-detection)
- [Snowpark ML modeling](https://docs.snowflake.com/en/developer-guide/snowflake-ml/modeling)
- [ML Jobs](https://docs.snowflake.com/en/developer-guide/snowflake-ml/ml-jobs/overview)
- [ML pipelines & orchestration](https://docs.snowflake.com/en/developer-guide/snowflake-ml/create-pipelines-deploy) · [Task graphs (DAGs) with Python](https://docs.snowflake.com/en/developer-guide/snowflake-python-api/snowflake-python-managing-tasks)
- [Model Registry](https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/overview)
- [ML Observability](https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/model-observability) · [CREATE MODEL MONITOR](https://docs.snowflake.com/en/sql-reference/sql/create-model-monitor)
- [Cortex Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents) · [Create and manage agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-manage)
