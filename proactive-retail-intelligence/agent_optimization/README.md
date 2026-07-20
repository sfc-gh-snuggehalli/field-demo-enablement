# Agent Optimization

Cortex Agent quality lives almost entirely in the **tool descriptions** and
**orchestration instructions** — they are how the orchestration model decides which tool to
call for each sub-task. This folder captures the before/after of the optimization pass done
in Section 6b of the lab.

- `versions/baseline/agent_spec.yaml` — thin descriptions, no orchestration guidance
  (created as `PROACTIVE_RETAIL_AGENT_BASELINE`).
- `versions/optimized/agent_spec.yaml` — the tuned spec (created as
  `PROACTIVE_RETAIL_AGENT`).

## What changed and why

| Dimension | Baseline | Optimized | Why it matters |
|-----------|----------|-----------|----------------|
| Tool descriptions | `"Returns a briefing."`, `"Store data."`, `"Return reasons."` | Purpose-driven: what the tool does, which data it reads, and **when NOT to use it** | The orchestrator picks tools from their descriptions. Vague descriptions cause wrong tool calls and hallucinated answers. |
| Orchestration instruction | *(none)* | Explicit routing: briefing first for "what changed"; Analyst for store metrics; Search for reason text; chart on request | Removes ambiguity when more than one tool could plausibly answer. |
| Response instruction | `"Answer questions about retail returns."` | Lead with headline → driver → 2-3 next steps; don't restate raw JSON | Produces the proactive, action-oriented voice the use case needs. |
| Sample questions | *(none)* | Three seeded questions that mirror the proactive + ad-hoc flows | Seeds the UI and steers first-turn behavior toward the intended experience. |
| Budget | *(default)* | `seconds: 30`, `tokens: 16000` | Bounds orchestration cost and latency. |
| `data_to_chart` | absent | added | Lets the agent visualize follow-up comparisons. |

## The single highest-leverage change

Adding **"when NOT to use it"** to each tool description. It is the most reliable way to stop
the orchestrator from reaching for the briefing tool when the user wants a specific store
metric, or reaching for Analyst when the user wants free-text reasons.

## How to apply

Both specs are the body of a `CREATE OR REPLACE AGENT ... FROM SPECIFICATION $$ ... $$`
statement (see the lab notebook). To iterate on a live agent without recreating it, use
`ALTER AGENT <name> MODIFY LIVE VERSION SET SPECIFICATION = $$ ... $$;` — note the new
specification fully replaces the old one.
