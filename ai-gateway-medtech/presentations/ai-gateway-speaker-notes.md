# Speaker Notes: Cortex AI Gateway: The Central AI Control Plane

## Account Context Summary

Prepared for a large medical device manufacturer that runs on AWS, uses Glean for enterprise search and Microsoft 365 / Teams for collaboration.

Scenario: a field sales assistant for a global medical device manufacturer. A LangChain agent outside Snowflake reasons with GPT-5.4 through Cortex AI Gateway and calls a governed Cortex Agent over MCP. The agent answers over sales performance, account health and a field document library, including share-loss risk scored by an XGBoost model in the Snowflake Model Registry. CoCo Desktop reaches the same agent, plus Glean, through Gateway Tools. The platform team wants one governed path for models and tools, full traces for every turn, and evidence-based tuning of prompts and models, with the optimizer itself governed and costed. The lab builds the data, the agent and MCP server, the gateway and Tools configuration, and a Streamlit Trace Analyzer that closes the loop from telemetry to a promoted config.

---

## Slide 1: Snowflake as the Central AI Control Plane

**Talking Points:**
- Part 2 of 2. Many AI clients run outside Snowflake: LangChain agents, CoCo Desktop, enterprise search in Glean. Rather than govern each one, govern what they all need: data and tools (MCP and Gateway Tools) and models (Cortex AI Gateway).
- Every LLM call, including the optimizer's own calls, goes through one endpoint, is traced in your account, and is attributed and capped per user.

**Presenter Notes:**
- Cortex AI Gateway and Gateway Tools are in preview, in AWS commercial regions only. Confirm the audience's region before promising a hands-on.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/tools

---

## Slide 2: The Agent We Are Governing

**Talking Points:**
- A one-slide recap of Part 1: MEDTECH_SALES_AGENT routes each question to sales_performance_analyst, account_health_analyst (including model share-loss scores) or product_knowledge_search, and runs the generated SQL under RBAC.
- Its instructions keep answers on-label, with no clinical superiority claims and no patient data. That governance travels with the agent wherever it is called from.

**Presenter Notes:**
- If the audience saw Part 1, keep this to 30 seconds. If not, this slide is enough context for the rest of the deck; the full build is in the agent deck linked on the slide.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents

---

## Slide 3: Why External Agents Need a Control Plane

**Talking Points:**
- Four pains: key sprawl, no visibility into multi-call agent turns, spend that can't be attributed or capped, and tuning by intuition.
- The gateway solves the first three directly. The fourth is what the optimization loop addresses.

**Presenter Notes:**
- Ask the audience how many places their teams store LLM provider keys today. It usually lands the point.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/inference

---

## Slide 4: The Control Plane Architecture

**Talking Points:**
- Three clients. The LangChain agent sends inference through the gateway and calls MEDTECH_MCP directly. CoCo Desktop reaches Glean (a custom server) and the Snowflake server (pointed at MEDTECH_MCP) through Gateway Tools. The Trace Analyzer's optimizer sends its own LLM calls through the gateway.
- MEDTECH_MCP exposes one governed Cortex Agent tool (two Analyst tools, product knowledge search, share-loss scores) and no raw SQL tool.
- Everything lands in `AGENT_TRACE_TABLE` and `AI_GATEWAY_USAGE_HISTORY`, which feed the optimization loop.

**Presenter Notes:**
- Every path authenticates as a Snowflake user (a PAT for the external agent, per-user OAuth for Tools), so RBAC governs tokens and tool calls alike.
- The deck doesn't claim which models CoCo Desktop uses for its own reasoning; this demo only shows its Tools path.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/observability
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/tools
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp

---

## Slide 5: Publishing the Agent to Any Client (MCP)

**Talking Points:**
- A Snowflake-managed MCP server is a first-class object. Here it exposes one tool: the Cortex Agent `MEDTECH_SALES_AGENT`, which orchestrates two Analyst tools (each generates and runs its SQL itself), a Cortex Search tool and a chart tool.
- There is deliberately no raw SQL tool. Exposed directly, Analyst only returns SQL text, and adding `SYSTEM_EXECUTE_SQL` would let the client run any SQL and bypass the semantic views. Snowflake recommends the agent as the single client-facing tool.
- Any MCP client connects over streamable HTTP.
- Two layers of orchestration: the external agent decides whether to ask Snowflake; the Cortex Agent decides how to answer. The gateway traces the first; agent monitoring covers the second.

**Presenter Notes:**
- Tools run as the calling role, so the semantic view, search service and warehouse grants control what the agent can see.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp

---

## Slide 6: Gateway Tools: Governed Enterprise Search with Glean

