"""Generate diverse AI Gateway trace data for the Trace Analyzer app.

Usage:
    export SNOWFLAKE_ACCOUNT=<org-account>   # e.g. myorg-myaccount
    export SNOWFLAKE_PAT=<pat>               # or SNOWFLAKE_PAT_FILE=<path>
    python generate_traffic.py

Uses LangChain ChatOpenAI (same as the demo notebook) to make real inference
calls through the Cortex AI Gateway. Intentionally calls unknown model names
to generate error traces for dashboard diversity.
"""

import os
import time
import uuid
from pathlib import Path

from langchain_openai import ChatOpenAI

# ---------------------------------------------------------------------------
# Config - PAT auth, same pattern as the lab notebook
# ---------------------------------------------------------------------------
ACCOUNT = os.environ["SNOWFLAKE_ACCOUNT"]
PAT = os.environ.get("SNOWFLAKE_PAT") or Path(
    os.path.expanduser(os.environ.get("SNOWFLAKE_PAT_FILE", "~/.snowflake/ai_gateway_demo.pat"))
).read_text().strip()
SF_HOST = f"{ACCOUNT}.snowflakecomputing.com".replace("_", "-").lower()
BASE_URL = f"https://{SF_HOST}/api/v2/aigateways/SNOWFLAKE/v1"

PRIMARY_MODEL = "openai-gpt-5.4"
# Smaller model used for part of the simple traffic so model comparisons have data
SECONDARY_MODEL = "openai-gpt-5.4-mini"
# Not served on the Chat Completions API -> error spans for the error-rate charts
# (unknown name, and a Claude model, which is only served on /v1/messages)
ERROR_MODELS = ["not-a-real-model", "claude-sonnet-4-5"]


def make_traceparent():
    trace_id = uuid.uuid4().hex
    parent_id = uuid.uuid4().hex[:16]
    return f"00-{trace_id}-{parent_id}-01", trace_id


def make_llm(model=PRIMARY_MODEL, traceparent=None, max_tokens=256):
    headers = {}
    if traceparent:
        headers["traceparent"] = traceparent
    return ChatOpenAI(
        model=model,
        base_url=BASE_URL,
        api_key=PAT,
        temperature=0.7,
        max_completion_tokens=max_tokens,  # GPT-5 family rejects max_tokens
        default_headers=headers or None,
    )


def safe_call(model, prompt, traceparent=None, max_tokens=256, system=None):
    """Call the gateway, print result, swallow errors (they still produce traces)."""
    try:
        llm = make_llm(model=model, traceparent=traceparent, max_tokens=max_tokens)
        messages = []
        if system:
            messages.append(("system", system))
        messages.append(("human", prompt))
        resp = llm.invoke(messages)
        print(f"  OK  {model:35s} | {resp.content[:70]}...")
        return True
    except Exception as e:
        err = str(e)[:80]
        print(f"  ERR {model:35s} | {err}")
        return False


# ===================================================================
print("=== Scenario 1: Simple single-turn calls (primary model) ===")
# ===================================================================
simple_prompts = [
    "What is ROAS in marketing? Answer in one sentence.",
    "Define CPC in digital advertising. One line.",
    "What does CTR mean? Brief answer.",
    "Explain attribution modeling in 2 sentences.",
    "What is a conversion funnel? Brief answer.",
    "Define customer lifetime value in one sentence.",
    "What is A/B testing? One sentence.",
    "Explain retargeting in marketing. Brief answer.",
    "What is impression share? One line.",
    "Define cost per acquisition.",
    "What is brand awareness? Brief answer.",
    "Explain frequency capping in one sentence.",
]

for i, prompt in enumerate(simple_prompts):
    safe_call(PRIMARY_MODEL if i % 2 == 0 else SECONDARY_MODEL, prompt, max_tokens=100)
    time.sleep(0.3)

# ===================================================================
print("\n=== Scenario 2: Multi-span agent traces ===")
# ===================================================================
agent_conversations = [
    [
        "What was the total marketing spend in Q4 2024?",
        "Break that down by channel: Paid Search, Social Media, Email, Display.",
        "Which channel had the highest ROI and why?",
    ],
    [
        "Summarize our attribution methodology.",
        "How does that compare to last-click attribution?",
    ],
    [
        "What are the performance benchmarks for Paid Search in 2024?",
        "How did we perform against those benchmarks in Q4?",
        "Generate a brief executive summary of Q4 Paid Search performance.",
    ],
    [
        "What was our email marketing ROAS for the full year?",
        "Compare email ROAS to social media ROAS.",
    ],
    [
        "What campaigns did we run in H2 2024?",
        "Which H2 campaign had the best conversion rate?",
        "What should we keep doing in 2025 based on H2 results?",
    ],
]

