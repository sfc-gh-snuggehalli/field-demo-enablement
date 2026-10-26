import json

import pandas as pd
import streamlit as st

from optimize_config import estimate_credits
from optimizer import RUBRIC_WEIGHTS, paired_bootstrap_ci

st.header("Before / after")

conn = st.session_state["conn"]
rates = st.session_state.get("credit_rates", {})

runs = conn.query(
    "SELECT RUN_ID, LABEL, MODEL, MAX_TOKENS, SYSTEM_PROMPT, SOURCE_FINDING, CREATED_AT "
    "FROM OPTIMIZATION_RUNS ORDER BY CREATED_AT DESC LIMIT 100",
    ttl=0,
)
if runs.empty:
    st.info("No experiment runs yet. Start one from the Experiments page.")
    st.stop()

ids = runs["RUN_ID"].tolist()
cfg = runs.set_index("RUN_ID")


def pair_of(run_id: str) -> str:
    return run_id.split("-", 1)[-1]


# Default to the experiment just run, else the newest complete baseline/candidate pair.
b_def, c_def = st.session_state.get("compare_runs", (None, None))
if b_def not in ids or c_def not in ids:
    b_def = c_def = None
    for rid in ids:
        if rid.startswith("candidate-") and f"baseline-{pair_of(rid)}" in ids:
            b_def, c_def = f"baseline-{pair_of(rid)}", rid
            break


def describe(rid: str) -> str:
    r = cfg.loc[rid]
    finding = f" - {r['SOURCE_FINDING'][:40]}" if isinstance(r["SOURCE_FINDING"], str) else ""
    return f"{rid} | {r['MODEL']} / {r['MAX_TOKENS']} tok{finding}"


c1, c2 = st.columns(2)
b_id = c1.selectbox("Baseline run", ids, index=ids.index(b_def) if b_def else min(1, len(ids) - 1),
                    format_func=describe)
c_id = c2.selectbox("Candidate run", ids, index=ids.index(c_def) if c_def else 0,
                    format_func=describe)
if b_id == c_id:
    st.warning("Pick two different runs to compare.")
    st.stop()
if pair_of(b_id) != pair_of(c_id):
    st.caption("These runs come from different experiments; eval prompts may differ.")

# Gateway-side duration comes from the trace table, joined on the trace_id we sent.
res = conn.query(
    f"""
    WITH spans AS (
        SELECT TRACE:"trace_id"::STRING AS TRACE_ID,
               MAX(DATEDIFF('millisecond', START_TIMESTAMP, TIMESTAMP)) AS GATEWAY_MS
        FROM TABLE(AGENT_TRACE_TABLE('SNOWFLAKE'))
        WHERE TIMESTAMP > DATEADD('day', -7, CURRENT_TIMESTAMP())
          AND SCOPE:"name"::STRING = 'aigateway/tracing'
        GROUP BY 1
    )
    SELECT x.*, s.GATEWAY_MS, e.PROMPT, e.CATEGORY, e.INTENT
    FROM OPTIMIZATION_RESULTS x
    LEFT JOIN spans s USING (TRACE_ID)
    JOIN EVAL_PROMPTS e USING (PROMPT_ID)
    WHERE x.RUN_ID IN ('{b_id}', '{c_id}')
    """,
    ttl=0,
)
for col in ("LATENCY_MS", "INPUT_TOKENS", "OUTPUT_TOKENS", "JUDGE_SCORE", "GATEWAY_MS"):
    res[col] = pd.to_numeric(res[col], errors="coerce")


def _detail(v):
    if isinstance(v, dict):
        return v
    try:
        return json.loads(v) if isinstance(v, str) else {}
    except json.JSONDecodeError:
        return {}


details = res["JUDGE_DETAIL"].map(_detail) if "JUDGE_DETAIL" in res else pd.Series([{}] * len(res))
for crit in RUBRIC_WEIGHTS:
    res[crit] = pd.to_numeric(details.map(lambda d: d.get(crit)), errors="coerce")
