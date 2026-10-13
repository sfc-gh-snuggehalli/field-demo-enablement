# {{DECK_TITLE}}

[View Presentation](https://{{GITHUB_USER}}.github.io/{{REPO_NAME}}/{{SLUG}}/presentations/{{SLUG}}.html)

{{MODULE_DESCRIPTION}}

## Audience

{{AUDIENCE}}

## Topics Covered

{{TOPICS_LIST}}

## Contents

| File | Description |
|------|-------------|
| `presentations/{{SLUG}}.html` | Slide deck ({{SLIDE_COUNT}} slides) |
| `presentations/{{SLUG}}-speaker-notes.md` | Per-slide speaker notes with talking points, presenter notes, and references |
| `demo.sh` | One script for setup, data load, notebook and teardown |
| `pyproject.toml`, `uv.lock` | Local Python environment (lab, notebook, Snowflake CLI), managed by uv |
| `lab/setup.sql` | SQL setup script (database, warehouse, sample data, objects) |
| `lab/cleanup.sql` | Tear everything down to start fresh |
| `lab/{{SLUG}}-lab.ipynb` | Hands-on lab notebook ({{LAB_DURATION}}) |

## Hands-On Lab

{{LAB_SUMMARY}}

### Prerequisites

{{PREREQUISITES_LIST}}
- [uv](https://docs.astral.sh/uv/) (`brew install uv`) and a Snowflake CLI connection (`snow connection add`, or any entry in `~/.snowflake/config.toml`) for the local quick start

### Quick start

```bash
./demo.sh setup        # prompts for a connection; creates the objects and loads the data
./demo.sh notebook     # the lab notebook, with the .venv kernel and the saved connection
./demo.sh teardown     # drop everything
```

`setup` is safe to re-run. Non-interactive: `./demo.sh setup -c <connection>`.

### Set up with Cortex Code

Open this repository in Cortex Code and paste:

```text
Set up the {{DECK_TITLE}} lab in the {{SLUG}} folder on my Snowflake account.
1. If uv is not installed, ask me before installing it (brew install uv).
2. Run ./demo.sh --help, then ./demo.sh setup. Add </dev/null to every demo.sh command
   so it never waits for typed input. When it stops and names a flag (such as
   -c <connection>), show me the options it printed (point out the connection marked
   is_default), ask me which to use, and re-run with that flag. If I have no Snowflake
   CLI connection, help me create one with snow connection add.
3. Judge progress by the lines starting with ==> or ERROR: (SQL output goes to .logs/).
   If it seems stuck on sign-in, tell me to finish the browser sign-in, then re-run the
   same command.
4. When setup prints Done, tell me how to open the notebook (./demo.sh notebook).
Do not run teardown unless I ask.
```

### Manual setup

Run `lab/setup.sql` in your Snowflake account. This creates:

{{SETUP_CREATES_LIST}}

### Lab Sections

{{LAB_SECTIONS_LIST}}

### Run in Snowflake (Workspaces / Git) — recommended for demos

Run everything inside Snowsight so `get_active_session()` handles auth (no local OAuth / connection
setup needed):

1. Snowsight → **Projects → Workspaces → Create Workspace from Git repository**, pointing at
   `https://github.com/{{GITHUB_USER}}/{{REPO_NAME}}`.
2. Open `{{SLUG}}/lab/setup.sql` and run it.
3. If present, run `lab/data_gen.py` as a notebook cell (uses `get_active_session()` — no
   `--connection` needed in-notebook).
4. Open `lab/{{SLUG}}-lab.ipynb` and walk the sections.

Running locally instead? Use `snow sql -f lab/setup.sql` and `python lab/data_gen.py --connection
<name>` with a connection whose **role can create the objects** and use a warehouse. If a referenced
warehouse already exists under a different owner, grant your role `USAGE, OPERATE` on it.

## Key Concepts

{{KEY_CONCEPTS_LIST}}

## References

{{REFERENCES_LIST}}
