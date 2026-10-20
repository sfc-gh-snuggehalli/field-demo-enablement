---
name: create-demo
description: "Generate a complete Snowflake enablement/demo module that mirrors the demos-enablement kit: a dark-themed HTML slide deck, per-slide speaker notes, a timed demo script (run of show), lab/setup.sql, a hands-on lab notebook, and a uv-packaged ./demo.sh that sets the lab up in one command (also from a Cortex Code prompt in the README), then register it in the root README index. Use whenever the user wants a new demo, lab, or presentation for a Snowflake feature (e.g. AI Functions, AI Function Studio, Cortex Search, semantic views, ML). Triggers: create demo, new demo, build a demo, make a presentation, new lab, add a module, demo for <feature>, presentation for <feature>, scaffold a demo. Requires the repo to be initialized with init-demo-repo first."
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
3. **Load** `reference/demo-sh-patterns.md` before writing `demo.sh` (Step 5e). It holds the
   vetted blocks for headless `build`, `app`/`smoke`, PAT issue/rotate/expiry, service-user key
   pairs and secret teardown.

## Workflow

### Step 1: Gather module inputs

Ask the user (question tool) for anything not already clear from their request:

- **Feature/use case** — what Snowflake capability the demo teaches (e.g. "AI Functions",
  "Cortex AI Function Studio"). Also capture the narrative/business scenario.
- **Slug** — kebab-case folder name (e.g. `ai-functions`). Propose one from the feature name.
- **Deck title** — human title (e.g. "AI Functions on Snowflake").
- **Audience** — who it's for (data & analytics teams, data engineers, etc.).
- **Include lab?** — default YES (deck + notes + setup.sql + notebook + `demo.sh`/uv packaging). If NO, skip the
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
The template's connect cell also carries the account guard (`DEMO_EXPECTED_ACCOUNT`), a local
`%%sql -r <name>` magic (so SQL cells run under `./demo.sh build` too; one statement per cell) and
`check(section, ok, evidence)`. **End every section with a `check(...)`** that tests a real
outcome (row counts, the expected answer, a grant present) and prints its evidence; `build` echoes
these `CHECK` lines and a FAIL stops the run. Give cells a `name` in metadata.
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

### Step 5e: Package the lab with uv + demo.sh (skip if include-lab = NO)

Every lab ships a one-command local setup that a person or an agent (Cortex Code) can run.
Package for the lab's own stack, and add no wrapper around commands that already exist:
a Node/npm app keeps its `package.json` (no `pyproject.toml`/`uv.lock`) and gets a single
`setup.sh` (setup + `--teardown`) with the same agent-safe contract below; after setup,
the README points at the npm scripts instead of re-wrapping them in subcommands. The
uv + `demo.sh` layout below is for Python labs (notebooks, Streamlit, lab scripts).

1. **pyproject.toml** - Copy `templates/pyproject.toml` to `<slug>/pyproject.toml`. Fill
   `{{SLUG}}` and replace the `{{EXTRA_DEPENDENCIES}}` comment with every package the notebook,
   `data_gen.py` and any lab script import (e.g. `snowflake-ml-python`, `xgboost`,
   `scikit-learn`, `streamlit[snowflake]`, `langchain-openai`). The notebook must NOT carry a
   `%pip install` cell; its first section says dependencies come from `./demo.sh setup`.
   If `app/` has its own `pyproject.toml` (the Streamlit-in-Snowflake manifest), leave it and
   run app commands with `uv run --project <module>` so uv does not pick up the app's file.
2. **Lock it**: `echo 3.11 > <slug>/.python-version`, then `(cd <slug> && uv lock && uv sync --frozen)`,
   and import every top-level package once with `uv run --frozen python -c "import ..."`.
   Commit `uv.lock`. `.venv/` and `.env` are gitignored at the repo root.
