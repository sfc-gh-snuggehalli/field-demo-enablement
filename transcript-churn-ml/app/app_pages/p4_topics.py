import altair as alt
import streamlit as st

import common
from common import DB, q, pretty_topic

st.title("What customers talk about")
st.markdown(
    "Each segment gets a topic. Business-defined topics (pricing, onboarding, renewals and five more) are matched "
    "first by embedding similarity. Whatever is left is clustered, and an LLM proposes a name for each new "
    "cluster. **Nobody asked for the discovered topics: the calls surfaced them.**"
)
if not common.january_loaded():
    st.warning("January is not loaded yet, so this page shows November and December only. "
               "Run the live step on the previous page first.", icon=":material/schedule:")

mix = q(f"""
SELECT TO_CHAR(DATE_TRUNC('month', CALL_TS), 'YYYY-MM') AS MONTH, TOPIC_SOURCE, TOPIC_NAME, COUNT(*) AS SEGMENTS
FROM {DB}.ML.SEGMENT_TOPICS GROUP BY ALL ORDER BY 1
""")
mix["TOPIC"] = mix.TOPIC_NAME.map(pretty_topic)
mix["MONTH"] = mix.MONTH.map({"2025-11": "Nov", "2025-12": "Dec", "2026-01": "Jan"}).fillna(mix.MONTH)

st.subheader("Discovered topics, month by month")
disc = mix[mix.TOPIC_SOURCE == "DISCOVERED"]
st.altair_chart(
    alt.Chart(disc).mark_bar().encode(
        x=alt.X("MONTH:N", title=None, sort=["Nov", "Dec", "Jan"]),
        xOffset="TOPIC:N",
        y=alt.Y("SEGMENTS:Q", title="Segments"),
        color=alt.Color("TOPIC:N", title="Discovered topic", legend=alt.Legend(orient="bottom")),
        tooltip=["MONTH", "TOPIC", "SEGMENTS"],
    ).properties(height=300),
    alt="Discovered topics by month",
)

proposed = q(f"""
SELECT p.CLUSTER_ID, p.LABEL, p.DESCRIPTION, p.MEMBERS, p.STATUS, p.DUPLICATES
FROM {DB}.ML.PROPOSED_TOPICS p
WHERE p.RUN_LABEL = (SELECT MAX(RUN_LABEL) FROM {DB}.ML.PROPOSED_TOPICS) ORDER BY p.CLUSTER_ID
""")
cols = st.columns(len(proposed))
for col, p in zip(cols, proposed.itertuples()):
    with col.container(border=True, height="stretch"):
        st.markdown(f"**{pretty_topic(p.LABEL)}**")
        st.badge("Pending review" if p.STATUS == "PENDING" else p.STATUS.title(),
                 icon=":material/pending:", color="orange")
        st.caption(p.DESCRIPTION)

choice = st.segmented_control(
    "Hear it from customers", [pretty_topic(x) for x in proposed.LABEL], default=pretty_topic(proposed.LABEL[0]))
if choice:
    label = proposed.LABEL[[pretty_topic(x) for x in proposed.LABEL].index(choice)]
    quotes = q(f"""
    SELECT r.REDACTED_CUSTOMER_TEXT AS QUOTE, TO_CHAR(t.CALL_TS, 'Mon YYYY') AS MONTH, t.CALL_TYPE
    FROM {DB}.ML.SEGMENT_TOPICS t JOIN {DB}.CORE.SEGMENTS_REDACTED r USING (SEGMENT_ID)
    WHERE t.TOPIC_NAME = ? AND LENGTH(r.REDACTED_CUSTOMER_TEXT) BETWEEN 60 AND 400
    ORDER BY t.CONFIDENCE DESC, t.CALL_TS DESC LIMIT 3
    """, (label,))
    for row in quotes.itertuples():
        st.markdown(f"> {row.QUOTE.replace('$', chr(92) + '$')}")
        st.caption(f"{row.CALL_TYPE.lower()} call, {row.MONTH} (redacted)")

with st.expander("Business topics (matched to exemplars)"):
    seeded = mix[mix.TOPIC_SOURCE == "SEEDED"].pivot_table(index="TOPIC", columns="MONTH", values="SEGMENTS",
                                                           aggfunc="sum").fillna(0).astype(int)
    st.dataframe(seeded[[c for c in ["Nov", "Dec", "Jan"] if c in seeded.columns]], alt="Business topics by month")

st.caption("Topic labels are proposed by AI_COMPLETE and stay pending until a person approves them. The clustering "
           "model is versioned in the Model Registry and scores new segments from SQL.")
common.next_button(3)
