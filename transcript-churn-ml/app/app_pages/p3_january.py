import json
from datetime import datetime

import pandas as pd
import streamlit as st

import common
from common import DB, STEPS

st.title("January's calls arrive")
st.markdown(
    "The call platform delivers a new month of recordings. The same pipeline picks up **only the new rows**: "
    "segments, redaction, embeddings, topics and price sentiment. History is not reprocessed or re-billed."
)

NEW = f"SELECT CALL_ID FROM {DB}.RAW.CALLS_NEW_MONTH"


def state() -> dict:
    """Where January stands, read from the data and the run log (never from this browser session)."""
    s = common.session()
    row = s.sql(f"""
    SELECT (SELECT COUNT(*) FROM {DB}.RAW.CALLS WHERE CALL_ID IN ({NEW})) AS RAW_CALLS,
           (SELECT COUNT(*) FROM {DB}.ML.SEGMENT_TOPICS WHERE CALL_ID IN ({NEW})) AS TOPICS,
           (SELECT COUNT(*) FROM {DB}.ANALYTICS.PRICE_SENTIMENT
             WHERE SEGMENT_ID IN (SELECT SEGMENT_ID FROM {DB}.ML.SEGMENT_TOPICS WHERE CALL_ID IN ({NEW}))) AS PRICE,
           (SELECT COUNT(*) FROM {DB}.CORE.SEGMENTS_REDACTED WHERE CALL_ID NOT IN ({NEW})) AS HISTORY,
           (SELECT COUNT(*) FROM {DB}.RAW.CALLS_NEW_MONTH) AS WAITING""").collect()[0]
    runs = s.sql(f"""
    SELECT RUN_ID, MIN(LOGGED_AT) AS STARTED,
           DATEDIFF('second', MAX(LOGGED_AT), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ) AS AGE_S,
           COUNT_IF(STEP = 'done') AS DONE, COUNT_IF(STEP = 'error') AS ERR
    FROM {DB}.ANALYTICS.LIVE_RUN_LOG WHERE RUN_ID IN (SELECT RUN_ID FROM {DB}.ANALYTICS.LIVE_RUN_LOG WHERE STEP = 'start')
    GROUP BY 1 ORDER BY STARTED DESC LIMIT 1""").to_pandas()
    run = runs.iloc[0] if not runs.empty else None
    # Same 15-minute window as LOAD_JANUARY's busy check; ages are computed in Snowflake, not on this host's clock.
    running = run is not None and run.DONE == 0 and run.ERR == 0 and run.AGE_S < 900
    return {"raw": int(row["RAW_CALLS"]), "topics": int(row["TOPICS"]), "price": int(row["PRICE"]),
            "history": int(row["HISTORY"]), "waiting": int(row["WAITING"]), "run": run, "running": running}


def run_log(run_id: str) -> pd.DataFrame:
    return common.session().sql(
        f"""SELECT STEP_NO, STEP, LABEL, ROWS_OUT, AI_CALLS, INPUT_TOKENS, SECONDS, DETAIL::STRING AS DETAIL, LOGGED_AT
            FROM {DB}.ANALYTICS.LIVE_RUN_LOG WHERE RUN_ID = ? ORDER BY STEP_NO, LOGGED_AT""", params=[run_id]).to_pandas()


def last_completed_run() -> str | None:
    df = common.session().sql(f"""SELECT MAX_BY(RUN_ID, LOGGED_AT) AS RUN_ID FROM {DB}.ANALYTICS.LIVE_RUN_LOG
                                  WHERE STEP = 'done'""").to_pandas()
    return None if df.empty or pd.isna(df.RUN_ID[0]) else df.RUN_ID[0]


def show_summary(run_id: str):
    log = run_log(run_id)
    steps = log[log.STEP_NO.between(1, 6)]
    if steps.empty:
        return
    started = log.LOGGED_AT.min()
    reprocessed = int(common.session().sql(
        f"""SELECT COUNT(*) FROM {DB}.CORE.SEGMENTS_REDACTED WHERE CALL_ID NOT IN ({NEW}) AND REDACTED_AT >= ?""",
        params=[started.to_pydatetime()]).collect()[0][0])
    seg = int(steps.loc[steps.STEP == "segments", "ROWS_OUT"].max())
    cols = st.columns(4)
    cols[0].metric("New segments processed", f"{seg:,}", border=True)
    cols[1].metric("History segments re-redacted", reprocessed, border=True)
    cols[2].metric("AI function calls", f"{int(steps.AI_CALLS.sum()):,}", border=True)
    cols[3].metric("End to end", f"{steps.SECONDS.sum():.0f} s", border=True)
    table = steps[["STEP_NO", "LABEL", "ROWS_OUT", "AI_CALLS", "SECONDS"]].rename(columns={
        "STEP_NO": "#", "LABEL": "Step", "ROWS_OUT": "Rows", "AI_CALLS": "AI function calls", "SECONDS": "Seconds"})
    st.dataframe(table, hide_index=True, alt="Live run steps",
                 column_config={"Seconds": st.column_config.NumberColumn(format="%.1f")})
    details = {r.STEP: json.loads(r.DETAIL) for r in steps.itertuples() if r.DETAIL}
    t, r = details.get("topics", {}), details.get("redact", {})
    st.caption(
        f"Redaction left {r.get('phones_left', 0)} phone numbers and {r.get('emails_left', 0)} email addresses. "
        f"Topics: {t.get('seeded', 0)} matched a business topic, {t.get('discovered', 0)} were placed by the "
        f"registered clustering model ({t.get('model_calls', 0)} model calls), {t.get('unassigned', 0)} unassigned. "
        f"Embedding input tokens: {int(steps.INPUT_TOKENS.sum()):,}."
    )


