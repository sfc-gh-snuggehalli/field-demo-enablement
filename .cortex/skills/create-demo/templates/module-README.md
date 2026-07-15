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
| `lab/setup.sql` | SQL setup script (database, warehouse, sample data, objects) |
| `lab/{{SLUG}}-lab.ipynb` | Hands-on lab notebook ({{LAB_DURATION}}) |

## Hands-On Lab

{{LAB_SUMMARY}}

### Prerequisites

{{PREREQUISITES_LIST}}

### Setup

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
