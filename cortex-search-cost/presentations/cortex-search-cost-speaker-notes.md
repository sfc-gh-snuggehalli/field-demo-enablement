# Speaker Notes: Cortex Search — BYO Embeddings & Cost Optimization

## Account Context Summary

This deck addresses a common pattern: an enterprise team pre-computes embeddings externally (e.g. OpenAI, SageMaker) and loads chunks + vectors into Snowflake for Cortex Search. The primary concern is whether Snowflake will re-run embeddings on user-provided vectors and what drives the serving bill. The team ingested ~2TB of document embeddings and sees ~361 cr/day in serving alone, with only a small amount of new data added monthly. Their setup is correct (PK, incremental, 1h lag, BYO vectors) -- the bill is proportional to corpus size, not a misconfiguration. The lab validates incremental refresh behavior, proves zero embedding cost for BYO vectors, and demonstrates optimization levers that do not require changing the corpus.

---

## Slide 1: Hero

**Talking Points:**
- Cortex Search provides hybrid search (keyword + semantic + reranking) as a managed service.
- When you bring your own embeddings, the embedding cost is zero — Snowflake indexes your vectors as-is.
- Serving cost is proportional to indexed data size (6.3 cr/GB/mo), metered per second.
- AUTO_SUSPEND (minimum 30 min) lets idle services stop incurring serving credits.

**Presenter Notes:**
- The 6.3 cr/GB/mo rate is from the Snowflake Service Consumption Table. Confirm it has not changed before presenting.
- The lab uses 768-dim vectors to keep demo cost negligible (~0.1 cr/mo). Production examples in the deck use 1,536-dim for realistic cost projections.
- This demo runs entirely in a single Snowflake account — no external API keys needed. We simulate BYO embeddings by pre-computing with EMBED_TEXT_768 inside Snowflake.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-costs
- https://docs.snowflake.com/en/sql-reference/sql/create-cortex-search

---

## Slide 2: The Cost Challenge

**Talking Points:**
- Serving is the dominant cost at scale. A 262M-row corpus at 1,536 dims can hit 12K+ cr/mo in serving alone — regardless of query volume.
- Accidental full rebuilds happen when teams use CREATE OR REPLACE instead of ALTER, or when they drop and recreate source tables (breaking change tracking).
- Without monitoring, teams cannot distinguish serving from embedding from warehouse costs, leading to incorrect root-cause analysis.
- Dev/staging services left running silently accumulate serving credits even with zero queries.

**Presenter Notes:**
- The 262M-row / 12K cr/mo figure matches real-world observations from large document stores. Use it to calibrate expectations.
- Common misconception: "reducing query volume will reduce cost." Query volume does not affect serving cost — only indexed data size matters.
- Another misconception: "FULL_INDEX_BUILD_INTERVAL_DAYS causes a full re-embed." It does not. It compacts fragmented index segments. Unchanged data is not re-embedded.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-costs#managing-serving-costs

---

## Slide 3: Architecture

**Talking Points:**
- The pipeline starts externally: documents are parsed, chunked, and embedded using the customer's model of choice.
- Chunks and pre-computed vectors land in a standard Snowflake table (DOCUMENT_CHUNKS) via INSERT or MERGE.
- The Cortex Search Service is defined with TEXT INDEXES (for keyword search on the text column) and VECTOR INDEXES (for semantic search on the BYO vector column).
- Downstream consumers — Cortex Agents, RAG apps, enterprise search UIs — query the service via REST API or Python SDK.
- Cost monitoring views (CORTEX_SEARCH_DAILY_USAGE_HISTORY) provide per-service, per-day breakdowns.

**Presenter Notes:**
- Emphasize that the source table can be a standard table or a Hybrid Table -- both work identically with Cortex Search. The Hybrid Table pattern is valid for teams that need low-latency single-row inserts from an application (e.g. Lambda writing chunks after OCR) before the batch index picks them up.
- The architecture supports filter-based multi-tenancy: include a TENANT_ID column as an ATTRIBUTE and filter at query time.
- For near-real-time "hot document" retrieval (sub-minute), direct SQL vector similarity on the table is the recommended complement. Cortex Search indexing has a refresh lag governed by TARGET_LAG.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview#multi-index-cortex-search
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview#user-provided-vector-embeddings

---

## Slide 4: BYO Embeddings

**Talking Points:**
- The key difference is the VECTOR INDEXES clause: a bare column name = user-provided vectors; a column with `model='...'` = Snowflake-managed embeddings.
- With BYO vectors, Snowflake does not call EMBED_TEXT at all. EMBED_TEXT_TOKENS credits = 0.
- At query time with BYO vectors, you must provide a query vector yourself (or set `query_model` on the column to let Snowflake embed the query text).
- TEXT INDEXES still provides keyword (lexical) search independently of the vector path.

