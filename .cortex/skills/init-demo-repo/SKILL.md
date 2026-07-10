---
name: init-demo-repo
description: "Bootstrap a new Snowflake enablement/demo repository that mirrors the demos-enablement kit structure. Use this ONCE when starting a fresh repo, before creating any demo modules. Sets up the root README index, GitHub Pages deploy workflow, .gitignore, and a demo-config.json that the create-demo skill reads. Triggers: init demo repo, bootstrap demo repo, set up demos repo, new enablement repo, scaffold demo repository, start a demos repo."
---

# Init Demo Repo

Bootstraps an empty repository into a Snowflake enablement kit: a root README index,
a GitHub Pages deploy workflow, a `.gitignore` tuned to keep in-repo skills committed,
and a `demo-config.json` consumed by the `create-demo` skill.

Run this once per repository. To add individual demo modules afterward, use `create-demo`.

## When to Use

- Starting a brand-new demo/enablement repo from scratch.
- The current workspace has no `demo-config.json` yet and the user wants to add demos.

If `demo-config.json` already exists, do NOT overwrite it — tell the user the repo is
already initialized and point them to `create-demo`.

## Prerequisites

- A git repository (or an empty folder that will become one) opened as the workspace.
- The user knows their GitHub username and intended repo name (needed for Pages URLs).

## Workflow

### Step 1: Gather repo identity

Ask the user (use the question tool) for:
- **GitHub username** — the account/org that will own the repo (used in Pages + GitHub link URLs).
- **Repository name** — the repo slug on GitHub (used in Pages URLs and the repo tree).
- **Repo title** — human-readable title for the root README H1 (e.g. "Cortex AI Enablement Kit").
- **One-line description** — shown under the title.

**STOP**: Confirm these four values before writing anything.

### Step 2: Detect existing initialization

Check whether `.cortex/demo-config.json` exists in the workspace root.
- If it exists: stop and report the repo is already initialized. Do not overwrite.
- If not: proceed.

### Step 3: Write repo scaffolding

Copy the bundled templates into the repo root, substituting `{{GITHUB_USER}}`,
`{{REPO_NAME}}`, `{{REPO_TITLE}}`, and `{{REPO_DESCRIPTION}}` throughout:

1. `templates/root-README.md` → `README.md`
   Leave the `<!-- MODULE_TABLE_* -->`, `<!-- MODULE_SECTIONS_* -->`, and
   `<!-- REPO_TREE_* -->` marker comments intact — `create-demo` uses them as insertion points.
2. `templates/static.yml` → `.github/workflows/static.yml` (verbatim, no substitution).
3. `templates/gitignore` → `.gitignore` (verbatim). This keeps `.cortex/skills/`
   committed while ignoring other `.cortex/` runtime state, so the in-repo skills
   travel with the repo.
4. `templates/demo-config.json` → `.cortex/demo-config.json`, substituting the four values.

Create parent directories as needed (`.github/workflows/`, `.cortex/`).

### Step 4: Report and hand off

Tell the user:
- What was created (list the four files).
- The one-time GitHub setting they must enable manually: **repo Settings → Pages →
  Build and deployment → Source: GitHub Actions**. Pages will not deploy until this is set.
- Their decks will publish at
  `https://<github_user>.github.io/<repo_name>/<module>/presentations/<slug>.html`.
- Next step: run `create-demo` to add the first module.

## Output

- `README.md` (index shell with insertion markers)
- `.github/workflows/static.yml`
- `.gitignore`
- `.cortex/demo-config.json`

## Stopping Points

- After Step 1: confirm repo identity values.
- Step 2: halt if already initialized.
