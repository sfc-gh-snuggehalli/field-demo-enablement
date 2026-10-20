import re

import streamlit as st

import common
from common import DB, q

st.title("Redact first, then let AI read it")
st.markdown(
    "The raw transcripts carry names, phone numbers and email addresses. Two controls sit in front of every "
    "AI step: a **masking policy** on the raw column, and **AI_REDACT** on each segment before it is embedded, "
    "classified or searched. Everything after this page reads the redacted text only."
)

k = q(f"""
SELECT COUNT(*) AS N,
       COUNT_IF(REGEXP_LIKE(REDACTED_TEXT, '.*[0-9]{{3}}-555-[0-9]{{4}}.*', 's')) AS PHONES_LEFT,
       COUNT_IF(REDACTED_TEXT ILIKE '%@homemail.example%') AS EMAILS_LEFT,
       COUNT_IF(EXISTS (SELECT 1 FROM {DB}.RAW.REPS r WHERE CONTAINS(REDACTED_TEXT, r.REP_NAME))) AS REPS_LEFT,
       COUNT_IF(REDACTED_TEXT LIKE '%[NAME]%') AS NAME_TAGS,
       (SELECT COUNT_IF(REGEXP_LIKE(SEGMENT_TEXT, '.*[0-9]{{3}}-555-[0-9]{{4}}.*', 's')) FROM {DB}.CORE.SEGMENTS) AS PHONES_IN
FROM {DB}.CORE.SEGMENTS_REDACTED
""").iloc[0]

cols = st.columns(4)
cols[0].metric("Segments redacted", f"{int(k.N):,}", border=True)
cols[1].metric("Phone numbers left", int(k.PHONES_LEFT), delta=f"{int(k.PHONES_IN)} before redaction",
               delta_color="off", border=True)
cols[2].metric("Email addresses left", int(k.EMAILS_LEFT), border=True)
cols[3].metric("Staff names left", int(k.REPS_LEFT), border=True)


def highlight(text: str) -> str:
    """Escape Markdown, then mark the placeholders AI_REDACT inserted."""
    text = re.sub(r"([\\`*_{}\[\]<>#+!|$~])", r"\\\1", text)
    # Placeholders such as [PHONE_NUMBER] are escaped as \[PHONE\_NUMBER\]; mark them and drop the escapes.
    text = re.sub(r"\\\[([A-Z\\_]+)\\\]", lambda m: f":orange-background[{m.group(1).replace(chr(92), '')}]", text)
    return text.replace("\n", "  \n")


st.subheader("What the AI functions see")
samples = q(f"""
SELECT SEGMENT_ID, CALL_TYPE, REDACTED_TEXT FROM {DB}.CORE.SEGMENTS_REDACTED
WHERE REDACTED_TEXT LIKE '%[PHONE_NUMBER]%' OR REDACTED_TEXT LIKE '%[EMAIL]%'
ORDER BY SEGMENT_ID LIMIT 3
""")
for row in samples.itertuples():
    with st.container(border=True):
        st.caption(f"Segment {row.SEGMENT_ID} · {row.CALL_TYPE.lower()} call")
        st.markdown(highlight(row.REDACTED_TEXT))

left, right = st.columns(2)
with left:
    st.subheader("The raw column is masked")
    st.code(
        """CREATE MASKING POLICY RAW.TRANSCRIPT_TEXT_MASK AS (VAL STRING) RETURNS STRING ->
  CASE WHEN IS_ROLE_IN_SESSION('SYSADMIN') THEN VAL
       ELSE '[masked: call transcript text]' END;

ALTER TABLE RAW.UTTERANCES MODIFY COLUMN TEXT
  SET MASKING POLICY RAW.TRANSCRIPT_TEXT_MASK;""",
        language="sql",
    )
    st.caption("Analysts querying RAW.UTTERANCES see the placeholder. The text on these pages is the redacted copy.")
with right:
    st.subheader("Redaction runs once per segment")
    st.markdown(
        "- A **stream** remembers which segments are new, so each one is redacted, and billed, once.\n"
        "- A known-names pass removes staff names deterministically on top of AI_REDACT.\n"
        "- Embeddings, topics, sentiment, the search index and the agent all read the redacted table."
    )

common.next_button(1)
