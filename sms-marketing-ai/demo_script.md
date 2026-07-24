# Demo Script — Semantic Views & the AI-BI Stack

A tight run-of-show for a live 20-30 minute demo. Each beat maps to a positioning point.
Run `lab/setup.sql` first (or the notebook in a Snowsight Workspace). Schema:
`SMS_MARKETING_DEMO.CORE`.

> **Scenario in one line:** an SMS/MMS marketing platform for e-commerce brands — shoppers opt
> in by keyword, brands send broadcasts and automated flows, and store orders attribute back to
> the send that drove them.

---

## Beat 0 — Set the stage (1 min)

> "Analytics teams don't struggle to write a query. They struggle to agree on what a metric
> *means*, then get that same meaning into every tool. Today I'll define seven marketing KPIs
> **once**, as a native governed object, and reuse them in Cortex Analyst, a Cortex Agent, Cortex
> Search grounding, raw SQL, and BI — with no drift."

---

## Beat 1 — The semantic view is the source of truth (5 min)

**Positioning: Define the metric ONCE in the platform.**

Show the DDL in `lab/setup.sql` (§4) or `GET_DDL`:

```sql
SELECT GET_DDL('SEMANTIC_VIEW', 'SMS_MARKETING_DEMO.CORE.SMS_MARKETING_SV');
```

Then query the metric directly — this is exactly the SQL a BI tool runs:

```sql
SELECT * FROM SEMANTIC_VIEW(
    SMS_MARKETING_SV
    DIMENSIONS campaigns.campaign_type
    METRICS revenue_per_send, ctr
) ORDER BY revenue_per_send DESC;
```

> "Flows earn about **$59 per send** at **13.5%** CTR; broadcasts about **$15** at **6.8%**.
> One definition of `revenue_per_send`, and every consumer will return this same number."

---

## Beat 2 — Three ways to build the same object (3 min)

**Positioning: Open & portable — no lock-in.**

- **Programmatic:** the `CREATE SEMANTIC VIEW` DDL you just saw. Lives in Git next to dbt.
- **CoCo-assisted:** run `/semantic-views` in Cortex Code, or generate the view from existing
  dbt models (schema.yml + metrics) — "zero-to-semantic-view in minutes."
- **No-code:** Snowsight → AI & ML → Cortex Analyst → Semantic View Generator wizard.

Round-trip to YAML for version control:

```sql
SELECT SYSTEM$READ_YAML_FROM_SEMANTIC_VIEW('SMS_MARKETING_DEMO.CORE.SMS_MARKETING_SV');
```

> "All three paths emit the identical OSI-format object. Export it to YAML, commit it to Git
> alongside your dbt project. No proprietary metric store to get locked into."

---

## Beat 3 — Cortex Analyst: governed answers, not prompt luck (4 min)

**Positioning: AI-native — the view kills text-to-SQL hallucination.**

