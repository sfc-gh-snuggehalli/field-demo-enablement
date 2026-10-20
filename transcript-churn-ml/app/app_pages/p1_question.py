import altair as alt
import streamlit as st

import common
from common import DB, q

st.title("What are customers telling us, and does it predict churn?")
if not common.preflight():
    st.stop()

k = q(f"""
SELECT (SELECT COUNT(*) FROM {DB}.RAW.ACCOUNTS) AS ACCOUNTS,
       (SELECT AVG(IFF(ACTUAL_CHURN = 1, 1, 0)) FROM {DB}.ANALYTICS.CHURN_SCORES
         WHERE SCORED_AT = (SELECT MAX(SCORED_AT) FROM {DB}.ANALYTICS.CHURN_SCORES)) AS CHURN_RATE,
       (SELECT COUNT(*) FROM {DB}.RAW.CALLS) AS CALLS,
       (SELECT COUNT(*) FROM {DB}.CORE.SEGMENTS_REDACTED) AS SEGMENTS,
       (SELECT SUM(MRR) FROM {DB}.RAW.ACCOUNTS) AS MRR
""").iloc[0]

cols = st.columns(4)
cols[0].metric("Accounts", f"{int(k.ACCOUNTS):,}", border=True)
cols[1].metric("Churned within 9 months", f"{k.CHURN_RATE:.0%}", border=True)
cols[2].metric("Recorded calls so far", f"{int(k.CALLS):,}", border=True)
cols[3].metric("Monthly revenue", f"${k.MRR / 1e6:,.2f}M", border=True)

st.markdown(
    """
Every week the sales and success teams record about a hundred calls. Today that text sits in the call platform:
nobody can count what customers complain about, and the churn model only sees product usage.

This demo answers three questions, all inside Snowflake:

1. **What do customers talk about?** Topics found in the calls, including ones nobody defined in advance.
2. **Does it predict churn?** Call signals added to the usage-only churn model.
3. **Can we trust it?** PII redacted before any other AI function reads the text, and no data leaving the platform.
"""
)

mix = q(f"""
SELECT CALL_TYPE, COUNT(*) AS CALLS FROM {DB}.RAW.CALLS GROUP BY 1 ORDER BY 2 DESC
""")
st.subheader("What landed")
st.altair_chart(
    alt.Chart(mix).mark_bar().encode(
        x=alt.X("CALLS:Q", title="Calls"),
        y=alt.Y("CALL_TYPE:N", sort="-x", title=None),
        tooltip=["CALL_TYPE", "CALLS"],
    ).properties(height=220),
    alt="Calls by type",
)
st.caption("Outbound dials are short and have no conversation: the pipeline drops them before any AI cost.")

common.next_button(0)
