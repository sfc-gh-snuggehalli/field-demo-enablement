# The Meta-Prompt Pattern

`PROMPT.md` was not written by hand. It came from a short seed prompt. Cortex Code asked clarifying questions and then expanded the answers into a full build specification. This file records that loop so you can rerun it for any brand or domain.

## Step 1 — Seed prompt (paste into Cortex Code, high-reasoning model)

```text
I want to build a branded, CoWork-style chat app for ACME Retail that fronts a
Cortex Agent over their store-operations data. It should use
@snowflake/cortex-agent-sdk, carry ACME's own logo/colors/animated thinking
logo, let the agent drive an embedded browser of ACME's internal apps, and
deploy to Snowflake.

Do not build anything yet. Ask me the questions you need answered to write a
complete, unambiguous build prompt, then write that prompt to PROMPT.md.
```

## Step 2 — Clarifying questions Cortex Code asked (and the answers given)

| # | Question | Answer |
|---|---|---|
| 1 | Frontend stack? | React + TypeScript + Vite, reusable inside a Next.js App Runtime wrapper |
| 2 | Where do credentials live? | Server-side proxy only (PAT locally, service OAuth token in Snowflake) |
| 3 | How is branding swapped? | One `brand.config.ts`; ship ACME plus a second theme to prove it |
| 4 | What does the thinking animation look like? | Original SVG + CSS, the ACME "A" with an orbiting orange chevron |
| 5 | How does the agent control the browser? | Client-side `generic` tools; the React app executes them via a postMessage bridge |
| 6 | Which write actions need approval? | Anything marked `data-agent-confirm`, plus every sandbox write |
| 7 | What data does the agent see? | Same seed JSON loaded into Snowflake and the simulator, so numbers match |
| 8 | Advanced modes? | Power Mode (`code_toolset_all`) and Studio (headless Cortex Code runner) |
| 9 | Deploy targets? | Docker, SPCS, and Snowflake App Runtime |
| 10 | What makes it feel production-grade? | Resumable runs, server-side history, SSO identity, small first load |
| 11 | How do we know it's done? | 21 acceptance criteria, including 3 end-to-end scenarios |

## Step 3 — Build

Open a fresh Cortex Code session (high reasoning effort), attach `PROMPT.md`, and say:

```text
Build the application described in PROMPT.md. Follow it exactly, starting with
the Step 0 client-side tool spike, and stop to ask me before any deploy.
```

## Re-targeting to another brand or domain

Re-run Step 1 with your company, data domain, and apps. The answers to questions 3–7 change. Everything else (SDK integration, tool loop, resumable runs, deploy paths) carries over unchanged.
