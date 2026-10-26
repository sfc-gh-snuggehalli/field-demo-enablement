"""Generate diverse AI Gateway trace data for the Trace Analyzer app.

Usage:
    export SNOWFLAKE_ACCOUNT=<org-account>   # e.g. myorg-myaccount
    export SNOWFLAKE_PAT=<pat>               # or SNOWFLAKE_PAT_FILE=<path>
    python generate_traffic.py

    # Cost governance demo: the territory-planning batch agent runs away until
    # its FIELD quota blocks it
    python generate_traffic.py --burst [--burst-pat-file ~/.snowflake/gateway_medtech_territory_planner.pat]

Uses LangChain ChatOpenAI (same as the demo notebook) to make real inference
calls through the Cortex AI Gateway. Each scenario runs as the commercial
persona it fits (setup.sql section 9b), using that persona's PAT from
$PERSONA_PAT_DIR/gateway_medtech_<persona>.pat, so traces and spend break down
by user. A persona without a PAT file falls back to SNOWFLAKE_PAT. Intentionally
calls unknown model names to generate error traces for dashboard diversity.
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
    os.path.expanduser(os.environ.get("SNOWFLAKE_PAT_FILE", "~/.snowflake/ai_gateway_medtech.pat"))
).read_text().strip()
PERSONA_PAT_DIR = Path(os.path.expanduser(os.environ.get("PERSONA_PAT_DIR", "~/.snowflake")))
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


_PERSONA_PATS = {}


def persona_pat(persona):
    """PAT for GATEWAY_MEDTECH_<persona>, or SNOWFLAKE_PAT if its file is missing."""
    if persona not in _PERSONA_PATS:
        f = PERSONA_PAT_DIR / f"gateway_medtech_{persona.lower()}.pat"
        if f.is_file():
            _PERSONA_PATS[persona] = f.read_text().strip()
        else:
            print(f"  (no {f}: {persona} traffic runs as you; ./demo.sh pat creates it)")
            _PERSONA_PATS[persona] = PAT
    return _PERSONA_PATS[persona]


def make_llm(model=PRIMARY_MODEL, traceparent=None, max_tokens=256, pat=None):
    headers = {}
    if traceparent:
        headers["traceparent"] = traceparent
    return ChatOpenAI(
        model=model,
        base_url=BASE_URL,
        api_key=pat or PAT,
        temperature=0.7,
        max_completion_tokens=max_tokens,  # GPT-5 family rejects max_tokens
        default_headers=headers or None,
    )


def claude_call(model, prompt, traceparent=None, max_tokens=256, system=None, pat=None):
    headers = {"Authorization": f"Bearer {pat or PAT}", "Content-Type": "application/json"}
    if traceparent:
        headers["traceparent"] = traceparent
    body = {"model": model, "max_tokens": max_tokens,
            "messages": [{"role": "user", "content": prompt}]}
    if system:
        body["system"] = system
    resp = requests.post(f"{BASE_URL}/messages", headers=headers, json=body, timeout=180)
    resp.raise_for_status()
    return "".join(b.get("text", "") for b in resp.json().get("content", []))


def safe_call(model, prompt, traceparent=None, max_tokens=256, system=None, endpoint="auto",
              persona=None):
    """Call the gateway as a persona, print result, swallow errors (they still produce traces).

    endpoint="auto" sends Claude to /v1/messages; "chat" forces /v1/chat/completions.
    """
    pat = persona_pat(persona) if persona else PAT
    who = f"{(persona or 'you'):17s} "
    max_tokens = max(max_tokens, REASONING_MIN_TOKENS.get(model, 0))
    if model.startswith("claude") and endpoint == "auto":
        try:
            text = claude_call(model, prompt, traceparent, max_tokens, system, pat=pat)
            print(f"  OK  {who}{model:22s} | {text[:60]}...")
            return True
        except Exception as e:
            print(f"  ERR {who}{model:22s} | {str(e)[:80]}")
            return False
    try:
        llm = make_llm(model=model, traceparent=traceparent, max_tokens=max_tokens, pat=pat)
        messages = []
        if system:
            messages.append(("system", system))
        messages.append(("human", prompt))
        resp = llm.invoke(messages)
        print(f"  OK  {who}{model:22s} | {resp.content[:60]}...")
        return True
    except Exception as e:
        err = str(e)[:80]
        print(f"  ERR {who}{model:22s} | {err}")
        return False


# Commercial personas (setup.sql section 9b; users are GATEWAY_MEDTECH_<persona>)
FIELD = ["REP_NORTHEAST", "REP_SOUTHEAST", "TM_WEST"]
ANALYSTS = ["SALES_OPS", "MARKET_ACCESS"]
PLATFORM = "AI_PLATFORM"
BATCH_AGENT = "TERRITORY_PLANNER"
EVERYONE = FIELD + ANALYSTS + [PLATFORM]


# ---------------------------------------------------------------------------
# Burst mode: the territory-planning batch agent runs away past its daily limit
# ---------------------------------------------------------------------------
DENIAL_FILE = Path(__file__).resolve().parent.parent / "app" / "output" / "last_quota_denial.json"
BURST_MODEL = "openai-gpt-5.4"
BURST_PROMPT = ("Write a detailed 8,000-word FY2027 territory and account plan for a medical device field team "
                "covering every therapy area, top IDNs, contract renewals, competitive threats, quota and risks for each. "
                "Give each therapy area its own section with account-by-account detail.")
# Measured for BURST_MODEL through the gateway: about 7.5 credits per million
# output tokens (input is negligible here). Only used to pace the burst.
BURST_CREDITS_PER_M_TOKENS = 7.5


def burst_call(pat, max_tokens):
    traceparent, trace_id = make_traceparent()
    try:
        resp = requests.post(
            f"{BASE_URL}/chat/completions", timeout=600,
            headers={"Authorization": f"Bearer {pat}", "traceparent": traceparent},
            json={"model": BURST_MODEL, "max_completion_tokens": max_tokens,
                  "messages": [{"role": "user", "content": BURST_PROMPT}]},
        )
    except requests.RequestException as e:
        return 0, str(e)[:300], trace_id, None
    usage = resp.json().get("usage", {}) if resp.ok else {}
    return resp.status_code, resp.text[:1000], trace_id, usage.get("completion_tokens")


def is_quota_denial(status, body):
    """The block is a 403 that names the quota; 429s and 5xx are just retried."""
    return status != 200 and (status == 403 or "quota" in body.lower())


def run_burst(pat, max_rounds, limit, workers=16, pause_s=5, probe_pause_s=30):
    """Spend in rounds until the gateway denies a request.

    Enforcement lands within minutes of the spend, not per request. Once the
    estimated spend passes the limit, send one small probe at a time so the
    overshoot is the enforcement lag, not more full rounds.
    """
    spent = 0.0
    for rnd in range(1, max_rounds + 1):
        probing = spent >= limit * 1.1
        n, max_tokens = (1, 200) if probing else (workers, 16000)
        with ThreadPoolExecutor(n) as pool:
            results = list(pool.map(lambda _: burst_call(pat, max_tokens), range(n)))
        spent += sum(t or 0 for _, _, _, t in results) * BURST_CREDITS_PER_M_TOKENS / 1e6
        print(f"round {rnd}{' (probe)' if probing else ''}: ~{spent:.1f} of {limit} credits | "
              + ", ".join(f"{s}:{t or '-'}tok" for s, _, _, t in results), flush=True)
        denied = [r for r in results if is_quota_denial(r[0], r[1])]
        for status, body, _, _ in results:
            if status != 200 and not is_quota_denial(status, body):
                print(f"  transient HTTP {status}: {body[:120]}", flush=True)
        if denied:
            status, body, trace_id, _ = denied[0]
            DENIAL_FILE.parent.mkdir(parents=True, exist_ok=True)
            DENIAL_FILE.write_text(json.dumps({
                "captured_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "user": f"GATEWAY_MEDTECH_{BATCH_AGENT}",
                "model": BURST_MODEL, "status": status, "body": body, "trace_id": trace_id}, indent=2))
            print(f"\nDenied with HTTP {status}: {body[:300]}\nSaved to {DENIAL_FILE}")
            return 0
        time.sleep(probe_pause_s if probing else pause_s)
    print("No denial yet: usage takes a few minutes to be evaluated. Re-run --burst shortly.")
    return 1


_args = argparse.ArgumentParser()
_args.add_argument("--burst", action="store_true",
                   help="run as the territory-planning batch agent until its quota blocks it")
_args.add_argument("--burst-pat-file", default=f"~/.snowflake/gateway_medtech_{BATCH_AGENT.lower()}.pat")
_args.add_argument("--rounds", type=int, default=40, help="max rounds, probes included")
_args.add_argument("--limit", type=float, default=5,
                   help="the agent's daily limit in credits (GATEWAY_MEDTECH_FIELD_QUOTA)")
ARGS = _args.parse_args()
if ARGS.burst:
    sys.exit(run_burst(Path(os.path.expanduser(ARGS.burst_pat_file)).read_text().strip(),
                       ARGS.rounds, ARGS.limit))


# ===================================================================
print("=== Scenario 1: Simple single-turn calls (primary model) ===")
# ===================================================================
simple_prompts = [
    "What is average selling price (ASP) in medical device sales? Answer in one sentence.",
    "Define a bill-only order. One line.",
    "What is a group purchasing organization (GPO)? Brief answer.",
    "Explain consignment inventory in 2 sentences.",
    "What is a hospital value analysis committee? Brief answer.",
    "Define procedure share in one sentence.",
    "What is an IDN? One sentence.",
    "Explain contract price tiers in device sales. Brief answer.",
    "What is quota attainment? One line.",
    "Define a competitive conversion.",
    "What is a KOL in medtech? Brief answer.",
    "Explain what MR Conditional means for an implant in one sentence.",
]

for i, prompt in enumerate(simple_prompts):
    safe_call(mix(i), prompt, max_tokens=100, persona=FIELD[i % len(FIELD)])
    time.sleep(0.3)

# ===================================================================
print("\n=== Scenario 2: Multi-span agent traces ===")
# ===================================================================
agent_conversations = [
    [
        "What was net revenue for Cardiac Rhythm in fiscal 2026?",
        "Break that down by product family: pacemaker, ICD, leadless pacemaker and insertable cardiac monitor.",
        "Which family had the lowest average selling price versus list, and why might that be?",
    ],
    [
        "Which accounts carry the most share-loss risk?",
        "What account plan would you run for an academic medical center trialing a competitor's TAVR valve?",
    ],
    [
        "How did procedure share for spinal cord stimulation trend from H1 to H2?",
        "Which competitor gained the most?",
        "Write a brief executive summary for the neuromodulation business leader.",
    ],
    [
        "What discount does a Tier 1 GPO agreement carry?",
        "Compare Tier 1 and Tier 3 on discount and committed share.",
    ],
    [
        "Which accounts have the most consigned units close to expiry?",
        "Which product families drive that?",
        "What should reps do with that stock this quarter?",
    ],
]

convo_personas = ["SALES_OPS", "TM_WEST", "MARKET_ACCESS", "MARKET_ACCESS", "REP_NORTHEAST"]
for n, convo in enumerate(agent_conversations):
    traceparent, trace_id = make_traceparent()
    convo_model = mix(n)
    persona = convo_personas[n % len(convo_personas)]
    print(f"\n  Trace {trace_id[:12]}... ({len(convo)} turns, {persona})")
    for msg in convo:
        safe_call(convo_model, msg, traceparent=traceparent, max_tokens=300, persona=persona)
        time.sleep(0.3)

# ===================================================================
print("\n=== Scenario 3: Long output / token bloat prompts ===")
# ===================================================================
verbose_prompts = [
    "Write a detailed 500-word FY2027 account plan for a 600-bed academic medical center covering every therapy area, physicians, contracts, competitive threats and quarterly actions.",
    "Create a comprehensive competitive defense playbook for structural heart covering triggers, value analysis committee engagement, pricing levers, clinical evidence and measurement. Be thorough and detailed.",
    "Draft a complete quarterly business review for Q4 fiscal 2026 medical device sales including executive summary, therapy-by-therapy analysis, key wins, losses, and recommendations.",
    "Write an extensive comparison of GPO agreements, IDN local agreements and direct agreements across discount, committed share, compliance risk and renewal strategy.",
]

verbose_personas = ["TM_WEST", "MARKET_ACCESS", "SALES_OPS", "MARKET_ACCESS"]
for i, prompt in enumerate(verbose_prompts):
    safe_call(
        PRIMARY_MODEL if i % 2 == 0 else "claude-sonnet-4-5",
        prompt,
        max_tokens=2048,
        system="You are a detailed medical device sales analytics assistant. Always give comprehensive, thorough responses with specific numbers and examples.",
        persona=verbose_personas[i],
    )
    time.sleep(1)

# ===================================================================
print("\n=== Scenario 4: Error traces (unknown models) ===")
# ===================================================================
# These will fail with 400 "unknown model" but still create trace spans
# with STATUS_CODE_ERROR — exactly what the error charts need.
error_prompts = [
    "Classify this complaint as device malfunction, labeling, delivery or use error: 'Reload did not fully fire on the second firing'",
    "Extract the key metrics from: 'Net revenue was $4.2M on 310 implants with a 17% average discount'",
    "Summarize: academic medical centers carry the highest share-loss risk but the largest procedure volumes.",
    "Which day of the week has the most elective procedures?",
    "List 3 ways to reduce expired consigned inventory.",
    "What is a field action notice? Brief answer.",
    "Define contract compliance.",
    "What is a pivotal trial? One sentence.",
]

# The AI platform team wiring up a new integration: unknown models and Claude
# sent to the wrong endpoint.
for i, prompt in enumerate(error_prompts):
    model = ERROR_MODELS[i % len(ERROR_MODELS)]
    safe_call(model, prompt, max_tokens=100, endpoint="chat", persona=PLATFORM)
    time.sleep(0.3)

# ===================================================================
print("\n=== Scenario 5: Mixed model multi-span traces ===")
# ===================================================================
# First span succeeds (Claude), second fails (unknown model)
# This creates interesting mixed-status traces.
mixed_traces = [
    ("Analyze fiscal 2026 medical device sales performance across all therapy areas.", "What were the key risks?"),
    ("What was our overall procedure share for the year?", "How does that compare to medtech industry benchmarks?"),
]

for q1, q2 in mixed_traces:
    traceparent, trace_id = make_traceparent()
    print(f"\n  Mixed trace {trace_id[:12]}...")
    safe_call("claude-sonnet-4-5", q1, traceparent=traceparent, max_tokens=400, persona=PLATFORM)
    time.sleep(0.3)
    safe_call(ERROR_MODELS[0], q2, traceparent=traceparent, max_tokens=200, persona=PLATFORM)
    time.sleep(0.5)

# ===================================================================
print("\n=== Scenario 6: Additional primary model variety ===")
# ===================================================================
# More calls with different prompt lengths for latency distribution variety
variety_prompts = [
    ("hi", 20),
    ("What is ASP?", 50),
    ("Explain the difference between bill-only consignment and direct-ship economics in detail.", 500),
    ("Write a one-paragraph summary of fiscal 2026 medical device sales results.", 300),
    ("What are KPIs?", 30),
    ("List the top 5 medtech commercial trends for 2027 with brief explanations.", 500),
    ("Define net revenue.", 20),
    ("What is account share loss and how does a share-loss model help a field sales team? Provide a detailed explanation.", 600),
]

for i, (prompt, max_tok) in enumerate(variety_prompts):
    safe_call(mix(i), prompt, max_tokens=max_tok, persona=EVERYONE[i % len(EVERYONE)])
    time.sleep(0.3)

# ===================================================================
print("\n=== Scenario 7: Nightly territory-planning batch run ===")
# ===================================================================
# The batch agent's normal run: one plan per region. ./demo.sh burst is this
# same agent stuck in a loop.
for region in ["Northeast", "Southeast", "West"]:
    safe_call(SECONDARY_MODEL, f"Draft a one-page FY2027 territory plan for the {region} region of a "
              "medical device field team: priority accounts, contract renewals and top risks.",
              max_tokens=800, persona=BATCH_AGENT)
    time.sleep(0.3)

# ===================================================================
print("\n=== Done ===")
print(f"Models: {MODEL_MIX} (success), {ERROR_MODELS} on /chat/completions (errors)")
print(f"Personas: {', '.join('GATEWAY_MEDTECH_' + p for p in EVERYONE + [BATCH_AGENT])}")
print("Traces should appear in AGENT_TRACE_TABLE within seconds.")