res["RATIONALE"] = details.map(lambda d: d.get("rationale"))
res["AGREEMENT"] = pd.to_numeric(details.map(lambda d: d.get("agreement")), errors="coerce")


def summarize(run_id):
    r = res[res["RUN_ID"] == run_id]
    ok = r[r["STATUS"] == "OK"]
    model = cfg.loc[run_id, "MODEL"]
    cost = ok.apply(lambda x: estimate_credits(model, x["INPUT_TOKENS"], x["OUTPUT_TOKENS"], rates), axis=1)
    return {
        "Quality (judge)": ok["JUDGE_SCORE"].mean(),
        "p50 latency ms": ok["LATENCY_MS"].median(),
        "p95 latency ms": ok["LATENCY_MS"].quantile(0.95),
        "Avg output tokens": ok["OUTPUT_TOKENS"].mean(),
        "Credits / 1k req": 1000 * cost.mean() if len(cost) and cost.notna().all() else None,
        "Error rate %": 100 * (1 - len(ok) / len(r)) if len(r) else None,
    }


b, c = summarize(b_id), summarize(c_id)
lower_is_better = {"p50 latency ms", "p95 latency ms", "Avg output tokens",
                   "Credits / 1k req", "Error rate %"}

with st.container(border=True):
    cols = st.columns(len(b))
    for col, key in zip(cols, b):
        bv, cv = b[key], c[key]
        if pd.isna(cv):
            col.metric(key, "-")
            continue
        delta = None if pd.isna(bv) else cv - bv
        fmt = "{:.2f}" if key in ("Quality (judge)", "Credits / 1k req") else "{:,.0f}"
        col.metric(key, fmt.format(cv),
                   delta=None if delta is None else fmt.format(delta),
                   delta_color="inverse" if key in lower_is_better else "normal",
                   help=f"Baseline: {fmt.format(bv) if not pd.isna(bv) else '-'}")

st.caption(
    f"Baseline `{cfg.loc[b_id, 'MODEL']}` / max_tokens {cfg.loc[b_id, 'MAX_TOKENS']}  ->  "
    f"Candidate `{cfg.loc[c_id, 'MODEL']}` / max_tokens {cfg.loc[c_id, 'MAX_TOKENS']}. "
    "Credits use per-model rates fitted from this account's AI_GATEWAY_USAGE_HISTORY."
)

# Is the quality change real? Paired bootstrap over the prompts both runs answered.
qb = res[res.RUN_ID == b_id].set_index("PROMPT_ID")["JUDGE_SCORE"]
qc = res[res.RUN_ID == c_id].set_index("PROMPT_ID")["JUDGE_SCORE"]
ci = paired_bootstrap_ci(qb, qc)
crit_rows = []
for crit, w in RUBRIC_WEIGHTS.items():
    bv = res.loc[res.RUN_ID == b_id, crit].mean()
    cv = res.loc[res.RUN_ID == c_id, crit].mean()
    crit_rows.append({"Criterion": crit, "Weight": w, "Baseline": bv, "Candidate": cv, "Delta": cv - bv})
with st.container(border=True):
    q1, q2 = st.columns([2, 3])
    if ci:
        mean, lo, hi = ci
        q1.metric("Quality delta (95% CI)", f"{mean:+.3f}", help="Paired bootstrap over shared prompts")
        q1.caption(f"CI [{lo:+.3f}, {hi:+.3f}] over {int(pd.concat([qb, qc], axis=1).dropna().shape[0])} prompts")
    else:
        q1.metric("Quality delta (95% CI)", "-")
        q1.caption("Needs at least 3 prompts judged in both runs.")
    q2.dataframe(pd.DataFrame(crit_rows).round(3), hide_index=True, use_container_width=True)
    agree = res.loc[res.RUN_ID.isin([b_id, c_id]), "AGREEMENT"].dropna()
    if not agree.empty:
        q2.caption(f"Two-judge agreement: {agree.mean():.2f} (1.0 = identical scores)")

