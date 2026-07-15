# Speaker Notes: Donor Lapse/Churn Intelligence — Snowflake ML → Agent

## Account Context Summary

Generic, client-agnostic demo for a **nonprofit fundraising CRM** scenario. Two personas
in the room: an **ML Ops / platform team** (owns churn models, Registry, Serving,
Observability) and an **executive** audience (wants a natural-language chatbot over
the data). The narrative deliberately maps to those two initiatives so it is reusable
across accounts — swap the entity (donor → customer / patient / subscriber) and the same
lifecycle demonstrates churn, propensity, or risk. All data is synthetic (~50K donors,
~600K gifts, ~950K engagements). Keep the live flow to ~15 minutes; the notebook carries
the depth.

---

## Slide 1: Overview

**Talking Points:**
- Frame the whole session in one sentence: predict which donors will lapse, explain every score, and let a fundraiser act on it in natural language — all inside one governed Snowflake account.
- The four stats are the spine of the demo: 50K donors modeled end-to-end, a 31% baseline lapse rate we're attacking, a 0.96 F1 model trained in-Snowflake, and 10+ distinct Snowflake ML capabilities exercised.
- Set expectations: we walk the full lifecycle, then finish by talking to a Cortex Agent that calls the deployed model as a tool.

**Presenter Notes:**
- This deck is intentionally comprehensive (17 slides, incl. one optional orchestration slide) because it doubles as an ML platform enablement asset. For a 15-minute flow, land slides 2, 3, 6, 9, 14, 15 and skim the rest.
- Versus running a separate ML stack, the advantage to say early is "no data movement + one governance perimeter."

**References:**
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/overview

---

## Slide 2: The Problem

**Talking Points:**
- Nonprofits today flag at-risk donors with hand-tuned RFM rules in a BI tool — brittle, drifting, and unable to rank a whole file by risk.
- Real models mean exporting donor PII to a separate platform: a governance and security blocker that stalls before production.
- Even a good model outputs a score, not an action; frontline gift officers can't self-serve "who's at risk in my region and what do I do?"

**Presenter Notes:**
- This is the "three separate platforms" pain: a BI tool, an ML stack, and a chatbot. The Snowflake answer is that all three collapse into one platform.
- Nonprofit organizations are especially sensitive to donor-PII movement — lean on governance, not just performance.

**References:**
- https://docs.snowflake.com/en/guides-overview-ml-functions

---

## Slide 3: Architecture

**Talking Points:**
- Walk the layers top to bottom: source tables → Feature Store + versioned Dataset → Snowpark ML + ML Jobs → Registry, Serving, Observability → the Cortex Agent.
- Emphasize the entry point (bottom node): the agent's two tools are Cortex Analyst (retrieval over a governed semantic view) and a custom tool that calls the *deployed lapse model* to score and explain donors.
- Everything in one account: no data leaves, one RBAC model, one lineage graph.

**Presenter Notes:**
- The four schemas (RAW / FEATURES / MODELS / ANALYTICS) mirror a real MLOps separation — call this out for the platform team; it's how they'd actually organize it.
- If asked "why not just Cortex Analyst?" — Analyst answers descriptive questions; it can't predict. The custom model tool is what makes this predictive + prescriptive.

**References:**
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/overview
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents

---

## Slide 4: Feature Store

**Talking Points:**
- Register a `donor` entity once, then define **managed** Feature Views that compute RFM, engagement, and wealth signals **directly from the raw `DONATIONS`, `ENGAGEMENTS`, and `DONORS` tables** — the store is the real source of truth, not a copy of a precomputed table.
- A static snapshot calendar gives every value an `AS_OF_TS` — the point-in-time key that prevents train/serve skew and lets us retrieve features "as of" any date.
- The same definitions feed both training (as-of 12 months ago) and inference (as-of today), so the score a gift officer sees is computed exactly like the model was trained. Notebook 01 proves it: the same view returns different values at the two as-of dates.

