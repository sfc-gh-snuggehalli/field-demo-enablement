import json

import altair as alt
import pandas as pd
import streamlit as st

import common
from common import DB, q

st.title("Does what customers say predict churn?")
st.markdown(
    "The churn model already used product usage. We added call signals (price complaints, competitor mentions, "
    "emerging topics) from the Feature Store and compared three model families on the same held-out accounts."
)


@st.cache_data(ttl=600, show_spinner=False)
def runs() -> pd.DataFrame:
    rows = common.session().sql(f"SHOW RUNS IN EXPERIMENT {DB}.ML.CHURN_SURVIVAL").collect()
    out = []
    for r in rows:
        name, meta = r["name"], json.loads(r["metadata"])
        score = meta.get("metrics", {}).get("test_c_index", {}).get("value")
        family, _, feats = name.partition("_USAGE")
        out.append({
            "Model": {"LOGISTIC": "Logistic regression", "COX": "Cox survival", "GB_SURVIVAL": "Gradient-boosted survival"}
                     .get(family, family),
            "Features": "Usage + calls" if feats == "_CALLS" else "Usage only",
            "C-index": score,
        })
    return pd.DataFrame(out)


r = runs()
base = r[r.Features == "Usage only"]["C-index"].max()
calls = r[r.Features == "Usage + calls"]["C-index"].max()
cols = st.columns(3)
cols[0].metric("Best, usage only", f"{base:.3f}", border=True)
cols[1].metric("Best, usage + calls", f"{calls:.3f}", delta=f"{calls - base:+.3f}", border=True)
cols[2].metric("Coin flip", "0.500", border=True)
st.caption("C-index: how often the model ranks an account that churned sooner above one that churned later or "
           "stayed. 0.5 is a coin flip. Measured on test accounts the models never saw.")
st.altair_chart(
    alt.Chart(r).mark_bar(clip=True).encode(
        x=alt.X("C-index:Q", scale=alt.Scale(domain=[0.5, 0.65]), title="C-index (test accounts)"),
        y=alt.Y("Model:N", title=None),
        yOffset="Features:N",
        color=alt.Color("Features:N", sort=["Usage only", "Usage + calls"], legend=alt.Legend(orient="bottom")),
        tooltip=["Model", "Features", alt.Tooltip("C-index:Q", format=".3f")],
    ).properties(height=240),
    alt="Model comparison by c-index",
)

st.subheader("Who is at risk, and why")
bands = q(f"""
SELECT RISK_BAND, TOP_DRIVER_SOURCE, COUNT(*) AS ACCOUNTS, SUM(MRR) AS MRR
FROM {DB}.ANALYTICS.ACCOUNT_RISK GROUP BY ALL
""")
left, right = st.columns([2, 3])
with left:
    hi = bands[bands.RISK_BAND == "HIGH"]
    calls_share = hi[hi.TOP_DRIVER_SOURCE == "Calls"].ACCOUNTS.sum() / hi.ACCOUNTS.sum()
    st.metric("High-risk accounts", f"{int(hi.ACCOUNTS.sum()):,}", border=True)
    st.metric("Their monthly revenue", f"${hi.MRR.sum():,.0f}", border=True)
    st.metric("Top reason comes from calls", f"{calls_share:.0%}", border=True)
with right:
    st.altair_chart(
        alt.Chart(bands).mark_bar().encode(
            x=alt.X("ACCOUNTS:Q", stack="normalize", title="Share of accounts", axis=alt.Axis(format="%")),
            y=alt.Y("RISK_BAND:N", sort=["HIGH", "MEDIUM", "LOW"], title="Risk band"),
            color=alt.Color("TOP_DRIVER_SOURCE:N", title="Top reason from", legend=alt.Legend(orient="bottom")),
            tooltip=["RISK_BAND", "TOP_DRIVER_SOURCE", "ACCOUNTS"],
        ).properties(height=220),
        alt="Where each account's top risk driver comes from, by risk band",
    )

