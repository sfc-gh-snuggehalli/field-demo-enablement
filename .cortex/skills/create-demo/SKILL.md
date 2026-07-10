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
- **Audience** — who it's for (SEs, data engineers, etc.).
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
Write one block per slide, in deck order, each with **Talking Points / Internal Context /
References** (real doc URLs). Internal Context is SE-only framing: competitive angles,
limits, common objections. The final block covers the Next Steps slide.

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
notebook), and to `git add`/commit/push to publish via GitHub Pages.

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
└── lab/                      (omitted if include-lab = NO)
    ├── setup.sql
    ├── data_gen.py           (omitted if generate-data = NO)
    └── <slug>-lab.ipynb
```
Plus updated root `README.md` (table row + section + tree node).

## Stopping Points

- After Step 1: confirm slug/title/DB/WH/audience/include-lab.
- Halt at Setup if `.cortex/demo-config.json` is missing (run init-demo-repo first).

## Quality Bar

- Real function names/signatures only — verify via docs (Step 2). No fabricated SQL.
- Deck sidebar hrefs all resolve to slide ids; template instructional comments removed.
- Deck includes an Architecture slide (`id="architecture"`, layered `.arch-diagram`) right after the Problem slide.
- setup.sql DDL compiles; notebook is valid JSON and is NOT executed here.
- data_gen.py compiles (`py_compile`) and uses `write_pandas`; NOT executed here.
- Structured data via SQL GENERATOR; unstructured text via data_gen.py write_pandas.
- Objects depending on unstructured tables are created after data_gen.py in the run order.
- Module README includes a "Run in Snowflake (Workspaces / Git)" section (Workspaces + `get_active_session()` is the recommended demo path).
- Root README markers preserved; new module appears in table, sections, and tree.
