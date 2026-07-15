"""
GTM Agents — Observability & Migration Command Center (Streamlit-in-Snowflake).

Five tabs turn the shared logging tables and in-plane agent traces into a live view of the
Claude Code + MCP -> Cortex Agents + CoWork migration:

  1. Live Traces      — agent spans (tool calls, tokens, model, latency) from AI Observability.
  2. Cost & Budget    — credits/$ per run, cost-per-email, projected monthly spend, per-user quota.
  3. Eval Dashboard   — native agent-eval scores (answer correctness, tool-selection accuracy, logical consistency).
  4. Recommendations  — top converting email patterns from the semantic model.
  5. Before vs After  — latency (MCP round-trip vs Agents-native), cost per 1k, governance matrix.

Deploy as a Streamlit-in-Snowflake app (Snowsight -> Projects -> Streamlit) in a role that has
USAGE on GTMAGENTS + SELECT on its tables, and MONITOR on GTM_SUPERVISOR + the SNOWFLAKE.CORTEX_USER
role to read AI Observability events. Run the four lab notebooks first so the tables are populated.
"""

import json

import pandas as pd
import streamlit as st

from snowflake.snowpark.context import get_active_session

DATABASE = "GTMAGENTS"
SCHEMA = "DEMO"
SUPERVISOR = "GTM_SUPERVISOR"

st.set_page_config(page_title="GTM Agents — Command Center", page_icon="📡", layout="wide")
session = get_active_session()
session.sql(f"USE SCHEMA {DATABASE}.{SCHEMA}").collect()


def q(sql: str) -> pd.DataFrame:
    """Run SQL and return a pandas DataFrame, or an empty frame on error."""
    try:
        return session.sql(sql).to_pandas()
    except Exception as exc:  # keep the dashboard rendering even if one query fails
        st.info(f"Query unavailable: {exc}")
        return pd.DataFrame()


st.title("GTM Agents — Observability & Migration Command Center")
st.caption(
    "Claude Code + Snowflake MCP  →  multi-agent Cortex Agents + CoWork. "
    "Every panel reads live from the lab's logging tables and in-plane agent traces."
)

tab_traces, tab_cost, tab_evals, tab_reco, tab_compare = st.tabs(
    ["🛰️ Live Traces", "💰 Cost & Budget", "🎯 Eval Dashboard", "📈 Recommendations", "⚖️ Before vs After"]
)

# ─────────────────────────────────────────────────────────────────────────────
# TAB 1 — Live Traces (Part D)
# ─────────────────────────────────────────────────────────────────────────────
with tab_traces:
    st.subheader("Agent execution traces (in-plane)")
    st.caption(
        "Server-side spans emitted by Cortex Agents into SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS — "
        "tool calls, model, tokens, latency. This is governance the external MCP brain cannot give you."
    )
    events = q(f"""
        SELECT
            TIMESTAMP AS ts,
            RECORD:name::STRING AS span,
            RECORD_ATTRIBUTES:"snow.ai.observability.agent.name"::STRING AS agent,
            RESOURCE_ATTRIBUTES:"snow.user.name"::STRING AS user_name
        FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
            '{DATABASE}', '{SCHEMA}', '{SUPERVISOR}', 'CORTEX AGENT'))
        ORDER BY TIMESTAMP DESC
        LIMIT 200
    """)
    if not events.empty:
        c1, c2 = st.columns(2)
        c1.metric("Trace spans (last 200)", len(events))
        c2.metric("Distinct span types", events["SPAN"].nunique())
        st.dataframe(events, use_container_width=True, hide_index=True)
    else:
        st.warning(
            "No AI Observability rows yet (run the supervisor in notebook 03, and ensure the app role "
            "has MONITOR on GTM_SUPERVISOR + CORTEX_USER). Showing the in-plane routing log instead:"
        )
    st.markdown("**Scoring routing decisions** (cheap model vs escalation) — `ROUTING_LOG`")
    routing = q("SELECT ts, email_id, model_used, ROUND(confidence,3) AS confidence, escalated, ROUND(intent_score,3) AS intent_score FROM ROUTING_LOG ORDER BY ts DESC LIMIT 200")
    if not routing.empty:
        c1, c2 = st.columns(2)
        c1.metric("Scored emails", len(routing))
        c2.metric("Escalated to strong model", int(routing["ESCALATED"].sum()))
        st.dataframe(routing, use_container_width=True, hide_index=True)
    else:
        st.info("No routing rows yet — run notebook 03.")

