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
| Conversational BI: Semantic Views + Cortex Analyst + Agent | Sales Engineers | Presentation + Hands-on Lab | [View](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/conversational-bi/presentations/conversational-bi.html) |
| Donor Lapse/Churn Intelligence: Snowflake ML → Agent | SEs + Customer ML Teams | Presentation + Hands-on Lab | [View](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/donor-churn-ml/presentations/donor-churn-ml.html) |
<!-- MODULE_TABLE_END -->

---

## Modules

<!-- MODULE_SECTIONS_START -->
### AI Functions: Customer Experience Telemetry

**Location:** `cx-ai-functions/`

Turn raw chat threads, call transcripts, and support tickets into structured sentiment and
topic telemetry — entirely in SQL with Snowflake AI Functions — then optimize a custom
function with AI Function Studio.

| File | Description |
|------|-------------|
| `presentations/cx-ai-functions.html` | Slide deck (12 slides) |
| `presentations/cx-ai-functions-speaker-notes.md` | Speaker notes |
| `lab/setup.sql` | Database, schema, warehouse, structured `CUSTOMERS` |
| `lab/data_gen.py` | Snowpark loader for the unstructured text tables |
| `lab/cx-ai-functions-lab.ipynb` | Hands-on lab notebook |

### Conversational BI: Semantic Views + Cortex Analyst + Agent

**Location:** `conversational-bi/`

Centralize churn, revenue, and engagement in one governed semantic view, query it in natural
language with Cortex Analyst, and wrap it in a Cortex Agent that also searches the CX chat
telemetry from the AI Functions module.

| File | Description |
|------|-------------|
| `presentations/conversational-bi.html` | Slide deck (11 slides) |
| `presentations/conversational-bi-speaker-notes.md` | Speaker notes |
| `lab/setup.sql` | Structured tables, semantic view, Cortex Search service, agent |
| `lab/conversational-bi-lab.ipynb` | Hands-on lab notebook |

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
| `lab/donor-churn-ml-lab.ipynb` | Hands-on lab notebook (full ML lifecycle + agent) |
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
├── cx-ai-functions/            # AI Functions: Customer Experience Telemetry
│   ├── README.md
│   ├── presentations/
│   │   ├── cx-ai-functions.html
│   │   └── cx-ai-functions-speaker-notes.md
│   └── lab/
│       ├── setup.sql
│       ├── data_gen.py
│       └── cx-ai-functions-lab.ipynb
├── conversational-bi/          # Conversational BI: Semantic Views + Analyst + Agent
│   ├── README.md
│   ├── presentations/
│   │   ├── conversational-bi.html
│   │   └── conversational-bi-speaker-notes.md
│   └── lab/
│       ├── setup.sql
│       └── conversational-bi-lab.ipynb
├── donor-churn-ml/             # Donor Lapse/Churn Intelligence: Snowflake ML → Agent
│   ├── README.md
│   ├── presentations/
│   │   ├── donor-churn-ml.html
│   │   └── donor-churn-ml-speaker-notes.md
│   ├── lab/
│   │   ├── setup.sql
│   │   └── donor-churn-ml-lab.ipynb
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
