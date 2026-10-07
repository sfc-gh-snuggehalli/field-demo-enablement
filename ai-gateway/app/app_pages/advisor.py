import streamlit as st
import pandas as pd

st.header("Advisor")

df: pd.DataFrame = st.session_state["df"]
usage_df: pd.DataFrame = st.session_state["usage_df"]

if df.empty:
    st.info("No trace data for the selected filters.")
    st.stop()

# ---------------------------------------------------------------------------
# Tunable thresholds
# ---------------------------------------------------------------------------
LATENCY_THRESHOLD_MS = 10_000
ERROR_RATE_THRESHOLD = 5.0
MIN_ERRORS_FOR_SPIKE = 3
TOKEN_BLOAT_THRESHOLD = 2000
TOKEN_BLOAT_MIN_REQUESTS = 3
SLOW_MODEL_MS = 5000
FAST_MODEL_MS = 3000
SINGLE_MODEL_MIN_REQUESTS = 5
COST_CREDIT_THRESHOLD = 0.5

# ---------------------------------------------------------------------------
# Recommendation engine
# ---------------------------------------------------------------------------
recommendations: list[dict] = []


CONCISE_SYSTEM = (
    "You are a concise marketing analyst. Answer in at most 3 short sentences or "
    "3 bullets. Lead with the number or the direct answer."
)
ALT_MODEL = "openai-gpt-5.4-mini"


def add_rec(severity: str, title: str, detail: str, proposal: dict | None = None):
    """proposal = candidate config overrides that the Experiments page can test."""
    recommendations.append({"severity": severity, "title": title, "detail": detail,
                            "proposal": proposal})


# Rule 1: High latency patterns
user_lat = df.groupby("USER_NAME")["DURATION_MS"].mean()
for user, avg_ms in user_lat.items():
    if avg_ms > LATENCY_THRESHOLD_MS:
        add_rec(
            "HIGH",
            f"High avg latency for {user}: {avg_ms:,.0f} ms",
            "Consider using faster models, reducing prompt length, or adding "
            "max_tokens to limit output size. For interactive workloads, target "
            "sub-5s latency.",
            {"max_tokens": 300, "system_prompt": CONCISE_SYSTEM},
        )

# Rule 2: Error rate spikes
total_by_model = df.groupby("REQUEST_MODEL").size()
errors_by_model = df[df["STATUS_CODE"] == "STATUS_CODE_ERROR"].groupby("REQUEST_MODEL").size()
for model in total_by_model.index:
    err_count = errors_by_model.get(model, 0)
    rate = err_count / total_by_model[model] * 100
    if rate > ERROR_RATE_THRESHOLD and err_count >= MIN_ERRORS_FOR_SPIKE:
        add_rec(
            "HIGH",
            f"Error rate spike for {model}: {rate:.1f}% ({err_count} errors)",
            "Check HTTP status codes for patterns (429 = rate limit, 500 = server "
            "error). Consider adding retry logic with exponential backoff or "
            "configuring a fallback model in the Gateway spec.",
            {"model": "openai-gpt-5.4"},
        )

# Rule 3: Token bloat
combo = df.groupby(["USER_NAME", "REQUEST_MODEL"]).agg(
    REQUESTS=("SPAN_ID", "count"),
    AVG_OUTPUT=("OUTPUT_TOKENS", "mean"),
).reset_index()
bloated = combo[(combo["AVG_OUTPUT"] > TOKEN_BLOAT_THRESHOLD) & (combo["REQUESTS"] >= TOKEN_BLOAT_MIN_REQUESTS)]
for _, row in bloated.iterrows():
    add_rec(
        "MEDIUM",
        f"Token bloat: {row['USER_NAME']} + {row['REQUEST_MODEL']} avg {row['AVG_OUTPUT']:,.0f} output tokens",
        "Set max_tokens in the API call, use structured output instructions "
        '("respond in JSON", "limit to 3 bullet points"), or add a system '
        "prompt that constrains verbosity.",
        {"model": row["REQUEST_MODEL"], "max_tokens": 300, "system_prompt": CONCISE_SYSTEM},
    )

# Rule 4: Underutilized fast models
model_avg_lat = df.groupby("REQUEST_MODEL").agg(
    AVG_LAT=("DURATION_MS", "mean"),
    VOLUME=("SPAN_ID", "count"),
).reset_index()
slow = model_avg_lat[model_avg_lat["AVG_LAT"] > SLOW_MODEL_MS]
fast = model_avg_lat[model_avg_lat["AVG_LAT"] < FAST_MODEL_MS]
if not slow.empty and not fast.empty:
    slow_vol = slow["VOLUME"].sum()
    fast_vol = fast["VOLUME"].sum()
    if fast_vol > 0 and slow_vol >= 2 * fast_vol:
        add_rec(
            "MEDIUM",
            f"Slow models handle {slow_vol} requests vs {fast_vol} on fast models",
            "Consider rebalancing workloads: route simpler tasks to faster, "
            "cheaper models and reserve high-latency models for complex reasoning.",
            {"model": ALT_MODEL},
        )

