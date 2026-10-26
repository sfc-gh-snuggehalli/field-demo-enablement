# Cortex AI Gateway for Medical Device Field Sales: Govern, Observe and Optimize Every AI Call

[Part 1: Build the Agent](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/ai-gateway-medtech/presentations/agent-build.html) | [Part 2: AI Gateway](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/ai-gateway-medtech/presentations/ai-gateway.html)

The two decks are linked: Part 1 ends with a hand-off to Part 2, and Part 2 opens with a one-slide recap of the agent, so it also stands alone.

Cortex AI Gateway gives agents, SDKs and AI clients one governed path to models and tools. It records every request as an OpenTelemetry span in your own account and attributes and caps spend per user. This module runs a LangChain agent through the gateway with a Snowflake MCP server that exposes one governed Cortex Agent for a global medical device manufacturer's field sales team: two Cortex Analyst tools (sales performance; account health and share-loss risk) and Cortex Search over product knowledge (IFU summaries, clinical evidence, battlecards, contract and compliance policy), with share-loss scores from an XGBoost model in the Snowflake Model Registry. **Gateway Tools** connects CoCo Desktop to Glean (enterprise search) and the same Snowflake MCP server. A Streamlit Trace Analyzer closes the loop: observe traces, diagnose problems with an LLM, replay an eval set with a candidate config, optimize the system prompt, compare with a rubric judge and confidence intervals, and promote the winner. Every LLM call the optimizer makes also goes through the gateway, so it is traced and costed like any other AI client.

## Audience

SEs, solution architects, platform engineers, and teams evaluating centralized AI governance and observability.

## Topics Covered

- **Gateway fundamentals**: auto-provisioned `SNOWFLAKE` gateway, Chat Completions and Messages APIs, model allowlist, logging and payload capture
- **LangChain + MCP**: `ChatOpenAI` pointed at the gateway; Snowflake MCP server exposing one governed tool, a Cortex Agent that runs two Cortex Analyst tools and a Cortex Search tool (no raw SQL tool)
- **Gateway Tools**: Glean as a custom MCP server (read-only tools) and the catalog Snowflake server, discovered automatically in CoCo Desktop; per-user OAuth; tool-call activity in `AGENT_TRACE_TABLE`
- **Governed ML**: train an XGBoost account share-loss model, log it to the Model Registry, batch-score in the warehouse with `mv.run()`, attach a Model Monitor; the agent answers from the new scores with no client change
- **Observability**: `AGENT_TRACE_TABLE('SNOWFLAKE')` spans, W3C `traceparent` grouping, conversation ids, Snowsight AI Gateway page
- **Optimization loop**: rule and AI-diagnosed findings -> eval-set experiments through the gateway -> rubric judge (correctness, completeness, conciseness, compliance) -> prompt optimizer with a dev/holdout split -> paired-bootstrap confidence interval -> route by intent -> promote. The optimizer's own LLM calls go through the gateway and are logged to `OPTIMIZER_CALLS`
- **Live prompt**: `lab/live_agent.py` sends one request that is visible in both Snowsight and the Trace Analyzer
- **Admin and cost controls**: spec management, USAGE vs MONITOR, `AI_GATEWAY_USAGE_HISTORY`, chargeback by cost-center tag, shared-resource budgets, per-user quotas with a live block on a demo user

## Contents

