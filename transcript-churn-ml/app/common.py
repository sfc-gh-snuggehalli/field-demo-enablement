"""Shared helpers for the story app: one connection, cached reads, the step list and a preflight check."""
import json

import streamlit as st

DB = "TRANSCRIPT_CHURN_ML_DEMO"

# The live step, in order. LABELS mirror ANALYTICS.LIVE_STEP.
STEPS = [
    ("arrive", "New calls land in RAW"),
    ("segments", "Conversations split into segments"),
    ("redact", "PII redacted with AI_REDACT"),
    ("embed", "Redacted text embedded with AI_EMBED"),
    ("topics", "Topics assigned"),
    ("price", "Price sentiment scored"),
]

# Page order for the Next buttons; filled in by streamlit_app.py.
PAGES: list = []


def session():
    return st.connection("snowflake").session()


@st.cache_data(ttl=600, show_spinner=False)
def q(sql: str, params: tuple = ()):
    """Cached read. Call st.cache_data.clear() after anything changes the data."""
    return session().sql(sql, params=list(params) if params else None).to_pandas()


def one(sql: str, params: tuple = ()):
    return q(sql, params).iloc[0, 0]


def call(sql: str, params: tuple = ()):
    """Uncached call to a stored procedure that returns a VARIANT. Shows the error and returns None on failure."""
    try:
        raw = session().sql(sql, params=list(params) if params else None).collect()[0][0]
    except Exception as e:  # noqa: BLE001 - surface any Snowflake error on the page instead of a traceback
        st.error(f"Snowflake returned an error: {e}", icon=":material/error:")
        return None
    return json.loads(raw) if isinstance(raw, str) else raw


def january_loaded() -> bool:
    return int(one(f"""SELECT COUNT(*) FROM {DB}.CORE.SEGMENTS_REDACTED
                       WHERE CALL_ID IN (SELECT CALL_ID FROM {DB}.RAW.CALLS_NEW_MONTH)""")) > 0


def preflight() -> bool:
    """Stop with a clear message when the build has not run. Returns True when everything is there."""
    needed = [
        ("CORE.SEGMENTS_REDACTED", "notebook 01"),
        ("ML.SEGMENT_TOPICS", "notebook 02"),
        ("ML.PROPOSED_TOPICS", "notebook 02"),
        ("ANALYTICS.PRICE_SENTIMENT", "notebook 03"),
        ("ANALYTICS.CHURN_SCORES", "notebook 04"),
        ("ANALYTICS.DATA_GRAVITY_LEDGER", "notebook 05"),
        ("ANALYTICS.ACCOUNT_RISK", "lab/app_setup.sql"),
    ]
    found = set(q(f"""SELECT TABLE_SCHEMA || '.' || TABLE_NAME AS T FROM {DB}.INFORMATION_SCHEMA.TABLES
                      WHERE ROW_COUNT > 0""")["T"])
    missing = [(t, src) for t, src in needed if t not in found]
    if missing:
        st.error(
            "This app reads what the lab builds, and some of it is missing: "
            + ", ".join(f"`{t}` (from {src})" for t, src in missing)
            + ". Run `./demo.sh build --yes`, then `./demo.sh app --yes`.",
            icon=":material/build:",
        )
        return False
    return True


def next_button(current: int):
    """A Next button at the bottom of a page, so the presenter never hunts for the sidebar."""
    if current + 1 < len(PAGES):
        st.divider()
        if st.button(f"Next: {PAGES[current + 1].title}", icon=":material/arrow_forward:", type="primary"):
            st.switch_page(PAGES[current + 1])


def pretty_topic(name: str) -> str:
    """ROI_CONCERNS -> Roi concerns; business topic names are already readable."""
    if name and name.isupper() and "_" in name:
        return name.replace("_", " ").capitalize().replace("Roi", "ROI").replace("Ai ", "AI ")
    return name