# Projected saving at the current gateway volume
usage_df = st.session_state.get("usage_df")
b_cost, c_cost = b["Credits / 1k req"], c["Credits / 1k req"]
if usage_df is not None and not usage_df.empty and b_cost and c_cost:
    span_days = max((usage_df["START_TIME"].max() - usage_df["START_TIME"].min()).days, 1)
    monthly_req = len(usage_df) / span_days * 30
    saving = (b_cost - c_cost) / 1000 * monthly_req
    st.info(f"At the current volume (~{monthly_req:,.0f} gateway requests/month), the candidate "
            f"{'saves' if saving >= 0 else 'adds'} about **{abs(saving):,.2f} credits/month** "
            f"({abs(1 - c_cost / b_cost):.0%} {'less' if saving >= 0 else 'more'} per request).")

st.subheader("Per prompt")
wide = res.pivot_table(index=["PROMPT_ID", "PROMPT"], columns="RUN_ID",
                       values=["JUDGE_SCORE", "OUTPUT_TOKENS", "LATENCY_MS"]).reset_index()
wide.columns = [" ".join(str(p) for p in c if p).replace(b_id, "base").replace(c_id, "cand")
                for c in wide.columns]
st.dataframe(wide, hide_index=True, use_container_width=True)

with st.expander("Response side by side"):
    pid = st.selectbox("Prompt", sorted(res["PROMPT_ID"].unique()))
    s1, s2 = st.columns(2)
    for col, rid, name in ((s1, b_id, "Baseline"), (s2, c_id, "Candidate")):
        row = res[(res.RUN_ID == rid) & (res.PROMPT_ID == pid)]
        if not row.empty:
            r0 = row.iloc[0]
            col.markdown(f"**{name}** - score {r0['JUDGE_SCORE']}, answer trace `{str(r0['TRACE_ID'])[:12]}...`")
            col.write(r0["RESPONSE"])
            if isinstance(r0.get("RATIONALE"), str):
                col.caption(f"Judge: {r0['RATIONALE']}  (judge trace `{str(r0.get('JUDGE_TRACE_ID'))[:12]}...`)")

# ---------------------------------------------------------------------------
# Route by intent: cheapest model within 0.05 of the best quality per intent
# ---------------------------------------------------------------------------
st.subheader("Route by intent")
allres = conn.query(
    """SELECT x.RUN_ID, r.MODEL, e.INTENT, x.JUDGE_SCORE, x.INPUT_TOKENS, x.OUTPUT_TOKENS
       FROM OPTIMIZATION_RESULTS x JOIN OPTIMIZATION_RUNS r USING (RUN_ID) JOIN EVAL_PROMPTS e USING (PROMPT_ID)
       WHERE x.STATUS = 'OK' AND x.JUDGE_SCORE IS NOT NULL""", ttl=0)
if allres.empty or allres["MODEL"].nunique() < 2:
    st.caption("Run experiments on at least two models to compare them per intent.")
else:
    for col in ("JUDGE_SCORE", "INPUT_TOKENS", "OUTPUT_TOKENS"):
        allres[col] = pd.to_numeric(allres[col], errors="coerce")
    allres["CREDITS"] = allres.apply(lambda x: estimate_credits(x["MODEL"], x["INPUT_TOKENS"], x["OUTPUT_TOKENS"], rates), axis=1)
    grid = (allres.groupby(["INTENT", "MODEL"])
            .agg(QUALITY=("JUDGE_SCORE", "mean"), N=("JUDGE_SCORE", "size"),
                 CREDITS_PER_1K=("CREDITS", lambda s: 1000 * s.mean() if s.notna().all() else None))
            .reset_index())
    routes = []
    for intent, g in grid.groupby("INTENT"):
        ok = g[g["QUALITY"] >= g["QUALITY"].max() - 0.05]
        pick = ok.sort_values("CREDITS_PER_1K", na_position="last").iloc[0]
        routes.append({"INTENT": intent, "ROUTE_TO": pick["MODEL"], "QUALITY": round(pick["QUALITY"], 3),
                       "CREDITS_PER_1K": pick["CREDITS_PER_1K"], "MODELS_TESTED": len(g), "N": int(g["N"].sum())})
    routes = pd.DataFrame(routes)
    st.dataframe(routes, hide_index=True, use_container_width=True)
    with st.expander("Quality vs cost by intent and model"):
        st.dataframe(grid.round(3), hide_index=True, use_container_width=True)
    st.markdown("Client-side routing table to ship with the promoted config:")
    st.code("ROUTES = {\n" + "\n".join(f'    "{r.INTENT}": "{r.ROUTE_TO}",' for r in routes.itertuples())
            + "\n}\nmodel = ROUTES.get(classify_intent(question), DEFAULT_MODEL)", language="python")

