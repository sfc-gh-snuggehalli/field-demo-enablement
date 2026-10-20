import altair as alt
import streamlit as st

import common
from common import DB, q, pretty_topic

st.title("Ask it yourself")
st.markdown(
    "Everything on the previous pages is also available to a **Cortex Agent** in Snowflake Intelligence. "
    "It answers in plain language with two tools: Cortex Analyst over a semantic view (topics, price "
    "sentiment, deals and churn risk), and Cortex Search over the **redacted** call segments for quotes."
)

st.link_button("Open Snowflake Intelligence", "https://ai.snowflake.com", icon=":material/open_in_new:",
               type="primary")
st.caption("Pick the agent **Call insights and churn risk**, then paste a question.")

for qtext in [
    "Which topics come up most on calls with high-risk accounts compared with low-risk accounts?",
    "What are customers saying about competitor pricing? Show a few quotes.",
    "How much monthly revenue is in high-risk accounts by plan tier, and what is their most common risk driver?",
]:
    st.code(qtext, language=None)

st.subheader("The numbers behind the first question")
st.caption("Queried here through the same semantic view the agent uses: ANALYTICS.CHURN_STORY_SV. Calls from all "
           "months, including January, against risk bands scored on 1 January 2026.")
sv = q(f"""
SELECT * FROM SEMANTIC_VIEW({DB}.ANALYTICS.CHURN_STORY_SV
  DIMENSIONS risk.risk_band, seg.topic
  METRICS seg.segment_count)
WHERE RISK_BAND IN ('HIGH', 'LOW')
""")
sv["SHARE"] = sv.SEGMENT_COUNT / sv.groupby("RISK_BAND").SEGMENT_COUNT.transform("sum")
sv["TOPIC"] = sv.TOPIC.map(pretty_topic)
st.altair_chart(
    alt.Chart(sv).mark_bar().encode(
        x=alt.X("SHARE:Q", title="Share of segments", axis=alt.Axis(format="%")),
        y=alt.Y("TOPIC:N", sort="-x", title=None),
        yOffset=alt.YOffset("RISK_BAND:N", sort=["HIGH", "LOW"]),
        color=alt.Color("RISK_BAND:N", title="Risk band", sort=["HIGH", "LOW"],
                        scale=alt.Scale(domain=["HIGH", "LOW"], range=["#E8572B", "#29B5E8"]),
                        legend=alt.Legend(orient="bottom")),
        tooltip=["RISK_BAND", "TOPIC", "SEGMENT_COUNT", alt.Tooltip("SHARE:Q", format=".1%")],
    ).properties(height=420),
    alt="Topic share on calls with high-risk vs low-risk accounts",
)

with st.expander("How it is built"):
    st.markdown(
        "The five lab notebooks build every table this app reads, and `lab/app_setup.sql` adds the live step, the "
        "risk tables, the semantic view, the search service and the agent. The demo script's technical deep dive "
        "walks the notebooks section by section."
    )
