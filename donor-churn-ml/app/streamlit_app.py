"""
Donor Retention Intelligence — Streamlit-in-Snowflake chat app.

A fundraising manager types a natural-language question and sees the agent's answer
inline: the agent retrieves donors via Cortex Analyst, scores them with the deployed
lapse model tool, and returns a ranked, explained action list.

Deploy as a Streamlit-in-Snowflake app (Snowsight -> Projects -> Streamlit) in a role
that has USAGE on the agent DONOR_CHURN_ML_DEMO.MODELS.DONOR_RETENTION_AGENT and on the
custom-tool function TOP_CHURN_RISK. Requires the notebook (Section 12) to have created
the agent first.

This app calls the Cortex Agents REST endpoint from inside Snowflake via
_snowflake.send_snow_api_request (no external auth needed in SiS).
"""

import json

import streamlit as st

try:
    import _snowflake  # available inside Streamlit-in-Snowflake
except ImportError:  # pragma: no cover - lets the file import locally for linting
    _snowflake = None

# ─────────────────────────────────────────────────────────────────────────────
# Config — the agent created in the lab notebook (Section 12).
# ─────────────────────────────────────────────────────────────────────────────
DATABASE = "DONOR_CHURN_ML_DEMO"
SCHEMA = "MODELS"
AGENT = "DONOR_RETENTION_AGENT"
API_TIMEOUT_MS = 60000

SAMPLE_QUESTIONS = [
    "Which of our major-gift donors in the West region are most at risk of "
    "lapsing this quarter, why, and what should we do?",
    "What is the lapse rate by region?",
    "Draft outreach for the top 3.",
]

st.set_page_config(page_title="Donor Retention Intelligence", page_icon="💙", layout="centered")
st.title("Donor Retention Intelligence")
st.caption(
    "Ask about donor lapse risk in natural language. The agent retrieves donors "
    "(Cortex Analyst), scores them with the deployed lapse model, and recommends actions."
)

with st.sidebar:
    st.subheader("Try asking")
    for q in SAMPLE_QUESTIONS:
        st.markdown(f"- {q}")
    st.divider()
    st.caption(f"Agent: `{DATABASE}.{SCHEMA}.{AGENT}`")


def run_agent(messages):
    """Call the Cortex Agents run endpoint and return (answer_text, tool_notes)."""
    if _snowflake is None:
        return ("This app must run inside Streamlit-in-Snowflake (the _snowflake API "
                "is unavailable locally).", [])

    payload = {"messages": messages}
    resp = _snowflake.send_snow_api_request(
        "POST",
        f"/api/v2/databases/{DATABASE}/schemas/{SCHEMA}/agents/{AGENT}:run",
        {},        # headers
        {},        # query params
        payload,   # body
        {},         # request-scoped params
        API_TIMEOUT_MS,
    )

    # The endpoint returns a (possibly streamed) list of events. Parse defensively:
    # collect any assistant text and note which tools were used.
    body = resp.get("content", resp) if isinstance(resp, dict) else resp
    try:
        events = json.loads(body) if isinstance(body, str) else body
    except (ValueError, TypeError):
        return (str(body), [])

    answer_parts, tool_notes = [], []
    if isinstance(events, dict):
        events = events.get("events", [events])
    for event in events or []:
        data = event.get("data", event) if isinstance(event, dict) else {}
        for item in data.get("content", []) if isinstance(data, dict) else []:
            itype = item.get("type")
            if itype == "text" and item.get("text"):
                answer_parts.append(item["text"])
            elif itype == "tool_use":
                tool_notes.append(item.get("name", "tool"))
            elif itype == "tool_results":
                tool_notes.append("tool_results")

    answer = "\n".join(answer_parts).strip() or "The agent returned no text. See raw response."
    if not answer_parts:
        answer += "\n\n```\n" + json.dumps(events, indent=2)[:2000] + "\n```"
    return (answer, tool_notes)


# ─────────────────────────────────────────────────────────────────────────────
# Chat state + loop
# ─────────────────────────────────────────────────────────────────────────────
if "history" not in st.session_state:
    st.session_state.history = []  # list of {"role", "content"}

for turn in st.session_state.history:
    with st.chat_message(turn["role"]):
        st.markdown(turn["content"])

prompt = st.chat_input("Ask about donor lapse risk...")
if prompt:
    st.session_state.history.append({"role": "user", "content": prompt})
    with st.chat_message("user"):
        st.markdown(prompt)

    # Build the message list the agent expects (role + typed content blocks).
    api_messages = [
        {"role": m["role"], "content": [{"type": "text", "text": m["content"]}]}
        for m in st.session_state.history
    ]

    with st.chat_message("assistant"):
        with st.spinner("Planning: retrieve → score → explain..."):
            answer, tools = run_agent(api_messages)
        st.markdown(answer)
        if tools:
            st.caption("Tools used: " + ", ".join(dict.fromkeys(tools)))

    st.session_state.history.append({"role": "assistant", "content": answer})