**Presenter Notes:**
- Common question: "If I bring my own 1,536-dim vectors from OpenAI, will Snowflake re-embed them with Arctic?" No. Snowflake indexes the vectors as-is with no model conversion.
- Common question: "Can I use TEXT INDEXES and VECTOR INDEXES on the same column?" Yes — the column gets both keyword and semantic search.
- The VECTOR column must be of type `VECTOR(FLOAT, N)`. You cannot load vectors directly as arrays; cast them: `[1.0, 2.0, ...]::VECTOR(FLOAT, 1536)`.
- EMBEDDING_MODEL parameter is only for single-index (ON clause) services. Multi-index services specify the model per column in VECTOR INDEXES.

**References:**
- https://docs.snowflake.com/en/sql-reference/sql/create-cortex-search#vector-indexes
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/query-cortex-search-service

---

## Slide 5: Incremental Refresh

**Talking Points:**
- With PRIMARY KEY + INCREMENTAL refresh mode, each refresh cycle processes only rows that changed since the last refresh.
- Change tracking (auto-enabled on the source table) detects the delta.
- FULL_INDEX_BUILD_INTERVAL_DAYS (default 1) controls how often fragmented index segments are compacted. This is a structural optimization, NOT a re-embedding.
- Anti-patterns: CREATE OR REPLACE on the service or source table, or changing the source query schema (adding/removing columns) — all trigger full rebuilds.

**Presenter Notes:**
- The lab will demonstrate this: insert 500 new chunks, trigger a refresh, and show that EMBED_TEXT_TOKENS stays at 0 and only the delta was processed.
- **How to confirm incremental refresh is working on a production service:** Query `INFORMATION_SCHEMA.CORTEX_SEARCH_REFRESH_HISTORY`. The `REFRESH_ACTION` column returns `INCREMENTAL`, `FULL`, or `NO_DATA`. If you see `FULL` on scheduled refreshes (not creation), something is forcing a full rebuild.
- **Diagnostic checklist when you see unexpected FULL refreshes:** (1) Is PRIMARY KEY set? (2) Is the source table being recreated (CREATE OR REPLACE) instead of incrementally updated? (3) Has the source query schema changed? (4) Is DATA_RETENTION_TIME_IN_DAYS > 0 on the source table?
- The `INDEX_PREPROCESSING_STATISTICS:numInsertedRows` field in the refresh history shows exactly how many rows were processed in each refresh. For a correctly incremental service adding small batches, this should match the batch size, not the total corpus size.
- FULL_INDEX_BUILD_INTERVAL_DAYS is a soft target — Snowflake may compact more frequently based on service size and change rate. A `FULL` refresh_action from compaction does NOT re-embed unchanged data.
- Time travel retention must be non-zero on source tables. If DATA_RETENTION_TIME_IN_DAYS = 0, incremental refresh breaks.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/cortex_search_refresh_history
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview#primary-keys
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview#refreshes
- https://docs.snowflake.com/en/sql-reference/sql/alter-cortex-search

---

## Slide 6: Cost Anatomy

**Talking Points:**
- Walk through the formula: 6.3 cr/GB/mo x rows x (dims x 4 bytes + payload) / 1e9.
- Vectors dominate: at 1,536 dims, each row contributes 6,144 bytes of vector data. The text payload (~1 KB) is secondary.
- Show the table: the demo at 5K rows costs ~0.1 cr/mo. A mid-size KB at 1M rows costs ~24 cr/mo. At enterprise scale (262M rows, 1,536 dims), it reaches ~11,500 cr/mo.
- This is an ongoing cost while the service is serving, even with zero queries.

**Presenter Notes:**
- **Live cost math validation** (use this to calibrate against a real-world service):
  ```
  262M rows x 1,536 dims x 4 bytes = ~1.6 TB vectors
  + 262M rows x ~1.2 KB payload    = ~0.3 TB text/metadata
  = ~1.9 TB total indexed data
  1,900 GB x 6.3 cr/GB/mo = ~11,970 cr/mo
  11,970 / 30 = ~399 cr/day
  Observed: ~361 cr/day -> within range (actual payload may be slightly smaller)
  ```
  This validates that the bill is expected and correctly configured — not a misconfiguration.
- The formula is an estimate. Actual indexed data includes internal overhead. Use DESCRIBE CORTEX SEARCH SERVICE to get the actual BILLABLE_BYTES.
- Common reaction: "Can we reduce cost by reducing query volume?" No — serving cost is independent of query volume. It is purely a function of indexed data size.
- **Framing for the team:** The setup is correct. The cost is a direct function of having ~2TB of indexed data active. The question is not "what is misconfigured" but rather "which operational levers can reduce the bill without changing the corpus."

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-costs#estimating-costs