Ask five marketer questions (in Analyst, or via the agent's Analyst tool):

1. Attributed revenue by campaign type
2. Which region has the fastest opt-in growth?
3. Revenue per send: flows vs broadcasts
4. Consent rate and list churn by region
5. Click-through rate by campaign theme

> "Accuracy comes from the view's metrics, dimensions, and synonyms — plus verified queries —
> not from a clever prompt. Analyst never guesses how `messages` joins to `orders`; the
> relationships are declared once. Its SQL resolves to the same `SEMANTIC_VIEW(...)` call, so the
> answer matches the dashboard by construction."

---

## Beat 4 — Cortex Search: grounded, cited knowledge (3 min)

**Positioning: Governed by default — same platform, same RBAC.**

```sql
SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
  'SMS_MARKETING_DEMO.CORE.SMS_DOCS_SEARCH',
  '{ "query": "why do flows outperform broadcasts", "columns": ["title","doc_type"], "limit": 3 }'
))['results'];
```

> "Not everything is a number. Briefs, copy, TCPA/consent rules, deliverability, segmentation, a
> quarterly performance review, an attribution whitepaper, and an incident postmortem live in
> documents. These are real PDFs — landed on a stage and parsed with `PARSE_DOCUMENT` in
> `setup.sql`. Cortex Search retrieves the actual text and cites it — no hallucinated policy."

---

## Beat 4b — Cortex Search over call transcripts + ingestion patterns (4 min)

**Positioning: hybrid retrieval wins on the messiest corpus; zero vector infra.**

First, the ingestion story (`setup.sql` §3b) — the same corpus, three ways in:

- **Pattern A — chunk directly off the stage:** reassemble + `SPLIT_TEXT_RECURSIVE_CHARACTER` in
  one query, nothing persisted.
- **Pattern B — COPY INTO a raw table (the production path):** bulk-load lines, `LISTAGG` back into
  whole transcripts, then chunk into `TRANSCRIPT_CHUNKS`.
- **Pattern C — Snowpipe / Snowpipe Streaming (narrated):** auto-ingest new files, or append live
  call rows in real time; a Dynamic Table keeps chunks fresh.

Then search the transcripts — and scope with an attribute filter:

```sql
SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
  'SMS_MARKETING_DEMO.CORE.CALL_TRANSCRIPTS_SEARCH',
  '{ "query": "express written consent dispute and STOP opt-out handling",
     "columns": ["call_id","brand","call_type","chunk_text"],
     "filter": { "@eq": { "call_type": "compliance" } }, "limit": 3 }'
))['results'];
```

> "Call transcripts are the hardest corpus for keyword search — multi-speaker, conversational, no
> tidy fields. That's exactly where Cortex Search's hybrid vector + keyword retrieval wins, with no
> vector DB and no embedding pipeline to maintain. I can scope to compliance calls only, or one
> brand, at retrieval time — RBAC inherited, no re-indexing. And the RAG closer in the notebook
> feeds the top chunks to `AI_COMPLETE` for a cited answer — no hallucination on *what the customer
> said*."

---

## Beat 5 — Cortex Agent: blend structured + unstructured (4 min)

**Positioning: Layered, not "versus" — one assistant over governed objects.**

Chat with `SMS_MARKETING_AGENT` in Snowsight → AI & ML → Agents:

> **"Trace the brand that had a 10DLC campaign suspension across its support and compliance calls —
> what did the customer say, and what was the remediation?"**

> "The agent routes to `Call_Transcript_Search`, pulls the Harbor & Pine Home support and compliance
> calls, and quotes what was actually said — cited by brand and call_id. Ask a blended question and
> it splits the work three ways: the number from Analyst (governed SQL over the view), our policy
> from Playbook Search, and the customer's words from Transcript Search."

Then the layering close:

> "This doesn't replace dbt or your BI tool. dbt is the code-first system of record; the semantic
> view is the native governed metric layer; BI (Omni, Tableau, Excel) is the render layer — Omni
> even reads and writes the view bi-directionally. RBAC, row-access, masking, tagging, and lineage
> on the base tables are inherited by all of them. Define the metric once, govern it in the
> platform, reuse it everywhere."

---

## Beat 6 — Build & optimize the agent programmatically (4 min)

**Positioning: AI-native — the agent is only as good as its tool descriptions.**

Show the before→after in the lab notebook (Section 7), or narrate it live:

- **Baseline** (`SMS_MARKETING_AGENT_BASELINE`): two tools named `analyst` / `search` with
  descriptions "Marketing data." / "Documents." — no orchestration, no response rules, no sample
  questions.
- **Optimized** (`SMS_MARKETING_AGENT`, shipped by `setup.sql`): descriptive tool names, coverage +
  **when-to-use / when-NOT-to-use** boundaries, orchestration vs response instructions separated,
  sample questions, and a chart tool.

> "Tool descriptions are the single highest-leverage factor in agent quality — a vague description
> cascades into wrong tool selection, irrelevant data, and hallucinated answers. Watch: I'll ask
> the same blended question of the baseline and the optimized agent in the playground and compare
> how each routes."

A/B the two agents in the Snowsight playground on question #12 from `agent_optimization/eval_questions.md`.

> "To take this to production I'd run **/agent-optimization** in Cortex Code: it sets up a versioned
> workspace, runs a 15-20 question eval, analyzes failures, fixes instructions, checks for
> overfitting, and — critically — clones the agent first so we never optimize a live agent in place.
> The versioned specs, the log, and the eval set for this agent are already in `agent_optimization/`."

---

## One-slide recap of the five positioning points

1. **Define once** — same "attributed revenue" in Analyst, Agents, Search, SQL, and BI.
2. **Layered, not versus** — dbt (code-first) + Semantic View (governed metric layer) + BI (render).
3. **Governed by default** — RBAC, RLS, masking, tagging, and lineage inherited, not bolted on.
4. **Open & portable** — OSI format, exportable as YAML into Git alongside dbt. No lock-in.
5. **AI-native** — the semantic view is the accuracy foundation that kills text-to-SQL hallucination.
