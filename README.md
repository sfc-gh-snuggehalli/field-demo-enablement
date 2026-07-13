# Field Demo Enablement Kit

Snowflake AI/ML field demos and enablement modules

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
| AI Functions: Customer Experience Telemetry | Sales Engineers | Presentation + Hands-on Lab | [View](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/cx-ai-functions/presentations/cx-ai-functions.html) |
| Donor Lapse/Churn Intelligence: Snowflake ML → Agent | SEs + Customer ML Teams | Presentation + Hands-on Lab | [View](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/donor-churn-ml/presentations/donor-churn-ml.html) |
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
| `lab/setup.sql` | Schemas, warehouse, structured `CUSTOMERS`, app-telemetry objects, semantic view, Cortex Search, agent |
| `lab/data_gen.py` | Snowpark loader for the unstructured text tables |
| `lab/cx-ai-functions-lab.ipynb` | Notebook 1 — AI-function pipeline + app UX telemetry ingestion + AI Function Studio |
| `lab/cx-ai-functions-extensions.ipynb` | Notebook 2 — semantic view / Analyst / Search / Agent (runs live) + cost & guardrails |

### Donor Lapse/Churn Intelligence: Snowflake ML → Agent

**Location:** `donor-churn-ml/`

The complete Snowflake ML lifecycle for a generic nonprofit fundraising CRM: predict donor
lapse, explain every score, and act on it in natural language. Feature Store → Datasets →
Cortex ML Functions → Snowpark ML + HPO → ML Jobs → Model Registry → Explainability →
Serving → Observability, culminating in a Cortex Agent that calls the deployed model as a
tool, plus a Streamlit chat app. Client-agnostic and reusable across accounts.

| File | Description |
|------|-------------|
| `presentations/donor-churn-ml.html` | Slide deck (16 slides) |
| `presentations/donor-churn-ml-speaker-notes.md` | Speaker notes |
| `lab/setup.sql` | DB, four schemas, warehouses, synthetic data, Cortex ML Functions, semantic view |
| `lab/donor-churn-01-features.ipynb` | Lab 1/3 — Feature Store, Datasets, Cortex ML Functions |
| `lab/donor-churn-02-model.ipynb` | Lab 2/3 — Snowpark ML + Experiment Tracking + HPO, ML Jobs, Registry, Explainability |
| `lab/donor-churn-03-serve-agent.ipynb` | Lab 3/3 — Serving, Observability, tool functions, Cortex Agent |
| `app/streamlit_app.py` | Streamlit-in-Snowflake chat UI over the agent |
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
│       ├── data_gen.py
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
- **Paired speaker notes** in Markdown with per-slide talking points, internal
  context, common audience questions, and reference URLs

Presentations are published via GitHub Pages at:
`https://sfc-gh-snuggehalli.github.io/field-demo-enablement/<module>/presentations/<slug>.html`
