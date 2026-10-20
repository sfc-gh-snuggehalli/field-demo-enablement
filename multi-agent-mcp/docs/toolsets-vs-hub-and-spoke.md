# Agent toolsets vs hub and spoke, explained simply

This lab puts two architectures behind one MCP connector. This page walks through how each one answers a question, using the lab's own objects. For the measured latencies, evaluation scores and the "claims, checked" table, see [The agent toolset pattern](../README.md#the-agent-toolset-pattern) in the README.

## Two architectures, not three

The "sproc approach" and hub and spoke are the same architecture. Hub and spoke is *built from* stored procedures: the orchestrator's "call a specialist" tools are the `ASK_SALES_SPECIALIST` and `ASK_SUPPORT_SPECIALIST` procedures.

| | Hub and spoke (procedure bridges) | Agent toolset |
|---|---|---|
| Front-door agent | `ORCHESTRATOR_AGENT` | `TOOLSET_AGENT` |
| MCP server | `ORCHESTRATOR_MCP` | `TOOLSET_MCP` |
| Defined in | [`lab/setup.sql`](../lab/setup.sql) Parts 5 and 6 | [Notebook](../lab/multi-agent-mcp-lab.ipynb) Section 3 |

From the MCP side they are identical. Both servers expose one tool, `northwind_assistant`, of type `CORTEX_AGENT_RUN`, so Claude cannot tell them apart. The app's architecture switch changes only the server URL (`SERVERS` in [`app/personas.py`](../app/personas.py)). Everything that differs happens inside Snowflake.

## The mental model

- **Hub and spoke is a phone call.** The orchestrator phones a specialist agent. The specialist answers with its own playbook (instructions, model, budget), and only a string comes back over the line.
- **A toolset is borrowing the toolbox.** The front-door agent takes the specialists' tools and uses them itself. The specialists' playbooks are never opened.

## What each spec contains

**Hub and spoke.** The orchestrator has two `generic` tools, each backed by a procedure ([`lab/setup.sql`](../lab/setup.sql) Part 6):

```yaml
tools:
  - tool_spec: { type: generic, name: ask_sales, input_schema: { user_query: string } }
tool_resources:
  ask_sales: { type: procedure, identifier: MULTI_AGENT_MCP_DEMO.APP.ASK_SALES_SPECIALIST }
```

The procedure is `EXECUTE AS CALLER` (Part 5). In outline:

```python
resp = session.sql("SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(?, ?)", params=[SALES_AGENT, body])
# error 399513 (no USAGE on the specialist) -> return "NOT_ENTITLED: ..."
# otherwise -> return the text, with tables rendered as markdown: one string
```

**Agent toolset.** `TOOLSET_AGENT` has no tools of its own, only two references (notebook Section 3):

```yaml
tools:
  - tool_spec: { type: agent_toolset, name: sales_tools }
  - tool_spec: { type: agent_toolset, name: support_tools }
tool_resources:
  sales_tools:   { agent_name: MULTI_AGENT_MCP_DEMO.APP.SALES_AGENT }
  support_tools: { agent_name: MULTI_AGENT_MCP_DEMO.APP.SUPPORT_AGENT }
```

At run time Snowflake reads `SALES_AGENT`'s specification and copies its `sales_analyst` tool, with the semantic view and warehouse, into `TOOLSET_AGENT`. It does the same with `support_kb` from `SUPPORT_AGENT`. There is no procedure, no `DATA_AGENT_RUN` and no second agent run.

## Example 1: the global sales exec asks "What were total new bookings in FY25-Q4 by theater?"

**Hub and spoke** (two agent runs):

1. Claude calls `northwind_assistant`, which starts `ORCHESTRATOR_AGENT` (agent run 1).
2. The orchestrator sees `ask_sales` and `ask_support`, and calls `ask_sales(user_query="...")`.
3. `ASK_SALES_SPECIALIST` calls `DATA_AGENT_RUN` on `SALES_AGENT`, as the caller's role.
4. `SALES_AGENT` starts (agent run 2, with its own instructions, model and 180-second budget). It calls `sales_analyst`, which runs SQL through `SALES_SEMANTIC_VIEW`.
5. The procedure flattens the reply to text plus a markdown table and returns that string.
6. The orchestrator relays the string. A chart cannot cross the procedure, so if one is asked for, the orchestrator redraws it from the markdown table. That is why the hub's chart is slower.

**Agent toolset** (one agent run):

1. Claude calls `northwind_assistant`, which starts `TOOLSET_AGENT`.
2. Snowflake resolves the references. This persona sees only `sales_analyst` (Example 2 explains why).
3. The agent calls `sales_analyst` directly and returns the table and a native chart in its own response.

`SALES_AGENT`'s instruction "Lead with the number ... format as $X.XM" never runs in the toolset path. That is why `TOOLSET_AGENT` repeats it in its own `response` instructions. **A toolset inherits tools, not behavior.**

## Example 2: who sees which tools, and how "no" happens

Both architectures use the same grants ([`lab/setup.sql`](../lab/setup.sql) Part 7): the sales roles have USAGE on `SALES_AGENT` only, and the support role on `SUPPORT_AGENT` only.

| Persona | Hub: tools the orchestrator sees | Toolset: tools the agent sees |
|---|---|---|
| Global sales exec | `ask_sales`, `ask_support` | `sales_analyst` |
| EMEA seller | `ask_sales`, `ask_support` | `sales_analyst` (the row access policy still returns EMEA rows only) |
| Support rep | `ask_sales`, `ask_support` | `support_kb` |

When the support rep asks a sales question:

- **Hub and spoke:** the orchestrator calls `ask_sales`. The procedure runs `DATA_AGENT_RUN` as the support role, and Snowflake rejects it with error 399513. The procedure returns `NOT_ENTITLED: ...`, and the orchestrator's instructions turn that into the refusal. The denial is **explicit**, and the app's inspector shows it under **Inside Snowflake**.
- **Agent toolset:** USAGE on `SALES_AGENT` is checked as the caller and fails, so the `sales_tools` reference is skipped **silently**. The agent has no sales tool at all. The refusal wording comes only from `TOOLSET_AGENT`'s instructions. Nothing errors, and the trace shows nothing.

The data is protected either way, because the boundary is grants, not prompts. The difference is whether the "no" is visible.

## Example 3: a cross-domain question

"What was total pipeline in FY25-Q4, and how do I schedule a recurring export?"

- **Hub and spoke:** the orchestrator calls `ask_sales` and `ask_support`, which makes three agent runs (the orchestrator and two specialists). Each specialist answers only the question it is handed and sees no conversation history, so the orchestrator rewrites follow-ups such as "break that down by territory" into self-contained questions.
- **Agent toolset:** one agent calls `sales_analyst` and `support_kb` in the same context and writes both parts itself.

## When to use which

| Use hub and spoke when | Use an agent toolset when |
|---|---|
| Each domain needs its own instructions, model, budget or owning team | One agent can hold all the tools and still choose well |
| There are enough tools that one context would choose badly | You want native charts and lower latency (one run, not two or three) |
| You want an explicit, auditable `NOT_ENTITLED` | The tools are owned centrally, and you will restate the behavior in one place |
| You accept maintaining bridge code, and losing everything but text at each hop | You accept that a missing grant leaves no trace |

The lab's evaluation (notebook Section 5) uses five questions over two tools, so its scores are directional. The real limit of a toolset is how many tools one context can choose between, and this lab does not test that.