**Presenter Notes:**
- Managed Feature Views are Dynamic Tables under the hood, so their definitions must be deterministic — that's why the as-of dates come from a static calendar table, never `CURRENT_DATE()` inside the view. Reassure platform teams they inspect/govern them with normal RBAC.
- Point-in-time correctness (ASOF JOIN) is the differentiator vs. hand-rolled feature tables; most home-grown pipelines leak future data.

**References:**
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/overview

---

## Slide 5: Datasets

**Talking Points:**
- `generate_dataset` materializes an immutable, versioned training snapshot from the Feature Store using point-in-time joins on a spine (donor_id + as_of_date + label).
- Each version is frozen and lineage-tracked — you can re-materialize the exact training set for an audit or a retrain.
- Stress the no-leakage design: features are computed as-of the snapshot; the label comes from the *following* 12 months.

**Presenter Notes:**
- Datasets incur storage cost — mention deleting stale versions. Good hygiene talking point for cost-conscious nonprofits.
- Datasets vs. a plain table: immutability + Parquet file access for external frameworks (PyTorch/TF) if they go deep learning later.

**References:**
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/dataset

---

## Slide 6: Cortex ML Functions

**Talking Points:**
- This is the "heuristics → ML" bridge, all in SQL: Forecasting (next-quarter donation volume), Anomaly Detection (giving drop-off), and Classification (baseline lapse model).
- The baseline classifier trains in about a minute and gives evaluation metrics and feature importance for free — analysts get value the same afternoon.
- Show the feature-importance result: recency → tenure → engagement → wealth. That ranking becomes the story for "why is this donor at risk."

**Presenter Notes:**
- Position ML Functions as the on-ramp, not the destination. When the team needs custom control, HPO, or per-donor Shapley, they graduate to Snowpark ML — on the same data.
- ML Functions run with limited privileges and need table/view references (SYSTEM$REFERENCE) — that's why the input is passed as a reference, not inline.
- Training uses a Snowpark-optimized warehouse in the lab for headroom on larger inputs.

**References:**
- https://docs.snowflake.com/en/user-guide/ml-functions/classification
- https://docs.snowflake.com/en/user-guide/ml-functions/anomaly-detection

---

## Slide 7: Snowpark ML Modeling + Experiment Tracking + HPO

**Talking Points:**
- Train an XGBoost lapse classifier with the `snowflake.ml.modeling` API — the fit runs in Snowflake, no data export.
- Every candidate config is logged as a run under one **experiment** (`DONOR_LAPSE`) via `snowflake.ml.experiment` — params + AUC/F1 from `predict_proba` — so runs compare side-by-side in AI & ML → Experiments.
- Distributed HPO (`GridSearchCV`) sweeps hyperparameters across the warehouse; the best config is refit and becomes the registered model.

**Presenter Notes:**
- Evaluate AUC on `predict_proba` output, not the hard class — a common mistake that makes AUC look degenerate.
- The modeling API mirrors scikit-learn (`input_cols`/`label_cols`/`output_cols`) — familiar to any data scientist, which lowers adoption friction.
- If they ask about class imbalance (31% lapse), mention `scale_pos_weight` and threshold tuning; don't rabbit-hole live.

**References:**
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/modeling

---

## Slide 8: ML Jobs on Container Runtime

**Talking Points:**
- The `@remote` decorator ships a Python function to a Snowflake compute pool running the Container Runtime — a pre-built ML image.
- You can add a GPU instance family, install any PyPI package, and productionize the exact code the data scientist wrote from VS Code or a notebook.
- `job.result()` blocks until the remote training finishes and returns the fitted model.

**Presenter Notes:**
- ML Jobs need `snowflake-ml-python >= 1.26` and a compute pool (CREATE COMPUTE POOL privilege). The lab's compute-pool DDL is commented out by default so setup.sql runs for roles without that privilege.
- This is the answer to "can my team keep their IDE?" — yes, remote execution into Snowflake compute, no infra to manage.