top = q(f"""
SELECT ACCOUNT_ID, CUSTOMER_SEGMENT, PLAN_TIER, MRR, CHURN_PROB, TOP_DRIVER
FROM {DB}.ANALYTICS.ACCOUNT_RISK WHERE RISK_BAND = 'HIGH' ORDER BY CHURN_PROB DESC LIMIT 25
""")
st.markdown("**Highest-risk accounts.** Select one to see why.")
sel = st.dataframe(
    top, hide_index=True, on_select="rerun", selection_mode="single-row", key="risk_table",
    alt="Highest-risk accounts",
    column_config={
        "ACCOUNT_ID": "Account", "CUSTOMER_SEGMENT": "Segment", "PLAN_TIER": "Plan",
        "MRR": st.column_config.NumberColumn("MRR", format="$%d"),
        "CHURN_PROB": st.column_config.ProgressColumn("Churn probability", min_value=0, max_value=1, format="%.2f"),
        "TOP_DRIVER": "Top reason",
    },
)
picked = sel.selection.rows
acct = top.ACCOUNT_ID.iloc[picked[0]] if picked else top.ACCOUNT_ID.iloc[0]

d = q(f"""
SELECT LABEL, SOURCE, CONTRIB FROM {DB}.ANALYTICS.ACCOUNT_RISK_DRIVERS
WHERE ACCOUNT_ID = ? ORDER BY ABS(CONTRIB) DESC LIMIT 6
""", (acct,))
quotes = q(f"""
SELECT r.REDACTED_CUSTOMER_TEXT AS QUOTE, t.TOPIC_NAME, TO_CHAR(t.CALL_TS, 'Mon YYYY') AS MONTH
FROM {DB}.ML.SEGMENT_TOPICS t JOIN {DB}.CORE.SEGMENTS_REDACTED r USING (SEGMENT_ID)
LEFT JOIN {DB}.ANALYTICS.PRICE_SENTIMENT p USING (SEGMENT_ID)
WHERE t.ACCOUNT_ID = ? AND t.CALL_TS < (SELECT MAX(AS_OF) FROM {DB}.ANALYTICS.ACCOUNT_RISK)
  AND LENGTH(r.REDACTED_CUSTOMER_TEXT) > 40
ORDER BY IFF(p.IS_NEGATIVE, 0, 1), IFF(t.TOPIC_SOURCE = 'DISCOVERED', 0, 1), t.CALL_TS DESC LIMIT 2
""", (acct,))

a, b = st.columns(2)
with a:
    st.markdown(f"**{acct}: what moves its risk**")
    st.altair_chart(
        alt.Chart(d).mark_bar().encode(
            x=alt.X("CONTRIB:Q", title="Contribution to churn risk"),
            y=alt.Y("LABEL:N", sort="-x", title=None),
            color=alt.condition("datum.CONTRIB > 0", alt.value("#E8572B"), alt.value("#29B5E8")),
            tooltip=["LABEL", "SOURCE", alt.Tooltip("CONTRIB:Q", format=".3f")],
        ).properties(height=220),
        alt=f"Risk drivers for {acct}",
    )
    st.caption("From the registered model's EXPLAIN method. Orange raises risk, blue lowers it.")
with b:
    st.markdown("**What they said** (before the scoring date)")
    if quotes.empty:
        st.caption("No conversations with this account before the scoring date.")
    for row in quotes.itertuples():
        st.markdown(f"> {row.QUOTE.replace('$', chr(92) + '$')}")
        st.caption(f"{common.pretty_topic(row.TOPIC_NAME)}, {row.MONTH}")

st.caption("Scores are as of 1 January 2026 and use calls from the 90 days before it. They come from the registered "
           "default, the Cox survival model with call features (c-index 0.611), through MODEL(CHURN_SURVIVAL)!PREDICT in "
           "SQL, and a model monitor watches them.")
common.next_button(4)
