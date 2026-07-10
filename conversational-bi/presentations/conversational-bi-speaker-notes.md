# Speaker Notes: Conversational BI — Semantic Views + Cortex Analyst + Agent

## Account Context Summary

Generic field-enablement scenario (synthetic, brand-free): a B2C + B2B home-valuation /
proptech company with two new data leaders who inherited scattered, inconsistent metric
definitions (churn, revenue, customer count, highly-engaged customers). They want one
governed source of truth in the warehouse and self-serve analytics for business users. This
module builds a semantic view, exposes it via Cortex Analyst, and wraps it in a Cortex Agent
that also searches the CX chat telemetry produced by the "AI Functions" module. Sigma is their
BI layer and they use desktop assistants + MCP, so the extensibility story matters.

---

## Slide 1: Overview

**Talking Points:**
- Lead with the outcome: one governed definition of churn/revenue/engagement, queried in natural language, and combined with customer conversations by an agent.
- The four stats frame the arc: single source of truth, governed NL→SQL, structured+text together, business-user self-serve.

**Internal Context:**
- Audience is SEs/field working with a new BI + data-eng team. Their explicit ask was "centralize business logic in the warehouse" — this module is the direct answer.
- This module consumes Module A's output; if you demoed AI Functions first, call back to it.

**References:**
- https://docs.snowflake.com/en/user-guide/views-semantic/overview

---

## Slide 2: The Problem

**Talking Points:**
- Walk the four cards: diverging definitions, a new team with no ground truth, BI that can't self-serve, and structured metrics divorced from unstructured "why."
- Land the cost: inconsistent metrics erode trust in every downstream dashboard.

**Internal Context:**
- This mirrors the real discovery: churn defined differently across a billing platform, reverse-ETL feeds, and Sigma. Let them tell their version.

**References:**
- https://docs.snowflake.com/en/user-guide/views-semantic/overview

---

## Slide 3: Architecture

**Talking Points:**
- Orient the room before the deep-dive: two inputs (structured tables in ANALYTICS, unstructured chat in AI_FUNCTIONS.CHAT_THREADS) feed two governed objects — the CX_ANALYTICS_SV semantic view and the CHAT_SEARCH Cortex Search service.
- Those become two agent tools (Cortex Analyst for text-to-SQL, Cortex Search for retrieval), and CX_INTELLIGENCE_AGENT orchestrates both behind Snowflake Intelligence.
- The payoff: one natural-language question can join a churn metric to the support chats that explain it.

**Internal Context:**
- This is the "one semantic layer, two retrieval paths, one agent" pattern — reuse it as the mental model for the rest of the deck; every later slide fills in one box of this diagram.
- CHAT_SEARCH reads Module A's CHAT_THREADS, so note the cross-module dependency here rather than surprising them on the Cortex Search slide.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents
- https://docs.snowflake.com/en/user-guide/views-semantic/overview

---

## Slide 4: Why Semantic Views

**Talking Points:**
- Define the business once; every tool inherits it. Governed definitions (RBAC, sharing) in one schema object, and it's tool-agnostic — Analyst, agents, and Sigma all read the same view.
- This is the slide the customer explicitly asked for ("why use a semantic view").

**Internal Context:**
- Contrast with stage-based YAML semantic models: semantic views are native schema objects with RBAC/sharing/catalog support and support derived metrics + access modifiers.
- Emphasize the "contract" framing — it resonates with a team trying to establish ground truth.

**References:**
- https://docs.snowflake.com/en/user-guide/views-semantic/overview
- https://docs.snowflake.com/en/user-guide/views-semantic/yaml-vs-ddl

---

## Slide 5: Build the View

**Talking Points:**
- Walk the clauses: TABLES (with PRIMARY KEY), RELATIONSHIPS, FACTS, METRICS. Relationship types are inferred — no join_type needed.
- `churn_rate` is a derived metric: a scalar expression of two other metrics, defined once.