**References:**
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/ml-jobs/overview

---

## Slide 9: Model Registry

**Talking Points:**
- `log_model` records the model with metrics, signature, sample input, and metadata as a first-class Snowflake object.
- `target_platforms` lets the same model serve from a warehouse or from SPCS — decided at log time.
- Promoting a challenger to DEFAULT is one line; lineage links source data → Feature Views → Dataset → model.

**Presenter Notes:**
- The Registry is the governance centerpiece for the platform team — versioning + lineage + RBAC on models is exactly what home-grown MLflow setups struggle to secure.
- Emphasize "regardless of where it was trained" — externally trained models can be logged and served here too.

**References:**
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/overview

---

## Slide 10: Model Explainability

**Talking Points:**
- Shapley attributions turn a probability into a reason a fundraiser trusts: "last gift 410 days ago, engagement down 63%."
- Explainability is enabled at registration (`options={"enable_explainability": True}` in `log_model`) and runs on the registered model via the `explain` function — no separate tooling.
- The per-donor drivers are what the agent surfaces in the final ranked list.

**Presenter Notes:**
- The table values are illustrative; the live feature-importance from our trained model ranks recency, tenure, engagement, wealth — consistent with the drivers shown.
- Explainability + a governed model is a strong nonprofit board/compliance story: every retention decision is defensible.

**References:**
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/model-explainability

---

## Slide 11: Model Serving

**Talking Points:**
- Two modes from one model: batch-score all 50K donors, or real-time score a single donor when a gift officer opens a record.
- `mv.run(..., function_name="predict")` for in-warehouse inference; `mv.run_batch(...)` on a compute pool for large or GPU workloads.
- Results land next to the CRM data — no export, no second system to secure.

**Presenter Notes:**
- Warehouse serving is the simplest path; SPCS serving is for high-throughput or GPU. Let the customer's latency/volume needs drive the choice.
- Batch inference writes to a stage and can run inside a Task DAG for scheduled scoring — good segue to their orchestration story.

**References:**
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/inference/batch-inference-jobs

---

## Slide 12: ML Observability

**Talking Points:**
- `CREATE MODEL MONITOR` tracks prediction drift, data drift, and accuracy over time against a baseline snapshot.
- `SEGMENT_COLUMNS=('REGION')` monitors quality per region — so you catch a model decaying in the West before it hurts a campaign.
- An alert fires when performance degrades; query metrics with the `MODEL_MONITOR_*_METRIC` table functions.

**Presenter Notes:**
- Constraints to know: timestamps must be TIMESTAMP_NTZ, prediction/actual columns must be NUMBER, monitor lives in the same schema as the model, and source data can't contain NULLs/NaNs.
- This directly answers the "how do we know the model still works?" governance question — usually the missing piece in home-grown MLOps.

**References:**
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/model-observability
- https://docs.snowflake.com/en/sql-reference/sql/create-model-monitor

---

## Slide 13 (Optional): Orchestrate the Pipeline as a Task Graph

**Talking Points:**
- Everything so far ran interactively; to productionize, wrap the same steps in a task graph (DAG) so retraining runs on a schedule or trigger, with automatic retries and full run history.
- Built with the Snowflake Python API (`snowflake.core.task.dagv1`): four stages — prep → train+register → score → refresh monitor — wired with `>>` and deployed in one call.
- The training stage is a Snowflake **ML Job on the compute pool**, attached natively to the task (not wrapped in a stored procedure) — the modern ML-Job-in-Task integration. Each run publishes a new Registry version and promotes it to DEFAULT.
- Show it in Snowsight → Monitoring → Task History (Graph view): nodes light up as each stage runs; click the train node to drill into the ML Job.

