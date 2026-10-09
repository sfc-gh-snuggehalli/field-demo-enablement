"""Generate diverse AI Gateway trace data for the Trace Analyzer app.

Usage:
    export SNOWFLAKE_ACCOUNT=<org-account>   # e.g. myorg-myaccount
    export SNOWFLAKE_PAT=<pat>               # or SNOWFLAKE_PAT_FILE=<path>
    python generate_traffic.py

    # Cost governance demo: spend as GATEWAY_RETAIL_COST_DEMO until its quota blocks it
    python generate_traffic.py --burst [--burst-pat-file ~/.snowflake/gateway_retail_cost.pat]

Uses LangChain ChatOpenAI (same as the demo notebook) to make real inference
calls through the Cortex AI Gateway. Intentionally calls unknown model names
to generate error traces for dashboard diversity.
"""

import argparse
import json
import os
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import requests
from langchain_openai import ChatOpenAI

# ---------------------------------------------------------------------------
# Config - PAT auth, same pattern as the lab notebook
# ---------------------------------------------------------------------------
ACCOUNT = os.environ["SNOWFLAKE_ACCOUNT"]
PAT = os.environ.get("SNOWFLAKE_PAT") or Path(
    os.path.expanduser(os.environ.get("SNOWFLAKE_PAT_FILE", "~/.snowflake/ai_gateway_retail.pat"))
).read_text().strip()
SF_HOST = f"{ACCOUNT}.snowflakecomputing.com".replace("_", "-").lower()
BASE_URL = f"https://{SF_HOST}/api/v2/aigateways/SNOWFLAKE/v1"

PRIMARY_MODEL = "openai-gpt-5.4"
# Smaller model used for part of the simple traffic so model comparisons have data
SECONDARY_MODEL = "openai-gpt-5.4-mini"
# Claude models are served on the Anthropic-compatible /v1/messages API
CLAUDE_MODELS = ["claude-sonnet-4-5", "claude-haiku-4-5"]
# Rotated through the scenarios so model comparisons have data on every family
# Open-weight models served on /v1/chat/completions
OPEN_WEIGHT_MODELS = ["kimi-k3", "deepseek-v4-flash"]
# kimi-k3 reasons before answering; with a small cap it returns no content
REASONING_MIN_TOKENS = {"kimi-k3": 1500}
MODEL_MIX = [PRIMARY_MODEL, "claude-sonnet-4-5", "kimi-k3", SECONDARY_MODEL,
             "claude-haiku-4-5", "deepseek-v4-flash"]
# Error spans for the error-rate charts: an unknown model, and a Claude model sent
# to /v1/chat/completions (the classic wrong-endpoint mistake)
ERROR_MODELS = ["not-a-real-model", "claude-sonnet-4-5"]


def mix(i):
    return MODEL_MIX[i % len(MODEL_MIX)]


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


def claude_call(model, prompt, traceparent=None, max_tokens=256, system=None):
    headers = {"Authorization": f"Bearer {PAT}", "Content-Type": "application/json"}
    if traceparent:
        headers["traceparent"] = traceparent
    body = {"model": model, "max_tokens": max_tokens,
            "messages": [{"role": "user", "content": prompt}]}
    if system:
        body["system"] = system
    resp = requests.post(f"{BASE_URL}/messages", headers=headers, json=body, timeout=180)
    resp.raise_for_status()
    return "".join(b.get("text", "") for b in resp.json().get("content", []))


def safe_call(model, prompt, traceparent=None, max_tokens=256, system=None, endpoint="auto"):
    """Call the gateway, print result, swallow errors (they still produce traces).

    endpoint="auto" sends Claude to /v1/messages; "chat" forces /v1/chat/completions.
    """
    max_tokens = max(max_tokens, REASONING_MIN_TOKENS.get(model, 0))
    if model.startswith("claude") and endpoint == "auto":
        try:
            text = claude_call(model, prompt, traceparent, max_tokens, system)
            print(f"  OK  {model:35s} | {text[:70]}...")
            return True
        except Exception as e:
            print(f"  ERR {model:35s} | {str(e)[:80]}")
            return False
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