# ---------------------------------------------------------------------------
# Cost of optimization: the optimizer is AI traffic too, governed by the same gateway
# ---------------------------------------------------------------------------
st.subheader("Cost of optimization")
pair = pair_of(c_id)
root = pair[4:] if pair.startswith("hold") else pair
opt_calls = conn.query(
    f"""SELECT ROLE, MODEL, COUNT(*) AS CALLS, SUM(INPUT_TOKENS) AS INPUT_TOKENS,
               SUM(OUTPUT_TOKENS) AS OUTPUT_TOKENS, MEDIAN(LATENCY_MS) AS P50_MS,
               COUNT_IF(STATUS <> 'OK') AS ERRORS
        FROM OPTIMIZER_CALLS
        WHERE RUN_ID IN ('{b_id}', '{c_id}') OR RUN_ID LIKE '%{root}'
        GROUP BY 1, 2 ORDER BY 1""", ttl=0)
replay = conn.query(
    f"""SELECT r.MODEL, SUM(x.INPUT_TOKENS) AS INPUT_TOKENS, SUM(x.OUTPUT_TOKENS) AS OUTPUT_TOKENS
        FROM OPTIMIZATION_RESULTS x JOIN OPTIMIZATION_RUNS r USING (RUN_ID)
        WHERE x.RUN_ID IN ('{b_id}', '{c_id}') OR x.RUN_ID LIKE '%{root}'
        GROUP BY 1""", ttl=0)


def _credits(frame):
    if frame.empty:
        return 0.0, False
    vals = frame.apply(lambda x: estimate_credits(x["MODEL"], pd.to_numeric(x["INPUT_TOKENS"]),
                                                  pd.to_numeric(x["OUTPUT_TOKENS"]), rates), axis=1)
    return float(vals.fillna(0).sum()), bool(vals.isna().any())


opt_cr, opt_missing = _credits(opt_calls)
rep_cr, rep_missing = _credits(replay)
k1, k2, k3 = st.columns(3)
k1.metric("Optimizer calls (diagnose / propose / judge)", f"{int(opt_calls['CALLS'].sum()) if not opt_calls.empty else 0}",
          help="Every one went through the AI Gateway with its own traceparent")
k2.metric("Experiment cost", f"{opt_cr + rep_cr:.3f} credits",
          help=f"Optimizer calls {opt_cr:.3f} + eval replays {rep_cr:.3f}")
if usage_df is not None and not usage_df.empty and b_cost and c_cost and b_cost > c_cost:
    daily_saving = (b_cost - c_cost) / 1000 * monthly_req / 30
    k3.metric("Payback", f"{(opt_cr + rep_cr) / daily_saving:.1f} days" if daily_saving else "-",
              help="Experiment cost / projected daily saving at current volume")
else:
    k3.metric("Payback", "-", help="Shown when the candidate is cheaper per request")
if opt_missing or rep_missing:
    st.caption("Some models have no fitted rate yet, so their calls are excluded from credits.")
if not opt_calls.empty:
    st.dataframe(opt_calls, hide_index=True, use_container_width=True)