3. **demo.sh** - Copy `templates/demo.sh` to `<slug>/demo.sh` (`chmod +x`). Fill `{{DECK_TITLE}}`,
   `{{SLUG}}`, `{{DB_NAME}}`. The template already checks the account behind the connection and
   writes `SNOWFLAKE_ACCOUNT` (org-account, for REST hosts) and `DEMO_EXPECTED_ACCOUNT` to `.env`.
   Add blocks from `reference/demo-sh-patterns.md` as the lab needs them:
   - **`build [--yes]`** whenever the notebook creates objects or is the verification run: it runs
     the notebook headless with nbconvert and echoes the `CHECK` lines (add `nbconvert` to
     `pyproject.toml`). Then setup only prepares (env, connection, account-level objects) and
     `build` does the rest; the README Quick start shows `setup -c` then `build --yes`.
   - **`app` / `smoke`** for a local app or a headless check script.
   - **PAT issue/rotate/expiry + `pat`** when anything calls a Snowflake REST API with a PAT;
     **service-user key pairs** when the lab signs in as persona/service users. Both keep secrets
     out of stdout, so they run safely under Cortex Code; never leave them as manual README steps.
   Add a subcommand per extra lab entry point, each `need_uv; load_env; run <cmd>`, and list it in
   the header comment and `usage()` range.
   Keep the agent-safe contract (Cortex Code runs it with no terminal):
   - every prompt goes through `ask <var> <prompt> <flag-hint>`, never a bare `read`: for a
     person at a terminal it prompts; otherwise it stops and names the flag that answers it.
     A TTY check alone is not enough: Cortex Code Desktop runs commands in a real terminal
     (sets `COCO_AGENT=1`), so a bare `read` hangs it. `ask` also treats `COCO_AGENT`/`CI` as
     non-interactive, and the README prompt tells the agent to add `</dev/null`
   - every interactive answer has a flag (`-c`, `-p`, `--create-pat`, `--yes` ...)
   - destructive or credit-spending commands (teardown, load bursts, deploy) need an explicit
     subcommand or `--yes`, never a default
   - run SQL files through `sql_file` (output to `.logs/<file>.log`, tail shown on failure,
     `DEMO_VERBOSE=1` streams it): `snow sql -f` echoes every statement, and hundreds of lines
     of SQL bury the `==>` progress lines an agent reads and get truncated by its tools
   - `usage()` reads `"$HERE/demo.sh"` (the script `cd`s to its folder), not `$0`
4. **setup.sql must survive re-runs**: `snow sql -f` stops at the first failing statement, so
   anything that errors on a second run (`ALTER USER ... ADD PROGRAMMATIC ACCESS TOKEN`, plain
   `CREATE` of an existing object) breaks `./demo.sh setup`. Use `CREATE OR REPLACE` / `IF NOT
   EXISTS`, and move PAT issuance into `demo.sh` (SHOW, then ROTATE if present else ADD; parse
   `token_secret` from `--format json`; write the file with umask 077). Account-specific values
   (e.g. an egress host) go in as `<% name %>` placeholders filled with `snow sql -D name=value`;
   `demo.sh` derives them from the connection. Document the placeholder for Snowsight runs.
5. **Credentials**: `demo.sh setup` writes `<slug>/.env` (connection name, account, and whatever the
   lab scripts read: PAT file path and expiry, key file paths) and every subcommand loads it, so
   nobody exports variables by hand. The notebook template's connect cell falls back to
   `SNOWFLAKE_DEFAULT_CONNECTION_NAME` when there is no active session. Never hard-code an account
   identifier in the module (app config, `.env.example`, notebook): derive it from the connection.
6. **Validate**: `bash -n <slug>/demo.sh`; `./demo.sh --help` from another directory; and
   `./demo.sh setup </dev/null` must stop with the `-c` message, not hang or exit silently; with
   `build`, `COCO_AGENT=1 ./demo.sh build` (after a `.env` exists) must stop with the `--yes` message.
   Running real setup/build is the user's call (it writes to their account); offer it.

### Step 6: Generate the module README

Copy `templates/module-README.md` to `<slug>/README.md` and fill all placeholders
(`{{MODULE_DESCRIPTION}}`, `{{AUDIENCE}}`, `{{TOPICS_LIST}}`, `{{SLIDE_COUNT}}`,
`{{LAB_*}}`, `{{PREREQUISITES_LIST}}`, `{{SETUP_CREATES_LIST}}`, `{{LAB_SECTIONS_LIST}}`,
`{{KEY_CONCEPTS_LIST}}`, `{{REFERENCES_LIST}}`). If no lab, drop the lab rows/sections and the
Quick start / Set up with Cortex Code / Manual setup headings. The Cortex Code prompt block
names the module's real subcommands and flags; add a line for each extra step (e.g. ask before
`build --yes` and show its CHECK lines; start the app in the background and give the URL) and
list every command it must not run unprompted. Link only within this repo: a module that grew out
of work in another repo carries that content (SQL, notes) itself, never a relative `../other-repo` path.

### Step 6b: Generate the demo script (run of show)

Every module ships `<slug>/demo_script.md`, the presenter's run of show for a live talk. The
speaker notes explain each slide; the demo script sequences the deck, the notebook(s), Snowsight
and any app into timed segments with the exact values the room should see.