# ---------------------------------------------------------------------------
# Burst mode: drive the quota-demo user past its daily limit
# ---------------------------------------------------------------------------
DENIAL_FILE = Path(__file__).resolve().parent.parent / "app" / "output" / "last_quota_denial.json"
BURST_MODEL = "openai-gpt-5.4"
BURST_PROMPT = ("Write a detailed 3,000-word merchandising and assortment plan for Fall 2026 covering "
                "every product line and channel, with buys, pricing, markdown cadence, KPIs and risks for each.")


def burst_call(pat):
    traceparent, trace_id = make_traceparent()
    resp = requests.post(
        f"{BASE_URL}/chat/completions", timeout=300,
        headers={"Authorization": f"Bearer {pat}", "traceparent": traceparent},
        json={"model": BURST_MODEL, "max_completion_tokens": 8000,
              "messages": [{"role": "user", "content": BURST_PROMPT}]},
    )
    usage = resp.json().get("usage", {}) if resp.ok else {}
    return resp.status_code, resp.text[:1000], trace_id, usage.get("completion_tokens")


def run_burst(pat, max_rounds, workers=8, pause_s=20):
    """Spend in rounds until the gateway denies a request (enforcement lands within minutes)."""
    for rnd in range(1, max_rounds + 1):
        with ThreadPoolExecutor(workers) as pool:
            results = list(pool.map(lambda _: burst_call(pat), range(workers)))
        denied = [r for r in results if r[0] >= 400]
        print(f"round {rnd}: " + ", ".join(f"{s}:{t or '-'}tok" for s, _, _, t in results))
        if denied:
            status, body, trace_id, _ = denied[0]
            DENIAL_FILE.parent.mkdir(parents=True, exist_ok=True)
            DENIAL_FILE.write_text(json.dumps({
                "captured_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "user": "GATEWAY_RETAIL_COST_DEMO",
                "model": BURST_MODEL, "status": status, "body": body, "trace_id": trace_id}, indent=2))
            print(f"\nDenied with HTTP {status}: {body[:300]}\nSaved to {DENIAL_FILE}")
            return 0
        time.sleep(pause_s)
    print("No denial yet: usage takes a few minutes to be evaluated. Re-run --burst shortly.")
    return 1


_args = argparse.ArgumentParser()
_args.add_argument("--burst", action="store_true", help="spend as the quota-demo user until blocked")
_args.add_argument("--burst-pat-file", default="~/.snowflake/gateway_retail_cost.pat")
_args.add_argument("--rounds", type=int, default=30)
ARGS = _args.parse_args()
if ARGS.burst:
    sys.exit(run_burst(Path(os.path.expanduser(ARGS.burst_pat_file)).read_text().strip(), ARGS.rounds))


# ===================================================================
print("=== Scenario 1: Simple single-turn calls (primary model) ===")
# ===================================================================
simple_prompts = [
    "What is sell-through rate in retail? Answer in one sentence.",
    "Define average order value. One line.",
    "What does GMROI mean? Brief answer.",
    "Explain weeks of supply in 2 sentences.",
    "What is a markdown cadence? Brief answer.",
    "Define customer lifetime value in one sentence.",
    "What is A/B testing? One sentence.",
    "Explain open-to-buy in retail planning. Brief answer.",
    "What is a stockout rate? One line.",
    "Define customer churn.",
    "What is DTC in retail? Brief answer.",
    "Explain MAPE for demand forecasts in one sentence.",
]

for i, prompt in enumerate(simple_prompts):
    safe_call(mix(i), prompt, max_tokens=100)
    time.sleep(0.3)

# ===================================================================
print("\n=== Scenario 2: Multi-span agent traces ===")
# ===================================================================
agent_conversations = [
    [
        "What was total net revenue for the 2024 holiday season?",
        "Break that down by channel: DTC Website, Retail Store, Wholesale, International DTC.",
        "Which channel had the best gross margin and why?",
    ],
    [
        "Which customer segments carry the most churn risk?",
        "What retention offer would you test for High-Value At-Risk customers?",
    ],
    [
        "How did the Performance product line sell through in Fall 2025?",
        "How does that compare to plan?",
        "Write a brief executive summary of Performance line results.",
    ],
    [
        "What was ROAS for Influencer campaigns?",
        "Compare Influencer ROAS to Retargeting ROAS.",
    ],
    [
        "Which stores had the most stockouts in November and December?",
        "Which product lines drove those stockouts?",
        "What should we change in the Holiday 2025 buy?",
    ],
]

