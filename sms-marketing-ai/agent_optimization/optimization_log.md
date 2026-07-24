# Optimization Log — SMS_MARKETING_AGENT

## Agent details
- Fully qualified agent name: `SMS_MARKETING_DEMO.CORE.SMS_MARKETING_AGENT`
- Clone FQN (if production): N/A — demo object on a sandbox account, optimized in place. For a
  production agent, clone first (`CREATE AGENT <db>.<schema>.<clone> CLONE <prod>`), optimize the
  clone, evaluate, then promote.
- Owner / stakeholders: field enablement (demo)
- Purpose / domain: AI-BI assistant for an SMS/MMS marketing platform — blends the
  `SMS_MARKETING_SV` semantic view (via Cortex Analyst) with the marketing document corpus (via
  Cortex Search).
- Current status: draft (demo)

## Evaluation dataset
- Location: `eval_questions.md` (in this workspace) — load into a table for
  `run_evaluation.py` when running the full loop.
- Coverage: 16 questions — core use cases, tool routing (analyst vs search), blended
  (analyst + search), boundary/out-of-scope.

## Agent versions
- `baseline`: weak spec — vague tool descriptions, no orchestration, no response guidance, no
  sample questions. Deployed as `SMS_MARKETING_AGENT_BASELINE` for A/B comparison.
- `optimized`: best-practices spec — descriptive tool names, coverage + when-to-use / when-NOT-to-use
  boundaries, separated orchestration vs response instructions, sample questions, `data_to_chart`.
  Deployed as `SMS_MARKETING_AGENT` (and shipped by `lab/setup.sql`).

## Optimization details
### Entry: 2026-07-20
- Version: `optimized`
- Goal: raise tool-routing accuracy and answer quality using the /agent-optimization best practices.
- Changes made (baseline → optimized):
  - **Tool descriptions (highest leverage):** `analyst`/"Marketing data." → `Marketing_KPI_Analyst`
    with metrics, dimensions, when-to-use and **when NOT to use**; `search`/"Documents." →
    `Marketing_Playbook_Search` with corpus coverage, filterable attributes, and routing boundaries.
  - **Orchestration instructions added:** role, domain context (broadcast vs flow, consent states,
    attribution, regions), explicit tool-selection rules, and business rules (no forecasting,
    default 12-month window, no invented metrics).
  - **Response instructions separated:** USD/percentage units, table for >3 rows, cite documents by
    title, graceful out-of-scope handling.
  - **Sample questions:** added 4 marquee questions including a blended analyst+search question.
  - **Added `data_to_chart`** tool for visualizations.
- Rationale: tool descriptions are the single most impactful factor in agent quality; separating
  orchestration from response and adding explicit routing boundaries prevents the agent from
  confusing metric questions with policy questions.
- Eval: run `run_evaluation.py` against `eval_questions.md` for baseline vs optimized (not run in
  this authoring pass; drive it via `/agent-optimization` OPTIMIZE mode).
- Result: both agents deployed and validated live (`CREATE ... AGENT` succeeded); optimized spot-checks
  route metric questions to the Analyst tool and policy questions to Search.
- Next steps: curate expected answers in a Snowflake table, run the baseline/optimized eval loop,
  analyze failures, then generalize and promote.

### Entry: 2026-07-24
- Version: `optimized` (updated in place)
- Goal: add a second Cortex Search corpus — customer call transcripts — as a third agent tool,
  so the agent can answer "voice of the customer" questions alongside KPI and policy questions.
- Changes made:
  - **New tool `Call_Transcript_Search`** (`cortex_search` over `CALL_TRANSCRIPTS_SEARCH`): 24
    synthetic transcripts (10 support, 8 sales, 6 compliance), chunked to preserve dialogue turns.
    Filterable attributes `call_type` (support/sales/compliance), `brand`, `call_date`; cited by
    brand + `call_id`.
  - **Orchestration routing updated:** explicit split between the two Search corpora —
    `Marketing_Playbook_Search` = OUR internal policy/playbook docs; `Call_Transcript_Search` =
    transcripts of CALLS with customers. Blended flow now pulls the number (Analyst), the policy
    (Playbook), and what the customer said (Transcripts).
  - **Sample question added:** cross-type trace of the 10DLC-suspension brand across its support
    and compliance calls.
  - **`tool_resources.Call_Transcript_Search`:** name, `id_column: chunk_id`, `title_column:
    call_id`, `max_results: 6`.
- Rationale: transcripts are the hardest corpus for keyword search (multi-speaker, conversational)
  and the clearest place to show hybrid vector+keyword retrieval + attribute filtering. Keeping the
  two search corpora as distinct tools (with sharp when-to-use boundaries) prevents the agent from
  conflating "our policy" with "what the customer said".
- Deploy: shipped in `lab/setup.sql`; mirrored here as the system of record. Validated live on
  SNUGGEHALLI_AWS1 (DESCRIBE AGENT shows all three tools; search + RAG queries return grounded hits).
