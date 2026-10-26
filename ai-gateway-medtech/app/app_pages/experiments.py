import uuid

import pandas as pd
import streamlit as st

from gateway_client import auth_hint, chat, new_traceparent
from optimize_config import MODELS, config
from optimizer import JUDGE_MODELS, judge_run, propose_prompts, split_dev_holdout

st.header("Experiments")
st.caption(
    "Replay a fixed eval set through the gateway with a baseline and a candidate "
    "config. Every call carries a traceparent, so each result links back to its "
    "gateway trace. A rubric judge (correctness, completeness, conciseness, compliance) scores each "
    "answer 0-1; the judge also runs through the gateway, so its calls are traced and costed too."
)

conn = st.session_state["conn"]
session = conn.session()

FIELDS = (("model", "m"), ("max_tokens", "t"), ("system_prompt", "s"))

# Facts the model needs; the eval measures answer quality, not retrieval.
CONTEXT_SQL = {
    "Fiscal 2026 totals (Oct 2025 - Sep 2026)": """
SELECT 'net revenue $' || TO_VARCHAR(ROUND(SUM(NET_REVENUE)), 'FM999,999,999,999') || ', units ' || SUM(UNITS)
FROM FACT_SALES_ORDERS""",
    "Net revenue by therapy area": """
SELECT LISTAGG(THERAPY_AREA || ' $' || TO_VARCHAR(ROUND(R), 'FM999,999,999,999'), '; ')
FROM (SELECT f.THERAPY_AREA, SUM(o.NET_REVENUE) R
      FROM FACT_SALES_ORDERS o JOIN DIM_PRODUCT_FAMILY f USING (FAMILY_ID) GROUP BY 1)""",
    "Quota attainment": """
SELECT 'overall ' || TO_VARCHAR(ROUND(100 * SUM(ACTUAL_REVENUE) / SUM(QUOTA_AMOUNT), 1)) || '%'
FROM FACT_QUOTA_ATTAINMENT""",
    "Procedure share and competitive conversions": """
SELECT 'our procedure share ' || TO_VARCHAR(ROUND(100 * COUNT_IF(USED_OUR_DEVICE) / COUNT(*), 1)) || '%; conversions to competitor: ' ||
       (SELECT LISTAGG(COMPETITOR || ' ' || N, ', ') FROM (SELECT COMPETITOR, COUNT(*) N FROM FACT_COMPETITIVE_EVENTS
        WHERE EVENT_TYPE = 'Converted to Competitor' GROUP BY 1))
FROM FACT_PROCEDURES""",
    "Consigned units within 90 days of expiry (2026-09-30)": """
SELECT TO_VARCHAR(SUM(UNITS_EXPIRING_90D)) FROM FACT_CONSIGNMENT_INVENTORY WHERE SNAPSHOT_DATE = '2026-09-30'""",
    "Share-loss model scores": """
SELECT SUM(SHARE_LOSS_PREDICTION) || ' accounts predicted at risk; avg score by region: ' ||
       (SELECT LISTAGG(REGION || ' ' || TO_VARCHAR(ROUND(S, 2)), ', ') FROM (SELECT a.REGION, AVG(p.SHARE_LOSS_SCORE) S
        FROM SHARE_LOSS_PREDICTIONS p JOIN DIM_ACCOUNT a USING (ACCOUNT_ID) GROUP BY 1)) ||
       '; academic medical centers at risk: ' ||
       (SELECT TO_VARCHAR(ROUND(100 * SUM(SHARE_LOSS_PREDICTION) / COUNT(*), 1)) || '%' FROM SHARE_LOSS_PREDICTIONS p
        JOIN DIM_ACCOUNT a USING (ACCOUNT_ID) WHERE a.ACCOUNT_TYPE = 'Academic Medical Center')
FROM SHARE_LOSS_PREDICTIONS""",
    "Product knowledge (labeling, evidence, policy)": """
SELECT LISTAGG(TITLE || ': ' || BODY, ' || ') FROM PRODUCT_KNOWLEDGE_DOCS
WHERE DOC_ID IN ('IFU-F08', 'IFU-F11', 'CLIN-F05', 'BC-F01', 'POL-TIER', 'POL-CONSIGN', 'FAN-TORQUE-2026')""",
}


@st.cache_data(ttl="1h")
def load_eval() -> pd.DataFrame:
    return conn.query("SELECT * FROM EVAL_PROMPTS ORDER BY PROMPT_ID", ttl="1h")


@st.cache_data(ttl="1h")
def load_context() -> str:
    return "\n".join(f"{title}: {session.sql(sql).collect()[0][0]}"
                     for title, sql in CONTEXT_SQL.items())


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
    "Eval prompts", eval_df["PROMPT_ID"].tolist(),
    # A spread across metric, ML, knowledge and definition intents
    default=[p for p in ("P01", "P04", "P07", "P10", "P11", "P12", "P15", "P17") if p in set(eval_df["PROMPT_ID"])],
    format_func=lambda p: f"{p} - {eval_df.set_index('PROMPT_ID').loc[p, 'PROMPT'][:60]}",
)