# Rule 5: No conversation threading
if "CONVERSATION_ID" in df.columns:
    non_null = df["CONVERSATION_ID"].dropna()
    non_empty = non_null[non_null.astype(str).str.strip() != ""]
    if non_empty.empty:
        add_rec(
            "LOW",
            "No conversation threading detected",
            "Add the x-snowflake-ai-gateway-conversation-id header to group "
            "multi-turn conversations. This enables conversation-level tracing "
            "and analytics. Especially useful since this LangChain agent makes "
            "multiple gateway calls per turn.",
        )

# Rule 6: Single-model usage
unique_models = df["REQUEST_MODEL"].nunique()
if unique_models == 1 and len(df) >= SINGLE_MODEL_MIN_REQUESTS:
    model_name = df["REQUEST_MODEL"].iloc[0]
    add_rec(
        "LOW",
        f"All {len(df)} requests use a single model: {model_name}",
        "Consider testing alternative models for cost/latency optimization. "
        "Configure model fallback in the AI Gateway spec so requests "
        "automatically route to a backup when the primary is slow or unavailable.",
        {"model": ALT_MODEL},
    )

# Rule 7: Cost optimization
if not usage_df.empty:
    total_credits = usage_df["CREDITS"].sum()
    if total_credits > COST_CREDIT_THRESHOLD:
        avg_input = df["INPUT_TOKENS"].mean()
        add_rec(
            "MEDIUM",
            f"Total credits: {total_credits:.4f} — review prompt efficiency",
            f"Average input token count is {avg_input:,.0f}. Consider trimming "
            "system prompts, reducing context window size, or using smaller "
            "models for simpler classification/extraction tasks.",
            {"system_prompt": CONCISE_SYSTEM, "max_tokens": 300},
        )

# ---------------------------------------------------------------------------
# Display recommendations
# ---------------------------------------------------------------------------
st.subheader("Recommendations")

SEVERITY_ORDER = {"HIGH": 0, "MEDIUM": 1, "LOW": 2}
SEVERITY_COLOR = {"HIGH": "red", "MEDIUM": "orange", "LOW": "blue"}

recommendations.sort(key=lambda r: SEVERITY_ORDER.get(r["severity"], 9))

if not recommendations:
    st.success("No issues detected — your gateway usage looks healthy.")
else:
    for i, rec in enumerate(recommendations):
        color = SEVERITY_COLOR[rec["severity"]]
        with st.container(border=True):
            st.markdown(f":{color}[**{rec['severity']}**] — {rec['title']}")
            st.caption(rec["detail"])
            if rec["proposal"]:
                st.caption("Proposed change: " + ", ".join(
                    f"`{k}`={str(v)[:40]}" for k, v in rec["proposal"].items()))
                if st.button(":material/science: Test this fix", key=f"exp_{i}"):
                    st.session_state["experiment_seed"] = {
                        "finding": rec["title"], **rec["proposal"]}
                    st.switch_page("app_pages/experiments.py")

# ---------------------------------------------------------------------------
# Best practices
# ---------------------------------------------------------------------------
st.subheader("Gateway and prompting best practices")

practices = [
    (
        ":material/format_list_bulleted: Structured prompts",
        "Use clear section markers (System, Context, Task, Format) in prompts "
        "for consistent, parseable outputs.",
    ),
    (
        ":material/smart_toy: System prompts",
        "Set a system prompt that defines the assistant's role, constraints, and "
        "output format. This reduces output token waste.",
    ),
    (
        ":material/token: max_tokens",
        "Always set max_tokens to prevent runaway generation. Match it to the "
        "expected output size for your use case.",
    ),
    (
        ":material/swap_vert: Model tier selection",
        "Use smaller/faster models for classification, extraction, and simple Q&A. "
        "Reserve large models for complex reasoning and creative tasks.",
    ),
    (
        ":material/link: W3C traceparent header",
        "Pass a traceparent header on every gateway call so all spans from one "
        "agent turn share a single trace_id. Without it each call appears as "
        "an unrelated event.",
    ),
    (
        ":material/forum: Conversation-id header",
        "Use x-snowflake-ai-gateway-conversation-id for multi-turn sessions. "
        "This groups related turns for analytics and enables conversation-level "
        "cost tracking.",
    ),
]

for title, tip in practices:
    with st.container(border=True):
        st.markdown(f"**{title}**")
        st.caption(tip)
