# Speaker Notes: Call-Transcript Topics to Churn, Where the Data Already Lives

## Account Context Summary

For teams that already land recorded sales and success calls in Snowflake, model churn on a separate ML platform, and
are planning topic modeling, LLM labeling and price-sentiment work on the transcripts. The demo shows each of those steps
running next to the data, with measured results from a full build on synthetic data, and is honest where the result is
"parity" rather than "better". The run of show is in `demo_script.md`.

---

## Slide 1: Hero

**Talking Points:**
- The question is a business one: what are customers telling us on calls, what is new, and does it predict who cancels?
- Four numbers from the build: no planted PII left in what was embedded, business topics assigned at 98% accuracy in SQL,
  both hidden topics recovered, and call features improving churn ranking by 0.068 c-index.

**Presenter Notes:**
- Every row is synthetic and the generator planted the answers (`RAW.SEED_TRUTH`, `RAW.SEED_ACCOUNTS`); the CHECKs grade
  against them. Say so up front: it is why the numbers are exact, and why the absolute accuracy will differ on real calls.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql

---

## Slide 2: The hybrid most teams end up with

**Talking Points:**
- Transcripts are in the warehouse; the models and LLM calls are somewhere else, so features go out and scores come back.
- The usual reason is an assumption that the clustering and survival libraries are not available on Snowflake runtimes.
- PII travels with every copy, and re-clustering renumbers topics under the dashboards built on them.

**Presenter Notes:**
- Let the room name its own version of each card before moving on. Do not claim their pipeline is wrong; the claim is that
  each step can be measured in place.

**References:**
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/overview

---

## Slide 3: Architecture

**Talking Points:**
- Five schemas in one database. RAW is what the call platform and CRM deliver; CORE is segments, redaction and
  embeddings; ML is topics and models; FEATURES is the Feature Store; ANALYTICS is what people query.
- Text flows one way: masked raw column, redacted segments, embeddings from redacted text only.

**Presenter Notes:**
- The segment and embedding layers are incremental dynamic tables; redaction is a stream plus MERGE, because AI_REDACT in a
  dynamic table failed on refresh in our testing (it works on the initial build). That is a tested workaround, not a doc claim.

**References:**
- https://docs.snowflake.com/en/user-guide/dynamic-tables-about
- https://docs.snowflake.com/en/user-guide/streams-intro

---

## Slide 4: Where each step runs

**Talking Points:**
- Four boxes: SQL for declarative, incremental steps; warehouse Python for anything in the Snowflake package channel;
  Container Runtime for anything on PyPI or GPUs; outside only with a reason.
- umap-learn, hdbscan, lifelines and scikit-survival are all in the channel, so this whole lab runs in the first two boxes.

**Presenter Notes:**
- Verified pins in this build: umap-learn 0.5.11, hdbscan 0.8.33, scikit-learn 1.7.2 (hdbscan 0.8.33 calls a scikit-learn
  argument removed in later versions), lifelines 0.30.0, scikit-survival 0.23.1. umap-learn 0.5.4 failed to import
  (`pkg_resources`); use 0.5.11.
- EVOC is not in the channel. The path is an ML Job or Container Runtime notebook installing from
  `snowflake.snowpark.pypi_shared_repository`. Our EVOC job did not complete in testing, so say "the documented path", not "verified".

**References:**
- https://docs.snowflake.com/en/developer-guide/udf/python/udf-python-packages
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/ml-jobs/overview
- https://docs.snowflake.com/en/developer-guide/code-bundles/ml-code-bundles

---

## Slide 5: PII is gone before anything is embedded

**Talking Points:**
- A masking policy hides the raw text from everyone but the pipeline owner.
- Segments are about 136 tokens; short dials (63% of calls) are dropped before any AI cost.
- AI_REDACT runs once per segment through a stream; embeddings are built only from its output.

**Presenter Notes:**
- AI_REDACT limits: 4,096 input + output tokens per call, output up to 1,024; US PII plus some UK and Canadian categories;
  best effort. In one build it missed 2 staff names in 1,227 segments, which is why the known-name pass exists. Detect mode
  plus an allowlist is the documented way to keep names you choose.