Copy `templates/demo-script.md` to `<slug>/demo_script.md` and fill every placeholder:
- **Header**: `{{TOTAL_MINUTES}}` (a 20-25 minute default), `{{CUT_MINUTES}}` (what the Cuts reach),
  `{{AUDIENCE}}`, `{{LIVE_SURFACES}}` (e.g. "the lab notebooks and Snowsight"), and three takeaways.
- **Pre-flight**: what must be true the day before (`build --yes` passed, screenshots of each
  expected result, credentials still valid), 30 minutes before (warm-up calls, open tabs) and the
  screen start state.
- **`{{RUN_OF_SHOW_ROWS}}`**: one row per segment, `| N | Segment | Where | Minutes | Ends at |`,
  numbered from 0 (the deck frame) to the close. `Where` names slides by number (`Deck, slides
  1-4`) and notebooks by section. `Ends at` is the running total (`3:00`, `6:00` ...).
- **`{{SEGMENTS}}`**: one `## N. <Segment> (<where>, <min> min)` block per row, written as
  **Say** / **Do** / **Show** / **If** beats. Every **Show** names the value the room should see,
  taken from a verified build (a CHECK line or a cell output), never invented. Add a
  **Fill while it runs** line for any call slower than ~10 s.
- **Cuts**: an ordered list with the minutes each saves, then the one segment that is never cut
  and why.
- **Recovery tips**: one row per live dependency (each AI call, refresh, UI page, app, PAT).
- **Q&A prep** (bold question, short answer) and **After the talk**.

Write a first pass from the design, then a final pass after the lab has run, replacing every
expected value with the measured one.

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

List every file created, the local path to open the deck, `demo_script.md` (its run-of-show
table and total minutes), and the published Pages URL.
Remind the user of the run order (`./demo.sh setup` → `./demo.sh build --yes` or `./demo.sh notebook`;
by hand: `setup.sql` → `python lab/data_gen.py` if present → notebook), that `./demo.sh teardown` (or
`lab/cleanup.sql`) tears the demo down to start fresh, that the README's "Set up with Cortex
Code" prompt lets a new user set it up by pasting it into Cortex Code, and to `git add`/commit/push
to publish via GitHub Pages.

**Best demo path (recommend this to the user):** run the lab inside Snowsight via
**Projects → Workspaces → Create Workspace from Git repository**. There `get_active_session()`
works with no local auth, and `data_gen.py` runs as a notebook cell (no `--connection`). The
module README already includes a "Run in Snowflake (Workspaces / Git)" section. For agent/Analyst
demos, finish in **AI & ML → Agents** (or Snowflake Intelligence) as the closing moment.

**Running locally / validating:** `./demo.sh` runs everything through the module's uv
environment. With an `oauth_authorization_code` connection, each new process (snow CLI,
notebook kernel, app) may open a browser sign-in; for headless or repeated runs use a PAT
connection. `snow sql -f setup.sql` works
with a connection whose **role can CREATE** the objects and use a warehouse. Gotcha: if a warehouse
named in setup.sql already exists under a different owner, `CREATE WAREHOUSE IF NOT EXISTS` won't
re-own it and Cortex Search reports the warehouse as "missing" — grant your role `USAGE, OPERATE`
on that warehouse first.

## Output

```
<slug>/
├── README.md
├── demo_script.md            (timed run of show for the live talk)
├── demo.sh                   (omitted if include-lab = NO)
├── pyproject.toml, uv.lock, .python-version   (omitted if include-lab = NO)
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
- **demo_script.md is REQUIRED** (Step 6b): the run-of-show minutes sum to the stated total and
  each `Ends at` is the running sum; every slide number it cites exists in the deck; every
  **Show** carries a concrete value from a verified run; the Cuts name one never-cut segment;
  Recovery has a row for each live dependency; no `{{` placeholder is left.
- setup.sql DDL compiles; notebook is valid JSON and is NOT executed here.
- **demo.sh + uv packaging is REQUIRED whenever include-lab = YES** (Step 5e): `uv.lock` resolves,
  every notebook/script import is a declared dependency, no `%pip install` cell, no bare `read`
  prompts, `./demo.sh setup </dev/null` stops with a flag message, setup.sql re-runs cleanly,
  and the README carries the Quick start and "Set up with Cortex Code" prompt.
- Every notebook section ends in a `check(...)` CHECK line; a lab whose notebook creates objects
  ships `./demo.sh build`. PATs and key pairs are issued by `demo.sh` (never pasted by hand), secrets
  never reach stdout, and teardown removes the PATs and local secret files it created.
- No hard-coded account identifiers and no links into other repos: `grep -rn "<your account>\|\.\./[a-z-]*/" <slug>/`
  finds nothing that points outside the repo.
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
