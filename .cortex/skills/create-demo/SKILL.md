---
name: create-demo
description: "Generate a complete Snowflake enablement/demo module that mirrors the demos-enablement kit: a dark-themed HTML slide deck, per-slide speaker notes, lab/setup.sql, and a hands-on lab notebook, then register it in the root README index. Use whenever the user wants a new demo, lab, or presentation for a Snowflake feature (e.g. AI Functions, AI Function Studio, Cortex Search, semantic views, ML). Triggers: create demo, new demo, build a demo, make a presentation, new lab, add a module, demo for <feature>, presentation for <feature>, scaffold a demo. Requires the repo to be initialized with init-demo-repo first."
---

# Create Demo Module

Generates one enablement module folder (`<slug>/`) matching the kit's fixed structure, then
wires it into the root `README.md` index. The design system, file layout, and naming are
fixed so every module is consistent; you fill the content for the specific feature.

## Prerequisites

- The repo must be initialized: `.cortex/demo-config.json` must exist. If it does not,
  tell the user to run `init-demo-repo` first, then stop.

## Setup

1. **Read** `.cortex/demo-config.json` for `github_user`, `repo_name`, and
   `default_warehouse_size`. Use these to fill URLs and warehouse naming — never re-ask.
2. **Load** `reference/design-system.md` before writing the deck. It documents every CSS
   component and the recommended slide arc. Do not invent CSS or change the palette.

## Workflow

### Step 1: Gather module inputs

Ask the user (question tool) for anything not already clear from their request:

- **Feature/use case** — what Snowflake capability the demo teaches (e.g. "AI Functions",
  "Cortex AI Function Studio"). Also capture the narrative/business scenario.
- **Slug** — kebab-case folder name (e.g. `ai-functions`). Propose one from the feature name.
- **Deck title** — human title (e.g. "AI Functions on Snowflake").
- **Audience** — who it's for (data & analytics teams, data engineers, etc.).
- **Include lab?** — default YES (deck + notes + setup.sql + notebook). If NO, skip the
  `lab/` artifacts and their README rows.
- **Generate data?** — default YES when the lab needs unstructured free text (chats,
  transcripts, tickets, reviews). Adds `lab/data_gen.py`. Skip for structured-only labs.
- **Slide count** — default 8-12.

