# Speaker Notes: Cortex AI Gateway: Govern, Observe and Optimize Every LLM Call

## Account Context Summary

Scenario: a marketing analytics team runs a LangChain agent outside Snowflake. It reasons with GPT-5.4 and answers questions over campaign spend data and strategy documents. The platform team wants one governed inference path, full traces for every agent turn, and evidence-based tuning of prompts and models. The lab builds the data, the MCP tools, the gateway configuration, and a Streamlit Trace Analyzer that closes the loop from telemetry to a promoted config.

---

## Slide 1: Hero

**Talking Points:**
- Every account gets one AI Gateway object, `SNOWFLAKE`, with nothing to create.
- It speaks the two APIs every SDK already uses, and records every request in an event table inside your account.
- Today we go one step further: we use that telemetry to make the agent cheaper and faster, and prove quality held.

**Presenter Notes:**
- Cortex AI Gateway is in preview, in AWS commercial regions only. Confirm the audience's region before promising a hands-on.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway

---

## Slide 2: Why Teams Need an AI Gateway

**Talking Points:**
- Four pains: key sprawl, no visibility into multi-call agent turns, spend that can't be attributed or capped, and tuning by intuition.
- The gateway solves the first three directly. The fourth is what the optimization loop on slides 9-10 addresses.

**Presenter Notes:**
- Ask the audience how many places their teams store LLM provider keys today. It usually lands the point.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/inference

---

## Slide 3: Architecture

**Talking Points:**
- Two clients: an external LangChain agent, and the Trace Analyzer app running in Snowflake.
- Inference goes through the gateway. Data access goes through the MCP server, which exposes one governed Cortex Agent tool (Cortex Analyst + Cortex Search) and no raw SQL tool.
- Everything lands in `AGENT_TRACE_TABLE` and `AI_GATEWAY_USAGE_HISTORY`, which feed the optimization loop.

**Presenter Notes:**
- Both paths authenticate as the same Snowflake user (a PAT for the external agent), so RBAC governs tokens and tool calls alike.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/observability
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp

---

## Slide 4: What is Cortex AI Gateway?

**Talking Points:**
- It has three capabilities: inference, observability and cost management, all governed by two privileges.
- `USAGE` sends requests, and `MONITOR` reads traces and usage.

**Presenter Notes:**
- USAGE is granted to PUBLIC by default. Model access still requires the Cortex model RBAC (e.g. SNOWFLAKE.CORTEX_USER), so the gateway does not widen what a user can reach.
- A common confusion is the Cortex Inference REST endpoint (`/api/v2/cortex`). It accepts the same payloads but gets no gateway traces or attribution.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway

---

## Slide 5: One Endpoint, Two Standard APIs

**Talking Points:**
- Chat Completions covers non-Claude models; Messages covers Claude. Point an existing SDK's base URL at the gateway and send a PAT as a Bearer token.

**Presenter Notes:**
- Gotchas we hit building the lab: underscores in the account host break TLS (use hyphens). GPT-5 models reject `max_tokens` (use `max_completion_tokens`), and only gpt-5.4 accepts a custom temperature. Claude on `/chat/completions` returns a 400.
- Which models are available depends on the account and cross-region settings. Check with a quick call, or `DESCRIBE AI GATEWAY SNOWFLAKE`.
- PATs are subject to network and authentication policies; check `PAT_POLICY` if calls return 401.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/inference
- https://docs.snowflake.com/en/user-guide/programmatic-access-tokens

---

## Slide 6: Snowflake as the Tool Provider (MCP)

**Talking Points:**
- A Snowflake-managed MCP server is a first-class object. Here it exposes one tool: the Cortex Agent `MARKETING_AGENT`, which orchestrates Analyst (it generates and runs the SQL itself) and Search.
- There is deliberately no raw SQL tool. Exposed directly, Analyst only returns SQL text, and adding `SYSTEM_EXECUTE_SQL` would let the client run any SQL and bypass the semantic view. Snowflake recommends the agent as the single client-facing tool.
- Any MCP client connects over streamable HTTP.

**Presenter Notes:**
- Tools run as the calling role, so the semantic view, search service and warehouse grants control what the agent can see.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp

---

## Slide 7: LangChain Agent in Action