- Expect "can we see the redaction?": notebook 01 Section 4 shows raw vs redacted side by side.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_redact
- https://docs.snowflake.com/en/user-guide/security-column-ddm-intro

---

## Slide 6: A new month costs only the new month

**Talking Points:**
- January arrives as appended rows. The redaction procedure processed 698 new segments and left the 1,227 history segments alone.
- The embedding dynamic table's refresh statistics say the same: 698 rows inserted.

**Presenter Notes:**
- Show the refresh statistics live if possible (notebook 01 Section 6, or Snowsight dynamic table refresh history). The
  whole month took 34 seconds on a MEDIUM warehouse.

**References:**
- https://docs.snowflake.com/en/user-guide/dynamic-tables-refresh

---

## Slide 7: Business topics first, then the ones nobody defined

**Talking Points:**
- The team writes two exemplar sentences per topic. Similarity in SQL assigns 75% of segments at 98% accuracy.
- What is left goes to UMAP + HDBSCAN in a stored procedure; both topics the generator hid were recovered.
- An LLM names each new cluster from six representatives: four calls, not hundreds, and the names wait for review.

**Presenter Notes:**
- The thresholds (similarity 0.47, margin 0.03, min_samples 10) were tuned on this data; on real calls tune them on a labeled sample.
- min_cluster_size scales with the leftovers (a tenth, at least 25). At a fixed 15 the seat-sharing topic split into three
  pure sub-clusters, a useful story about granularity.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_embed
- https://docs.snowflake.com/en/sql-reference/functions/vector_cosine_similarity
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/complete-structured-outputs

---

## Slide 8: Why density clustering and not k-means

**Talking Points:**
- k-means needs the number of clusters and assigns every segment, including the 44 that belong to no topic.
- HDBSCAN leaves those as noise, which keeps a new topic's members clean enough to name and to use as a feature.

**Presenter Notes:**
- Be honest about purity: on this clean synthetic text, k-means given the right k was about as pure (96.4% vs 95.7%). The
  argument is the forced assignment and not having to know k, not a purity win.

**References:**
- https://hdbscan.readthedocs.io/en/latest/how_hdbscan_works.html

---

## Slide 9: The clusterer is a versioned model

**Talking Points:**
- The fitted reducer and clusterer are a custom model with one array input, scored from SQL.
- V2, refit with January, kept both emerging topics (overlap 1.00 and 0.73 with V1); the version map carries reviewed names forward.

**Presenter Notes:**
- Model methods take at most 500 arguments, so a 1,024-dimension vector goes in as one array column (`EMBEDDING::ARRAY`).
- Each version's metrics name its training snapshot table, `ML.CLUSTER_TRAINING_V1` / `V2`.
- HDBSCAN `approximate_predict` assigns new points to existing clusters without refitting; refit on a schedule and map.

**References:**
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/custom-models
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/overview

---

## Slide 10: Price negativity by driver, and topics on lost deals

**Talking Points:**
- A cascade: a free keyword filter keeps a third of segments; AI_SENTIMENT with three price aspects; AI_CLASSIFY names the
  driver on the 292 negatives only.
- Driver attribution matched the planted driver 95.5% of the time, and price talk is more common on lost deals.

**Presenter Notes:**
- The per-aspect labels over-fire: one competitor complaint marked all three aspects negative. Use the overall label to
  decide negativity and AI_CLASSIFY for the single driver. That is a measured finding, worth sharing.
- AI_SENTIMENT takes up to 10 aspects of 30 characters or fewer.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_sentiment
- https://docs.snowflake.com/en/sql-reference/functions/ai_classify
- https://docs.snowflake.com/en/user-guide/views-semantic/overview

---

## Slide 11: Call signals are features, next to usage

**Talking Points:**
- Two managed feature views, computed from raw tables at every date in a snapshot calendar.
- Training is a point-in-time Dataset; scoring reads the same definitions at a later date.

**Presenter Notes:**
- Managed feature views must be deterministic: no CURRENT_DATE inside; the calendar is a plain table.
- dbt-built tables can be registered as external (view-backed) feature views; the Dataset can be read by a trainer outside
  Snowflake. The question "Feature Store or dbt?" usually becomes "dbt builds it, the Feature Store serves it point in time".

