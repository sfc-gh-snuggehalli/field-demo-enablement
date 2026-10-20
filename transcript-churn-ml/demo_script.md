# Demo Script: Call-Transcript Topics to Churn, Where the Data Already Lives

Three ways to run this demo:

- **[App path](#app-path-recommended-15-min)** (recommended, about 15 minutes, any audience): a Streamlit story app with one live moment, then the Snowflake Intelligence agent. No code on screen.
- **[ML lifecycle path](#ml-lifecycle-path-cowork-app-notebooks-35-min)** (about 35 minutes, an ML, BI and data engineering team that sent questions in advance): CoWork, then the app's live step, then the notebooks and Snowsight in ML lifecycle order. Each stop answers named questions from the Section 6 brief.
- **[Technical deep dive](#technical-deep-dive-notebooks-25-min)** (about 25 minutes, ML engineers, data scientists and data engineers): the deck interleaved with the five lab notebooks and Snowsight. The [Cuts](#cuts) bring it to 15. Slide-by-slide detail lives in `presentations/transcript-churn-ml-speaker-notes.md`.

The audience should leave with three points:

1. **The text never leaves, and PII is gone before anything is embedded.** Masked raw column, redaction once per segment, embeddings from redacted text only, and each new month costs only its own rows.
2. **Business topics in SQL, new topics by density clustering, both versioned.** The clusterer is a registry model scored from SQL; a refit is matched to the last one so names survive.
3. **Call signals improve churn ranking, measured next to the data.** The libraries are in the Snowflake channel; the honest result is a +0.068 c-index lift from call features, and survival tied with logistic on ranking.

How to read the beats: **Say** is spoken (paraphrase freely), **Do** is a click or keystroke, **Show** is where to point and the value the room should see, **If** is the fallback.

## App path (recommended, ~15 min)

One app, one live moment, one question. Everything on screen is a page of `CHURN_STORY_APP` or a chat in Snowflake
Intelligence; the notebooks stay closed unless someone asks how it is built.

### Pre-flight (app path)

- The day before: `./demo.sh build --yes` has passed, then `./demo.sh app --yes` printed the app URL and the agent name.
- Rehearse once: open the app, run page 3 live, ask the agent all three sample questions. Screenshot page 3's step
  table and the agent's revenue answer; they are your fallback.
- 30 minutes before: `./demo.sh app-reset` (January must be waiting for page 3), resume the warehouse
  (`ALTER WAREHOUSE TRANSCRIPT_CHURN_ML_WH RESUME;`), open the app on page 1 and Snowflake Intelligence
  (`https://ai.snowflake.com`) in a second tab with the agent **Call insights and churn risk** selected.

### Run of show (app path)

| # | Page | Minutes | The one point |
|---|---|---|---|
| A0 | 1. The question | 1 | 2,000 accounts, 27% churned, calls nobody can count yet |
| A1 | 2. Governed text | 2 | PII is gone before any AI reads the text |
| A2 | 3. January arrives (live) | 3 | New calls flow through on their own; history is not reprocessed |
| A3 | 4. What customers talk about | 2 | The calls surfaced topics nobody defined |
| A4 | 5. Does it predict churn? | 3 | Call signals lift the churn model, and explain who is at risk |
| A5 | 6. Where the data stayed | 1 | Scoring in place moves zero rows |
| A6 | 7. Ask it yourself | 3 | Anyone can ask, in plain language, over the same governed data |
| | **Total** | **15** | |

### A0. The question (page 1, 1 min)

- **Say:** "Two thousand subscription accounts, and about a quarter of them churned. Every week the team records
  about a hundred calls, but nobody can count what customers complain about, and the churn model only sees product usage."
- **Show:** the four tiles (Accounts 2,000; Churned within 9 months 27%; Recorded calls; Monthly revenue) and the
  calls-by-type bar: most calls are short outbound dials with no conversation.
- **Do:** Next.

### A1. Governed text (page 2, 2 min)

- **Say:** "Before any other AI function reads this text, two controls apply: a masking policy on the raw column,
  and AI_REDACT on every segment."
- **Show:** Phone numbers left **0**, against the count before redaction; email addresses and staff names left 0.
  Point at the orange placeholders in the sample segments.
- **If** asked "is AI_REDACT perfect?": "No, it is best effort, which is why a deterministic pass removes the names
  we know, such as our own staff."

### A2. January arrives, live (page 3, 3 min)

- **Say:** "January's recordings just landed. Watch what the pipeline does with them."
- **Do:** **Load January's calls**. The checklist ticks through six steps in about 1.5 to 2 minutes; talk over it.
- **Show:** 698 new segments, the AI-call count, and **History segments re-redacted: 0** (measured from the
  redaction timestamps). "Each segment is redacted, embedded and billed once."
- **If** it is slow: the run executes in Snowflake, not in the browser, so move on to page 4 and come back; page 3
  shows the steps finishing. If a step fails, the page says which one and offers **Finish loading January**, which
  skips the steps already done (`./demo.sh app-load` does the same from a terminal). Before the reset, the expander
  **Last completed run** shows your rehearsal's numbers; your screenshot is the last resort.

### A3. What customers talk about (page 4, 2 min)

- **Say:** "Eight topics the business defined are matched first. The rest are clustered, and an LLM proposes a
  name. Nobody asked for these three."
- **Show:** AI content generation more than triples in January (26 to 95 segments) in the discovered-topics chart. Then the three cards
  marked **Pending review**: a person approves a topic before it becomes official. Pick a topic to read a few quotes.

### A4. Does it predict churn? (page 5, 3 min) — never cut

- **Say:** "The churn model already had usage. Adding what customers say lifts it, on accounts the model never saw."
- **Show:** best c-index usage only about 0.55, usage plus calls about 0.62 (0.5 is a coin flip). Then
  **Top reason comes from calls** for the high-risk band. Select the top account: orange bars raise its risk, and
  most of them are call features; the quotes on the right say the same thing in the customer's words. The scores
  come from the registered Cox model (c-index 0.611) and are as of 1 January 2026, so January's calls do not change
  them.
- **If** asked about the Cox model: "The registered default is a survival model; on ranking it tied with logistic,
  and the survival form gives time-to-churn."

### A5. Where the data stayed (page 6, 1 min)

- **Show:** Round trip moved 4,000 rows out and 2,000 back; in place moved 0. "At this size both take seconds. What
  differs is how much data crosses the boundary." Then the live step's AI calls.

### A6. Ask it yourself (page 7, then Snowflake Intelligence, 3 min)

- **Do:** switch to the Snowflake Intelligence tab and paste: *How much monthly revenue is in high-risk accounts by
  plan tier, and what is their most common risk driver?*
- **Show:** the answer by tier, with Enterprise carrying the most revenue at risk (value-for-money complaints).
  Then *What are customers saying about competitor pricing?* for quotes.
- **Say:** "Same semantic view, same redacted text, same governance. The agent never sees the raw transcripts."
- **If** the agent is unavailable: page 7's chart is the first question answered through the same semantic view.

### Cuts (app path)

- 10 minutes: page 2 to one sentence and the zero tile; skip page 6; ask the agent one question.
- Never cut page 3 (live) or page 5 (the churn lift).

### After a show

- `./demo.sh app-reset` if you will present again; otherwise leave January loaded.

---

# ML lifecycle path (CoWork, app, notebooks, ~35 min)

Start where a business user ends up, the agent in CoWork (formerly Snowflake Intelligence), then walk back through how
the answer was produced, one ML lifecycle stage at a time: ingest and govern, features, train and track, register and
version, evaluate, score, monitor, control cost. Each stop names the Section 6 questions it answers (ML 1-9, Gov 1-2,
Arch 1-2), so the brief and the screen tell the same story.

### Pre-flight (lifecycle path)

- Everything in the app path's pre-flight: build passed, `./demo.sh app-reset` so January is waiting, warehouse
  resumed, CoWork (`https://ai.snowflake.com`) open with **Call insights and churn risk** selected.
- The five executed notebooks open, as in the deep dive's pre-flight. Present from their outputs; nothing below needs
  a notebook cell re-run live.
- Snowsight tabs: **AI & ML » Models** (TOPIC_CLUSTERER, CHURN_SURVIVAL), **AI & ML » Feature Store**, and a SQL
  worksheet with the three queries from L3, L6 and L7 pasted in.

### Question coverage

| Brief question | Stop | What the room sees |
|---|---|---|
| ML 1 Packages and dev loop | L4 | UMAP + HDBSCAN, lifelines, scikit-survival trained in warehouse stored procedures |
| ML 2 Registry for the clusterer | L5 | TOPIC_CLUSTERER V1 and V2, `!PREDICT` from SQL, Jaccard version map |
| ML 3 Feature Store vs dbt | L3 | Two feature views, a point-in-time Dataset, lineage from raw tables |
| ML 4 AI_EMBED model, cost, retirement | L2 | 698 new segments embedded incrementally; token estimate before the run |
| ML 5 AI function accuracy | L6 | Price cascade: 95.5% driver attribution, 91% recall, aspect over-firing |
| ML 6 Vector similarity vs Cortex Search | L1, L3 | Agent quotes via Cortex Search; seeded topics via a 1.7 s SQL join |
| ML 7 Monitoring | L8 | CHURN_MONITOR AUC by scoring date; topic-mix shift by month |
| ML 8 Labeling | L5 | Proposed topic names land PENDING; the app's review cards |
| ML 9 Open-weights model in a container | Close | Not shown; say the pattern |
| Gov 1 Spend controls | L2, L9 | AI-call count on the live step; token estimate vs usage history; quota and budget SQL |
| Gov 2 Transcript PII | L1, L2 | Masked raw column, AI_REDACT before embedding, agent quotes keep placeholders |
| Arch 1 Airflow vs tasks and dynamic tables | L2 | A new month flows through a dynamic table and a stream; procedures any scheduler can call |
| Arch 2 Data share vs Fivetran | Close | Not shown; say the pattern |

### Run of show (lifecycle path)

| # | Lifecycle stage | Where | Minutes | Questions |
|---|---|---|---|---|
| L1 | Consume: the answer a business user gets | CoWork | 3 | ML 6, Gov 2 |
| L2 | Ingest and govern, live | App pages 2-3, notebook 01 §5 | 5 | Gov 2, Arch 1, ML 4, Gov 1 |
| L3 | Features | Notebook 02 §1, notebook 04 §1-2, Feature Store, lineage | 5 | ML 3, ML 6 |
| L4 | Train and track | Notebook 02 §2, notebook 04 §3-4 | 5 | ML 1 |
| L5 | Register, version, review | Models page, notebook 02 §4-6, app page 4 | 5 | ML 2, ML 8 |
| L6 | Evaluate the AI functions | Notebook 03 §1 | 3 | ML 5 |
| L7 | Score in place | App page 5, notebook 05 §1-2 | 3 | ML 2, ML 3 |
| L8 | Monitor | Monitor SQL, topic-mix SQL | 3 | ML 7 |
| L9 | Control cost | Notebook 05 §4-5 | 2 | Gov 1 |
| | Close: what we did not show | Brief | 1 | ML 9, Arch 2 |
| | **Total** | | **35** | |

### L1. Consume: the answer a business user gets (CoWork, 3 min)

- **Say:** "This is where most people will meet the work: a question in plain language. The next half hour walks
  back from this answer to how each piece was built and kept up to date."
- **Do:** paste *How much monthly revenue is in high-risk accounts by plan tier, and what is their most common risk
  driver?*
- **Show:** revenue at risk by tier, Enterprise carrying the most. Expand the reasoning: the **call_metrics** tool is
  Cortex Analyst over `ANALYTICS.CHURN_STORY_SV`.
- **Do:** paste *What are customers saying about competitor pricing? Show a few quotes.*
- **Show:** quotes with `[NAME]` placeholders, from the **call_quotes** tool (Cortex Search over the redacted
  segments). "The index only ever saw redacted text." (Gov 2)
- **Say (ML 6):** "Search is here because a person is asking open questions interactively. The batch topic matching
  you'll see in L3 is a plain SQL similarity join; it doesn't need a search service."

### L2. Ingest and govern, live (app pages 2-3, notebook 01 §5, 5 min)

- **Do:** app page 2. **Show:** the masked raw column and phone numbers left **0**. (Gov 2)
- **Do:** page 3, **Load January's calls**; talk through L2 while the six steps tick (about 1.5 to 2 minutes).
- **Say (Arch 1):** "Segments and embeddings are dynamic tables; redaction runs through a stream because AI_REDACT
  failed on dynamic-table refresh in testing. Each step is a stored procedure call, so Airflow can trigger it
  exactly as it triggers your jobs today."
- **Say (ML 4):** "Embeddings are snowflake-arctic-embed-l-v2.0: 1,024 dimensions, 512-token context, 0.05 AI credits
  per million tokens. Segments are about 136 tokens, so nothing is truncated, and every vector stores its model name
  for the day the model is retired and you re-embed."
- **Show:** **698 new segments**, the AI function call count (Gov 1), **History segments re-redacted: 0**.
- **Do:** notebook 01 §5, `check_s5`. **Show:** one embedding model across all vectors.
- **If** asked about retirement: `SHOW CORTEX BASE MODELS` lists each model's status; plan a re-embed backfill,
  exemplars included, when a model goes legacy.

### L3. Features (notebook 02 §1, notebook 04 §1-2, Feature Store, 5 min)

- **Do:** notebook 02 §1, `seeded_by_topic`. **Show:** **74.8% of segments seeded at 97.9% accuracy; the join over
  16 exemplars ran in under 2 seconds**. (ML 6)
- **Do:** Snowsight **Feature Store**: entity ACCOUNT, views **ACCOUNT_USAGE_FV** and **ACCOUNT_CALL_SIGNALS_FV**.
- **Do:** notebook 04 §1 CHECK. **Show:** negative price remarks per account **0 → 0.051 → 0.087** across snapshot
  dates. Then §2: the **CHURN_TRAINING** Dataset V1, 2,000 accounts as of 2026-01-01.
- **Say (ML 3):** "Keep dbt building tables. Register them as feature views, or let the Feature Store manage them.
  What it adds is the point-in-time join and a versioned Dataset that a model trained anywhere can read."
- **Do:** the lineage query in the worksheet (or the Dataset's **Lineage** tab):

  ```sql
  SELECT DISTANCE, SOURCE_OBJECT_NAME, TARGET_OBJECT_DOMAIN, TARGET_OBJECT_NAME, TARGET_OBJECT_VERSION
  FROM TABLE(SNOWFLAKE.CORE.GET_LINEAGE('TRANSCRIPT_CHURN_ML_DEMO.FEATURES.CHURN_TRAINING', 'DATASET', 'UPSTREAM', 3, 'V1'));
  ```

- **Show:** raw `ACCOUNTS`, `USAGE_EVENTS`, `SEGMENT_TOPICS` and `PRICE_SENTIMENT` feed the two feature views, which
  feed the Dataset.

### L4. Train and track (notebook 02 §2, notebook 04 §3-4, 5 min)

- **Do:** notebook 02 §2, `register_discovery_procedure` (scroll the package list) and the CHECK.
- **Show:** **4 clusters on 252 leftovers, 44 noise**. **Say (ML 1):** "umap-learn, hdbscan and scikit-learn come
  from the Snowflake channel and run in a warehouse stored procedure: no image to build. Pin versions: umap-learn
  0.5.11, hdbscan 0.8.33 with scikit-learn 1.7.2."
- **Do:** notebook 04 §3, the c-index pivot. **Show:** **usage only 0.548 → with call features 0.616**, survival
  tied with logistic. lifelines and scikit-survival trained the same way.
- **Do:** §4, the six runs in experiment **CHURN_SURVIVAL** (Snowsight, or `check_s4`). "Every candidate is logged
  with its parameters and test c-index, including the ones we didn't ship."
- **Say (ML 1, the rest):** "Packages outside the channel, EVOC for example, run in Container Runtime notebooks or ML
  Jobs installed from PyPI. Keep uv locally; Workspaces with Git share the notebooks. We didn't run EVOC here."

### L5. Register, version, review (Models page, notebook 02 §4-6, app page 4, 5 min)

- **Do:** Snowsight **Models » TOPIC_CLUSTERER**. **Show:** V1 and V2, V2 the default, V1's metrics naming its
  training snapshot. Then **CHURN_SURVIVAL**: **COX_CALLS** (default) and **GB_CALLS**.
- **Do:** notebook 02 §4, `score_from_sql`. **Show:** January leftovers scored with
  `TOPIC_CLUSTERER!PREDICT(EMBEDDING::ARRAY)`, noise as `-1`. **Say (ML 2):** "One array input, because a method takes
  at most 500 arguments. Scoring is SQL, so a task or your scheduler can run it."
- **Do:** §6 CHECK. **Show:** emerging topics carried V1 → V2 at **Jaccard 1.0 and 0.73**. "A refit renumbers
  clusters; the overlap map keeps the reviewed name."
- **Do:** §5, `PROPOSED_V1`, then app page 4's cards marked **Pending review**. **Say (ML 8):** "There's no labeling
  product. This is a review table with a status, and a Streamlit page over it. The reviewed rows become the labeled
  sample for L6."
- **Do:** the second lineage query: the training table feeds both model versions, and the default feeds the monitor.

  ```sql
  SELECT DISTANCE, SOURCE_OBJECT_NAME, TARGET_OBJECT_DOMAIN, TARGET_OBJECT_NAME, TARGET_OBJECT_VERSION
  FROM TABLE(SNOWFLAKE.CORE.GET_LINEAGE('TRANSCRIPT_CHURN_ML_DEMO.FEATURES.CHURN_TRAINING_SOURCE', 'TABLE', 'DOWNSTREAM', 2));
  ```

### L6. Evaluate the AI functions (notebook 03 §1, 3 min)

- **Do:** notebook 03 §1, `price_negatives_by_driver` and the CHECK.
- **Show:** AI_SENTIMENT ran on **33% of segments** after a keyword prefilter; driver attribution matched the planted
  driver **95.5%** of the time, **91% recall**.
- **Say (ML 5):** "Per-aspect labels over-fired: one competitor complaint marked all three price aspects negative. So
  the overall label decides negativity and AI_CLASSIFY names one driver. This is clean synthetic text; on your calls,
  hand-label 200 to 300 segments and compare functions and models in AI Function Studio's evaluation, in Preview."

### L7. Score in place (app page 5, notebook 05 §1-2, 3 min)

- **Do:** app page 5, select the top account. **Show:** its drivers from the model's EXPLAIN method, mostly call
  features, and the quotes beside them. "Scores come from `MODEL(CHURN_SURVIVAL)!PREDICT` in SQL over Feature Store
  features: the same definitions as training."
- **Do:** notebook 05 §2, `LEDGER`. **Show:** round trip **4,000 rows out, 2,000 back**; in place **0, 0, 0**.

### L8. Monitor (worksheet, 3 min)

- **Do:** the monitor query:

  ```sql
  SELECT EVENT_TIMESTAMP, ROUND(METRIC_VALUE, 3) AS ROC_AUC, COUNT_USED
  FROM TABLE(MODEL_MONITOR_PERFORMANCE_METRIC('TRANSCRIPT_CHURN_ML_DEMO.ML.CHURN_MONITOR', 'ROC_AUC', '1 DAY',
       '2025-01-01'::TIMESTAMP_NTZ, '2027-01-01'::TIMESTAMP_NTZ))
  ORDER BY 1;
  ```

- **Show:** AUC by scoring date, **0.550** (October 2025) to **0.660** (January 2026), about 2,000 accounts each.
- **Say (ML 7):** "The monitor watches the default version's scores against outcomes. Drift metrics need a baseline,
  which this build doesn't set, so we show performance. A monitor tracks a model's outputs, not the topic mix."
- **Do:** the topic-mix query:

  ```sql
  SELECT TO_CHAR(DATE_TRUNC('month', CALL_TS), 'YYYY-MM') AS MONTH,
         ROUND(100 * AVG(IFF(TOPIC_SOURCE = 'DISCOVERED', 1, 0)), 1) AS DISCOVERED_PCT,
         ROUND(100 * AVG(IFF(TOPIC_SOURCE = 'NOISE', 1, 0)), 1) AS NOISE_PCT, COUNT(*) AS SEGMENTS
  FROM TRANSCRIPT_CHURN_ML_DEMO.ML.SEGMENT_TOPICS GROUP BY 1 ORDER BY 1;
  ```

- **Show:** the discovered share jumps from **18.7%** in December to **33.1%** in January (run after L2, so January
  is loaded). "That's the signal to review new topic names or refit. Schedule this query, or a data metric function,
  with an alert."

### L9. Control cost (notebook 05 §4-5, 2 min)

- **Do:** notebook 05 §4, `ai_estimates` next to `ai_usage_history`. **Show:** the embed pass estimated at
  **167,461 input tokens** before it ran, and actual usage by query tag.
- **Say (Gov 1):** "Estimate with AI_COUNT_TOKENS, process each row once, cap each user with a quota that blocks, and
  put a budget on the pipeline. The cascade called an LLM 7 times, not 737." §5 has the quota and budget SQL as
  reference; it isn't run in the lab.

### Close: what we did not show (1 min)

- **ML 9:** "For an open-weights model, log it from Hugging Face to the Registry and serve it on Container Services
  with a GPU; the text stays here. Not part of this build."
- **Arch 2:** "A share from your call vendor is live and read-only. Keep history with a stream on it, if they enable
  change tracking, or a scheduled snapshot. Ask the vendor."
- Point to the brief for docs links and the proposed first slice.

### Cuts (lifecycle path)

- 25 minutes: L1 to one question; skip L7's ledger (say the result); L9 to one sentence; L3 without the Feature Store
  page.
- Never cut L2 (live), L5 (registry) or L8 (monitoring): they answer the questions the team asked hardest.

---

# Technical deep dive (notebooks, ~25 min)

## Pre-flight

### The day before

- `./demo.sh build --yes` has run on the demo account and every CHECK line passed (README, Quick start).
- Rehearse once end to end, and screenshot each expected result: the raw-vs-redacted rows (notebook 01 Section 4), the January refresh statistics (01 Section 6), the seeded topic table and the k-means comparison (02 Sections 1 and 3), the clusterer versions in **AI & ML » Models**, the price-driver table (03 Section 4), the c-index pivot (04 Section 3) and the ledger table (05 Section 2). They are your fallback if a live call fails.
- If you will re-run anything live, decide which notebook and section now; the rest is shown from the executed notebooks.

### 30 minutes before

- Resume the warehouse: `ALTER WAREHOUSE TRANSCRIPT_CHURN_ML_WH RESUME;`
- Open the five executed notebooks (`./demo.sh notebook 1` ... `5`, or in Snowsight Workspaces), scrolled to their first section.
- Run one `SELECT * FROM SEMANTIC_VIEW(...)` from notebook 03 Section 4 to warm the semantic view.
- Tab 1: the deck at slide 1. Tab 2: notebooks. Tab 3: Snowsight at **AI & ML » Models**. Tab 4: Snowsight at **AI & ML » Feature Store**. Tab 5: **AI & ML » Cortex Analyst** on `ANALYTICS.CALL_INSIGHTS_SV`.

### Screen setup

- Browser at 125-150% zoom; results must be readable from the back row.
- Hide bookmarks, notifications and the terminal.
- Notebooks collapsed to outputs where possible; start on notebook 01, Section 1.

## Run of show

| # | Segment | Where | Minutes | Ends at |
|---|---|---|---|---|
| 0 | Frame: the hybrid and where each step runs | Deck, slides 1-4 | 3 | 3:00 |
| 1 | Segments, and PII gone before embedding | Notebook 01 Sections 1-5, slide 5 | 3 | 6:00 |
| 2 | A new month refreshes only new rows | Notebook 01 Section 6, slide 6 | 2 | 8:00 |
| 3 | Seeded and density topics vs k-means | Notebook 02 Sections 1-3 and 5, slides 7-8 | 4 | 12:00 |
| 4 | The clusterer in the registry | Snowsight Models, notebook 02 Sections 4 and 6, slide 9 | 3 | 15:00 |
| 5 | Price negativity by driver; topics on won and lost deals | Cortex Analyst, notebook 03, slide 10 | 3 | 18:00 |
| 6 | Call signals into the Feature Store and survival churn | Snowsight Feature Store, notebook 04, slides 11-12 | 4 | 22:00 |
| 7 | Data-gravity ledger | Notebook 05, slide 13 | 2 | 24:00 |
| 8 | Close: spend controls and a first slice | Slides 14-15 | 1 | 25:00 |

Every slide is used once; slides 14 and 15 share the close.

## 0. Frame: the hybrid and where each step runs (deck, slides 1-4, 3 min)

**Slide 1. Say:** "Three questions: what are customers telling the sales and success teams, which topics are new, and do those signals predict who cancels. Everything you'll see ran next to the call data, on synthetic data where we planted the answers, so every number is checkable."

**Slide 2. Say:** "This is the usual hybrid: transcripts in the warehouse, models and LLM calls on another platform, features out and scores back every day. The usual reason is an assumption that the clustering and survival libraries aren't available here."

**Slide 3. Say:** "Five schemas. Text flows one way: a masked raw column, redacted segments, embeddings from redacted text only. Topics, sentiment and churn features all read the redacted layer."

**Slide 4. Say:** "Four places a step can run. In this lab everything runs in SQL or warehouse Python, because umap-learn, hdbscan, lifelines and scikit-survival are in the Snowflake package channel. Anything else on PyPI goes to Container Runtime."

**Do:** Switch to notebook 01.

## 1. Segments, and PII gone before embedding (notebook 01, slide 5, 3 min)

**Do:** Notebook 01 Section 1, the `landed_profile` output.

**Show:** **960 history calls, 63% short dials**. "Those never reach an AI function."

**Do:** Section 3, the `segment_tokens` output.

**Show:** **1,227 segments, about 136 tokens each**, and the full embed pass estimate. **Say:** "A segment is four consecutive turns, enough to mean something and well inside AI_REDACT's 4,096-token limit."

**Do:** Section 4, the `redaction_before_after` table.

**Show:** Raw rows with a phone number and a name; the redacted column with `[NAME]` and `[PHONE_NUMBER]`. Then the CHECK: **planted phone numbers 243 → left 0, emails 0, rep names 0**.

**Say:** "AI_REDACT is best effort. In one build it missed two staff names out of 1,227, so a deterministic pass removes known names afterwards. Embeddings are built from this column and nothing else."

**Do:** Slide 5 for ten seconds as the summary.

**If** the notebook isn't open: show the rehearsal screenshot of the raw-vs-redacted table.

## 2. A new month refreshes only new rows (notebook 01 Section 6, slide 6, 2 min)

**Do:** Notebook 01 Section 6, the `redact_and_embed_new_month` output and its CHECK.

**Show:** **redacted 698 new segments; embedding refresh `insertedRows: 698`; history 1,227 untouched; 34 s**.

**Say:** "January arrived as appended rows. The stream handed only the new segments to redaction, and the embedding dynamic table inserted only those. Next month costs next month."

**Do:** Slide 6 if you want the code on screen; otherwise move on.

## 3. Seeded and density topics vs k-means (notebook 02, slides 7-8, 4 min)

**Slide 7. Say:** "Two passes. First the business topics: the team wrote two exemplar sentences for each of eight topics, and SQL similarity assigns a topic when it is clearly the best match."

**Do:** Notebook 02 Section 1, `seeded_by_topic` and the CHECK.

**Show:** **74.8% of segments seeded at 97.9% accuracy; 485 leftovers; the similarity join in under 2 seconds**.

**Do:** Section 2 CHECK.

**Show:** **V1 on 252 leftovers: 4 clusters, 44 noise; hidden topics matched at 0.88 and 1.00**.

**Fill while scrolling:** "UMAP to five dimensions, HDBSCAN on top, in a stored procedure on the warehouse. The rows never left."

**Do:** Section 5, the `PROPOSED_V1` table.

**Show:** The proposed labels (in the reference build **SEAT_SHARING** and **AI_CONTENT_GENERATION**; wording varies by run), status PENDING. "Four LLM calls named four clusters. A person approves them."

**Slide 8. Say:** "Why not k-means? Given the right number of clusters it is about as pure on clean synthetic text, but it assigns every segment, including the 44 that belong to no topic. HDBSCAN leaves them out, and you don't have to know k."

**Do:** Section 3, `kmeans_vs_hdbscan`. **Show:** **k-means 100% assigned, HDBSCAN 82.5%**.

## 4. The clusterer in the registry (Snowsight, notebook 02, slide 9, 3 min)

**Do:** Snowsight tab, **AI & ML » Models » TOPIC_CLUSTERER**.

**Show:** Versions **V1** and **V2**, V2 the default; the V1 metrics with **training_snapshot ML.CLUSTER_TRAINING_V1**.

**Say:** "The fitted reducer and clusterer are a model version with one input, the embedding as an array, because a model method takes at most 500 arguments."

**Do:** Notebook 02 Section 4, `score_from_sql`.

**Show:** Ten January leftovers scored with `TOPIC_CLUSTERER!PREDICT(EMBEDDING::ARRAY)`, some assigned, some `-1`.

**Do:** Section 6 CHECK. **Show:** **emerging-topic clusters carried V1 → V2 with Jaccard 1.0 and 0.73**.

**Say:** "Refit renumbers clusters; the member-overlap map keeps a reviewed name attached to its topic."

**If** the Models page is slow to load: show the `show_clusterer_versions` cell output instead.

## 5. Price negativity by driver; topics on won and lost deals (Cortex Analyst, notebook 03, slide 10, 3 min)

**Slide 10. Say:** "Price sentiment as a cascade: a free keyword filter keeps a third of the segments, AI_SENTIMENT with three price aspects, and AI_CLASSIFY names the driver on the negatives only."

**Do:** Cortex Analyst tab on `CALL_INSIGHTS_SV`. Ask **"What is driving negative price remarks?"**

**Fill while it runs (a few seconds):** "This is a semantic view over segment topics, price sentiment and CRM outcomes. Analyst writes the SQL against those definitions."

**Show:** **competitor price 117, value for money 100, pricing model 75**.

**Do:** Ask **"Which topics come up on lost deals compared with won deals?"**

**Show:** Price and cost at **12.7% of lost-deal segments vs 9.7% of won**.

**If** Analyst is slow or rephrases oddly: notebook 03 Section 4, `sv_price_drivers` and `sv_topics_by_outcome`, same numbers.

**Say:** "Driver attribution matched the planted driver 95.5% of the time. On real calls you would measure it on a hand-labeled sample of a few hundred segments."

## 6. Call signals into the Feature Store and survival churn (Snowsight, notebook 04, slides 11-12, 4 min)

**Slide 11. Say:** "Call signals become features next to product usage: two managed feature views, computed from raw tables at every date in a snapshot calendar."

**Do:** Snowsight tab, **AI & ML » Feature Store**: entity **ACCOUNT**, views **ACCOUNT_USAGE_FV** and **ACCOUNT_CALL_SIGNALS_FV**.

**Do:** Notebook 04 Section 1 CHECK. **Show:** average negative price remarks per account **0 → 0.051 → 0.087** across the snapshot dates. "Same definitions, different dates. That is point-in-time correctness."

**Slide 12, then notebook 04 Section 3**, the c-index pivot.

**Show:** **usage-only 0.548 → with call features 0.616 (+0.068)**; logistic **0.616**, best survival **0.611**.

**Say:** "Call features clearly help. On ranking alone, logistic ties survival, and I'm not going to pretend otherwise. Survival gives you the probability of cancelling by any date from one model, and handles accounts that hadn't cancelled when follow-up ended. lifelines and scikit-survival trained in a warehouse procedure."

**Do:** Section 6, `top_risk_explained`. **Show:** the top-risk account's drivers, led by **PRICE_NEG_90D**. "This is what a success manager hears: negative price remarks, not a score of 0.7."

**If** the Feature Store page is slow: skip it and show the `register_feature_views` cell output.

## 7. Data-gravity ledger (notebook 05, slide 13, 2 min)

**Do:** Notebook 05 Section 2, the `LEDGER` table.

**Show:** **Round trip: 4,000 rows (60,000 feature values) out, 2,000 back, 2 crossings. In place: 0, 0, 0.**

**Say:** "One scoring task, two paths, two query tags: the round trip trains and scores on the client; in place uses the registered model in SQL. At 2,000 rows the round trip was faster, 5 seconds against 13. The point is the rows that left and came back, and the copies you now govern. The same query-history queries size your own daily loop."

**Do:** Slide 13 as the summary.

## 8. Close: spend controls and a first slice (slides 14 and 16, 1 min)

**Slide 14. Say:** "Estimate with AI_COUNT_TOKENS before a full pass, process each row once, cap per user and watch usage history by query tag, and govern the text before anything else touches it. Here an LLM ran 7 times, not 737."

**Slide 16. Say:** "A first slice: one month of your calls segmented, redacted and embedded; the business topics seeded and measured on a labeled sample; price sentiment by driver behind a semantic view. Churn second, once call signals exist as a feature view."

## Cuts

Cut from the top of this list first:

1. **Segment 7** (ledger): saves 2 min. Say the one-line result during the close.
2. **Segment 4's Snowsight Models page**: saves 1 min. Show the `show_clusterer_versions` output in the notebook.
3. **Segment 5's Cortex Analyst**: saves 1.5 min. Show the two notebook 03 outputs instead.
4. **Segment 2**: saves 1.5 min. Say "January processed only its 698 new segments" during segment 1.
5. **Segment 3's k-means comparison (slide 8)**: saves 1 min. One sentence: "k-means assigns everything, HDBSCAN leaves noise out."
6. **Segment 6's Feature Store page and explain cell**: saves 1.5 min. Keep the c-index pivot.
7. **Segment 0's slides 2 and 3**: saves 1.5 min. Say the hybrid in one sentence on slide 1, then go to slide 4.

Together these save 10 minutes. Never cut segment 1. It is the proof that the text is governed before any model or LLM sees it.

## Recovery tips

| Symptom | Likely cause | Recovery |
|---|---|---|
| An AI function cell is slow (AI_REDACT, AI_SENTIMENT, AI_COMPLETE) | Model latency or queueing on the day | Don't re-run live; show the executed output or the rehearsal screenshot |
| Dynamic table refresh shows no inserted rows | January was already loaded by an earlier run | Re-run notebook 01 from Section 1 (it resets to history first), or show the rehearsal refresh statistics |
| Snowsight **Models** or **Feature Store** page is slow or empty | UI metadata lag after a fresh build | Use the notebook outputs (`show_clusterer_versions`, `register_feature_views`) |
| Cortex Analyst gives a different breakdown | Question phrasing | Use the exact questions above, or the `SEMANTIC_VIEW(...)` outputs in notebook 03 |
| Experiment runs missing in Snowsight | UI lag | Show notebook 04 Section 4 CHECK (6 runs listed) |
| A notebook cell fails live | Warehouse suspended or session expired | Resume the warehouse; present from the executed notebook outputs |
| Local notebook kernel can't connect | Browser sign-in timed out | Present from the saved outputs; re-run later with `./demo.sh build --yes --from <n>` |

## Q&A prep

**"Are hdbscan, umap-learn, lifelines and scikit-survival really available?"** Yes, in the Snowflake package channel; this lab trains and scores them in warehouse stored procedures. Pins that worked: umap-learn 0.5.11, hdbscan 0.8.33 with scikit-learn 1.7.2, lifelines 0.30.0, scikit-survival 0.23.1.

**"What about packages that aren't in the channel, like EVOC or BERTopic extras?"** Container Runtime notebooks and ML Jobs install from PyPI through the PyPI artifact repository or an external access integration, or use a custom image. We didn't complete an EVOC run in testing, so that is the documented path, not a verified one.

**"Does Snowflake publish accuracy numbers for AI_SENTIMENT or AI_CLASSIFY on our kind of text?"** Not that we'd quote. Hand-label a few hundred segments and measure; AI Function Studio's evaluation (Preview) scores a function against a labeled dataset and compares prompts and models on quality and cost.

**"Can the model monitor track topic drift?"** It monitors model outputs (scores, classes) against a source table. Topic-mix drift is a metrics table over `SEGMENT_TOPICS` by month, or data metric functions.

**"Why a stream for redaction instead of a dynamic table?"** In testing, AI_REDACT inside a dynamic table built on create but failed on refresh; AI_EMBED refreshed incrementally fine. The stream plus MERGE gives the same "each row once" behavior.

**"Can we keep Airflow?"** Yes. Airflow can trigger the same procedures, ML Jobs or Code Bundles; the steps that are declarative and incremental can become dynamic tables so the scheduler has less to do.

The full answers to the Section 6 questions are in the separate brief.

## After the talk

- Suspend the warehouse if the room is moving on: `ALTER WAREHOUSE TRANSCRIPT_CHURN_ML_WH SUSPEND;`
- Clear any live re-runs you started; the executed notebooks remain the reference outputs.
- When you're done with the demo for good: `./demo.sh teardown --yes`.
