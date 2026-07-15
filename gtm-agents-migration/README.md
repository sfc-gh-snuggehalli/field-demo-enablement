# Migrating GTM AI: Claude Code + MCP to Cortex Agents + CoWork

[View Presentation](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/gtm-agents-migration/presentations/gtm-agents-migration.html)

A sales demo that migrates an AI-over-sales-email workload from an **external brain**
(Claude Code + the Snowflake-managed MCP server) to an **in-data-plane multi-agent architecture** (Cortex
Agents + Snowflake CoWork). It proves the gains on four pillars Snowflake can measure — **governance/security,
cost control, observability, and data locality** — over the same governed data and tools. The Claude + MCP
comparison is presented qualitatively (its latency and cost are billed outside Snowflake).

Scenario: a B2B sales-intelligence / go-to-market (GTM) SaaS company scores every rep email for buyer intent
and mines winning email patterns. All objects live in database `GTMAGENTS`, schema `DEMO`.

## Audience

Sales engineers and data & AI teams evaluating Cortex Agents, Snowflake CoWork, and the Snowflake-managed MCP
server — especially cost-sensitive orgs weighing an external LLM client against in-plane agents.

## Topics Covered

- Snowflake-managed MCP server (`CREATE MCP SERVER`) exposing Cortex Analyst, Cortex Search, and a governed UDF
- OAuth security integration for external MCP clients (Claude), plus the connect gotchas
- Multi-agent orchestration: a supervisor over three specialists via agent-to-agent `DATA_AGENT_RUN`
- Cost control: cheap model + confidence-based escalation, orchestration budget caps, and an `AI_FILTER` gate
- Snowflake CoWork as a zero-connector front door for the supervisor agent
- Native Cortex Agent Evaluation of the supervisor (answer correctness, tool-selection accuracy, logical consistency) with a baseline→improve→promote loop and scheduled regression detection
- AI Observability (`SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS`) surfaced inline in the lab
- A side-by-side comparison: external brain vs in-data-plane brain (latency, cost, governance)

## Contents

| File | Description |
|------|-------------|
| `presentations/gtm-agents-migration.html` | Slide deck (12 slides) |
| `presentations/gtm-agents-migration-speaker-notes.md` | Per-slide speaker notes with talking points, presenter notes, and references |
| `lab/setup.sql` | Part 0 foundation: DB/schema/warehouse/role, synthetic data, semantic view, Cortex Search, governed UDF, shared log tables |
| `lab/cleanup.sql` | Tear the whole demo down (DB + warehouse + role + OAuth integration) to start fresh |
| `lab/gtm-01-foundation.ipynb` | Part 0 tour + Cortex Analyst |
| `lab/gtm-02-before-mcp.ipynb` | Part A — MCP server + OAuth + Claude connect stubs |
| `lab/gtm-03-after-agents.ipynb` | Part B — multi-agent supervisor + AI_FILTER gate |
| `lab/gtm-04-evals.ipynb` | Part C — native agent evaluation of GTM_SUPERVISOR (dataset, metrics, baseline vs improved, promote, regression) + a four-pillar observability/before-after recap |
| `lab/tests/checkpoints.ipynb` | **Internal QA (not client-facing)** — PASS/FAIL checkpoints for all four notebooks; run after executing them |

## Hands-On Lab

Four lifecycle notebooks build the demo strictly in order; the final notebook (`gtm-04`) closes with an
in-plane recap of the four pillars — live traces, eval history, the governance/before-after matrix, and the
`AI_FILTER` volume cut — so there is no separate app to deploy. A separate internal-only
`lab/tests/checkpoints.ipynb` holds the PASS/FAIL checks that validate each part is wired correctly — run it
after the four notebooks; it is not part of the client walkthrough.

### Prerequisites

- A role that can `CREATE DATABASE`, `WAREHOUSE`, and `ROLE` (SYSADMIN + grant, or ACCOUNTADMIN).
- **ACCOUNTADMIN** for the OAuth security integration and `ALTER USER ... DEFAULT_ROLE` in Part A, and to grant `EXECUTE TASK ON ACCOUNT` (Part C evaluations run via a managed task).
- Cortex enabled (the `SNOWFLAKE.CORTEX_USER` database role).
- **Cross-region inference** enabled (the agent-evaluation LLM judges in Part C).
- For live traces and evaluation: `MONITOR` on the supervisor agent + `SNOWFLAKE.CORTEX_USER`.
- A personal Claude account (claude.ai or Claude Desktop) for the optional live MCP connect in Part A.

### Setup

