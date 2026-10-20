import streamlit as st

import common
from common import DB, q

st.title("Where the data stayed")
st.markdown(
    "The same scoring job, done two ways. The **round trip** pulls features out to a Python client and writes "
    "scores back. **In place** calls the registered model from SQL: no row leaves the platform, and the "
    "governance on the tables still applies."
)

ledger = q(f"SELECT * FROM {DB}.ANALYTICS.DATA_GRAVITY_LEDGER ORDER BY ROWS_OUT DESC")
cols = st.columns(len(ledger))
for col, row in zip(cols, ledger.itertuples()):
    with col.container(border=True):
        st.markdown(f"**{row.PATH}**")
        st.metric("Rows moved out", f"{int(row.ROWS_OUT):,}")
        st.metric("Feature values out", f"{int(row.FEATURE_VALUES_OUT):,}")
        st.metric("Rows written back", f"{int(row.ROWS_BACK):,}")
        st.caption(f"{int(row.BOUNDARY_CROSSINGS)} boundary crossings · {row.SECONDS:.1f} s on 2,000 accounts")
st.caption("Rows counted on the client side of each path; each ran under its own query tag, and query history "
           "confirms the in-place path returned no rows to the client. At this size both take seconds; what differs is "
           "how much data crosses the boundary.")

st.subheader("What the live step cost")
log = q(f"""
SELECT STEP, LABEL, AI_CALLS, INPUT_TOKENS, SECONDS FROM {DB}.ANALYTICS.LIVE_RUN_LOG
WHERE RUN_ID = (SELECT MAX_BY(RUN_ID, LOGGED_AT) FROM {DB}.ANALYTICS.LIVE_RUN_LOG WHERE STEP = 'done')
  AND STEP_NO BETWEEN 1 AND 6 ORDER BY STEP_NO
""")
if log.empty:
    st.info("Run the live step on page 3 to see its AI calls here.", icon=":material/info:")
else:
    ai = log[log.AI_CALLS > 0][["LABEL", "AI_CALLS", "INPUT_TOKENS"]].rename(
        columns={"LABEL": "Step", "AI_CALLS": "AI function calls", "INPUT_TOKENS": "Embedding input tokens"})
    st.dataframe(ai, hide_index=True, alt="AI function calls in the last live run")
    st.caption("Embedding tokens are counted with AI_COUNT_TOKENS. Actual AI spend per function and query "
               "appears in SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY.")

st.subheader("Controls in place")
st.markdown(
    "- **Masking policy** on the raw transcript column; AI reads redacted text only.\n"
    "- **Incremental pipeline**: dynamic tables and a stream, so each segment is processed once.\n"
    "- **Model Registry**: the topic model and the churn model are versioned, with a default version for scoring.\n"
    "- **Model monitor** on the churn scores, and pending review on every AI-proposed topic."
)
common.next_button(5)