def start_run():
    run_id = "APP-" + datetime.now().strftime("%Y%m%d-%H%M%S")
    # Runs server-side: leaving or reloading this page does not stop it.
    common.session().sql(f"CALL {DB}.ANALYTICS.LOAD_JANUARY(?)", params=[run_id]).collect_nowait()
    st.session_state.live_run = run_id
    st.session_state.live_started = datetime.now()


@st.fragment(run_every="2s")
def progress(run_id: str):
    log = run_log(run_id)
    done = {r.STEP: r for r in log.itertuples()}
    if "error" in done:
        detail = json.loads(done["error"].DETAIL or "{}")
        st.session_state.live_error = f"Step '{detail.get('step')}' failed: {detail.get('message')}"
        st.session_state.live_run = None
        st.rerun(scope="app")
    if log.empty:
        if (datetime.now() - st.session_state.live_started).total_seconds() > 60:
            st.session_state.live_error = "The run did not start. Check the warehouse, then try again."
            st.session_state.live_run = None
            st.rerun(scope="app")
        st.caption("Starting...")
        return
    with st.container(border=True):
        for step, label in STEPS:
            if step in done:
                r = done[step]
                st.markdown(f":material/check_circle: **{label}**: {int(r.ROWS_OUT):,} rows in {r.SECONDS:.1f} s")
            else:
                st.markdown(f":material/hourglass_top: {label}")
    if "done" in done:
        st.session_state.live_run = None
        st.cache_data.clear()
        st.rerun(scope="app")


st.session_state.setdefault("live_run", None)
st.session_state.setdefault("live_error", None)
st.session_state.setdefault("live_started", datetime.now())
s = state()
complete = s["raw"] > 0 and s["topics"] > 0 and s["price"] > 0

if s["running"] or st.session_state.live_run:
    run_id = s["run"].RUN_ID if s["running"] else st.session_state.live_run
    st.info("Processing January. This keeps running even if you switch pages.", icon=":material/sync:")
    progress(run_id)
elif s["raw"] == 0:
    if st.session_state.live_error:
        st.error(st.session_state.live_error, icon=":material/error:")
    c1, c2 = st.columns(2)
    c1.metric("Segments already processed (Nov-Dec)", f"{s['history']:,}", border=True)
    c2.metric("January calls waiting", f"{s['waiting']:,}", border=True)
    if st.button("Load January's calls", icon=":material/play_arrow:", type="primary"):
        start_run()
        st.rerun()
    prior = last_completed_run()
    if prior:
        with st.expander("Last completed run (for reference)"):
            show_summary(prior)
elif not complete:
    st.warning("A January run stopped partway. Finishing it skips the steps that already completed.",
               icon=":material/warning:")
    if st.session_state.live_error:
        st.error(st.session_state.live_error, icon=":material/error:")
    if st.button("Finish loading January", icon=":material/play_arrow:", type="primary"):
        st.session_state.live_error = None
        start_run()
        st.rerun()
else:
    st.success("January is loaded. Pages 4 and 7 now include it; churn scores stay as of 1 January 2026.",
               icon=":material/check_circle:")
    prior = last_completed_run()
    if prior:
        st.subheader("What just ran")
        show_summary(prior)
    else:
        st.caption("January was loaded by the lab build. Reset it below to show the live step.")

with st.expander("Rehearsal controls"):
    st.caption("Removes January again (raw rows, redacted segments, topics and price sentiment) so the live step "
               "can be shown again.")
    if st.button("Reset January", icon=":material/restart_alt:", disabled=s["raw"] == 0 or s["running"]):
        with st.spinner("Removing January..."):
            res = common.call(f"CALL {DB}.ANALYTICS.DEMO_RESET_JANUARY()")
        if res is not None:
            st.session_state.live_run = None
            st.session_state.live_error = None
            st.cache_data.clear()
            st.rerun()

common.next_button(2)