# ─────────────────────────────────────────────────────────────────────────────
# TAB 2 — Cost & Budget (Part D)
# ─────────────────────────────────────────────────────────────────────────────
with tab_cost:
    st.subheader("Cost & budget")
    req = q("SELECT source, scenario, latency_ms, tokens, est_credits, ts FROM REQUEST_LOG")
    if not req.empty:
        by_src = req.groupby("SOURCE").agg(
            requests=("SCENARIO", "count"),
            avg_latency_ms=("LATENCY_MS", "mean"),
            credits=("EST_CREDITS", "sum"),
        ).reset_index()
        cols = st.columns(3)
        total_emails = q("SELECT COUNT(*) AS n FROM EMAILS")
        n_emails = int(total_emails["N"].iloc[0]) if not total_emails.empty else 3000
        agents_credits = float(by_src.loc[by_src["SOURCE"] == "AGENTS", "credits"].sum() or 0)
        cost_per_email = agents_credits / max(n_emails, 1)
        cols[0].metric("Total logged credits", f"{req['EST_CREDITS'].sum():.4f}")
        cols[1].metric("Cost per email (AGENTS)", f"{cost_per_email:.6f} cr")
        cols[2].metric("Projected / 1M emails", f"{cost_per_email * 1_000_000:,.0f} cr")

        st.markdown("**Credits by source**")
        st.bar_chart(by_src.set_index("SOURCE")["credits"])

        st.markdown("**Cost-per-request trend**")
        trend = req.sort_values("TS")[["TS", "SOURCE", "EST_CREDITS"]].copy()
        trend_pivot = trend.pivot_table(index="TS", columns="SOURCE", values="EST_CREDITS", aggfunc="mean")
        st.line_chart(trend_pivot)
    else:
        st.info("REQUEST_LOG is empty — run notebooks 02 and 03.")

    st.markdown("---")
    st.markdown("**Per-user budget guardrails** (available in-plane, absent for the external MCP brain)")
    st.code(
        "-- Cap per-user AI spend and block when exceeded\n"
        "CREATE SNOWFLAKE.CORE.QUOTA q();\n"
        "CALL q!ADD_SHARED_RESOURCE('AI FUNCTION');\n"
        "CALL q!SET_PER_USER_LIMIT(50, 'DAILY');\n"
        "CALL q!SET_BLOCK_ENFORCEMENT_ENABLED(TRUE);",
        language="sql",
    )
    st.caption(
        "Account-wide AI cost also lands in SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY "
        "(CREDITS, MODEL_NAME, USER_ID) for chargeback."
    )

# ─────────────────────────────────────────────────────────────────────────────
# TAB 3 — Eval Dashboard (Part D)
# ─────────────────────────────────────────────────────────────────────────────
with tab_evals:
    st.subheader("Native agent evaluation")
    st.caption(
        "Scores from Cortex Agent Evaluation of GTM_SUPERVISOR — answer correctness, tool-selection "
        "accuracy, logical consistency, and a custom routing-quality judge. Persisted per run to EVAL_SCORE_HISTORY."
    )
    hist = q(
        "SELECT run_name, run_ts, metric_name, avg_score, min_score, max_score, num_records "
        "FROM EVAL_SCORE_HISTORY ORDER BY run_ts"
    )
    if not hist.empty:
        runs = list(dict.fromkeys(hist["RUN_NAME"].tolist()))  # preserve chronological order
        latest_run = runs[-1]
        latest = hist[hist["RUN_NAME"] == latest_run]

        st.markdown(f"**Latest run:** `{latest_run}`")
        metric_scores = dict(zip(latest["METRIC_NAME"], latest["AVG_SCORE"]))
        headline = ["answer_correctness", "tool_selection_accuracy", "logical_consistency", "routing_quality"]
        shown = [m for m in headline if m in metric_scores] or list(metric_scores)
        cols = st.columns(len(shown))
        for col, m in zip(cols, shown):
            col.metric(m.replace("_", " ").title(), f"{metric_scores[m]:.3f}")

        # Baseline vs latest delta (first vs last run)
        if len(runs) >= 2:
            base = hist[hist["RUN_NAME"] == runs[0]][["METRIC_NAME", "AVG_SCORE"]]
            curr = latest[["METRIC_NAME", "AVG_SCORE"]]
            delta = base.merge(curr, on="METRIC_NAME", suffixes=(f" ({runs[0]})", f" ({latest_run})"))
            delta["Δ"] = (delta.iloc[:, 2] - delta.iloc[:, 1]).round(3)
            st.markdown(f"**{runs[0]} → {latest_run}**")
            st.dataframe(delta, use_container_width=True, hide_index=True)

        st.markdown("**Average score by metric across runs**")
        pivot = hist.pivot_table(index="RUN_NAME", columns="METRIC_NAME", values="AVG_SCORE", sort=False)
        st.line_chart(pivot)
        st.dataframe(hist, use_container_width=True, hide_index=True)
    else:
        st.info(
            "EVAL_SCORE_HISTORY is empty — run notebook 04 (gtm-04-evals) to evaluate GTM_SUPERVISOR "
            "and persist baseline + improved scores."
        )