**Presenter Notes:**
- This is the optional Section 14 of the lab — advanced. Requires the `DONOR_CHURN_ML_POOL` compute pool, `snowflake-ml-python >= 1.26`, and CREATE/EXECUTE TASK. Skip for audiences without a platform/MLOps focus.
- Best slide for the platform team's "how do we operationalize this?" question. Snowflake ML also integrates with external orchestrators (Airflow/Dagster/Prefect), but Task Graphs are the native, zero-infra option.
- Deploying the DAG does not run it — you trigger a one-off run or let the schedule fire. Parameterize the script for DEV/PROD and keep it in Git.

**References:**
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/create-pipelines-deploy
- https://docs.snowflake.com/en/developer-guide/snowflake-python-api/snowflake-python-managing-tasks

---

## Slide 14: Cortex Agent — Model as a Tool

**Talking Points:**
- The agent has two tools: Cortex Analyst (text-to-SQL over the governed semantic view) and a custom tool that calls the deployed lapse model.
- The custom tool is backed by a SQL procedure — `PREDICT_DONOR_CHURN(donor_id)` and the batch variant `TOP_CHURN_RISK(segment, n)` — that returns churn probability, top-3 Shapley drivers, and a recommended action.
- The agent plans across tools: retrieve a segment via Analyst, score it via the model tool, then rank and explain.

**Presenter Notes:**
- In the agent spec, the custom tool is `type: "generic"`. Attaching a stored-procedure/UDF tool is most reliable through the Snowsight UI (AI & ML → Agents → Custom tools), which wires the identifier, parameters, and warehouse; the notebook shows the spec and the UI step.
- Grant USAGE on the procedure to the agent's role; owner's-rights vs. caller's-rights matters for what data the tool can read.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-manage
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents

---

## Slide 15: The "Wow" Moment

**Talking Points:**
- Ask the agent live: "Which of our major-gift donors in the West region are most at risk of lapsing this quarter, why, and what should we do?"
- Narrate the plan as it runs: Analyst pulls the West major-gift segment → the model tool scores each donor → the agent returns a ranked list with probabilities, drivers, and next-best actions.
- Then the follow-up: "Draft outreach for the top 3." The agent writes personalized stewardship messages grounded in each donor's risk drivers.

**Presenter Notes:**
- This is the emotional peak — retrieval + prediction + explanation + generation in one conversation. Slow down and let it land.
- In our data, West + Major is a *low* lapse segment (~7%), which is realistic — high-wealth donors churn less. If you want a scarier number live, ask for a higher-churn segment (Grassroots, or Online-acquired) or just rank within West-Major.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents

---

## Slide 16: Mapping to Live Use Cases

**Talking Points:**
- Two common nonprofit-CRM initiatives map cleanly onto this demo: an ML Ops & Platform build (churn models, Registry, Serving, Observability, plus the optional Task-Graph orchestration — slides 1–9 + 13) and an executive chatbot (Analyst + Snowflake Intelligence + Streamlit — slides 14–15).
- The scenario is deliberately generic: swap donor → customer / patient / subscriber and the exact same lifecycle demonstrates churn, propensity, or risk.

**Presenter Notes:**
- Use this slide to connect the demo to whatever initiative the audience has already described — pick the row that matches and go deeper there.
- No client names in this asset by design, so it is reusable across any scenario.
- The hands-on lab is three notebooks — `donor-churn-01-features`, `-02-model`, `-03-serve-agent` — each standalone with a rehydrate cell, so you can demo one lifecycle stage without running the others end-to-end.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-intelligence

---

## Slide 17: Next Steps

**Talking Points:**
- Concrete path: run `setup.sql`, walk the notebook sections 2–13 (optional Section 14 orchestrates it as a Task Graph), then chat with the agent (Streamlit app or Snowsight AI & ML → Agents).
- Reframe the entity/features for the customer's domain — the lifecycle is unchanged.
- Offer to scope their MLOps program: map Registry, Serving, and Observability to their governance and retraining requirements.

**Presenter Notes:**
- Best live path is Snowsight → Workspaces → Create Workspace from Git repo, so `get_active_session()` handles auth with no local setup.
- Leave them with the one-liner on the slide; it's the whole story in a sentence.

**References:**
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/overview