| File | Description |
|------|-------------|
| `presentations/agent-build.html` | Part 1 deck (8 slides): semantic views, Cortex Search, the share-loss model and the Cortex Agent, ending with a hand-off to Part 2 |
| `presentations/agent-build-speaker-notes.md` | Part 1 talking points, presenter notes, and references |
| `presentations/ai-gateway.html` | Part 2 deck (18 slides): agent recap, then MCP, Gateway Tools, Cortex AI Gateway, the optimizer and spend governance |
| `presentations/ai-gateway-speaker-notes.md` | Part 2 talking points, presenter notes, and references |
| `demo_script.md` | Live run-of-show for the demo |
| `demo.sh` | One script for setup, traffic, notebook, app, deploy and teardown |
| `pyproject.toml`, `uv.lock` | Local Python environment (lab, notebook with the share-loss model, app, Snowflake CLI), managed by uv |
| `lab/setup.sql` | Database, warehouse, medical device commercial data (fiscal year Oct 2025 - Sep 2026), product knowledge corpus + Cortex Search, two semantic views, share-loss predictions table, Cortex Agent, MCP server, gateway spec + grants, Tools OAuth client, eval/optimization/optimizer tables, app access |
| `lab/tools_setup.sql` | After enabling Tools in Snowsight: OAuth client id/secret for the Snowflake server entry, the `SNOWFLAKE$OPS.MCP$USER` grant, and a trace check |
| `lab/cleanup.sql` | Tear everything down to start fresh |
| `lab/ai-gateway-lab.ipynb` | Hands-on notebook: gateway + LangChain + MCP, share-loss model (registry, batch inference, monitor), observability, cost management |
| `lab/live_agent.py` | CLI: send one live prompt through the agent and print its trace_id |
| `lab/generate_traffic.py` | Generates varied traffic (multi-span, verbose, error) so the dashboards have data |
| `app/` | Trace Analyzer, a Streamlit in Snowflake app (container runtime) |

## Hands-On Lab

### Prerequisites

