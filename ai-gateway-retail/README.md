# Cortex AI Gateway for Retail Analytics: Govern, Observe and Optimize Every LLM Call

[View Presentation](https://sfc-gh-snuggehalli.github.io/field-demo-enablement/ai-gateway-retail/presentations/ai-gateway.html)

Cortex AI Gateway gives agents and SDKs one governed inference endpoint. It records every request as an OpenTelemetry span in your own account and attributes and caps spend per user. This module runs a LangChain agent through the gateway with a Snowflake MCP server that exposes one governed Cortex Agent tool for an athletic apparel retailer: two Cortex Analyst tools over customer + churn and executive KPI semantic views, with churn scores from an XGBoost model in the Snowflake Model Registry. It then uses a Streamlit Trace Analyzer to close the loop: observe traces, diagnose problems, replay an eval set with a candidate config, compare before and after, and promote the winner.

## Audience

SEs, solution architects, platform engineers, and teams evaluating centralized AI governance and observability.

## Topics Covered

- **Gateway fundamentals**: auto-provisioned `SNOWFLAKE` gateway, Chat Completions and Messages APIs, model allowlist, logging and payload capture
- **LangChain + MCP**: `ChatOpenAI` pointed at the gateway; Snowflake MCP server exposing one governed tool, a Cortex Agent that runs two Cortex Analyst tools (no raw SQL tool)
- **Governed ML**: train an XGBoost churn model, log it to the Model Registry, batch-score in the warehouse with `mv.run()`, attach a Model Monitor; the agent answers from the new scores with no client change
- **Observability**: `AGENT_TRACE_TABLE('SNOWFLAKE')` spans, W3C `traceparent` grouping, conversation ids, Snowsight AI Gateway page
- **Optimization loop**: Advisor findings -> eval-set experiments through the gateway -> LLM-judge scoring -> before/after -> promote
- **Live prompt**: `lab/live_agent.py` sends one request that is visible in both Snowsight and the Trace Analyzer
- **Admin and cost controls**: spec management, USAGE vs MONITOR, `AI_GATEWAY_USAGE_HISTORY`, chargeback by cost-center tag, shared-resource budgets, per-user quotas with a live block on a demo user

## Contents

| File | Description |
|------|-------------|
| `presentations/ai-gateway.html` | Slide deck (23 slides: AI in Snowflake, then Snowflake as the AI control plane) |
| `presentations/ai-gateway-speaker-notes.md` | Per-slide talking points, presenter notes, and references |
| `demo_script.md` | Live run-of-show for the demo |
| `demo.sh` | One script for setup, traffic, notebook, app, deploy and teardown |
| `pyproject.toml`, `uv.lock` | Local Python environment (lab, notebook with the churn model, app, Snowflake CLI), managed by uv |
| `lab/setup.sql` | Database, warehouse, retail data (13 tables, Oct 2024 - Sep 2025), two semantic views, churn predictions table, Cortex Agent, MCP server, gateway spec + grants, eval/optimization tables, app access |
| `lab/cleanup.sql` | Tear everything down to start fresh |
| `lab/ai-gateway-lab.ipynb` | Hands-on notebook: gateway + LangChain + MCP, churn model (registry, batch inference, monitor), observability, cost management |
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
./demo.sh burst        # before a demo: drive the cost demo user over its quota
./demo.sh teardown     # drop everything
```

`setup` is safe to re-run. Non-interactive: `./demo.sh setup -c <connection> -p <pat-file>`. It writes `.env` (connection, account, user, PAT file, gateway host); every other command loads it. `./demo.sh ask "..."` sends one prompt and prints its trace_id; `./demo.sh deploy` deploys the app to Streamlit in Snowflake.

### Set up with Cortex Code

Open this repository in Cortex Code and paste:

```text
Set up the Cortex AI Gateway retail lab in the ai-gateway-retail folder on my Snowflake account.
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

Without uv, install Python 3.11+ with `langchain-openai langchain-mcp-adapters langgraph snowflake-connector-python snowflake-snowpark-python snowflake-ml-python xgboost scikit-learn pandas streamlit requests`, and Snowflake CLI 3.14+.

1. Run the setup script with your account host (hyphens, not underscores; `SELECT LOWER(REPLACE(CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME(), '_', '-')) || '.snowflakecomputing.com';` returns it):
   ```bash
   snow sql -f lab/setup.sql -D gateway_host=<org-account>.snowflakecomputing.com
   ```
   This creates `CORTEX_GATEWAY_RETAIL_LAB` (13 retail tables with deterministic synthetic data, CHURN_PREDICTIONS seeded from the legacy score, semantic views CUSTOMER_INTERACTIONS_SV and CONVERSATIONAL_BI_SV, Cortex Agent RETAIL_ANALYTICS_AGENT, MCP server RETAIL_MCP, the EVAL_PROMPTS view, OPTIMIZATION_RUNS, OPTIMIZATION_RESULTS), the warehouse `GATEWAY_RETAIL_WH`, and the integration `GATEWAY_RETAIL_APP_EAI`. It turns on gateway logging with client telemetry and payload capture, and grants SYSADMIN gateway MONITOR plus the usage, budget and quota roles. Create the cost demo PAT once with the commented `ALTER USER GATEWAY_RETAIL_COST_DEMO ADD PROGRAMMATIC ACCESS TOKEN` in the cost governance section, and create your own:
   ```sql
   ALTER USER <you> ADD PROGRAMMATIC ACCESS TOKEN ai_gateway_retail ROLE_RESTRICTION = 'SYSADMIN' DAYS_TO_EXPIRY = 7;
   ```
2. Export credentials for the local tools:
   ```bash
   export SNOWFLAKE_ACCOUNT=<org-account> SNOWFLAKE_USER=<you>
   export SNOWFLAKE_PAT=<pat>          # or SNOWFLAKE_PAT_FILE=~/.snowflake/ai_gateway_retail.pat
   ```
3. Generate background traffic: `python lab/generate_traffic.py`
4. Run the notebook `lab/ai-gateway-lab.ipynb` top to bottom.
5. Run the app locally (use this for demos; see [Where to run the app](#where-to-run-the-app)):
   ```bash
   cd app
   SNOWFLAKE_DEFAULT_CONNECTION_NAME=<connection in ~/.snowflake/config.toml> \
   GATEWAY_HOST=<org-account>.snowflakecomputing.com \
   streamlit run streamlit_app.py
   ```
   Gateway calls use `SNOWFLAKE_PAT` or `SNOWFLAKE_PAT_FILE` (default `~/.snowflake/ai_gateway_retail.pat`). Use dashes, not underscores, in the host.
6. Optional: deploy the app to Snowflake for read-only analysis: `cd app && snow streamlit deploy --replace`
7. Before a demo, block the cost demo user so Cost governance has something to enforce:
   ```bash
   python lab/generate_traffic.py --burst   # uses ~/.snowflake/gateway_retail_cost.pat
   ```
   Section 9b of `setup.sql` creates `GATEWAY_RETAIL_COST_DEMO`, a service user tagged `COST_CENTER = 'MERCHANDISING'` and `QUOTA_TIER = 'RETAIL_DEMO'`, and `GATEWAY_RETAIL_QUOTA`: 1 credit per day, block enforcement on, scoped to that tag only. The burst spends about 1.5 credits until the gateway returns HTTP 403 ("exceeded the usage quota limit"), and saves the response to `app/output/last_quota_denial.json`. The block lasts until 00:00 UTC. Keep real users out of this quota: a block covers every AI domain the user touches.

### Lab Sections

1. Install dependencies
2. Configuration (PAT, gateway endpoint)
3. Gateway LLM with `traceparent`
4. MCP tools over streamable HTTP
5. LangChain ReAct agent
6. Queries: executive KPIs (business_kpi_analyst), customers and churn (customer_interactions_analyst), cross-domain (both)
7. Churn model: feature view, XGBoost vs legacy score, Model Registry, `mv.run()` batch inference into CHURN_PREDICTIONS, Model Monitor, then the churn question again through the gateway
8. Observability: recent traces, credit usage, single-trace drill-down, conversation reconstruction
9. Cost management: spend by user, shared-resource budget, per-user quota

### Trace Analyzer app

| Group | Page | What it shows |
|-------|------|---------------|
| Act (local only) | Live prompt | Sends one prompt through the gateway and polls until its trace lands, then shows the span waterfall |
| Observe | Overview, Model performance, User deep dive | KPIs, latency, errors, tokens and credits by model and user |
| Observe | Trace explorer | One trace: span timeline plus captured system prompt, input and output messages |
| Optimize | Advisor | Rules over telemetry (latency, error spikes, token bloat, model mix, cost), each with a proposed change and a "Test this fix" button |
| Optimize | Experiments | Replays EVAL_PROMPTS through the gateway with baseline vs candidate config; scores each answer 0-1 with an AI_COMPLETE judge |
| Optimize | Before / after | Quality, p50/p95, tokens, credits per 1k requests (rates fitted from billed usage) and error-rate deltas, projected monthly saving, per-prompt and side-by-side answers, plus the client config, gateway allowlist and quota SQL to promote |
| Govern | Cost governance | Month-to-date gateway credits, spend by `COST_CENTER` tag, budget limit, per-user spend against quota limits, active blocks, block history and the last captured gateway denial |

#### Where to run the app

Run it locally with `streamlit run` for demos. The Experiments and Live prompt pages need gateway calls to be traced, and that works only with a PAT sent from outside Snowflake:

| Where | Gateway credential | Served | Traced |
|-------|-------------------|--------|--------|
| Laptop (`streamlit run`) | PAT | Yes | Yes, in about a minute |
| Streamlit in Snowflake | Container session token | Yes | No (in testing) |
| Streamlit in Snowflake | PAT secret | No: HTTP 401 `INCOMING_REQUEST_BLOCKED` when the account has a network policy | - |

An IP allowlist does not fix the in-Snowflake PAT case. LOGIN_HISTORY records gateway PAT calls with `CLIENT_IP = 0.0.0.0`, so there is no container address to allow, short of opening the policy to all IPs.

The deployed app still runs the Observe pages, Advisor and Before/After. Its Experiments results land in OPTIMIZATION_RESULTS without gateway traces, and Live prompt is hidden there.

### Run in Snowflake (Workspaces / Git)

The SQL and the app can run entirely from Snowsight:

1. Snowsight -> **Projects -> Workspaces -> Create Workspace from Git repository**, pointing at `https://github.com/sfc-gh-snuggehalli/field-demo-enablement`.
2. Open `ai-gateway-retail/lab/setup.sql`, replace `<% gateway_host %>` in the network rule with your account host (`<org-account>.snowflakecomputing.com`, hyphens not underscores), and run it.
3. Create the Streamlit app from `ai-gateway-retail/app` (container runtime, compute pool `SYSTEM_COMPUTE_POOL_CPU`, integration `GATEWAY_RETAIL_APP_EAI`).

The LangChain notebook, `live_agent.py` and the traced Experiments play the external client, so they run on a laptop with a PAT.

## Key Concepts

- **Gateway endpoint**: `https://<account-host>/api/v2/aigateways/SNOWFLAKE/v1` plus `/chat/completions` (non-Claude) or `/messages` (Claude). Use hyphens in the host.
- **GPT-5 parameters**: use `max_completion_tokens`, not `max_tokens`. Only `openai-gpt-5.4*` accepts a custom temperature.
- **Trace hierarchy**: conversation (`x-snowflake-ai-gateway-conversation-id`) -> trace (`traceparent`) -> span (one inference call).
- **Payload capture**: prompts and responses are recorded only with `logging.capture_payload.request_response: true`. Treat the trace table as sensitive.
- **Spec replacement**: `ALTER AI GATEWAY ... FROM SPECIFICATION` replaces the whole spec, so start from `DESCRIBE AI GATEWAY`.
- **Privileges**: `USAGE` to call (granted to PUBLIC by default), `MONITOR` to read traces and usage.

## Cleanup

Run `lab/cleanup.sql`. It drops the database, warehouse and integration. The shared gateway spec reset and grant revokes are included but commented out; review them before running.

## References

- [Cortex AI Gateway](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway)
- [Inference with Cortex AI Gateway](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/inference)
- [Observability for Cortex AI Gateway](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/observability)
- [Cost management for Cortex AI Gateway](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/cost-management)
- [Snowflake-managed MCP server](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp)
- [Per-user quotas](https://docs.snowflake.com/en/user-guide/budgets/per-user-quotas)
- [Streamlit secrets and container runtime](https://docs.snowflake.com/en/developer-guide/streamlit/app-development/secrets-and-configuration)