Run `lab/setup.sql` in your Snowflake account. This creates:

- Database `GTMAGENTS`, schema `DEMO`, warehouse `GTMAGENTS_WH`, and least-privilege role `GTMAGENTS_ROLE`
- `REPS`, `EMAILS` (~3,000 quality-tiered emails), `OUTCOMES`, `EMAIL_FRAMEWORK` (rubric)
- Semantic view `EMAIL_GTM_SV` (Cortex Analyst), Cortex Search `FRAMEWORK_SEARCH`, governed UDF `GTM_TEAM_PERFORMANCE`
- Shared logging tables: `ROUTING_LOG`, `FILTER_VOLUME`
- Evaluation infrastructure: `AGENT_EVAL_QUESTIONS` (12 labeled questions), `EVAL_SCORE_HISTORY`, and the `EVAL_STAGE` internal stage

### Lab Sections

1. **gtm-01-foundation** — tour the data, run a Cortex Analyst NL question, confirm the three tools.
2. **gtm-02-before-mcp** — create the MCP server + OAuth integration, print the endpoint URL + client id/secret, log the MCP latency/cost baseline, and follow the manual Claude connect step-list.
3. **gtm-03-after-agents** — build the scoring/recommendation/coaching specialists, wrapper procedures, and supervisor; run the `AI_FILTER` volume gate; batch-score; run the supervisor end-to-end.
4. **gtm-04-evals** — register the labeled dataset, run a native Cortex Agent Evaluation of `GTM_SUPERVISOR` (answer correctness, tool-selection accuracy, logical consistency, custom routing judge), improve the orchestration, re-run and compare, promote the better version to a `production` alias, wire up regression + feedback, and close with the four-pillar observability/before-after recap.

> **Internal QA:** after running the four notebooks, run `lab/tests/checkpoints.ipynb` to verify every part is wired correctly. This test notebook is not part of the client-facing walkthrough.

**Run order:** `setup.sql` → `gtm-01` → `gtm-02` → `gtm-03` → `gtm-04`.

The recap in `gtm-04` reads AI Observability events, so the running role needs `MONITOR` on `GTM_SUPERVISOR`
and the `SNOWFLAKE.CORTEX_USER` database role (the notebook grants `MONITOR` idempotently).

### Run in Snowflake (Workspaces / Git) — recommended for demos

Run everything inside Snowsight so `get_active_session()` handles auth (no local OAuth / connection setup):

1. Snowsight → **Projects → Workspaces → Create Workspace from Git repository**, pointing at
   `https://github.com/sfc-gh-snuggehalli/field-demo-enablement`.
2. Open `gtm-agents-migration/lab/setup.sql` and run it.
3. Open the four `lab/gtm-0*.ipynb` notebooks in order and walk the sections; `gtm-04` ends with the recap.
   (Optional internal QA: run `lab/tests/checkpoints.ipynb` afterward to validate the build.)

Running locally instead? Use `snow sql -f lab/setup.sql` with a connection whose **role can create the
objects** and use a warehouse. If `GTMAGENTS_WH` already exists under a different owner, grant your role
`USAGE, OPERATE` on it. The notebooks are designed for the Snowsight `get_active_session()` path.

## Key Concepts

- **MCP server = front door, not data:** `CREATE MCP SERVER` wraps existing governed objects; access to the server is not access to the tools (grant each separately).
- **Agent-to-agent orchestration:** a supervisor's `generic` tools are bound to owner's-rights procedures that call `DATA_AGENT_RUN`; each returns a single cell (the custom-tool contract).
- **Cost control:** cheap model + confidence-based escalation, `orchestration.budget` caps, and an `AI_FILTER` gate that treats only underperforming emails.
- **In-plane governance & observability:** per-user quotas, tagging, chargeback, and server-side traces are native only when the reasoning loop runs inside Snowflake.
- **Migration ≠ rewrite:** the data and tools are shared; migration relocates the reasoning loop from an external client into the data plane.

## References

- [Cortex Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents)
- [Snowflake-managed MCP server](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp)
- [Snowflake CoWork](https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork)
- [Monitor Cortex Agent requests](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-monitor)
- [DATA_AGENT_RUN](https://docs.snowflake.com/en/sql-reference/functions/data_agent_run-snowflake-cortex)
- [Cortex Agent Evaluations](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations)
- [AI_FILTER](https://docs.snowflake.com/en/sql-reference/functions/ai_filter)
- [CREATE SECURITY INTEGRATION (Snowflake OAuth)](https://docs.snowflake.com/en/sql-reference/sql/create-security-integration-oauth-snowflake)