Derive: `DB_NAME = <SLUG_UPPER>_DEMO`, `SCHEMA_NAME` (a sensible schema like `DEMO` or
feature-appropriate), `WH_NAME = <SLUG_UPPER>_WH`, `WH_SIZE = default_warehouse_size`,
`CONNECTION_NAME` (the user's default local connection; ask if unknown, else use `default`).

**STOP**: Confirm slug, title, DB/WH names, audience, and include-lab before generating.

### Step 2: Research the feature (accuracy gate)

Before writing SQL or slides, ground the content in real Snowflake behavior:
- Use `snowflake_product_docs` (and `snowflake_object_search` if referencing account objects)
  to confirm actual function names, signatures, arguments, limits, and privileges.
- Do NOT fabricate function names or parameters. If unsure, search first. Wrong SQL in a
  demo erodes trust — this is the single most important quality bar.

### Step 3: Generate the presentation deck

1. Copy `templates/presentation.html` to `<slug>/presentations/<slug>.html`.
2. Substitute `{{GITHUB_USER}}`, `{{REPO_NAME}}`, `{{SLUG}}`, and all `{{DECK_*}}` /
   `{{STAT*}}` / `{{PROBLEM_*}}` / `{{NEXT_*}}` / `{{CLOSING_CALLOUT}}` placeholders.
3. Build the real slide arc per `reference/design-system.md`: keep hero + problem + closing,
   and insert feature/concept/comparison/decision slides between the `<!-- ADD FEATURE ... -->`
   marker and the closing slide. Every deck MUST keep an Architecture slide (`id="architecture"`,
   layered `.arch-diagram`) right after The Problem — fill its `{{ARCH_*}}` placeholders with the
   real objects and how they connect. Each slide needs a unique `id`.
4. Rebuild the sidebar nav between `<!-- NAV_LINKS_START -->` and `<!-- NAV_LINKS_END -->`:
   one `<a href="#id">Label</a>` per slide, in order. Every href must match a slide `id`.
5. Remove the template's instructional HTML comments once content is in.

### Step 4: Generate speaker notes

Copy `templates/speaker-notes.md` to `<slug>/presentations/<slug>-speaker-notes.md`.
Write one block per slide, in deck order, each with **Talking Points / Presenter Notes /
References** (real doc URLs). Presenter Notes are facilitator guidance: prerequisites,
limits, gotchas, common questions. The final block covers the Next Steps slide.

### Step 5: Generate the lab (skip if include-lab = NO)

**setup.sql** — Copy `templates/setup.sql` to `<slug>/lab/setup.sql`. Substitute
`{{DB_NAME}}`, `{{SCHEMA_NAME}}`, `{{WH_NAME}}`, `{{WH_SIZE}}`, `{{SLUG}}`,
`{{DECK_TITLE}}`, and the prerequisites comments. Fill the stubs:
- `{{STRUCTURED_DATA_STUB}}` — structured tables via `TABLE(GENERATOR(...))` + `UNIFORM`/
  `RANDOM`/`SEQ`/`DATEADD`/array indexing, sized to run interactively.
- `{{UNSTRUCTURED_DATA_STUB}}` — a short comment listing the free-text tables that
  `data_gen.py` will create (no DDL; `write_pandas` creates them).
- `{{FEATURE_OBJECTS_STUB}}` — the objects the lab demonstrates (AI-function views,
  semantic views, Cortex Search services, agents). Objects that read the unstructured
  tables must be created AFTER `data_gen.py` runs; note this in the lab ordering.
Validate the DDL compiles with `snowflake_sql_execute` (`only_compile: true`).

**notebook** — Create the notebook by copying the template, then filling it:
```bash
cp <SKILL_DIR>/templates/lab.ipynb.tmpl <slug>/lab/<slug>-lab.ipynb
```
Then use the notebook tools (`notebook_edit_cell`, `notebook_add_cell`) to substitute the
`{{...}}` placeholders and add one markdown+code Section pair per lab section. Use
`get_active_session()` and `USE DATABASE/SCHEMA/WAREHOUSE` (already in the connect cell).
Do NOT run cells — the lab runs in the user's Snowflake account. Confirm the file is valid
JSON afterward (e.g. `python3 -c "import json,sys; json.load(open(sys.argv[1]))" <path>`).

> **If the lab involves ML** (training, feature store, registry, serving, monitoring, agents-over-models),
> STOP and load the `/machine-learning` skill (+ `feature-store`, `experiment-tracking` sub-skills)
> before writing cells, then follow the ML/MLOps non-negotiables in the Quality Bar. Consider
> splitting a long ML lifecycle into multiple lifecycle notebooks.

### Step 5b: Generate the data loader (skip if generate-data = NO)

**data_gen.py** — Copy `templates/data_gen.py` to `<slug>/lab/data_gen.py`. Substitute
`{{DECK_TITLE}}`, `{{DB_NAME}}`, `{{SCHEMA_NAME}}`, `{{WH_NAME}}`, `{{CONNECTION_NAME}}`, and
replace `{{DATA_GEN_STUB}}` inside `build_frames()` with code that builds one pandas
DataFrame per free-text table and returns them keyed by table name. Author the text with
real variety (positive/negative/mixed sentiment, a realistic topic taxonomy) so AI Functions
return interesting results. Reading/writing to Snowflake:
- The template's `get_session()` uses `get_active_session()` in a notebook/worksheet and
  falls back to `Session.builder.config("connection_name", ...)` when run locally via CLI.
- Write with `session.write_pandas(df, TABLE, auto_create_table=True, overwrite=True)` —
  this creates/replaces and bulk-loads. Do NOT hand-write per-row INSERTs for text tables.
Validate it parses (`python3 -m py_compile <slug>/lab/data_gen.py`). Do NOT execute it here —
it loads into the user's account. Keep row counts modest (hundreds–low thousands).

### Step 5c: Generate a Streamlit chat app (optional — agent/chat demos)

If the demo ends in a Cortex Agent (or otherwise benefits from a chat UI), add
`<slug>/app/streamlit_app.py`: a Streamlit-in-Snowflake app that sends natural-language
questions to the agent and renders answers inline. Use `_snowflake.send_snow_api_request`
against `POST /api/v2/databases/<db>/schemas/<schema>/agents/<agent>:run` (no external auth
needed in SiS), keep a `st.session_state` chat history, and pre-seed the demo's marquee
questions in the sidebar. Validate with `python3 -m py_compile`; do NOT run it here. Note in
the module README that it deploys as a Streamlit-in-Snowflake app and needs USAGE on the
agent and any custom-tool function.

### Step 5d: Generate the cleanup script (skip if include-lab = NO)

**cleanup.sql** — Copy `templates/cleanup.sql` to `<slug>/lab/cleanup.sql`. Substitute
`{{DECK_TITLE}}`, `{{DB_NAME}}`, `{{WH_NAME}}`, and fill the two stubs so the teardown mirrors
what setup.sql AND the notebook(s) actually create:
- `{{CLEANUP_ACCOUNT_LEVEL_STUB}}` — the account-level objects `DROP DATABASE` does NOT cascade
  that this module created: extra warehouses, dedicated roles, compute pools, **security
  integrations**, and any `ALTER USER ... DEFAULT_ROLE/DEFAULT_WAREHOUSE` the lab set (add the
  revert). These need ACCOUNTADMIN for roles/integrations.
- `{{CLEANUP_OBJECT_BY_OBJECT_STUB}}` — the "keep the database" alternative: every schema-level
  object in reverse-dependency order (agents → wrapper/tool procedures & functions → MCP servers →
  semantic views → search services → views → tables). Objects created in the NOTEBOOK (models,
  monitors, agents, tool functions) belong here too, not just setup.sql objects.
Every statement uses `IF EXISTS` (safe to re-run). The fast path is `DROP DATABASE` + the
account-level drops; the alternative is the object-by-object block. Validate the fast-path DDL
compiles (`snowflake_sql_execute` with `only_compile: true` against dummy names) — do NOT run the
real drops here (they would delete the user's demo).

### Step 6: Generate the module README

Copy `templates/module-README.md` to `<slug>/README.md` and fill all placeholders
(`{{MODULE_DESCRIPTION}}`, `{{AUDIENCE}}`, `{{TOPICS_LIST}}`, `{{SLIDE_COUNT}}`,
`{{LAB_*}}`, `{{PREREQUISITES_LIST}}`, `{{SETUP_CREATES_LIST}}`, `{{LAB_SECTIONS_LIST}}`,
`{{KEY_CONCEPTS_LIST}}`, `{{REFERENCES_LIST}}`). If no lab, drop the lab rows/sections.

### Step 7: Register the module in the root README

Edit the repo root `README.md` at its marker comments (created by init-demo-repo):

1. **Module table** — insert a row before `<!-- MODULE_TABLE_END -->`:
   `| <Title> | <Audience> | Presentation + Hands-on Lab | [View](https://<github_user>.github.io/<repo_name>/<slug>/presentations/<slug>.html) |`
   (Use "Presentation" as the format if no lab.)
2. **Module sections** — insert a section before `<!-- MODULE_SECTIONS_END -->` with the
   module title, `**Location:** <slug>/`, a one-line description, and a Contents table.
3. **Repo tree** — insert the module's tree nodes before `<!-- REPO_TREE_END -->`.

Preserve all marker comments so future runs can append again.

### Step 8: Report

List every file created, the local path to open the deck, and the published Pages URL.
Remind the user of the run order (`setup.sql` → `python lab/data_gen.py` if present →
notebook), that `lab/cleanup.sql` tears the demo down to start fresh, and to `git add`/commit/push
to publish via GitHub Pages.

**Best demo path (recommend this to the user):** run the lab inside Snowsight via
**Projects → Workspaces → Create Workspace from Git repository**. There `get_active_session()`
works with no local auth, and `data_gen.py` runs as a notebook cell (no `--connection`). The
module README already includes a "Run in Snowflake (Workspaces / Git)" section. For agent/Analyst
demos, finish in **AI & ML → Agents** (or Snowflake Intelligence) as the closing moment.

**Running locally / validating:** the Python connector can't drive `oauth_authorization_code`
(needs a client_id), so prefer the notebook path for `data_gen.py`. `snow sql -f setup.sql` works
with a connection whose **role can CREATE** the objects and use a warehouse. Gotcha: if a warehouse
named in setup.sql already exists under a different owner, `CREATE WAREHOUSE IF NOT EXISTS` won't
re-own it and Cortex Search reports the warehouse as "missing" — grant your role `USAGE, OPERATE`
on that warehouse first.

## Output

```
<slug>/
├── README.md
├── presentations/
│   ├── <slug>.html
│   └── <slug>-speaker-notes.md
├── lab/                      (omitted if include-lab = NO)
│   ├── setup.sql
│   ├── cleanup.sql
│   ├── data_gen.py           (omitted if generate-data = NO)
│   └── <slug>-lab.ipynb
└── app/                      (optional — agent/chat demos)
    └── streamlit_app.py
```
Plus updated root `README.md` (table row + section + tree node).

## Stopping Points

- After Step 1: confirm slug/title/DB/WH/audience/include-lab.
- Halt at Setup if `.cortex/demo-config.json` is missing (run init-demo-repo first).

## Quality Bar

- **No customer names, and no meta-framing in shipped content** — every artifact (deck, speaker
  notes, README, SQL/Python comments, notebook cells, agent config) is sent directly to clients, so:
  (a) NEVER put a real customer or company name anywhere — use a generic scenario + personas
  (e.g. "a nonprofit fundraising CRM", "an ML platform team"); and
  (b) NEVER describe the demo to the reader as "client-agnostic", "reusable across accounts/customers",
  "generic demo", or otherwise reveal that it is a reusable template — that framing reads wrong to a
  client. Just present the scenario directly (e.g. "Scenario: a B2B GTM SaaS company…"). Keeping content
  customer-neutral is an authoring constraint, not something to state in the artifact.
  Verify before finishing with two scans: `grep -ri "<customer>" <slug>/` returns nothing, and
  `grep -rin "client-agnostic\|reusable across" <slug>/` returns nothing.
- Real function names/signatures only — verify via docs (Step 2). No fabricated SQL.
- Deck sidebar hrefs all resolve to slide ids; template instructional comments removed.
- Deck includes an Architecture slide (`id="architecture"`, layered `.arch-diagram`) right after the Problem slide.
- setup.sql DDL compiles; notebook is valid JSON and is NOT executed here.
- **cleanup.sql is REQUIRED whenever include-lab = YES** — every module ships a `lab/cleanup.sql`
  that tears down the full demo. It MUST cover objects created in the notebook(s), not just
  setup.sql, and MUST drop the account-level objects `DROP DATABASE` does not cascade (extra
  warehouses, dedicated roles, compute pools, security integrations) plus revert any `ALTER USER`
  session defaults the lab set. Fast-path DDL compiles (only_compile against dummy names); real
  drops are NOT run during the build.
- data_gen.py compiles (`py_compile`) and uses `write_pandas`; NOT executed here.
- Structured data via SQL GENERATOR; unstructured text via data_gen.py write_pandas.
- Objects depending on unstructured tables are created after data_gen.py in the run order.
- **ML / MLOps demos — REQUIRED: load the `/machine-learning` skill FIRST.** Before authoring any
  demo that trains, tunes, registers, serves, monitors, or explains a model, invoke the
  `machine-learning` skill and read the sub-skills you will touch — at minimum `feature-store`
  (and its `create`) and `experiment-tracking`. Do NOT hand-write ML code from memory; the
  sub-skills carry API signatures and gotchas that direct tool use misses. Then follow these
  **non-negotiables** (learned from the donor-churn build):
  1. **Feature Store is the real source of truth, not decoration.** Managed Feature Views must
     COMPUTE features FROM the raw tables (aggregations off event dates), not re-`SELECT`
     precomputed columns from a training table at one hardcoded timestamp. BOTH training and
     inference must flow through the store (`generate_dataset` for training; `retrieve_feature_values`
     for serving), so point-in-time correctness is actually demonstrated (same definitions,
     different as-of → different values).
  2. **Managed FVs must be deterministic** (Dynamic-Table-backed): no `CURRENT_DATE()`/
     `CURRENT_TIMESTAMP()` inside the view. Use a static snapshot-calendar table for as-of dates.
  3. **Experiment Tracking on every training section** — `snowflake.ml.experiment.ExperimentTracking`,
     one experiment, one run per candidate config logging params + metrics; tie the winner to the
     registry via `exp.log_model`.
  4. **Use `predict_proba` for probabilities** — AUC, risk ranking, scored tables, and the monitor's
     `PREDICTION_SCORE_COLUMNS` must use the probability, never the hard predicted class.
  5. **Explainability must be enabled at registration** (`options={"enable_explainability": True}`
     in `log_model`) or the `explain` function won't exist.
  6. **Split long ML notebooks (>~10 sections) by lifecycle** into multiple notebooks, each opening
     with a rehydrate cell (reconnect + reload Feature Store / dataset / model) so it runs standalone.
  7. **No hardcoded row keys** (e.g. a specific donor_id) — pick demo rows dynamically.
  Placement: objects that depend on a trained/deployed model — Model Registry entries, Model Monitors,
  SQL tool-wrapper functions, and any agent that calls the model — are created IN THE NOTEBOOK, after
  training/serving. `setup.sql` holds only model-independent objects (data, Cortex ML Function objects,
  the Analyst semantic view). Document the run order (setup.sql → notebook(s) → app). Real ML API refs:
  Feature Store (`FeatureStore`/`Entity`/`FeatureView`, `generate_dataset`, `retrieve_feature_values`),
  Datasets, Snowpark ML (`snowflake.ml.modeling.xgboost`), distributed HPO, ML Jobs
  (`snowflake.ml.jobs.remote`, compute pool, `snowflake-ml-python>=1.26`), Registry (`log_model`,
  `target_platforms`, `default`), Explainability, Serving (`mv.run` / `run_batch`), Observability
  (`CREATE MODEL MONITOR`, `MODEL_MONITOR_*_METRIC`), and the model-as-a-tool agent (custom tool
  `type: "generic"` backed by a SQL procedure/UDF; bind it in Snowsight UI). For a strong lab signal,
  drive the training label from a hidden latent propensity (not the raw features), so RFM/behavior
  features are genuinely predictive without leakage.
- **Agent/Streamlit demos:** optionally add `app/streamlit_app.py` (Streamlit-in-Snowflake chat
  over the agent via `_snowflake.send_snow_api_request` to `agents/<name>:run`); compile it
  with `py_compile`; NOT executed here.
- Module README includes a "Run in Snowflake (Workspaces / Git)" section (Workspaces + `get_active_session()` is the recommended demo path).
- Root README markers preserved; new module appears in table, sections, and tree.