**Talking Points:**
- Gateway Tools connects AI clients (CoCo Desktop and CLI, Claude, Cursor) to business tools over MCP. It's in Public Preview as of October 19, 2026, in AWS commercial regions.
- The admin (ACCOUNTADMIN) enables servers in Snowsight under AI & ML > AI Gateway > MCP & Tools. Glean isn't in the catalog, so it's added as a custom server: the URL must end in `/mcp`, with OAuth. The catalog Snowflake server is pointed at MEDTECH_MCP.
- Tool policies: the admin restricts which tools a server exposes. Here Glean exposes only read-only tools: search, read_document and chat.
- Grant `SNOWFLAKE$OPS.MCP$USER` and CoCo discovers the servers automatically. Each user completes their own OAuth.
- One CoCo Desktop prompt combines enterprise knowledge from Glean with governed account numbers from the Snowflake agent. Tool-call activity lands in `AGENT_TRACE_TABLE` and on the Tools Activity page.

**Presenter Notes:**
- A Microsoft Teams MCP server is in the Tools catalog as Private Preview. Mention it as optional; don't demo or promise it.
- Use the vetted prompts from `demo_script.md`. If the Glean tenant has no consignment guidance, switch to one of the Glean-only alternatives listed there.
- Get the Glean server URL from Glean's MCP configurator.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/tools
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/tools/admin-custom-apps
- https://developers.glean.com/guides/mcp

---

## Slide 7: What is Cortex AI Gateway?

**Talking Points:**
- It provides inference, observability and cost management, governed by two privileges.
- `USAGE` sends requests, and `MONITOR` reads traces and usage.

**Presenter Notes:**
- USAGE is granted to PUBLIC by default. Model access still requires the Cortex model RBAC (e.g. SNOWFLAKE.CORTEX_USER), so the gateway does not widen what a user can reach.
- A common confusion is the Cortex Inference REST endpoint (`/api/v2/cortex`). It accepts the same payloads but gets no gateway traces or attribution.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway

---

## Slide 8: One Endpoint, Two Standard APIs

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

## Slide 9: LangChain Agent in Action

**Talking Points:**
- One field question ("Which Northeast accounts are at risk, and what does our evidence say?") becomes two gateway calls: one to pick the tool, one to write the answer from the agent's result. Most of the turn's time is spent inside the agent, running the Analyst SQL and the knowledge search.
- Sending the same `traceparent` header on every call in the turn is what turns those calls into one trace.

**Presenter Notes:**
- `./demo.sh ask "..."` (or `lab/live_agent.py`) is the CLI version of this agent for a live demo. It prints the trace_id to search for.
- Point out the guardrails in the answer: on-label evidence only, and no superiority claim against the competitor.

**References:**
- https://www.w3.org/TR/trace-context/#traceparent-header

---

## Slide 10: Every Call is Traced

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

## Slide 11: From Telemetry to a Better Agent

**Talking Points:**
- The loop: Observe, Diagnose, Optimize, Judge, Decide, Route, Promote. Each step is a page or panel in the Trace Analyzer app.
- AI diagnosis: claude-sonnet-4-5 reads a per-user, per-model telemetry profile plus sampled captured payloads and returns findings with a root cause, evidence span ids and one testable config change. "Test this fix" seeds an experiment, just like the rule findings.
- Prompt optimizer (OPRO/APE-style): proposes candidate system prompts from the weakest answers and the judge's rationales, selects on a dev split, and confirms against the baseline on held-out prompts.
- Rubric judge: correctness 0.5, completeness 0.2, conciseness 0.1, compliance 0.2 (on-label, no superiority claims, no patient data), returned as JSON with a rationale. An optional second judge from another provider (openai-gpt-5.4) reports an agreement score.

**Presenter Notes:**
- The eval set (`EVAL_PROMPTS`) has 20 prompts across 7 intents: sales metric, account health, share loss, labeling, evidence, policy and definition. Numeric expectations are computed in SQL from the current data (a view, so they track SHARE_LOSS_PREDICTIONS after the model runs).
- The judge is directional, not a benchmark, so say so.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_complete

---

## Slide 12: Before / After: Proving the Fix

**Talking Points:**
- Each lever maps to a telemetry signal, a candidate change and a metric, including weak answers (prompt optimizer) and one-model-for-everything (route by intent).
- Promote on cost, gated on statistics: a paired bootstrap 95% CI on the quality delta. The candidate ships only if the CI lower bound is above -0.05 and it is cheaper. "We promote on the lower bound of the interval, not on a lucky average."
- Route by intent picks the cheapest model within 0.05 of the best quality for each intent and produces a client routing table.
- Promotion produces four artifacts: client settings, the routing table, a pinned gateway allowlist, and a per-user quota.

**Presenter Notes:**
- Credits per request use per-model rates fitted from this account's AI_GATEWAY_USAGE_HISTORY (credits against input and output tokens).
- The app only displays the ALTER AI GATEWAY and quota SQL; it does not run them. They need ACCOUNTADMIN or quota privileges, and replacing the gateway spec affects the whole account.
- Quote results from your own run on the day; don't reuse numbers from another account.

**References:**
- https://docs.snowflake.com/en/user-guide/budgets/per-user-quotas

---

## Slide 13: The Optimizer Runs Through the Gateway Too

