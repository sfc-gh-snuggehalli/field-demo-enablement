import uuid

import pandas as pd
import streamlit as st

from gateway_client import chat, new_traceparent
from optimize_config import MODELS, config

st.header("Experiments")
st.caption(
    "Replay a fixed eval set through the gateway with a baseline and a candidate "
    "config. Every call carries a traceparent, so each result links back to its "
    "gateway trace. Answers are scored 0-1 by an LLM judge against the expected answer."
)

conn = st.session_state["conn"]
session = conn.session()

JUDGE_MODEL = "claude-sonnet-4-5"
FIELDS = (("model", "m"), ("max_tokens", "t"), ("system_prompt", "s"))

# Facts the model needs; the eval measures answer quality, not retrieval.
CONTEXT_SQL = """
SELECT LISTAGG(CHANNEL || ': spend $' || TO_VARCHAR(S, 'FM999,999,990') ||
               ', revenue $' || TO_VARCHAR(R, 'FM999,999,990') ||
               ', conversions ' || C || ', Q4 revenue $' || TO_VARCHAR(Q4, 'FM999,999,990'), '; ')
FROM (SELECT CHANNEL, SUM(SPEND) S, SUM(REVENUE) R, SUM(CONVERSIONS) C,
             SUM(IFF(MONTH >= '2024-10-01', REVENUE, 0)) Q4
      FROM CAMPAIGN_SPEND GROUP BY CHANNEL)
"""


@st.cache_data(ttl="1h")
def load_eval() -> pd.DataFrame:
    return conn.query("SELECT * FROM EVAL_PROMPTS ORDER BY PROMPT_ID", ttl="1h")


@st.cache_data(ttl="1h")
def load_context() -> str:
    data = session.sql(CONTEXT_SQL).collect()[0][0]
    docs = session.sql("SELECT LISTAGG(TITLE || ': ' || CONTENT, '\\n') FROM STRATEGY_DOCS").collect()[0][0]
    return f"2024 channel data -> {data}\n\nStrategy documents:\n{docs}"


eval_df = load_eval()

# An Advisor seed is applied once: written straight into widget state (so it
# wins over any values left from an earlier visit), then consumed.
seed = st.session_state.pop("experiment_seed", None)
if seed:
    for label in ("Baseline", "Candidate"):
        cfg = seed[label.lower()]
        for field, suffix in FIELDS:
            st.session_state[f"{label}_{suffix}"] = cfg[field]
    st.session_state["exp_finding"] = seed["finding"]
    st.session_state["exp_seeded_configs"] = {"Baseline": seed["baseline"],
                                             "Candidate": seed["candidate"]}
    unknown = {seed["baseline"]["model"], seed["candidate"]["model"]} - set(MODELS)
    st.session_state["exp_unknown_models"] = sorted(unknown)

for label in ("Baseline", "Candidate"):  # first visit: neutral defaults
    for field, suffix in FIELDS:
        st.session_state.setdefault(f"{label}_{suffix}", config()[field])

finding = st.session_state.get("exp_finding")
if finding:
    f1, f2 = st.columns([5, 1])
    f1.info(f"Seeded from Advisor finding: **{finding}**")
    if f2.button("Clear finding", use_container_width=True):
        st.session_state.pop("exp_finding", None)
        st.session_state.pop("exp_seeded_configs", None)
        st.rerun()
for m in st.session_state.pop("exp_unknown_models", []):
    st.warning(f"`{m}` from the traces is not callable through the gateway here; "
               f"pick a supported model.")


def config_form(col, label):
    for field, suffix in FIELDS:  # fall back if a stale value is no longer valid
        if field == "model" and st.session_state[f"{label}_{suffix}"] not in MODELS:
            st.session_state[f"{label}_{suffix}"] = MODELS[0]
    with col.container(border=True):
        st.markdown(f"**{label}**")
        model = st.selectbox("Model", MODELS, key=f"{label}_m")
        max_tokens = st.number_input("max_tokens", 16, 4096, step=50, key=f"{label}_t")
        system = st.text_area("System prompt", key=f"{label}_s", height=110)
    return {"model": model, "max_tokens": int(max_tokens), "system_prompt": system}


c1, c2 = st.columns(2)
baseline = config_form(c1, "Baseline")
candidate = config_form(c2, "Candidate")

# The finding labels the runs only while the configs are still the ones it seeded.
seeded = st.session_state.get("exp_seeded_configs")
if finding and seeded and seeded != {"Baseline": baseline, "Candidate": candidate}:
    st.caption("Configs edited since seeding: runs will not be tagged with the finding.")
    finding = None
