# {{REPO_TITLE}}

{{REPO_DESCRIPTION}}

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
<!-- MODULE_TABLE_END -->

---

## Modules

<!-- MODULE_SECTIONS_START -->
<!-- MODULE_SECTIONS_END -->

---

## Repository Structure

```
{{REPO_NAME}}/
├── README.md
├── .github/
│   └── workflows/
│       └── static.yml          # GitHub Pages deploy
<!-- REPO_TREE_START -->
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
`https://{{GITHUB_USER}}.github.io/{{REPO_NAME}}/<module>/presentations/<slug>.html`