# ─────────────────────────────────────────────────────────────────────────────
# TAB 4 — Recommendations (Part D)
# ─────────────────────────────────────────────────────────────────────────────
with tab_reco:
    st.subheader("Winning email patterns")
    st.caption("Top converting patterns from the governed semantic model — the Recommendation agent's source.")
    perf = q("""
        SELECT e.quality_tier AS quality_tier,
               COUNT(*) AS emails,
               ROUND(AVG(IFF(e.replied,1,0)),3) AS reply_rate,
               ROUND(AVG(IFF(e.meeting_booked,1,0)),3) AS meeting_rate,
               ROUND(AVG(IFF(o.won,1,0)),3) AS win_rate,
               SUM(o.revenue) AS revenue
        FROM EMAILS e JOIN OUTCOMES o ON o.email_id = e.id
        GROUP BY e.quality_tier ORDER BY e.quality_tier
    """)
    if not perf.empty:
        st.markdown("**Win rate by quality tier** (1=poor, 2=mixed, 3=good)")
        st.bar_chart(perf.set_index("QUALITY_TIER")["WIN_RATE"])
        st.dataframe(perf, use_container_width=True, hide_index=True)
    region = q("""
        SELECT r.region, r.team,
               ROUND(AVG(IFF(e.replied,1,0)),3) AS reply_rate,
               SUM(o.revenue) AS revenue
        FROM EMAILS e JOIN REPS r ON e.rep_id=r.rep_id JOIN OUTCOMES o ON o.email_id=e.id
        GROUP BY r.region, r.team ORDER BY revenue DESC LIMIT 12
    """)
    if not region.empty:
        st.markdown("**Top region × team by revenue**")
        st.dataframe(region, use_container_width=True, hide_index=True)

# ─────────────────────────────────────────────────────────────────────────────
# TAB 5 — Before vs After (Part E)
# ─────────────────────────────────────────────────────────────────────────────
with tab_compare:
    st.subheader("External brain (MCP) vs in-data-plane brain (Cortex Agents)")
    req = q("SELECT source, scenario, latency_ms, tokens, est_credits FROM REQUEST_LOG")
    if not req.empty:
        lat = req.groupby("SOURCE")["LATENCY_MS"].mean().reset_index()
        c1, c2 = st.columns(2)
        with c1:
            st.markdown("**(a) Avg latency per request (ms)** — lower is better")
            st.bar_chart(lat.set_index("SOURCE")["LATENCY_MS"])
            mcp = float(lat.loc[lat["SOURCE"] == "MCP", "LATENCY_MS"].mean() or 0)
            agents = float(lat.loc[lat["SOURCE"] == "AGENTS", "LATENCY_MS"].mean() or 0)
            if mcp and agents:
                st.metric("Latency reduction (Agents vs MCP)", f"{(1 - agents / mcp):.0%}")
        with c2:
            st.markdown("**(b) Cost per 1,000 emails (credits)**")
            cc = q("SELECT approach, emails_treated, est_credits FROM COST_COMPARISON")
            if not cc.empty:
                cc["credits_per_1k"] = cc["EST_CREDITS"] / (cc["EMAILS_TREATED"].clip(lower=1) / 1000)
                st.bar_chart(cc.set_index("APPROACH")["credits_per_1k"])
                st.dataframe(cc, use_container_width=True, hide_index=True)
    else:
        st.info("REQUEST_LOG / COST_COMPARISON empty — run notebooks 02 and 03.")

    st.markdown("**(c) Governance matrix**")
    gov = pd.DataFrame(
        {
            "Capability": [
                "Per-user budgets / quotas",
                "Cost chargeback (usage history)",
                "Object tagging & classification",
                "Server-side execution traces",
                "Row/column governance on tools",
                "No external data egress",
            ],
            "BEFORE (Claude + MCP)": ["Partial", "No", "Partial", "No", "Yes", "No"],
            "AFTER (Cortex Agents)": ["Yes", "Yes", "Yes", "Yes", "Yes", "Yes"],
        }
    )
    st.dataframe(gov, use_container_width=True, hide_index=True)
    st.caption(
        "The external brain only sees tool outputs; budgets, quotas, tagging, and traces live outside "
        "Snowflake. Moving the brain in-plane makes every one of these native and enforced."
    )