**Talking Points:**
- One question becomes two gateway calls: one to pick the tool, one to write the answer from the agent's result. In our live run, "ROAS by channel for Q4 2024 and how to improve Display" took 2 gateway calls in about 46 seconds, most of it inside the agent.
- Sending the same `traceparent` header on every call in the turn is what turns those calls into one trace.

**Presenter Notes:**
- `lab/live_agent.py` is the CLI version of this agent for a live demo. It prints the trace_id to search for.

**References:**
- https://www.w3.org/TR/trace-context/#traceparent-header

---

## Slide 8: Every Call is Traced

**Talking Points:**
- Each span is one row with standard OpenTelemetry attributes: model, tokens, status, duration and HTTP code.
- Three grouping levels: conversation via a header, trace via traceparent, and span.

**Presenter Notes:**
- Payload capture is opt-in and makes the trace table sensitive, so recommend scoping MONITOR tightly. Records are capped at 1 MB; larger ones are truncated in the middle.
- Trace ingestion and storage are billed like other telemetry.
- The Snowsight page AI & ML > Cortex AI Gateway shows the same data without SQL.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/observability

---

## Slide 9: From Telemetry to a Better Agent

**Talking Points:**
- The loop is Observe, Diagnose, Experiment, Compare, Promote. Each step is a page in the Trace Analyzer app.
- The Advisor turns telemetry patterns into a concrete proposed change. "Test this fix" seeds an experiment with that change.

**Presenter Notes:**
- The eval set (`EVAL_PROMPTS`) has 15 questions: metrics with expected values computed from CAMPAIGN_SPEND, plus knowledge and definition questions.
- The judge is AI_COMPLETE with claude-sonnet-4-5 returning a 0-1 score. It is directional, not a benchmark, so say so.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_complete

---

## Slide 10: Before / After: Proving the Fix

**Talking Points:**
- Each lever maps to a telemetry signal, a candidate change and a metric.
- Promotion produces three artifacts: client settings, a pinned gateway allowlist, and a per-user quota.

**Presenter Notes:**
- The app only displays the ALTER AI GATEWAY and quota SQL; it does not run them. They need ACCOUNTADMIN or quota privileges, and replacing the gateway spec affects the whole account.

**References:**
- https://docs.snowflake.com/en/user-guide/budgets/per-user-quotas

---

## Slide 11: Live Demo: One Prompt, Three Views

**Talking Points:**
- Send a prompt, find it in Snowsight, then find it in the app. Same trace_id everywhere.

**Presenter Notes:**
- Traces usually appear within 20-40 seconds of the call.
- Run the traced live prompt from a laptop with a PAT. The app's Experiments page uses the container session token: the gateway serves it, but those calls were not traced in testing. A PAT from inside the container is blocked if the account's network policy doesn't allow the container's egress IP (HTTP 401, INCOMING_REQUEST_BLOCKED).
- See `demo_script.md` for the full run-of-show.

**References:**
- https://docs.snowflake.com/en/developer-guide/streamlit/app-development/secrets-and-configuration

---

## Slide 12: Admin Controls

**Talking Points:**
- The spec controls which models are exposed and what is logged. Grants control who can call and who can watch. Quotas cap spend per user with automatic blocking.

**Presenter Notes:**
- `FROM SPECIFICATION` replaces the whole spec, so always start from `DESCRIBE AI GATEWAY` output.
- Quota block enforcement is evaluated within minutes, not at request time, so a user can briefly overshoot. Size limits accordingly.
- Creating quotas needs SNOWFLAKE.QUOTA_CREATOR plus CREATE SNOWFLAKE.CORE.QUOTA on the schema. Budgets need SNOWFLAKE.BUDGET_CREATOR.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway
- https://docs.snowflake.com/en/user-guide/budgets/per-user-quotas

---

## Slide 13: When to Use What

**Talking Points:**
- Use the AI Gateway when the agent lives outside Snowflake and you need governance and telemetry.
- Use an MCP server to give any agent governed Snowflake tools.
- Use Cortex Agents when you want Snowflake to host the orchestration and front end.

**Presenter Notes:**
- These combine: a Cortex Agent can be one consumer of the same data while external agents use the gateway plus MCP.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents

---

## Slide 14: Next Steps

**Talking Points:**
- Turn on logging, point one agent at the gateway, run one optimization loop, then add guardrails.

**Presenter Notes:**
- Offer to run the lab in the customer's account: `lab/setup.sql`, then the notebook, then deploy the app.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/cost-management
