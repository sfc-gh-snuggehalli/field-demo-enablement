# Presentation Design System

The deck template (`templates/presentation.html`) ships a fixed CSS design system.
When composing slides, reuse these components — do NOT invent new CSS or change the
`:root` palette, the `<style>` block, or the `<script>` block. Only add/fill
`<section class="slide">` blocks and matching sidebar `<a>` links.

## Palette (CSS variables, do not change)

| Variable | Hex | Use |
|----------|-----|-----|
| `--bg` | `#0F1B2D` | Page background |
| `--sidebar-bg` | `#1B2A4A` | Sidebar |
| `--primary` | `#29B5E8` | Snowflake blue — accents, links, stat values |
| `--accent` | `#7C3AED` | Purple — secondary accent, gradients |
| `--text` / `--text-muted` | `#E2E8F0` / `#94A3B8` | Body text |
| `--card-bg` / `--border` | `#162236` / `#2D4A6F` | Cards, code blocks, borders |
| `--green` / `--orange` / `--red` | `#10B981` / `#F59E0B` / `#EF4444` | Status colors |

## Slide skeleton

```html
<section class="slide" id="unique-id">
  <h2>Slide Title</h2>
  <h3>Optional subtitle</h3>
  <!-- one or more components below, each wrapped with class="anim-fade" -->
</section>
```

Every slide needs a unique `id`, and a matching `<a href="#unique-id">Label</a>` in the
sidebar `<nav>`. The active-nav script keys off these ids. Wrap content blocks in
`class="anim-fade"` so they fade in on scroll.

## Components

| Component | Markup | When to use |
|-----------|--------|-------------|
| Hero stats | `.stat-grid` > 4x `.stat-card` (`.value` + `.label`) | Title slide headline numbers |
| Feature/pain cards | `.card-grid` > `.card` (`h4` + `p`) | 2-6 parallel points; auto-wraps |
| Side-by-side | `.two-col` > 2x `.card` | Compare exactly two things |
| Process flow | `.flow-diagram` > `.flow-step` (`.step-label` + `.step-title`) separated by `<div class="flow-arrow">&rarr;</div>` | Sequential pipeline; add `.active` to highlight steps |
| Architecture diagram | `.arch-diagram` > stacked `.level` (each holding one or more `.node`), separated by `<div class="arrow">&darr;</div>` | Layered system architecture (which objects talk to which). Accent the entry point with `.node node-primary` and mid-tier objects with `.node node-accent`. Use this for the Architecture slide; use `.flow-diagram` for linear pipelines |
| Comparison table | `<table>` with `<thead>`/`<tbody>` | Multi-dimension comparisons |
| Status pill | `<span class="badge-green\|orange\|red\|blue\|purple">` | Inline ratings inside tables/cards |
| Emphasis callouts | `.highlight-box` (blue), `.context-box` (purple), `.warning-box` (orange) | Key insight / presenter framing / caveat |
| Code block | `<pre>` with span classes `.keyword` `.string` `.comment` `.function` | SQL/Python snippets with manual syntax highlighting |
| Bulleted list | `.slide ul > li` | Short lists (auto blue-dot bullets) |

## Code block highlighting

Wrap tokens by hand:

```html
<pre><span class="comment">-- comment</span>
<span class="keyword">SELECT</span> <span class="function">MY_FUNC</span>(col) <span class="keyword">FROM</span> t
<span class="keyword">WHERE</span> x = <span class="string">'value'</span>;</pre>
```

- `.keyword` — SQL/Python keywords (SELECT, CREATE, FROM, def, import) — purple
- `.function` — function/UDF names — blue
- `.string` — string literals — green
- `.comment` — comments — muted italic

## Recommended slide arc (8-14 slides)

1. **Hero** (`id="hero"`) — title + 4 stat cards.
2. **The Problem** (`id="problem"`) — card-grid of pain points, optional warning-box.
3. **Architecture** (`id="architecture"`) — layered `.arch-diagram` showing the objects
   involved and how they connect (sources &rarr; processing layer &rarr; entry point),
   plus a `.context-box` summarizing the pattern. Every deck should have this slide right
   after The Problem — it orients the audience before the feature deep-dives.
4-N. **Feature/concept slides** — one per capability. Mix code blocks, flow diagrams,
   two-col, and callout boxes. This is where the tool/feature is demonstrated.
- **Comparison** (`id="comparison"`) — table with badges when contrasting approaches.
- **Decision framework** (`id="decision"`) — card-grid with colored borders
  (`style="border-color: var(--green)"`) mapping options to when-to-use bullets.
- **Next Steps** (`id="closing"`) — card-grid of actions + closing highlight-box.

Keep body copy tight; the speaker notes carry the depth.