second_judge = st.toggle(
    f"Second judge ({JUDGE_MODELS[1]})", value=False,
    help="Score every answer with a second model from another provider and report judge agreement.")
judges = JUDGE_MODELS if second_judge else JUDGE_MODELS[:1]


def run_config(label: str, cfg: dict, prompts: pd.DataFrame, progress, offset: int, total: int,
               pair: str, source: str | None = None, optimizer_trace: str | None = None) -> str | None:
    # Both runs of one experiment share the suffix, which is how Before/After pairs them.
    run_id = f"{label}-{pair}"
    session.sql(
        "INSERT INTO OPTIMIZATION_RUNS (RUN_ID, LABEL, MODEL, SYSTEM_PROMPT, MAX_TOKENS, SOURCE_FINDING, "
        "OPTIMIZER_TRACE_ID) VALUES (?, ?, ?, ?, ?, ?, ?)",
        params=[run_id, label, cfg["model"], cfg["system_prompt"], cfg["max_tokens"],
                source if source is not None else finding, optimizer_trace],
    ).collect()
    context = load_context()
    rows = []
    for i, p in enumerate(prompts.itertuples()):
        traceparent, trace_id = new_traceparent()
        res = chat(f"{context}\n\nQuestion: {p.PROMPT}", cfg["model"],
                   system=cfg["system_prompt"], max_tokens=cfg["max_tokens"],
                   traceparent=traceparent, conversation_id=run_id)
        if res.status_code == 401:
            # Every later call would fail the same way, so drop this run and say why
            session.sql("DELETE FROM OPTIMIZATION_RUNS WHERE RUN_ID = ?", params=[run_id]).collect()
            progress.empty()
            st.error(f"HTTP 401 from the gateway on {p.PROMPT_ID}; the {label} run was not saved.")
            if hint := auth_hint(res):
                st.info(hint)
            return None
        rows.append([run_id, p.PROMPT_ID, trace_id, res.content[:16000],
                     round(res.latency_ms), res.input_tokens, res.output_tokens,
                     "OK" if res.ok else f"HTTP {res.status_code}"])
        progress.progress((offset + i + 1) / total, f"{label}: {p.PROMPT_ID}")
    for r in rows:
        session.sql(
            "INSERT INTO OPTIMIZATION_RESULTS (RUN_ID, PROMPT_ID, TRACE_ID, RESPONSE, LATENCY_MS, "
            "INPUT_TOKENS, OUTPUT_TOKENS, STATUS) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", params=r,
        ).collect()
    ok = pd.DataFrame(rows, columns=["RUN_ID", "PROMPT_ID", "TRACE_ID", "RESPONSE", "LATENCY_MS",
                                     "INPUT_TOKENS", "OUTPUT_TOKENS", "STATUS"])
    ok = ok[ok["STATUS"] == "OK"].merge(prompts[["PROMPT_ID", "PROMPT", "EXPECTED", "CATEGORY"]], on="PROMPT_ID")
    if not ok.empty:
        progress.progress((offset + len(prompts)) / total, f"{label}: judging through the gateway")
        judge_run(session, run_id, ok, judges)
    return run_id


def run_score(run_id: str) -> float | None:
    v = session.sql("SELECT AVG(JUDGE_SCORE) FROM OPTIMIZATION_RESULTS WHERE RUN_ID = ?",
                    params=[run_id]).collect()[0][0]
    return None if v is None else float(v)


if st.button(":material/play_arrow: Run experiment", type="primary", disabled=not picked):
    prompts = eval_df[eval_df["PROMPT_ID"].isin(picked)]
    total = 2 * len(prompts)
    bar = st.progress(0.0, "Starting...")
    pair = uuid.uuid4().hex[:8]
    b_id = run_config("baseline", baseline, prompts, bar, 0, total, pair)
    c_id = run_config("candidate", candidate, prompts, bar, len(prompts), total, pair) if b_id else None
    bar.empty()
    if b_id and c_id:
        st.session_state["compare_runs"] = (b_id, c_id)
        st.success(f"Runs complete: `{b_id}` vs `{c_id}`")
        st.page_link("app_pages/compare.py", label="See before / after", icon=":material/compare_arrows:")
    elif b_id:
        st.warning(f"The baseline run `{b_id}` was saved, with no candidate run to compare it to.")

