# Speaker Notes: Cortex AI Gateway for Retail Analytics: Govern, Observe and Optimize Every LLM Call

## Account Context Summary

Scenario: an athletic apparel retailer's analytics team runs a LangChain agent outside Snowflake. It reasons with GPT-5.4 and answers questions over sales, product, store, customer and campaign data, including churn risk scored by an XGBoost model in the Snowflake Model Registry. The platform team wants one governed inference path, full traces for every agent turn, and evidence-based tuning of prompts and models. The lab builds the data, the MCP tools, the gateway configuration, and a Streamlit Trace Analyzer that closes the loop from telemetry to a promoted config.

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
- Inference goes through the gateway. Data access goes through the MCP server, which exposes one governed Cortex Agent tool (two Cortex Analyst tools: customer + churn, executive KPIs) and no raw SQL tool.
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
- A Snowflake-managed MCP server is a first-class object. Here it exposes one tool: the Cortex Agent `RETAIL_ANALYTICS_AGENT`, which orchestrates two Analyst tools (each generates and runs its SQL itself): `customer_interactions_analyst` and `business_kpi_analyst`.
- There is deliberately no raw SQL tool. Exposed directly, Analyst only returns SQL text, and adding `SYSTEM_EXECUTE_SQL` would let the client run any SQL and bypass the semantic views. Snowflake recommends the agent as the single client-facing tool.
- Any MCP client connects over streamable HTTP.

**Presenter Notes:**
- Tools run as the calling role, so the semantic view and warehouse grants control what the agent can see.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp

---

## Slide 7: LangChain Agent in Action

**Talking Points:**
- One question becomes two gateway calls: one to pick the tool, one to write the answer from the agent's result. Most of the turn's time is spent inside the agent, running the Analyst SQL.
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
- The eval set (`EVAL_PROMPTS`) has 15 questions: retail metrics and churn-model questions whose expected values are computed in SQL from the current data (a view, so they track CHURN_PREDICTIONS after the model runs), plus definition questions.
- The judge is AI_COMPLETE with claude-sonnet-4-5 returning a 0-1 score. It is directional, not a benchmark, so say so.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_complete

---

## Slide 10: Before / After: Proving the Fix

**Talking Points:**
- Each lever maps to a telemetry signal, a candidate change and a metric.
- Promote on cost, gated on quality: in our validation run the candidate held 0.98 judge quality at 76% fewer credits per request.
- Promotion produces three artifacts: client settings, a pinned gateway allowlist, and a per-user quota.

**Presenter Notes:**
- Credits per request use per-model rates fitted from this account's AI_GATEWAY_USAGE_HISTORY (credits against input and output tokens). In testing the fit matched billed credits within about 1%.
- The app only displays the ALTER AI GATEWAY and quota SQL; it does not run them. They need ACCOUNTADMIN or quota privileges, and replacing the gateway spec affects the whole account.

**References:**
- https://docs.snowflake.com/en/user-guide/budgets/per-user-quotas

---

## Slide 11: Governing Spend: Attribute, Cap, Enforce

**Talking Points:**
- Attribute: every gateway request is billed to the calling user; a COST_CENTER tag on users gives chargeback by team.
- Cap: budgets for team spend, per-user quotas for individual limits (daily, weekly, monthly) on the AI GATEWAY domain.
- Enforce: at the limit the platform denies the user's next request with HTTP 403 and tells them when access returns.

**Presenter Notes:**
- Enforcement is evaluated within minutes of the spend, so a user can overshoot. In testing, the block landed at 1.07 credits on a 1-credit daily limit, and in-flight calls took the user to about 1.46.
- Blocks clear at the cycle reset (00:00 UTC for daily) or about 5-10 minutes after the limit is raised.
- One quota applies one limit to all its users. For tiers, tag users (for example QUOTA_TIER) and scope each quota with INTERSECTION.
- Quota limits are whole credits; 1 credit per day is the smallest.
- A block covers every AI domain the user touches, not just the gateway, so don't demo it on your own user.
- Creating quotas needs SNOWFLAKE.QUOTA_CREATOR plus CREATE SNOWFLAKE.CORE.QUOTA on the schema. Budgets need SNOWFLAKE.BUDGET_CREATOR.

**References:**
- https://docs.snowflake.com/en/user-guide/budgets/per-user-quotas
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/cost-management

---

## Slide 12: Live Demo: One Prompt, Four Views

**Talking Points:**
- Send a prompt, find it in Snowsight, then find it in the app. Same trace_id everywhere.
- Then show the same traffic as spend: cost centers, a user over quota, and the platform's block.

**Presenter Notes:**
- Traces usually appear within 20-40 seconds of the call.
- Run the Trace Analyzer from a laptop with a PAT (`streamlit run`): that's where Live prompt and Experiments calls are traced. Inside Snowflake, the container session token is served but not traced in testing, and a PAT from the container is rejected by account network policies (HTTP 401, INCOMING_REQUEST_BLOCKED).
- Block the cost demo user at least 10 minutes before presenting: `python lab/generate_traffic.py --burst`.
- See `demo_script.md` for the full run-of-show.

**References:**
- https://docs.snowflake.com/en/developer-guide/streamlit/app-development/secrets-and-configuration

---

## Slide 13: Admin Controls

**Talking Points:**
- The spec controls which models are exposed and what is logged. Grants control who can call and who can watch. Spend controls are covered in Governing Spend.

**Presenter Notes:**
- `FROM SPECIFICATION` replaces the whole spec, so always start from `DESCRIBE AI GATEWAY` output.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway
- https://docs.snowflake.com/en/user-guide/budgets/per-user-quotas

---

## Slide 14: When to Use What

**Talking Points:**
- Use the AI Gateway when the agent lives outside Snowflake and you need governance and telemetry.
- Use an MCP server to give any agent governed Snowflake tools.
- Use Cortex Agents when you want Snowflake to host the orchestration and front end.

**Presenter Notes:**
- These combine: a Cortex Agent can be one consumer of the same data while external agents use the gateway plus MCP.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents

---

## Slide 15: Next Steps

**Talking Points:**
- Turn on logging, point one agent at the gateway, run one optimization loop, then add guardrails.

**Presenter Notes:**
- Offer to run the lab in the customer's account: `lab/setup.sql`, then the notebook, then deploy the app.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/cost-management