if baseline == candidate:
    st.warning("Baseline and candidate are identical: the experiment cannot show a difference.")

picked = st.multiselect(
    "Eval prompts", eval_df["PROMPT_ID"].tolist(), default=eval_df["PROMPT_ID"].tolist()[:8],
    format_func=lambda p: f"{p} - {eval_df.set_index('PROMPT_ID').loc[p, 'PROMPT'][:60]}",
)

JUDGE_SQL = f"""
UPDATE OPTIMIZATION_RESULTS r
SET JUDGE_SCORE = TRY_TO_DOUBLE(REGEXP_SUBSTR(AI_COMPLETE('{JUDGE_MODEL}',
    'Score how well the RESPONSE answers the QUESTION compared with the EXPECTED answer. '
    || 'Return only a number between 0 and 1 (1 = fully correct and complete, 0 = wrong). '
    || 'QUESTION: ' || e.PROMPT || ' EXPECTED: ' || e.EXPECTED || ' RESPONSE: ' || r.RESPONSE),
    '[01](\\\\.[0-9]+)?'))
FROM EVAL_PROMPTS e
WHERE r.PROMPT_ID = e.PROMPT_ID AND r.RUN_ID = ? AND r.STATUS = 'OK'
"""


def run_config(label: str, cfg: dict, prompts: pd.DataFrame, progress, offset: int, total: int,
               pair: str) -> str:
    # Both runs of one experiment share the suffix, which is how Before/After pairs them.
    run_id = f"{label}-{pair}"
    session.sql(
        "INSERT INTO OPTIMIZATION_RUNS (RUN_ID, LABEL, MODEL, SYSTEM_PROMPT, MAX_TOKENS, SOURCE_FINDING) "
        "VALUES (?, ?, ?, ?, ?, ?)",
        params=[run_id, label, cfg["model"], cfg["system_prompt"], cfg["max_tokens"],
                finding],
    ).collect()
    context = load_context()
    rows = []
    for i, p in enumerate(prompts.itertuples()):
        traceparent, trace_id = new_traceparent()
        res = chat(f"{context}\n\nQuestion: {p.PROMPT}", cfg["model"],
                   system=cfg["system_prompt"], max_tokens=cfg["max_tokens"],
                   traceparent=traceparent, conversation_id=run_id)
        rows.append([run_id, p.PROMPT_ID, trace_id, res.content[:16000],
                     round(res.latency_ms), res.input_tokens, res.output_tokens,
                     "OK" if res.ok else f"HTTP {res.status_code}"])
        progress.progress((offset + i + 1) / total, f"{label}: {p.PROMPT_ID}")
    for r in rows:
        session.sql(
            "INSERT INTO OPTIMIZATION_RESULTS (RUN_ID, PROMPT_ID, TRACE_ID, RESPONSE, LATENCY_MS, "
            "INPUT_TOKENS, OUTPUT_TOKENS, STATUS) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", params=r,
        ).collect()
    session.sql(JUDGE_SQL, params=[run_id]).collect()
    return run_id


if st.button(":material/play_arrow: Run experiment", type="primary", disabled=not picked):
    prompts = eval_df[eval_df["PROMPT_ID"].isin(picked)]
    total = 2 * len(prompts)
    bar = st.progress(0.0, "Starting...")
    pair = uuid.uuid4().hex[:8]
    b_id = run_config("baseline", baseline, prompts, bar, 0, total, pair)
    c_id = run_config("candidate", candidate, prompts, bar, len(prompts), total, pair)
    bar.empty()
    st.session_state["compare_runs"] = (b_id, c_id)
    st.success(f"Runs complete: `{b_id}` vs `{c_id}`")
    st.page_link("app_pages/compare.py", label="See before / after", icon=":material/compare_arrows:")

st.subheader("Recent runs")
runs = conn.query(
    """SELECT r.RUN_ID, r.LABEL, r.MODEL, r.MAX_TOKENS, r.CREATED_AT, r.SOURCE_FINDING,
              COUNT(x.PROMPT_ID) AS PROMPTS, ROUND(AVG(x.JUDGE_SCORE), 2) AS AVG_SCORE
       FROM OPTIMIZATION_RUNS r LEFT JOIN OPTIMIZATION_RESULTS x USING (RUN_ID)
       GROUP BY ALL ORDER BY r.CREATED_AT DESC LIMIT 20""",
    ttl=0,
)
st.dataframe(runs, hide_index=True, use_container_width=True)
