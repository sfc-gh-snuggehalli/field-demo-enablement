# Snowflake AI/ML Demo Kit

Hands-on Snowflake AI/ML demo modules

---

## Table of Contents

- [Overview](#overview)
- [Modules](#modules)
- [Repository Structure](#repository-structure)
- [Getting Started](#getting-started)
- [Presentation Format](#presentation-format)

---

## Overview

This repository contains enablement modules covering Snowflake features. Each module
includes an HTML slide deck, companion speaker notes, and (where applicable) a
hands-on lab with SQL setup and a notebook.

Some modules set themselves up in one step, and their README has a prompt to paste
into Cortex Code that does it for you. The Cortex AI Gateway, likely-to-sell and multi-agent MCP
modules: install [uv](https://docs.astral.sh/uv/) (`brew install uv`), then run `./demo.sh setup` in the
module folder (`./demo.sh --help` lists the other commands). The Cortex Agent SDK
module: run `./setup.sh`, then `cd app && npm run dev`.

<!-- MODULE_TABLE_START -->
| Module | Audience | Format | Presentation |
|--------|----------|--------|--------------|
| AI Functions: Customer Experience Telemetry | Data & Analytics teams | Presentation + Hands-on Lab | [View](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/cx-ai-functions/presentations/cx-ai-functions.html) |
| Donor Lapse/Churn Intelligence: Snowflake ML → Agent | Engineering leadership (VP-level) & data science / ML platform teams | Presentation + Hands-on Lab | [View](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/donor-churn-ml/presentations/donor-churn-ml.html) |
| Migrating GTM AI: Claude Code + MCP → Cortex Agents + CoWork | Sales engineers & data/AI teams | Presentation + Hands-on Lab | [View](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/gtm-agents-migration/presentations/gtm-agents-migration.html) |
| Semantic Views & the AI-BI Stack on Snowflake | Field SEs, marketing/analytics teams & data engineers | Presentation + Hands-on Lab | [View](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/sms-marketing-ai/presentations/sms-marketing-ai.html) |
| Proactive Retail Intelligence with Snowflake Cortex | Data & analytics engineers, ML/platform teams & product leaders | Presentation + Hands-on Lab | [View](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/proactive-retail-intelligence/presentations/proactive-retail-intelligence.html) |
| Cortex Search: BYO Embeddings & Cost Optimization | Data engineers, platform teams & solutions architects | Presentation + Hands-on Lab | [View](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/cortex-search-cost/presentations/cortex-search-cost.html) |
| Cortex AI Gateway: Govern, Observe and Optimize Every LLM Call | SEs, platform engineers & AI governance teams | Presentation + Hands-on Lab + App | [View](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/ai-gateway/presentations/ai-gateway.html) |
| Cortex AI Gateway for Retail Analytics: Govern, Observe and Optimize Every LLM Call | SEs, platform engineers & retail analytics teams | Presentation + Hands-on Lab + App | [View](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/ai-gateway-retail/presentations/ai-gateway.html) |
| Building Agentic AI Applications on the Cortex Agent SDK | SEs, architects & app developers | Presentation + Meta-Prompt + App | [View](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/cortex-agent-sdk-whitelabel/presentations/cortex-agent-sdk-whitelabel.html) |
| Run the likely-to-sell score where the homeowner data already lives | ML engineers & product leaders who own a production score | Presentation + Hands-on Lab + App | [View](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/likely-to-sell-ml/presentations/likely-to-sell-ml.html) |
| Multi-Agent Orchestration over MCP: One Governed Front Door for Any AI Client | SEs, architects & AI platform teams | Presentation + Hands-on Lab + App | [View](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/multi-agent-mcp/presentations/multi-agent-mcp.html) |
| Call-Transcript Topics to Churn, Where the Data Already Lives | ML engineers, data scientists & data engineers | Presentation + Hands-on Lab | [View](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/transcript-churn-ml/presentations/transcript-churn-ml.html) |
<!-- MODULE_TABLE_END -->

---

## Modules

<!-- MODULE_SECTIONS_START -->
### AI Functions: Customer Experience Telemetry

**Location:** `cx-ai-functions/`

Turn raw chat threads, call transcripts, and support tickets into structured sentiment and
topic telemetry — entirely in SQL with Snowflake AI Functions — optimize a custom function with
AI Function Studio, and govern it with a semantic view and a Cortex Agent. Also shows how an app's
own UX data (chat threads + thumbs up/down) flows in via a stage → raw `VARIANT` → curated tables.

| File | Description |
|------|-------------|
| `presentations/cx-ai-functions.html` | Slide deck (20 slides) |
| `presentations/cx-ai-functions-speaker-notes.md` | Speaker notes |
| `lab/setup.sql` | One-step setup — schemas, warehouse, all structured + unstructured data, app-telemetry ingestion, semantic view, Cortex Search, agent |
| `lab/cleanup.sql` | Tear everything down to start fresh |
| `lab/cx-ai-functions-lab.ipynb` | Notebook 1 — run the AI-function pipeline (+ read-only app-telemetry tour) + AI Function Studio |
| `lab/cx-ai-functions-extensions.ipynb` | Notebook 2 — integrate: semantic view / Analyst / Search / Agent (runs live) + cost & guardrails |

### Donor Lapse/Churn Intelligence: Snowflake ML → Agent

**Location:** `donor-churn-ml/`

The complete Snowflake ML lifecycle for a generic nonprofit fundraising CRM: predict donor
lapse, explain every score, and act on it in natural language. Feature Store → Datasets →
Cortex ML Functions → Snowpark ML + HPO → ML Jobs → Model Registry → Explainability →
Serving → Observability, culminating in a Cortex Agent that calls the deployed model as a
tool, plus a Streamlit chat app.

| File | Description |
|------|-------------|
| `presentations/donor-churn-ml.html` | Slide deck (21 slides — 4-slide executive layer + full lifecycle) |
| `presentations/donor-churn-ml-speaker-notes.md` | Speaker notes |
| `lab/setup.sql` | DB, four schemas, warehouses, synthetic data, Cortex ML Functions, semantic view |
| `lab/donor-churn-01-features.ipynb` | Lab 1/3 — Feature Store, Datasets, Cortex ML Functions |
| `lab/donor-churn-02-model.ipynb` | Lab 2/3 — Snowpark ML + Experiment Tracking + HPO, ML Jobs, Registry, Explainability |
| `lab/donor-churn-03-serve-agent.ipynb` | Lab 3/3 — Serving, Observability, tool functions, Cortex Agent |
| `app/streamlit_app.py` | Streamlit-in-Snowflake chat UI over the agent |

### Migrating GTM AI: Claude Code + MCP → Cortex Agents + CoWork

**Location:** `gtm-agents-migration/`

Migrate an AI-over-sales-email workload from an external brain (Claude Code + the Snowflake-managed MCP
server) to an in-data-plane multi-agent architecture (Cortex Agents + Snowflake CoWork), proving the gains on
four pillars Snowflake can measure — governance/security, cost control, observability, and data locality — over
the same governed tools (the Claude + MCP comparison stays qualitative). A supervisor orchestrates scoring /
recommendation / coaching specialists via agent-to-agent `DATA_AGENT_RUN`, with a cheap-model-plus-escalation
approach and an `AI_FILTER` targeting gate.

| File | Description |
|------|-------------|
| `presentations/gtm-agents-migration.html` | Slide deck (12 slides) |
| `presentations/gtm-agents-migration-speaker-notes.md` | Speaker notes |
| `lab/setup.sql` | Part 0 foundation — DB/schema/warehouse/role, synthetic data, semantic view, Cortex Search, governed UDF, log tables |
| `lab/gtm-01-foundation.ipynb` | Part 0 — data tour + Cortex Analyst |
| `lab/gtm-02-before-mcp.ipynb` | Part A — MCP server + OAuth + Claude connect stubs |
| `lab/gtm-03-after-agents.ipynb` | Part B — multi-agent supervisor + AI_FILTER gate |
| `lab/gtm-04-evals.ipynb` | Part C — evals harness + four-pillar observability/before-after recap |
| `lab/tests/checkpoints.ipynb` | Internal QA (not client-facing) — PASS/FAIL checkpoints for the four notebooks |

### Semantic Views & the AI-BI Stack on Snowflake

**Location:** `sms-marketing-ai/`

Define a business metric once, as a native governed semantic view, then reuse it identically
across Cortex Analyst, Cortex Agents, Cortex Search grounding, SQL, and BI. Grounded in an SMS/MMS
marketing platform for e-commerce brands (opt-in keywords, broadcast vs automated flows, orders
attributed to sends). Shows all three ways to create a semantic view (DDL, YAML/dbt, no-code
wizard), then layers Cortex Analyst, Cortex Search, and a Cortex Agent on the single source of truth.

| File | Description |
|------|-------------|
| `presentations/sms-marketing-ai.html` | Slide deck (13 slides) |
| `presentations/sms-marketing-ai-speaker-notes.md` | Speaker notes |
| `demo_script.md` | Run-of-show live talk track mapped to the positioning |
| `lab/setup.sql` | Idempotent setup — data + semantic view + two Cortex Search services + Cortex Agent |
| `lab/cleanup.sql` | Tear everything down to start fresh |
| `lab/docs/` | 10 real PDFs (playbook/policy corpus) for `SMS_DOCS_SEARCH` |
| `lab/transcripts/` | 24 synthetic call transcripts + manifest for `CALL_TRANSCRIPTS_SEARCH` |
| `lab/sms-marketing-ai-lab.ipynb` | Hands-on lab — semantic view, Analyst, two Search services, Agent |
| `app/streamlit_app.py` | Optional Streamlit-in-Snowflake chat app over the agent |

### Proactive Retail Intelligence with Snowflake Cortex

**Location:** `proactive-retail-intelligence/`

Turn an embedded, reactive analytics assistant into a proactive one — it leads with
unprompted, explained observations and still answers ad-hoc questions on live data — without
paying a language model to scan the whole data estate. Cheap in-warehouse ML
(`ANOMALY_DETECTION`, `TOP_INSIGHTS`) detects and explains; a semantic view + Cortex Analyst
handles ad-hoc questions; and an optimized Cortex Agent narrates only the small flagged slice,
surfaced in Snowflake CoWork / Snowflake Intelligence and via REST `agent:run`.

| File | Description |
|------|-------------|
| `presentations/proactive-retail-intelligence.html` | Slide deck (12 slides) |
| `presentations/proactive-retail-intelligence-speaker-notes.md` | Speaker notes |
| `lab/setup.sql` | One-step setup — data + ML models + findings/drivers + semantic view + Cortex Search + task |
| `lab/cleanup.sql` | Tear everything down to start fresh |
| `lab/proactive-retail-intelligence-lab.ipynb` | Hands-on lab — detect, explain, query, build + optimize the agent, CoWork climax |
| `agent_optimization/` | Baseline vs. optimized agent specs and a diff summary |
### Cortex Search: BYO Embeddings & Cost Optimization

**Location:** `cortex-search-cost/`

Validate the cost behavior of Cortex Search with user-provided (BYO) embeddings. Proves zero
EMBED_TEXT cost for BYO vectors, demonstrates incremental refresh mechanics with PRIMARY KEY,
breaks down the serving cost formula (6.3 cr/GB/mo of indexed data), and walks through
optimization levers (AUTO_SUSPEND, TARGET_LAG, corpus pruning, vector dimension reduction).

| File | Description |
|------|-------------|
| `presentations/cortex-search-cost.html` | Slide deck (9 slides) |
| `presentations/cortex-search-cost-speaker-notes.md` | Speaker notes |
| `lab/setup.sql` | DB, schema, warehouse, document metadata table |
| `lab/cleanup.sql` | Tear everything down to start fresh |
| `lab/data_gen.py` | Generates ~5,000 document chunks with 768-dim embeddings via AI_EMBED |
| `lab/cortex-search-cost-lab.ipynb` | Hands-on lab — create service, validate incremental refresh, measure cost, test optimization levers |

### Cortex AI Gateway: Govern, Observe and Optimize Every LLM Call

**Location:** `ai-gateway/`

A LangChain agent reasons through the Cortex AI Gateway and uses a Snowflake MCP server exposing one governed Cortex Agent tool (Analyst + Search). A Streamlit Trace Analyzer then turns the gateway's traces into a closed optimization loop: diagnose, run an eval-set experiment, compare before and after, and promote.

| File | Description |
|------|-------------|
| `presentations/ai-gateway.html` | Slide deck (14 slides) |
| `presentations/ai-gateway-speaker-notes.md` | Speaker notes |
| `demo_script.md` | Live run-of-show |
| `lab/setup.sql` | Data, semantic view, Cortex Search, MCP server, gateway spec + grants, eval/optimization tables, app access |
| `lab/cleanup.sql` | Tear everything down to start fresh |
| `lab/ai-gateway-lab.ipynb` | Hands-on notebook: gateway + LangChain + MCP, observability, cost controls |
| `lab/live_agent.py` | Send one live prompt through the agent; prints the trace_id |
| `lab/generate_traffic.py` | Generates varied gateway traffic for the dashboards |
| `app/` | Trace Analyzer (Streamlit in Snowflake): live prompt, trace explorer, advisor, experiments, before/after |

### Cortex AI Gateway for Retail Analytics: Govern, Observe and Optimize Every LLM Call

**Location:** `ai-gateway-retail/`

The same gateway, MCP, Trace Analyzer and cost-governance flow on athletic apparel retail data. A LangChain agent reasons through the Cortex AI Gateway and calls one governed Cortex Agent tool with two Cortex Analyst tools (customer + churn, executive KPIs). An XGBoost churn model is trained, logged to the Model Registry, batch-scored in the warehouse and monitored; the agent answers from its scores with no client change.

| File | Description |
|------|-------------|
| `presentations/ai-gateway.html` | Slide deck (15 slides) |
| `presentations/ai-gateway-speaker-notes.md` | Speaker notes |
| `demo_script.md` | Live run-of-show |
| `lab/setup.sql` | Retail data (13 tables), two semantic views, churn predictions, Cortex Agent, MCP server, gateway spec + grants, eval set, app access, cost demo quota |
| `lab/cleanup.sql` | Tear everything down to start fresh |
| `lab/ai-gateway-lab.ipynb` | Hands-on notebook: gateway + LangChain + MCP, churn model, observability, cost controls |
| `lab/live_agent.py` | Send one live prompt through the agent; prints the trace_id |
| `lab/generate_traffic.py` | Generates varied gateway traffic for the dashboards |
| `app/` | Trace Analyzer: live prompt, trace explorer, advisor, experiments, before/after, cost governance |

### Building Agentic AI Applications on the Cortex Agent SDK

**Location:** `cortex-agent-sdk-whitelabel/`

How to build a fully branded, CoWork-style agent app (ACME Assist for the fictional ACME Retail) on `@snowflake/cortex-agent-sdk`, generated from one meta-prompt in Cortex Code. It covers config-driven branding with an animated logo, an embedded browser the agent drives through client-side tools, approval cards, Power Mode (`code_toolset_all`), a Studio runner, resumable runs and SSO identity, and deploys to Docker, SPCS and Snowflake App Runtime.

| File | Description |
|------|-------------|
| `presentations/cortex-agent-sdk-whitelabel.html` | Slide deck (12 slides) |
| `presentations/cortex-agent-sdk-whitelabel-speaker-notes.md` | Speaker notes |
| `demo_script.md` | Run-of-show (live one-shot or pre-built walkthrough) |
| `META_PROMPT.md` / `PROMPT.md` | Seed prompt + clarifying Q&A, and the full build spec |
| `lab/setup.sql`, `lab/seed_data.sql`, `lab/history.sql` | Retail ops data, semantic view, two agents, roles, history table |
| `lab/cleanup.sql` | Tear everything down to start fresh |
| `app/` | Reference build: React/Vite client, Express proxy, Next.js App Runtime variant, Store Ops simulator, CoCo runner |

### Run the likely-to-sell score where the homeowner data already lives

**Location:** `likely-to-sell-ml/`

A likely-to-sell XGBoost model that is scored on another platform every night, brought home: every feature defined once in the Snowflake Feature Store with a point-in-time training Dataset, the same model trained inside Snowflake, registered next to the imported artifact under one model name, scored from SQL, retrained by a daily task graph with lineage behind every version, and shown to the business in a Result | Trust | Value app.

| File | Description |
|------|-------------|
| `presentations/likely-to-sell-ml.html` | Slide deck (10 slides) |
| `presentations/likely-to-sell-ml-speaker-notes.md` | Speaker notes |
| `demo.sh`, `pyproject.toml`, `uv.lock` | One-command setup, headless build, notebook, app and teardown |
| `lab/ml_demo_run_the_likely_to_sell_demo.ipynb` | The live demo notebook: Phases 0-7 with a CHECK per phase |
| `lab/setup.sql` | Database, schemas and warehouse (Phase 0) |
| `lab/cleanup.sql` | Tear everything down to start fresh |
| `app/` | Streamlit in Snowflake business app (Result, Trust, Value) |

### Multi-Agent Orchestration over MCP: One Governed Front Door for Any AI Client

**Location:** `multi-agent-mcp/`

Any MCP client (Claude, ChatGPT, Cursor, or the included Claude-style Streamlit app) reaches governed sales and support data through one Snowflake-managed MCP server: an orchestrator agent delegates to specialist agents through caller's-rights bridges, so grants and a row access policy, not prompts, decide each persona's answer. Compares hub and spoke with agent toolsets, measured with Cortex Agent evaluations.

| File | Description |
|------|-------------|
| `presentations/multi-agent-mcp.html` | Slide deck (12 slides) |
| `presentations/multi-agent-mcp-speaker-notes.md` | Speaker notes |
| `demo_script.md` | Live run-of-show |
| `demo.sh`, `pyproject.toml`, `uv.lock` | One-command setup (stack, persona key pairs, PAT), headless build, notebook, app, smoke test and teardown |
| `lab/setup.sql` | The governed stack: data, semantic views, row access policy, bridges, agents, persona grants |
| `lab/multi-agent-mcp-lab.ipynb` | MCP servers, the toolset agent, the persona boundary over MCP, evaluations; a CHECK per section |
| `lab/cleanup.sql` | Tear everything down to start fresh |
| `app/`, `client/` | Claude-style MCP client (Streamlit) and a headless MCP smoke test |

### Call-Transcript Topics to Churn, Where the Data Already Lives

**Location:** `transcript-churn-ml/`

Recorded calls become topics, price sentiment and churn features without the text leaving Snowflake: masked, redacted and embedded in incremental pipelines; business topics in SQL and new ones discovered with UMAP + HDBSCAN, versioned in the Model Registry; call signals in the Feature Store beside product usage; survival models (lifelines, scikit-survival) trained, registered, scored from SQL and monitored; and a data-gravity ledger against the round trip. For presenting, a Streamlit story app with one live step and a Snowflake Intelligence agent tell the same story without code on screen.

| File | Description |
|------|-------------|
| `presentations/transcript-churn-ml.html` | Slide deck (16 slides) |
| `presentations/transcript-churn-ml-speaker-notes.md` | Speaker notes |
| `demo_script.md` | Run of show: 15-minute app path, then the 25-minute notebook deep dive |
| `demo.sh`, `pyproject.toml`, `uv.lock` | One-command setup, headless build of all five notebooks, notebook, ledger and teardown |
| `lab/setup.sql` | Database, warehouse and all synthetic data (calls, turns, CRM, subscriptions, usage, topic taxonomy) |
| `lab/transcript-churn-0[1-5]-*.ipynb` | Segments and governance, topics and registry, insights and semantic view, churn with the Feature Store, ledger and cost; a CHECK per section |
| `lab/app_setup.sql`, `app/` | Presenter path: live January step, account risk, semantic view, search service, agent, and the Streamlit story app |
| `lab/cleanup.sql` | Tear everything down to start fresh |

<!-- MODULE_SECTIONS_END -->

---

## Repository Structure

```
field-demo-enablement/
├── README.md
├── .github/
│   └── workflows/
│       └── static.yml          # GitHub Pages deploy
<!-- REPO_TREE_START -->
├── cx-ai-functions/            # AI Functions + Conversational BI: CX Intelligence
│   ├── README.md
│   ├── presentations/
│   │   ├── cx-ai-functions.html
│   │   └── cx-ai-functions-speaker-notes.md
│   └── lab/
│       ├── setup.sql
│       ├── cleanup.sql
│       ├── cx-ai-functions-lab.ipynb
│       └── cx-ai-functions-extensions.ipynb
├── donor-churn-ml/             # Donor Lapse/Churn Intelligence: Snowflake ML → Agent
│   ├── README.md
│   ├── presentations/
│   │   ├── donor-churn-ml.html
│   │   └── donor-churn-ml-speaker-notes.md
│   ├── lab/
│   │   ├── setup.sql
│   │   ├── donor-churn-01-features.ipynb
│   │   ├── donor-churn-02-model.ipynb
│   │   └── donor-churn-03-serve-agent.ipynb
│   └── app/
│       └── streamlit_app.py
├── gtm-agents-migration/       # Claude Code + MCP → Cortex Agents + CoWork migration
│   ├── README.md
│   ├── presentations/
│   │   ├── gtm-agents-migration.html
│   │   └── gtm-agents-migration-speaker-notes.md
│   └── lab/
│       ├── setup.sql
│       ├── cleanup.sql
│       ├── gtm-01-foundation.ipynb
│       ├── gtm-02-before-mcp.ipynb
│       ├── gtm-03-after-agents.ipynb
│       ├── gtm-04-evals.ipynb
│       └── tests/
│           └── checkpoints.ipynb
├── sms-marketing-ai/        # Semantic Views & the AI-BI Stack (Analyst + Search + Agent)
│   ├── README.md
│   ├── demo_script.md
│   ├── presentations/
│   │   ├── sms-marketing-ai.html
│   │   └── sms-marketing-ai-speaker-notes.md
│   ├── lab/
│   │   ├── setup.sql
│   │   ├── cleanup.sql
│   │   ├── docs/                # 10 PDFs — SMS_DOCS_SEARCH corpus
│   │   ├── transcripts/         # 24 call transcripts + manifest — CALL_TRANSCRIPTS_SEARCH corpus
│   │   └── sms-marketing-ai-lab.ipynb
│   ├── app/
│   │   └── streamlit_app.py
│   └── agent_optimization/
│       ├── optimization_log.md
│       ├── eval_questions.md
│       └── versions/
│           ├── baseline/agent_spec.yaml
│           └── optimized/agent_spec.yaml
├── proactive-retail-intelligence/  # Proactive Retail Intelligence with Snowflake Cortex
│   ├── README.md
│   ├── presentations/
│   │   ├── proactive-retail-intelligence.html
│   │   └── proactive-retail-intelligence-speaker-notes.md
│   ├── lab/
│   │   ├── setup.sql
│   │   ├── cleanup.sql
│   │   └── proactive-retail-intelligence-lab.ipynb
│   └── agent_optimization/
│       ├── README.md
│       └── versions/
│           ├── baseline/agent_spec.yaml
│           └── optimized/agent_spec.yaml
├── cortex-search-cost/          # Cortex Search: BYO Embeddings & Cost Optimization
│   ├── README.md
│   ├── presentations/
│   │   ├── cortex-search-cost.html
│   │   └── cortex-search-cost-speaker-notes.md
│   └── lab/
│       ├── setup.sql
│       ├── cleanup.sql
│       ├── data_gen.py
│       └── cortex-search-cost-lab.ipynb
├── ai-gateway/                  # Cortex AI Gateway: Govern, Observe and Optimize
│   ├── README.md
│   ├── demo_script.md
│   ├── presentations/
│   │   ├── ai-gateway.html
│   │   └── ai-gateway-speaker-notes.md
│   ├── lab/
│   │   ├── setup.sql
│   │   ├── cleanup.sql
│   │   ├── ai-gateway-lab.ipynb
│   │   ├── live_agent.py
│   │   └── generate_traffic.py
│   └── app/
│       ├── streamlit_app.py
│       ├── gateway_client.py
│       ├── trace_queries.py
│       ├── snowflake.yml
│       └── app_pages/
├── ai-gateway-retail/           # AI Gateway on retail data + churn model
│   ├── README.md
│   ├── demo_script.md
│   ├── presentations/
│   ├── lab/
│   │   ├── setup.sql
│   │   ├── cleanup.sql
│   │   ├── ai-gateway-lab.ipynb
│   │   ├── live_agent.py
│   │   └── generate_traffic.py
│   └── app/
├── cortex-agent-sdk-whitelabel/  # Branded agentic app on the Cortex Agent SDK (meta-prompt)
│   ├── README.md
│   ├── demo_script.md
│   ├── META_PROMPT.md
│   ├── PROMPT.md
│   ├── presentations/
│   │   ├── cortex-agent-sdk-whitelabel.html
│   │   └── cortex-agent-sdk-whitelabel-speaker-notes.md
│   ├── lab/
│   │   ├── setup.sql
│   │   ├── seed_data.sql
│   │   ├── history.sql
│   │   └── cleanup.sql
│   └── app/                     # React/Vite + Express, app-runtime/ (Next.js), coco-runner/
├── likely-to-sell-ml/
│   ├── README.md
│   ├── demo.sh
│   ├── pyproject.toml, uv.lock
│   ├── presentations/
│   │   ├── likely-to-sell-ml.html
│   │   └── likely-to-sell-ml-speaker-notes.md
│   ├── lab/
│   │   ├── ml_demo_run_the_likely_to_sell_demo.ipynb
│   │   ├── setup.sql
│   │   └── cleanup.sql
│   └── app/                     # streamlit_app.py, queries.py, environment.yml
├── multi-agent-mcp/
│   ├── README.md
│   ├── demo_script.md
│   ├── demo.sh
│   ├── pyproject.toml, uv.lock
│   ├── presentations/
│   │   ├── multi-agent-mcp.html
│   │   └── multi-agent-mcp-speaker-notes.md
│   ├── lab/
│   │   ├── multi-agent-mcp-lab.ipynb
│   │   ├── setup.sql
│   │   └── cleanup.sql
│   ├── app/                     # streamlit_app.py, host_llm.py, snowflake_mcp.py, personas.py
│   └── client/                  # mcp_smoke.py
├── transcript-churn-ml/
│   ├── README.md
│   ├── demo_script.md
│   ├── demo.sh
│   ├── pyproject.toml, uv.lock
│   ├── presentations/
│   │   ├── transcript-churn-ml.html
│   │   └── transcript-churn-ml-speaker-notes.md
│   ├── app/                      # Streamlit story app (snowflake.yml, streamlit_app.py, app_pages/)
│   └── lab/
│       ├── transcript-churn-01-segments-governance.ipynb
│       ├── transcript-churn-02-topics-registry.ipynb
│       ├── transcript-churn-03-insights-semantic-view.ipynb
│       ├── transcript-churn-04-churn-feature-store.ipynb
│       ├── transcript-churn-05-ledger-cost.ipynb
│       ├── setup.sql
│       ├── app_setup.sql
│       └── cleanup.sql
<!-- REPO_TREE_END -->
```

---

## Getting Started

1. Clone this repository
2. Open any `.html` presentation file in a browser to view slides
3. Reference the corresponding `-speaker-notes.md` file for talking points
4. For hands-on labs, run the module's `lab/setup.sql` in your Snowflake account,
   then open the module's `lab/*.ipynb` in Snowflake Notebooks

---

## Presentation Format

All presentations follow a consistent format:

- **Dark-themed scrolling HTML** with sidebar navigation
- **Snowflake-branded** styling and color palette
- **Paired speaker notes** in Markdown with per-slide talking points, presenter
  notes, common audience questions, and reference URLs

Presentations are published via GitHub Pages at:
`https://sfc-gh-snuggehalli.github.io/field-demo-enablement/<module>/presentations/<slug>.html`