**Internal Context:**
- Derived metrics can use scalar expressions of metrics or aggregations of facts/dimensions — but not aggregations of other metrics, and not raw physical columns. That's why churn_rate uses the two metrics via DIV0, not raw COUNT/SUM of columns.
- The full lab view has more tables (engagement, valuations) and dimensions; the deck trims it for readability.

**References:**
- https://docs.snowflake.com/en/sql-reference/sql/create-semantic-view
- https://docs.snowflake.com/en/user-guide/views-semantic/sql

---

## Slide 6: Query the View

**Talking Points:**
- `SELECT ... FROM SEMANTIC_VIEW(view METRICS ... DIMENSIONS ...)` — pick metrics and dimensions; joins and metric logic are already defined.
- Analysts never touch the physical schema, so churn means one thing everywhere.

**Internal Context:**
- Note the special SEMANTIC_VIEW() table function syntax — it's not a plain SELECT of columns. Good place to demo live if you have the lab loaded.

**References:**
- https://docs.snowflake.com/en/sql-reference/constructs/semantic_view

---

## Slide 7: Cortex Analyst

**Talking Points:**
- Point Cortex Analyst at the semantic view; business users ask in natural language and get governed SQL.
- Verified queries defined in the view improve accuracy and double as onboarding suggestions.

**Internal Context:**
- Key governance point: because Analyst reads the semantic view, it can't invent its own churn definition — it inherits yours. That's the trust story for a BI team.
- When Analyst is invoked via an agent, it uses a managed set of models (not open-source LLMs).

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst

---

## Slide 8: Cortex Search

**Talking Points:**
- Create a Cortex Search service over the chat threads from the AI Functions module — this indexes the unstructured side.
- This is the explicit bridge between the two modules: the same threads scored for sentiment are now searchable.

**Internal Context:**
- The service reads FIELD_CX_DEMO.AI_FUNCTIONS.CHAT_THREADS, so Module A must be set up first for this piece. If it isn't, the semantic view + Analyst still work standalone.
- Search runs with owner's rights — mention the security implication if asked about row access.

**References:**
- https://docs.snowflake.com/en/sql-reference/sql/create-cortex-search
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-agents

---

## Slide 9: The Agent

**Talking Points:**
- The agent has two tools: Cortex Analyst over the semantic view (structured) and Cortex Search over chat telemetry (unstructured).
- Ask "Which churn-risk customers had negative support chats last month?" — the agent routes to both and returns one answer.

**Internal Context:**
- Orchestration instructions in the spec tell the agent when to use Analyst vs Search — walk that part of the YAML.
- Recommend `orchestration: auto` for model selection; note cross-region inference may be needed for some models.

**References:**
- https://docs.snowflake.com/en/sql-reference/sql/create-agent
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-manage

---

## Slide 10: Extensions & MCP

**Talking Points:**
- Extend with custom tools (stored procs/UDFs, type `generic`) for actions like opening a save-motion task; the built-in `data_to_chart` tool visualizes results; MCP connectors reach external systems like Jira/Salesforce.
- The same governed view backs Sigma and desktop assistants — one definition, many surfaces.

**Internal Context:**
- This maps directly to the customer's stack (Sigma as viz, desktop assistants, MCP). Position the semantic view as the shared foundation under all of it.
- Custom tools need USAGE grants; agents honor owner's vs caller's rights on procedures.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-manage

---

## Slide 11: When to Use What

**Talking Points:**
- Use the table to route: metric questions → Analyst; conversation questions → Search; combined → the agent; actions → custom tool / MCP.
- Everything plugs into the semantic view.

**Internal Context:**
- If asked "why not just Analyst?": Analyst answers structured questions; the agent adds unstructured retrieval and multi-step orchestration across tools.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents

---

## Slide 12: Next Steps

**Talking Points:**
- Four actions: run the lab, model real metrics into one semantic view, wire up Analyst for self-serve, and ship the agent into Snowsight/Sigma/MCP.
- Close on the one-liner: define the business once, and let every tool speak the same language.

**Internal Context:**
- Leave-behind pairs with the AI Functions module for a full CX-intelligence story (telemetry → governed analytics → conversational agent).

**References:**
- https://docs.snowflake.com/en/user-guide/views-semantic/overview