# ---------------------------------------------------------------------------
# Prompt optimizer: propose system prompts from the weakest answers, pick the best on a
# dev split, then confirm it against the baseline on held-out prompts.
# ---------------------------------------------------------------------------
with st.expander(":material/auto_fix_high: Prompt optimizer (LLM-proposed system prompts)"):
    st.caption(
        "Reads the lowest-scoring answers of a run and their judge rationales, asks "
        "`claude-sonnet-4-5` (through the gateway) for improved system prompts, scores each on a "
        "dev split of the selected prompts, then reruns the winner against the baseline on the "
        "held-out split. The confirmation pair opens on Before / after."
    )
    base_runs = conn.query(
        "SELECT r.RUN_ID FROM OPTIMIZATION_RUNS r JOIN OPTIMIZATION_RESULTS x USING (RUN_ID) "
        "WHERE x.JUDGE_SCORE IS NOT NULL GROUP BY 1, r.CREATED_AT ORDER BY r.CREATED_AT DESC LIMIT 20", ttl=0)
    if base_runs.empty:
        st.info("Run an experiment first: the optimizer learns from a judged run.")
    else:
        src_run = st.selectbox("Learn from run", base_runs["RUN_ID"].tolist())
        n_cand = st.slider("Candidate prompts", 1, 3, 2)
        if st.button(":material/auto_fix_high: Optimize the system prompt", disabled=len(picked) < 4):
            src_cfg = session.sql("SELECT MODEL, MAX_TOKENS, SYSTEM_PROMPT FROM OPTIMIZATION_RUNS WHERE RUN_ID = ?",
                                  params=[src_run]).collect()[0].as_dict()
            weak = conn.query(
                f"""SELECT x.PROMPT_ID, e.PROMPT, e.EXPECTED, x.RESPONSE, x.JUDGE_SCORE, x.JUDGE_DETAIL
                    FROM OPTIMIZATION_RESULTS x JOIN EVAL_PROMPTS e USING (PROMPT_ID)
                    WHERE x.RUN_ID = '{src_run}' AND x.JUDGE_SCORE IS NOT NULL
                    ORDER BY x.JUDGE_SCORE LIMIT 4""", ttl=0)
            pair = uuid.uuid4().hex[:8]
            with st.status("Optimizing through the gateway...", expanded=True) as status:
                st.write("Proposing candidate system prompts...")
                cands, prop_trace = propose_prompts(session, f"opt-{pair}", src_cfg["SYSTEM_PROMPT"], weak, n_cand)
                if not cands:
                    status.update(label="The optimizer returned no usable prompts.", state="error")
                    st.stop()
                st.write(f"{len(cands)} candidates. Proposal trace `{prop_trace}`.")
                dev_ids, hold_ids = split_dev_holdout(picked)
                dev = eval_df[eval_df["PROMPT_ID"].isin(dev_ids)]
                hold = eval_df[eval_df["PROMPT_ID"].isin(hold_ids)]
                bar = st.progress(0.0)
                scores = []
                for k, c in enumerate(cands, 1):
                    cfg_k = {"model": src_cfg["MODEL"], "max_tokens": int(src_cfg["MAX_TOKENS"]),
                             "system_prompt": c["system_prompt"]}
                    rid = run_config(f"promptopt{k}", cfg_k, dev, bar, 0, len(dev), pair,
                                     source="prompt-optimizer (dev)", optimizer_trace=prop_trace)
                    scores.append((run_score(rid) if rid else None, k, cfg_k, c.get("rationale", "")))
                    st.write(f"Candidate {k}: dev score {scores[-1][0]}")
                scores = [s for s in scores if s[0] is not None]
                if not scores:
                    status.update(label="No candidate could be scored.", state="error")
                    st.stop()
                best_score, best_k, best_cfg, why = max(scores, key=lambda s: s[0])
                st.write(f"Best on dev: candidate {best_k} ({best_score:.2f}). Confirming on {len(hold)} held-out prompts...")
                base_cfg = {"model": src_cfg["MODEL"], "max_tokens": int(src_cfg["MAX_TOKENS"]),
                            "system_prompt": src_cfg["SYSTEM_PROMPT"]}
                hb = run_config("baseline", base_cfg, hold, bar, 0, 2 * len(hold), f"hold{pair}",
                                source="prompt-optimizer (holdout)")
                hc = run_config("candidate", best_cfg, hold, bar, len(hold), 2 * len(hold), f"hold{pair}",
                                source="prompt-optimizer (holdout)", optimizer_trace=prop_trace)
                bar.empty()
                status.update(label="Prompt optimization complete", state="complete")
            if hb and hc:
                st.session_state["compare_runs"] = (hb, hc)
                st.success(f"Holdout: baseline {run_score(hb):.2f} vs optimized {run_score(hc):.2f}.")
                st.markdown(f"**Winning prompt** (candidate {best_k}): {best_cfg['system_prompt']}")
                st.caption(f"Why: {why}")
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