for convo in agent_conversations:
    traceparent, trace_id = make_traceparent()
    print(f"\n  Trace {trace_id[:12]}... ({len(convo)} turns)")
    for msg in convo:
        safe_call(PRIMARY_MODEL, msg, traceparent=traceparent, max_tokens=300)
        time.sleep(0.3)

# ===================================================================
print("\n=== Scenario 3: Long output / token bloat prompts ===")
# ===================================================================
verbose_prompts = [
    "Write a detailed 500-word marketing strategy for Q1 2025 covering all channels with specific budget allocations, KPIs, and timelines for each channel.",
    "Create a comprehensive attribution analysis report covering methodology, data sources, limitations, and recommendations for improvement. Be thorough and detailed.",
    "Draft a complete quarterly business review document for Q4 2024 marketing performance including executive summary, channel-by-channel analysis, key wins, misses, and recommendations.",
    "Write an extensive competitive analysis of digital marketing channels comparing Paid Search, Social Media, Email, and Display across cost efficiency, reach, conversion, and brand impact.",
]

for prompt in verbose_prompts:
    safe_call(
        PRIMARY_MODEL,
        prompt,
        max_tokens=2048,
        system="You are a detailed marketing analyst. Always give comprehensive, thorough responses with specific numbers and examples.",
    )
    time.sleep(1)

# ===================================================================
print("\n=== Scenario 4: Error traces (unknown models) ===")
# ===================================================================
# These will fail with 400 "unknown model" but still create trace spans
# with STATUS_CODE_ERROR — exactly what the error charts need.
error_prompts = [
    "Classify this text as positive, negative, or neutral: 'Our Q4 campaign exceeded ROAS targets'",
    "Extract the key metrics from: 'We spent $580K and generated $2M revenue with 12,249 conversions'",
    "Summarize: Our email channel achieved 12.32x ROAS, the highest across all channels.",
    "What day of the week is best for email marketing?",
    "List 3 ways to improve paid search conversion rates.",
    "What is programmatic advertising? Brief answer.",
    "Define impression share in digital advertising.",
    "What is frequency capping? One sentence.",
]

for i, prompt in enumerate(error_prompts):
    model = ERROR_MODELS[i % len(ERROR_MODELS)]
    safe_call(model, prompt, max_tokens=100)
    time.sleep(0.3)

# ===================================================================
print("\n=== Scenario 5: Mixed model multi-span traces ===")
# ===================================================================
# First span succeeds (primary model), second fails (unknown model)
# This creates interesting mixed-status traces.
mixed_traces = [
    ("Analyze Q4 2024 marketing performance across all channels.", "What were the key risks?"),
    ("What was our overall ROAS for 2024?", "How does that compare to industry benchmarks?"),
]

for q1, q2 in mixed_traces:
    traceparent, trace_id = make_traceparent()
    print(f"\n  Mixed trace {trace_id[:12]}...")
    safe_call(PRIMARY_MODEL, q1, traceparent=traceparent, max_tokens=400)
    time.sleep(0.3)
    safe_call(ERROR_MODELS[0], q2, traceparent=traceparent, max_tokens=200)
    time.sleep(0.5)

# ===================================================================
print("\n=== Scenario 6: Additional primary model variety ===")
# ===================================================================
# More calls with different prompt lengths for latency distribution variety
variety_prompts = [
    ("hi", 20),
    ("What is SEO?", 50),
    ("Explain the difference between organic and paid marketing in detail.", 500),
    ("Write a one-paragraph summary of Q4 2024 holiday marketing results.", 300),
    ("What are KPIs?", 30),
    ("List the top 5 digital marketing trends for 2025 with brief explanations.", 500),
    ("Define ROI.", 20),
    ("What is a marketing funnel and how does it relate to customer journey mapping? Provide a detailed explanation.", 600),
]

for prompt, max_tok in variety_prompts:
    safe_call(PRIMARY_MODEL, prompt, max_tokens=max_tok)
    time.sleep(0.3)

# ===================================================================
print("\n=== Done ===")
print(f"Models: {PRIMARY_MODEL}, {SECONDARY_MODEL} (success), {ERROR_MODELS} (errors)")
print("Traces should appear in AGENT_TRACE_TABLE within seconds.")