**Talking Points:**
- Every LLM call the optimizer makes (diagnose, propose, judge) goes through the Cortex AI Gateway endpoint. It is governed, traced and costed like any other AI client.
- Traced: each call has its own traceparent and a conversation id `optimizer-<role>-<run>`, is logged to `OPTIMIZER_CALLS`, and shows up in `AGENT_TRACE_TABLE` with its captured payload. Open a judge span to show the rubric prompt and the JSON verdict.
- Costed: the Cost of optimization panel shows the experiment's credits and the payback in days.
- "We ship the evidence, and the evidence has a receipt."

**Presenter Notes:**
- In the Trace explorer, the "Optimizer traces only" filter isolates these spans.
- The optimizer's calls count against the same allowlist and the calling user's quota, so size quotas for whoever runs experiments.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/observability
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway

---

## Slide 14: Governing Spend: Attribute, Cap, Enforce

**Talking Points:**
- Attribute: every gateway request is billed to the calling user; a COST_CENTER tag on users gives chargeback by team.
- Cap: budgets for team spend, per-user quotas for individual limits (daily, weekly, monthly) on the AI GATEWAY domain.
- Enforce: at the limit the platform denies the user's next request with HTTP 403 and tells them when access returns.

**Presenter Notes:**
- Enforcement is evaluated within minutes of the spend, so a user can overshoot. Size limits with headroom.
- Blocks clear at the cycle reset (00:00 UTC for daily) or about 5-10 minutes after the limit is raised.
- One quota applies one limit to all its users. For tiers, tag users (for example QUOTA_TIER) and scope each quota with INTERSECTION.
- Quota limits are whole credits; 1 credit per day is the smallest. The lab uses three tiers: FIELD 5/day, ANALYST 15/day, PLATFORM 40/day and 150/week.
- A block covers every AI domain the user touches, not just the gateway, so don't demo it on your own user.
- Creating quotas needs SNOWFLAKE.QUOTA_CREATOR plus CREATE SNOWFLAKE.CORE.QUOTA on the schema. Budgets need SNOWFLAKE.BUDGET_CREATOR.

**References:**
- https://docs.snowflake.com/en/user-guide/budgets/per-user-quotas
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/cost-management

---

## Slide 15: Admin Controls

**Talking Points:**
- The spec controls which models are exposed and what is logged. Grants control who can call and who can watch. Spend controls are covered in Governing Spend; Tools servers and policies are administered in Snowsight by ACCOUNTADMIN.

**Presenter Notes:**
- `FROM SPECIFICATION` replaces the whole spec, so always start from `DESCRIBE AI GATEWAY` output.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/tools
- https://docs.snowflake.com/en/user-guide/budgets/per-user-quotas

---

## Slide 16: Live Demo: One Field Question, Every View

**Talking Points:**
- Ask a share-loss and clinical evidence question from the LangChain agent, then run one CoCo Desktop prompt that combines the Snowflake agent with Glean.
- Find the same trace in Snowsight and in the Trace Analyzer. Same trace_id everywhere.
- Close the loop: AI diagnosis, an experiment with the rubric judge and confidence interval, route by intent, and the Cost of optimization receipt.
- Then show the same traffic as spend: cost centers, a user over quota, and the platform's block.

**Presenter Notes:**
- Traces usually appear within 20-40 seconds of the call.
- Run the Trace Analyzer from a laptop with a PAT (`streamlit run`): that's where Live prompt and Experiments calls are traced. Inside Snowflake, the container session token is served but not traced in testing, and a PAT from the container is rejected by account network policies (HTTP 401, INCOMING_REQUEST_BLOCKED).
- At least 30 minutes before presenting, run `./demo.sh traffic` (the commercial personas) and `./demo.sh burst` (the territory-planning batch agent runs away until its FIELD quota blocks it; about 6 credits, 20 minutes). The block lasts until 00:00 UTC.
- Complete your own Glean OAuth in CoCo Desktop before the session.
- See `demo_script.md` for the full run-of-show.

**References:**
- https://docs.snowflake.com/en/developer-guide/streamlit/app-development/secrets-and-configuration
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/tools

---

## Slide 17: When to Use What

**Talking Points:**
- Use the AI Gateway when the agent lives outside Snowflake and you need governance and telemetry.
- Use an MCP server to give any agent governed Snowflake tools.
- Use Gateway Tools to connect AI clients to business tools like Glean, with admin tool policies and per-user OAuth.
- Use Cortex Agents when you want Snowflake to host the orchestration and front end.

**Presenter Notes:**
- These combine: a Cortex Agent can be one consumer of the same data while external clients use the gateway, MCP and Tools.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/tools

---

## Slide 18: Next Steps

**Talking Points:**
- Turn on logging and point one agent at the gateway.
- Point Tools at your Glean tenant: a custom server with OAuth, read-only tools, MCP$USER for a pilot field team.
- Connect your semantic layer and publish the agent over MCP.
- Run the optimizer on your own eval set, then add guardrails.

**Presenter Notes:**
- Offer to run the lab in the customer's account: `lab/setup.sql`, then the notebook, then `lab/tools_setup.sql` and the Tools UI steps, then deploy the app.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/tools/admin-custom-apps
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/cost-management