**References:**
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/overview
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/dataset

---

## Slide 12: Survival models, trained next to the data

**Talking Points:**
- Call features lift the best c-index from 0.548 to 0.616.
- On ranking, logistic regression ties the survival models. Survival earns its place by giving the probability of
  cancelling by any date from one model and by handling accounts still active at the end of follow-up.

**Presenter Notes:**
- Do not claim survival beats logistic here: it did not (0.611 vs 0.616 on the test split).
- Explainability: the Cox version has an `explain` method returning each feature's contribution to the log-hazard; the
  top-risk account's leading drivers were negative price remarks. Built-in explainability does not apply to custom
  models, which is why it is a model method.
- The model monitor needed a model task set (`TABULAR_BINARY_CLASSIFICATION`) because it monitors a probability against a 0/1 outcome.

**References:**
- https://lifelines.readthedocs.io/en/latest/
- https://scikit-survival.readthedocs.io/en/stable/
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/experiments
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/model-observability

---

## Slide 13: The data-gravity ledger

**Talking Points:**
- One scoring task, two paths under two query tags: the round trip trains and scores a model on the client (4,000 rows out, 2,000 back); in place scores with the registered model in SQL (none).
- The same query-history queries size an existing loop.

**Presenter Notes:**
- Wall time is not the argument at this size: the round trip took 5.2 s and in place 12.6 s for 2,000 rows. Say it
  before someone else does; the argument is rows moved and copies created.
- INTERNAL ONLY, do not show or forward: on the account this demo was prepared for, a scheduled pipeline builds about five
  million feature rows a day in Snowflake and Python write_pandas loads write about fifteen million prediction rows a day
  back (about 81,600 COPY statements in 90 days, about 16 minutes a day on a Large warehouse). Use it only to frame the
  question "what does your daily loop move?"; never quote it to the customer as our measurement of them.

**References:**
- https://docs.snowflake.com/en/sql-reference/account-usage/query_history
- https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/overview

---

## Slide 14: Spend and PII controls

**Talking Points:**
- Estimate before running, process each row once, cap and watch spend, govern the text.

**Presenter Notes:**
- Per-user AI quotas: `SNOWFLAKE.CORE.QUOTA` with the `AI FUNCTION` shared resource and block enforcement; custom budgets on
  the warehouse; `CORTEX_AI_FUNCTIONS_USAGE_HISTORY` filtered by query tag (each notebook sets one).
- AI_COUNT_TOKENS on a one-line input to `ai_redact` returned 434 tokens in testing: prompt overhead dominates short inputs,
  another reason to segment rather than redact turn by turn.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-func-cost-management
- https://docs.snowflake.com/en/user-guide/budgets
- https://docs.snowflake.com/en/sql-reference/functions/ai_count_tokens

---

## Slide 15: The demo

**Talking Points:**
- One app, one live moment, one question: the story without code on screen.
- Switch to the app here (demo script, App path); come back for the first slice.

**Presenter Notes:**
- `CHURN_STORY_APP` reads tables the notebooks built; page 3 runs `ANALYTICS.LIVE_STEP` six times (arrive, segments,
  redact, embed, topics, price). Rehearsal runs took about 90-115 s; the topics step is about 50 s of it, mostly the
  clustering model's Python startup in the warehouse.
- Run `./demo.sh app-reset` before the show so January is waiting; `./demo.sh app-load` is the terminal fallback.
- The agent `CHURN_INSIGHTS_AGENT` uses `ANALYTICS.CHURN_STORY_SV` and `ANALYTICS.CALL_SEARCH` (redacted segments only).

**References:**
- https://docs.snowflake.com/en/developer-guide/streamlit/app-development/runtime-environments
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents

---

## Slide 16: A first slice

**Talking Points:**
- One month of calls: segment, redact, embed; seed the business topics and measure them on a labeled sample; price
  sentiment by driver behind a semantic view. Churn second, once the call signals exist as a feature view.

**Presenter Notes:**
- Agree readiness criteria before the slice starts: redaction reviewed on a sample, seeded-topic accuracy on the labeled
  sample, token cost per month, and who owns reviewing proposed topics.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql
