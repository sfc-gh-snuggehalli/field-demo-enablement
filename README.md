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

<!-- MODULE_TABLE_START -->
| Module | Audience | Format | Presentation |
|--------|----------|--------|--------------|
| AI Functions: Customer Experience Telemetry | Data & Analytics teams | Presentation + Hands-on Lab | [View](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/cx-ai-functions/presentations/cx-ai-functions.html) |
| Donor Lapse/Churn Intelligence: Snowflake ML → Agent | Engineering leadership (VP-level) & data science / ML platform teams | Presentation + Hands-on Lab | [View](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/donor-churn-ml/presentations/donor-churn-ml.html) |
| Migrating GTM AI: Claude Code + MCP → Cortex Agents + CoWork | Sales engineers & data/AI teams | Presentation + Hands-on Lab | [View](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/gtm-agents-migration/presentations/gtm-agents-migration.html) |
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