gw = conn.query(
    """SELECT SPLIT_PART(RECORD_ATTRIBUTES:"gen_ai.conversation.id"::STRING, '-', 2) AS ROLE,
              COUNT(*) AS GATEWAY_SPANS, COUNT(DISTINCT TRACE:"trace_id"::STRING) AS TRACES
       FROM TABLE(AGENT_TRACE_TABLE('SNOWFLAKE'))
       WHERE TIMESTAMP > DATEADD('day', -7, CURRENT_TIMESTAMP())
         AND RECORD_ATTRIBUTES:"gen_ai.conversation.id"::STRING LIKE 'optimizer-%'
       GROUP BY 1 ORDER BY 1""", ttl=0)
st.caption("Gateway-side view: optimizer spans in AGENT_TRACE_TABLE over the last 7 days, by role "
           "(conversation id `optimizer-<role>-<run>`). Filter the Trace explorer on these to open one.")
st.dataframe(gw, hide_index=True, use_container_width=True)

# ---------------------------------------------------------------------------
# Promote
# ---------------------------------------------------------------------------
st.subheader("Promote")
# With a CI, require its lower bound above -0.05 (no evidence of a real quality loss).
if ci:
    quality_ok = ci[1] >= -0.05
    wide_ci = (ci[2] - ci[1]) > 0.4
else:
    quality_ok = not pd.isna(c["Quality (judge)"]) and (
        pd.isna(b["Quality (judge)"]) or c["Quality (judge)"] >= b["Quality (judge)"] - 0.05)
    wide_ci = True
if b_cost and c_cost:
    cheaper = c_cost < b_cost
else:  # no fitted rate for a model: compare output tokens instead
    cheaper = not pd.isna(c["Avg output tokens"]) and not pd.isna(b["Avg output tokens"]) \
        and c["Avg output tokens"] < b["Avg output tokens"]

if wide_ci:
    st.caption("Not enough evidence for a confident call: the CI is wide or missing. Add prompts and rerun.")
if quality_ok and cheaper:
    st.success("Candidate holds quality (95% CI lower bound above -0.05) at lower cost: promote it.")
elif quality_ok:
    st.info("Candidate holds quality but is not cheaper. Promote only if latency matters more.")
else:
    st.warning("Candidate loses quality. Keep the baseline, or iterate on the candidate.")

model = cfg.loc[c_id, "MODEL"]
st.markdown("**1. Application config** - ship the candidate settings in the client:")
st.code(
    f'llm = ChatOpenAI(model="{model}", base_url=GATEWAY_URL, api_key=PAT,\n'
    f'                 max_tokens={cfg.loc[c_id, "MAX_TOKENS"]})\n'
    f'SYSTEM_PROMPT = """{cfg.loc[c_id, "SYSTEM_PROMPT"]}"""',
    language="python",
)
st.markdown("**2. Gateway guardrail** - pin the allowlist to the promoted model "
            "(run as ACCOUNTADMIN; the spec is replaced as a whole):")
# Keep the baseline model allowed during rollout only if it differs from the promoted one
allow = f"  - name: '{model}'"
base_model = cfg.loc[b_id, "MODEL"]
if base_model != model:
    allow += f"\n  - name: '{base_model}'   # baseline: remove after rollout"
st.code(
    f"""ALTER AI GATEWAY SNOWFLAKE FROM SPECIFICATION $$
schema_version: 1
models:
{allow}
logging:
  enabled: true
  enable_client_telemetry: true
  capture_payload:
    request_response: true
$$;""",
    language="sql",
)
st.markdown("**3. Cost guardrail** - cap per-user gateway spend:")
st.code(
    """CREATE SNOWFLAKE.CORE.QUOTA CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.GATEWAY_USER_QUOTA();
CALL CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.GATEWAY_USER_QUOTA!ADD_SHARED_RESOURCE('AI GATEWAY');
CALL CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.GATEWAY_USER_QUOTA!SET_PER_USER_LIMIT(5, 'DAILY');
CALL CORTEX_GATEWAY_MEDTECH_LAB.PUBLIC.GATEWAY_USER_QUOTA!SET_BLOCK_ENFORCEMENT_ENABLED(TRUE, FALSE);""",
    language="sql",
)
st.caption("Then return to Overview: new traffic on the promoted config closes the loop.")
