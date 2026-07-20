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