for n, convo in enumerate(agent_conversations):
    traceparent, trace_id = make_traceparent()
    convo_model = mix(n)
    print(f"\n  Trace {trace_id[:12]}... ({len(convo)} turns)")
    for msg in convo:
        safe_call(convo_model, msg, traceparent=traceparent, max_tokens=300)
        time.sleep(0.3)

# ===================================================================
print("\n=== Scenario 3: Long output / token bloat prompts ===")
# ===================================================================
verbose_prompts = [
    "Write a detailed 500-word assortment strategy for Spring 2026 covering every product line with buy depth, price points, KPIs, and launch timing.",
    "Create a comprehensive churn retention playbook covering segments, triggers, offers, channels, and measurement. Be thorough and detailed.",
    "Draft a complete quarterly business review for Q3 2025 retail performance including executive summary, channel-by-channel analysis, key wins, misses, and recommendations.",
    "Write an extensive competitive analysis of DTC Website, Retail Store, Wholesale, and International DTC across margin, return rate, customer acquisition cost, and growth.",
]

for i, prompt in enumerate(verbose_prompts):
    safe_call(
        PRIMARY_MODEL if i % 2 == 0 else "claude-sonnet-4-5",
        prompt,
        max_tokens=2048,
        system="You are a detailed retail analytics assistant. Always give comprehensive, thorough responses with specific numbers and examples.",
    )
    time.sleep(1)

# ===================================================================
print("\n=== Scenario 4: Error traces (unknown models) ===")
# ===================================================================
# These will fail with 400 "unknown model" but still create trace spans
# with STATUS_CODE_ERROR — exactly what the error charts need.
error_prompts = [
    "Classify this review as positive, negative, or neutral: 'The DreamKnit joggers pilled after two washes'",
    "Extract the key metrics from: 'Net revenue was $4.2M on 38,000 orders with a 14% return rate'",
    "Summarize: Loyal VIP customers have the lowest churn risk but the highest lifetime value.",
    "What day of the week has the highest DTC traffic?",
    "List 3 ways to reduce online return rates.",
    "What is omnichannel retail? Brief answer.",
    "Define inventory turns.",
    "What is a size curve? One sentence.",
]

for i, prompt in enumerate(error_prompts):
    model = ERROR_MODELS[i % len(ERROR_MODELS)]
    safe_call(model, prompt, max_tokens=100, endpoint="chat")
    time.sleep(0.3)

# ===================================================================
print("\n=== Scenario 5: Mixed model multi-span traces ===")
# ===================================================================
# First span succeeds (primary model), second fails (unknown model)
# This creates interesting mixed-status traces.
mixed_traces = [
    ("Analyze holiday 2024 retail performance across all channels.", "What were the key risks?"),
    ("What was our overall return rate for the year?", "How does that compare to apparel benchmarks?"),
]

for q1, q2 in mixed_traces:
    traceparent, trace_id = make_traceparent()
    print(f"\n  Mixed trace {trace_id[:12]}...")
    safe_call("claude-sonnet-4-5", q1, traceparent=traceparent, max_tokens=400)
    time.sleep(0.3)
    safe_call(ERROR_MODELS[0], q2, traceparent=traceparent, max_tokens=200)
    time.sleep(0.5)

# ===================================================================
print("\n=== Scenario 6: Additional primary model variety ===")
# ===================================================================
# More calls with different prompt lengths for latency distribution variety
variety_prompts = [
    ("hi", 20),
    ("What is AOV?", 50),
    ("Explain the difference between wholesale and DTC economics in detail.", 500),
    ("Write a one-paragraph summary of holiday 2024 retail results.", 300),
    ("What are KPIs?", 30),
    ("List the top 5 athletic apparel trends for 2026 with brief explanations.", 500),
    ("Define gross margin.", 20),
    ("What is customer churn and how does a churn model help retention marketing? Provide a detailed explanation.", 600),
]

for i, (prompt, max_tok) in enumerate(variety_prompts):
    safe_call(mix(i), prompt, max_tokens=max_tok)
    time.sleep(0.3)

# ===================================================================
print("\n=== Done ===")
print(f"Models: {MODEL_MIX} (success), {ERROR_MODELS} on /chat/completions (errors)")
print("Traces should appear in AGENT_TRACE_TABLE within seconds.")