---

## Slide 7: Cost Monitoring

**Talking Points:**
- CORTEX_SEARCH_DAILY_USAGE_HISTORY gives daily totals per service, broken by SERVING / EMBED_TEXT_TOKENS / BATCH.
- For BYO embeddings, EMBED_TEXT_TOKENS will show 0 credits — this is the proof point.
- DESCRIBE CORTEX SEARCH SERVICE shows BILLABLE_BYTES, NUM_SHARDS, INDEXING_STATE, and SERVING_STATE.
- Use a dedicated warehouse per service during cost baselining to isolate warehouse refresh credits.

**Presenter Notes:**
- The CORTEX_SEARCH_DAILY_USAGE_HISTORY view has up to 24h latency. For the lab demo, you may need to wait or use the hourly CORTEX_SEARCH_SERVING_USAGE_HISTORY view (Organization Usage, requires Enterprise Edition).
- Warehouse refresh costs are NOT in CORTEX_SEARCH_DAILY_USAGE_HISTORY. They appear under standard warehouse credit consumption. This is why a dedicated warehouse is recommended during baselining.
- CORTEX_SEARCH_SERVING_USAGE_HISTORY (Account Usage) provides hourly granularity for serving credits.

**References:**
- https://docs.snowflake.com/en/sql-reference/account-usage/cortex_search_daily_usage_history
- https://docs.snowflake.com/en/sql-reference/account-usage/cortex_search_serving_usage_history

---

## Slide 8: Optimization Levers

**Talking Points:**
- **Lead with operational levers that do not require changing the corpus:**
- (1) AUTO_SUSPEND — if the service has predictable idle windows (nights, weekends), this directly reduces serving cost. At 361 cr/day, 8 hours of overnight suspension saves ~120 cr/day (~3,600 cr/mo).
- (2) Manual SUSPEND SERVING / SUSPEND INDEXING — for maintenance windows. More aggressive than AUTO_SUSPEND (no 30-min minimum).
- (3) Increase TARGET_LAG — if data is only added monthly, a 1-hour lag over-refreshes. Match lag to actual data arrival cadence to cut warehouse compute.
- (4) FULL_INDEX_BUILD_INTERVAL_DAYS — increase for large, low-churn corpora. This controls compaction, NOT re-embedding.
- (5) Verify incremental refresh — use CORTEX_SEARCH_REFRESH_HISTORY to confirm every scheduled refresh is INCREMENTAL, not FULL.
- **Only if the team is open to it:** corpus pruning / dimension reduction. Frame as "if quality trade-offs are acceptable."

**Presenter Notes:**
- AUTO_SUSPEND returns HTTP 429 (Retry-After) to concurrent requests during resume. Client code must implement retry logic.
- Suspending serving (ALTER ... SUSPEND SERVING) is different from AUTO_SUSPEND. Manual suspend requires manual resume; AUTO_SUSPEND auto-resumes on query.
- For production services with continuous 24/7 traffic, AUTO_SUSPEND will not help. Focus on verifying incremental refresh and matching TARGET_LAG.
- **What does not exist yet (be transparent):** no per-query pricing option (serving is always-on per GB), no tiered storage for "hot" vs. "cold" indexed data within a single service, no way to reduce serving cost without reducing indexed data size or suspending. These are product asks worth escalating.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview#auto-suspend-serving-on-inactivity
- https://docs.snowflake.com/en/sql-reference/sql/alter-cortex-search

---

## Slide 9: Next Steps

**Talking Points:**
- First action: audit refresh behavior with CORTEX_SEARCH_REFRESH_HISTORY. Confirm every refresh is INCREMENTAL.
- Second: baseline cost with CORTEX_SEARCH_DAILY_USAGE_HISTORY. Confirm EMBED_TEXT_TOKENS = 0 for BYO and validate serving credits match the formula.
- Third: enable AUTO_SUSPEND on all services with idle windows. Quantify the savings from overnight/weekend suspension.
- Fourth: match TARGET_LAG to actual data arrival cadence. If data arrives monthly, a 1-hour lag wastes warehouse compute.

**Presenter Notes:**
- If the audience has a specific production service, offer to walk through the refresh history and cost queries live.
- The lab takes approximately 30-45 minutes to run through completely.
- Remind the audience: the lab creates a small service (~5K rows) so it costs nearly nothing. The formulas in the deck let them project to their production scale.
- **For the internal team:** The setup is correct -- this is a sizing problem, not a misconfiguration. Escalate to Product if additional cost levers beyond AUTO_SUSPEND / corpus reduction are needed.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-costs
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview
