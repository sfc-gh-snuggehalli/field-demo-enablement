# Demo Script: Cortex AI Gateway

About 20 minutes. Before you present, run `lab/setup.sql`, deploy the app, and run `python lab/generate_traffic.py` once so the dashboards have history.

## Pre-flight (5 min before)

- Terminal: `export SNOWFLAKE_ACCOUNT=<org-account> SNOWFLAKE_PAT_FILE=~/.snowflake/ai_gateway_demo.pat`
- Browser tab 1: Snowsight -> **AI & ML -> Cortex AI Gateway**
- Browser tab 2: Trace Analyzer app (Projects -> Streamlit -> AI_GATEWAY_TRACE_ANALYZER), set lookback to 1 day
- Deck open at the Architecture slide

## 1. Frame it (deck, 3 min)

Slides 1-3. One governed endpoint, MCP for data, telemetry you own.

## 2. Live prompt from an external agent (4 min)

```bash
python lab/live_agent.py "What was the ROAS by channel for Q4 2024, and how does it compare to our Q4 ROAS target?"
```

- Point out the single tool call printed (`marketing_agent`) and the `trace_id`. The agent behind the MCP server ran the Analyst SQL and the strategy search itself.
- "Two gateway calls in one agent turn, all under one trace. The client never got a raw SQL tool, so it can't go around the semantic view."

## 3. Find it in Snowsight (2 min)

Tab 1, AI Gateway traces. Search the trace_id and open it: the spans, model, tokens and captured messages.
"Same data, no SQL. It lives in an event table in this account."

## 4. Find it in the Trace Analyzer (3 min)

- **Trace explorer**: pick the trace and show the waterfall and the system prompt, input and output for each span.
- **Overview**: the error rate and token charts now include those calls.

## 5. Close the loop (6 min)

1. **Advisor**: find the token-bloat or latency finding (the generator's verbose scenario produces one) and click **Test this fix**.
2. **Experiments**: the candidate is pre-filled (smaller max tokens, concise system prompt; optionally `openai-gpt-5.4-mini`). Keep about 6 prompts selected and click **Run experiment**. It takes about a minute.
3. **Before / after**: in our validation run the candidate held judge quality (0.98 vs 0.98) with about 60% fewer output tokens and lower p50 latency. Your numbers will vary.
4. Scroll to **Promote**: client config, the allowlist `ALTER AI GATEWAY`, and a per-user quota. "We ship the evidence, not a hunch."

## 6. Governance close (deck, 2 min)

Slides 12-14: USAGE vs MONITOR, the spec replaces as a whole, quotas block within minutes. Then next steps.

## Recovery tips

- Trace Analyzer doesn't show the trace yet: traces normally land within a minute; refresh the Trace explorer.
- Gateway returns 401 locally: the PAT expired or a network policy blocked it. Create a new PAT.
- Experiments calls return HTTP 401: a PAT secret is bound and the network policy blocks the container's IP. Unset it with `ALTER STREAMLIT ... UNSET SECRETS`.
- `unknown model`: that model isn't available on this account's Chat Completions API, and Claude only works on `/v1/messages`.