- AWS commercial region account (Cortex AI Gateway is in preview, AWS-only)
- ACCOUNTADMIN for setup (gateway spec, grants, integration); the lab objects are owned by SYSADMIN
- A programmatic access token (PAT) for the local notebook and scripts. `demo.sh setup` offers to create one. PATs follow your account's network and authentication policies.
- [uv](https://docs.astral.sh/uv/) (`brew install uv`). uv installs Python 3.11, the lab and ML dependencies and the Snowflake CLI into `.venv`.
- On macOS, `brew install libomp` for XGBoost
- A Snowflake CLI connection for your user (`snow connection add`, or any entry in `~/.snowflake/config.toml`)

### Quick start

```bash
./demo.sh setup        # prompts for a connection; creates the objects, PATs and .env, runs one live prompt
./demo.sh traffic      # background traces for the Trace Analyzer
./demo.sh notebook     # the lab notebook, with the .venv kernel and .env loaded
./demo.sh app          # Trace Analyzer at http://localhost:8501
./demo.sh burst        # before a demo: the batch agent runs away until its quota blocks it
./demo.sh pat          # reissue the demo PATs when they expire
./demo.sh teardown     # drop everything
```

`setup` is safe to re-run. Non-interactive: `./demo.sh setup -c <connection> -p <pat-file>`. It writes `.env` (connection, account, user, PAT file and expiry, gateway host); every other command loads it. The demo PATs last 7 days: commands that need one warn in its last day and stop once it has expired (unless you passed your own PAT with `-p`), and `./demo.sh pat` reissues them without rerunning setup (it rewrites `.env`). `./demo.sh ask "..."` sends one prompt and prints its trace_id; `./demo.sh deploy` deploys the app to Streamlit in Snowflake.

### Set up with Cortex Code

Open this repository in Cortex Code and paste:

```text
Set up the Cortex AI Gateway medical device lab in the ai-gateway-medtech folder on my Snowflake account.
1. If uv is not installed, ask me before installing it (brew install uv). On macOS,
   if setup warns that libomp is missing, ask me before running brew install libomp.
2. Run ./demo.sh --help, then ./demo.sh setup. Add </dev/null to every demo.sh command
   so it never waits for typed input. When it stops and names a flag (-c <connection>,
   -p <pat-file> or --create-pat), show me the options it printed (point out the
   connection marked is_default), ask me which to use, and re-run with that flag.
   If I have no Snowflake CLI connection, help me create one with snow connection add.
   The connection's user needs the ACCOUNTADMIN and SYSADMIN roles.
3. Judge progress by the lines starting with ==> or ERROR:. If it says "Using your PAT
   at ...", tell me which file. If it seems stuck on sign-in, tell me to finish the
   browser sign-in, then re-run the same command.
4. When setup prints Done, run ./demo.sh traffic (the ERR / HTTP 400 lines in its
   error scenarios are deliberate). Then start ./demo.sh app in the background and give
   me the Local URL (ignore Streamlit's watchdog install hint). Tell me how to open the
   notebook (./demo.sh notebook).
Do not run teardown, burst or deploy unless I ask.
```

### Manual setup

Without uv, install Python 3.11+ with `langchain-openai langchain-mcp-adapters langgraph snowflake-connector-python snowflake-snowpark-python snowflake-ml-python xgboost scikit-learn pandas streamlit requests`, and Snowflake CLI 3.14+. The commands below use `python3`, because macOS has no `python` command outside a virtual environment. If you have uv, use the [Quick start](#quick-start) instead: `./demo.sh ask "..."` replaces `python3 lab/live_agent.py "..."`.

1. Run the setup script with your account host (hyphens, not underscores; `SELECT LOWER(REPLACE(CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME(), '_', '-')) || '.snowflakecomputing.com';` returns it):
   ```bash
   snow sql -f lab/setup.sql -D gateway_host=<org-account>.snowflakecomputing.com
   ```
   This creates `CORTEX_GATEWAY_MEDTECH_LAB` (13 medical device tables with deterministic synthetic data, the PRODUCT_KNOWLEDGE_DOCS corpus and PRODUCT_KNOWLEDGE_SEARCH service, SHARE_LOSS_PREDICTIONS seeded from the legacy score, semantic views SALES_PERFORMANCE_SV and ACCOUNT_HEALTH_SV, Cortex Agent MEDTECH_SALES_AGENT, MCP server MEDTECH_MCP, the EVAL_PROMPTS view, OPTIMIZATION_RUNS, OPTIMIZATION_RESULTS, OPTIMIZER_CALLS), the OAuth integration `GATEWAY_MEDTECH_TOOLS_OAUTH`, the warehouse `GATEWAY_MEDTECH_WH`, and the integration `GATEWAY_MEDTECH_APP_EAI`. It turns on gateway logging with client telemetry and payload capture, and grants SYSADMIN gateway MONITOR plus the usage, budget and quota roles. It also creates the commercial personas (seven service users in three roles) with their per-user quotas and the gateway budget; `./demo.sh setup` issues a PAT per persona, or run the commented `ALTER USER ... ADD PROGRAMMATIC ACCESS TOKEN` in section 9b for each one and save it to `~/.snowflake/gateway_medtech_<persona>.pat`. Create your own PAT too:
   ```sql
   ALTER USER <you> ADD PROGRAMMATIC ACCESS TOKEN ai_gateway_medtech ROLE_RESTRICTION = 'SYSADMIN' DAYS_TO_EXPIRY = 7;
   ```
2. Export credentials for the local tools:
   ```bash
   export SNOWFLAKE_ACCOUNT=<org-account> SNOWFLAKE_USER=<you>
   export SNOWFLAKE_PAT=<pat>          # or SNOWFLAKE_PAT_FILE=~/.snowflake/ai_gateway_medtech.pat
   ```
3. Generate background traffic: `python3 lab/generate_traffic.py`. Each scenario runs as the persona it fits, using that persona's PAT; a persona without a PAT file runs as you.
4. Run the notebook `lab/ai-gateway-lab.ipynb` top to bottom.
5. Run the app locally (use this for demos; see [Where to run the app](#where-to-run-the-app)):
   ```bash
   cd app
   SNOWFLAKE_DEFAULT_CONNECTION_NAME=<connection in ~/.snowflake/config.toml> \
   GATEWAY_HOST=<org-account>.snowflakecomputing.com \
   streamlit run streamlit_app.py
   ```
   Gateway calls use `SNOWFLAKE_PAT` or `SNOWFLAKE_PAT_FILE` (default `~/.snowflake/ai_gateway_medtech.pat`). Use dashes, not underscores, in the host.
6. Optional: deploy the app to Snowflake for read-only analysis: `cd app && snow streamlit deploy --replace`
7. Before a demo, make the territory-planning batch agent run away so Cost governance has a block to show:
   ```bash
   python3 lab/generate_traffic.py --burst   # uses ~/.snowflake/gateway_medtech_territory_planner.pat
   ```
   Section 9b of `setup.sql` creates a small commercial org as service users, each tagged with a `COST_CENTER` (chargeback and budget scope) and a `QUOTA_TIER` (which quota applies):

   | User | Role | COST_CENTER | Quota (block enforcement on) |
   |---|---|---|---|
   | `GATEWAY_MEDTECH_REP_NORTHEAST`, `_REP_SOUTHEAST`, `_TM_WEST` | `GATEWAY_MEDTECH_FIELD_RL` | `FIELD_SALES` | `GATEWAY_MEDTECH_FIELD_QUOTA`: 5 credits/day, 60/month |
   | `GATEWAY_MEDTECH_TERRITORY_PLANNER` (scheduled batch agent) | `GATEWAY_MEDTECH_FIELD_RL` | `FIELD_SALES` | `GATEWAY_MEDTECH_FIELD_QUOTA` |
   | `GATEWAY_MEDTECH_SALES_OPS`, `_MARKET_ACCESS` | `GATEWAY_MEDTECH_ANALYST_RL` | `SALES_OPS`, `COMMERCIAL_ANALYTICS` | `GATEWAY_MEDTECH_ANALYST_QUOTA`: 15/day, 200/month |
   | `GATEWAY_MEDTECH_AI_PLATFORM` | `GATEWAY_MEDTECH_PLATFORM_RL` | `AI_PLATFORM` | `GATEWAY_MEDTECH_PLATFORM_QUOTA`: 40/day, 150/week |

   Each role has only USAGE on the AI Gateway. `GATEWAY_BUDGET` tracks all five cost centers (including the notebook's `ENGINEERING`) against 2,500 credits a month. The notebook's `GATEWAY_QUOTA` (10/day for everyone else) excludes the tiered users. The burst sends 16 long territory plans at a time as the batch agent until its estimated spend passes the 5-credit daily limit, then one small probe every 30 seconds until the gateway returns HTTP 403 ("exceeded the usage quota limit"). It saves that response to `app/output/last_quota_denial.json`. Expect about 6 credits and 20 minutes (measured: 6.07 credits, blocked on the first probe after 18 minutes). The block lasts until 00:00 UTC, and the reps in the same tier keep working because the limit is per user. Keep real users out of the tier quotas: a block covers every AI domain the user touches.

### Lab Sections

1. Install dependencies
2. Configuration (PAT, gateway endpoint)
3. Gateway LLM with `traceparent`
4. MCP tools over streamable HTTP
5. LangChain ReAct agent
6. Queries: revenue and quota (sales_performance_analyst), share-loss risk by region (account_health_analyst), competitor conversions plus clinical evidence and battlecard guidance (account_health_analyst + product_knowledge_search)
7. Share-loss model: feature view of H1 signals (as of 2026-03-31), XGBoost vs the legacy rule of thumb, Model Registry, `mv.run()` batch inference into SHARE_LOSS_PREDICTIONS, Model Monitor, then the risk question again through the gateway
8. Observability: recent traces, credit usage, single-trace drill-down, conversation reconstruction
9. Cost management: spend by user, shared-resource budget, per-user quota

### Gateway Tools: Glean and Snowflake MCP in CoCo Desktop

Tools (AI & ML > AI Gateway > MCP & Tools) is in Public Preview for AWS commercial regions. Only ACCOUNTADMIN administers it, and the servers are configured in Snowsight, not SQL. `setup.sql` already created the OAuth client the Snowflake server entry needs.

1. **Enable Tools.** Sign in to Snowsight as ACCOUNTADMIN, open **AI & ML > AI Gateway > MCP & Tools** (it opens in a new tab). This creates the `SNOWFLAKE$OPS` database used below.
2. **Snowflake server (catalog).** Find **Snowflake**, enter host `<org-account>.snowflakecomputing.com` (hyphens), database `CORTEX_GATEWAY_MEDTECH_LAB`, schema `PUBLIC`, name `MEDTECH_MCP`. Run the first query in `lab/tools_setup.sql` for the client id and secret, enter them, save and enable the server.
3. **Glean (custom server).** Glean isn't in the catalog. In the Glean admin console, open the MCP Configurator and copy your Glean MCP server URL. In Tools, **Add app > Remote URL**, paste it and choose OAuth. Tools requires the URL to end in `/mcp`; if yours does not, see the note below. Under the server's tools, allow only read tools (search, read document, chat).
4. **Grant discovery.** Run the rest of `lab/tools_setup.sql`: it grants `SNOWFLAKE$OPS.MCP$USER` to SYSADMIN. The MCP session uses your `DEFAULT_ROLE` and needs a `DEFAULT_WAREHOUSE`.
5. **Connect in CoCo Desktop.** **Agent Settings > MCP > Snowflake Managed** now lists both servers. Authorize each with your own Glean and Snowflake identity.
6. **Check.** Ask one combined question (see `demo_script.md` section 3). The Tools **Activity** page shows the tool calls; `lab/tools_setup.sql` ends with a query over `AGENT_TRACE_TABLE`.

If your Glean server URL doesn't end in `/mcp`, Tools can't register it as a custom server. For the demo you can connect Glean directly in CoCo Desktop as a regular remote MCP server instead; it is then not governed by Tools, so say so. Microsoft Teams, Outlook and SharePoint servers are in the Tools catalog as Private Preview: they need account enablement and an Entra tenant id.

### Trace Analyzer app

| Group | Page | What it shows |
|-------|------|---------------|
| Act (local only) | Live prompt | Sends one prompt through the gateway and polls until its trace lands, then shows the span waterfall |
| Observe | Overview, Model performance, User deep dive | KPIs, latency, errors, tokens and credits by model and user |
| Observe | Trace explorer | One trace: span timeline plus captured system prompt, input and output messages. **Optimizer traces only** filters to the app's own diagnose, propose and judge calls |
| Optimize | Advisor | Rules over telemetry (latency, error spikes, token bloat, model mix, cost), plus **Diagnose with AI**: `claude-sonnet-4-5` reads the telemetry profile and sampled payloads and returns findings with a root cause, evidence spans and one config change. Each finding has a "Test this fix" button |
| Optimize | Experiments | Replays EVAL_PROMPTS through the gateway with baseline vs candidate config; a rubric judge (correctness 0.5, completeness 0.2, conciseness 0.1, compliance 0.2) scores each answer through the gateway, with an optional second judge from another provider. The **Prompt optimizer** proposes system prompts from the weakest answers, picks the best on a dev split and confirms it on held-out prompts |
| Optimize | Before / after | Quality with a paired-bootstrap 95% CI and the rubric breakdown, p50/p95, tokens, credits per 1k requests (rates fitted from billed usage), error rate, projected monthly saving, judge rationales, **Route by intent** (cheapest model within 0.05 of the best quality per intent), **Cost of optimization** (optimizer calls by role, experiment credits, payback days), and the client config, gateway allowlist and quota SQL to promote |
| Govern | Cost governance | Month-to-date gateway credits, spend by `COST_CENTER` tag, budget limit, per-user spend against quota limits, active blocks, block history and the last captured gateway denial |

#### Where to run the app

Run it locally (`./demo.sh app`) for demos. The Experiments and Live prompt pages need gateway calls to be traced, and that works only with a PAT sent from outside Snowflake:

| Where | Gateway credential | Served | Traced |
|-------|-------------------|--------|--------|
| Laptop (`./demo.sh app`) | PAT | Yes | Yes, in about a minute |
| Streamlit in Snowflake | Container session token | Yes | No (in testing) |
| Streamlit in Snowflake | PAT secret | No: HTTP 401 `INCOMING_REQUEST_BLOCKED` when the account has a network policy | - |

An IP allowlist does not fix the in-Snowflake PAT case. LOGIN_HISTORY records gateway PAT calls with `CLIENT_IP = 0.0.0.0`, so there is no container address to allow, short of opening the policy to all IPs.

**The optimizer runs through the gateway too.** Diagnosis, prompt proposals and judging use the gateway endpoint (`/api/v2/aigateways/SNOWFLAKE/v1`), each call with its own `traceparent` and the conversation id `optimizer-<role>-<run_id>`, logged to `OPTIMIZER_CALLS`. Run the app locally to see those traces; the deployed app's optimizer calls fail without a PAT from outside Snowflake.

The deployed app still runs the Observe pages, Advisor rules and Before/After. Its Experiments results land in OPTIMIZATION_RESULTS without gateway traces, and Live prompt is hidden there.

### Run in Snowflake (Workspaces / Git)

The SQL and the app can run entirely from Snowsight:

1. Snowsight -> **Projects -> Workspaces -> Create Workspace from Git repository**, pointing at `https://github.com/sfc-gh-snuggehalli/field-demo-enablement`.
2. Open `ai-gateway-medtech/lab/setup.sql`, replace `<% gateway_host %>` in the network rule with your account host (`<org-account>.snowflakecomputing.com`, hyphens not underscores), and run it.
3. Create the Streamlit app from `ai-gateway-medtech/app` (container runtime, compute pool `SYSTEM_COMPUTE_POOL_CPU`, integration `GATEWAY_MEDTECH_APP_EAI`).

The LangChain notebook, `live_agent.py` and the traced Experiments play the external client, so they run on a laptop with a PAT.

## Key Concepts

- **Gateway endpoint**: `https://<account-host>/api/v2/aigateways/SNOWFLAKE/v1` plus `/chat/completions` (non-Claude) or `/messages` (Claude). Use hyphens in the host.
- **GPT-5 parameters**: use `max_completion_tokens`, not `max_tokens`. Only `openai-gpt-5.4*` accepts a custom temperature.
- **Trace hierarchy**: conversation (`x-snowflake-ai-gateway-conversation-id`) -> trace (`traceparent`) -> span (one inference call).
- **Payload capture**: prompts and responses are recorded only with `logging.capture_payload.request_response: true`. Treat the trace table as sensitive.
- **Spec replacement**: `ALTER AI GATEWAY ... FROM SPECIFICATION` replaces the whole spec, so start from `DESCRIBE AI GATEWAY`.
- **Privileges**: `USAGE` to call (granted to PUBLIC by default), `MONITOR` to read traces and usage.
- **Tools**: ACCOUNTADMIN enables MCP servers and tool policies in Snowsight; `SNOWFLAKE$OPS.MCP$USER` makes enabled servers discoverable in CoCo Desktop; each user authorizes with their own OAuth identity. A custom server URL must end in `/mcp` and support OAuth.
- **Optimizer as a client**: the optimizer's LLM calls carry conversation ids `optimizer-<role>-<run_id>`, so they are separable from workload traffic in `AGENT_TRACE_TABLE` and costed in the app.

## Cleanup

Run `lab/cleanup.sql`. It drops the database, warehouse, integrations and the Tools OAuth client. Remove the Glean and Snowflake servers in Tools (Snowsight) yourself; they are not SQL objects. The shared gateway spec reset and grant revokes are included but commented out; review them before running.

## References

- [Cortex AI Gateway](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway)
- [Inference with Cortex AI Gateway](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/inference)
- [Observability for Cortex AI Gateway](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/observability)
- [Cost management for Cortex AI Gateway](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/cost-management)
- [Snowflake-managed MCP server](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp)
- [Tools in Cortex AI Gateway](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/tools)
- [Adding a custom MCP server](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/tools/admin-custom-apps)
- [Setting up MCP servers needing additional configuration](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/tools/admin-server-oauth-setup)
- [Glean MCP server](https://developers.glean.com/guides/mcp)
- [Cortex Search](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview)
- [Per-user quotas](https://docs.snowflake.com/en/user-guide/budgets/per-user-quotas)
- [Streamlit secrets and container runtime](https://docs.snowflake.com/en/developer-guide/streamlit/app-development/secrets-and-configuration)
