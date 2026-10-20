"""Call transcripts to churn risk: the presenter's story app.

Seven pages, one point each. Everything is read from tables the lab already built, except page 3,
which runs January's calls through the pipeline live.
"""
import streamlit as st

import common

st.set_page_config(page_title="From calls to churn risk", page_icon=":material/forum:", layout="wide")

pages = [
    st.Page("app_pages/p1_question.py", title="The question", icon=":material/help:", default=True),
    st.Page("app_pages/p2_governed.py", title="Governed text", icon=":material/shield_lock:"),
    st.Page("app_pages/p3_january.py", title="January arrives (live)", icon=":material/play_circle:"),
    st.Page("app_pages/p4_topics.py", title="What customers talk about", icon=":material/forum:"),
    st.Page("app_pages/p5_churn.py", title="Does it predict churn?", icon=":material/trending_down:"),
    st.Page("app_pages/p6_data_stayed.py", title="Where the data stayed", icon=":material/database:"),
    st.Page("app_pages/p7_ask.py", title="Ask it yourself", icon=":material/chat:"),
]
common.PAGES[:] = pages

with st.sidebar:
    st.caption("Synthetic data: a subscription software business, 2,000 accounts, two months of calls with a third "
               "arriving live on page 3.")

st.navigation(pages).run()
