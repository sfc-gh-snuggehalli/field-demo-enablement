"""The optimizer's own LLM calls: diagnosis, prompt proposals and the rubric judge.

Every call goes through the Cortex AI Gateway (gateway_client.chat), never through
in-warehouse AI_COMPLETE, so the optimizer is governed, traced and costed like any
other AI client:

  * each call gets its own W3C traceparent
  * the conversation id is optimizer-<role>-<run_id>, which groups optimizer traces
    and keeps them separate from the workload in AGENT_TRACE_TABLE
  * each call is logged to OPTIMIZER_CALLS with its trace_id, tokens and latency
"""

from __future__ import annotations

import json
import re
import uuid
from concurrent.futures import ThreadPoolExecutor

import numpy as np
import pandas as pd

from gateway_client import GatewayResult, chat, new_traceparent

OPTIMIZER_MODEL = "claude-sonnet-4-5"
JUDGE_MODELS = ["claude-sonnet-4-5", "openai-gpt-5.4"]   # primary, optional second judge
RUBRIC_WEIGHTS = {"correctness": 0.5, "completeness": 0.2, "conciseness": 0.1, "compliance": 0.2}

COMPLIANCE_RULES = (
    "Field communication must stay within the labeled indications, must not claim clinical "
    "superiority over a competitor without head-to-head data, must not suggest off-label use, "
    "and must never include patient-identifiable information."
)


def conversation_id(role: str, run_id: str) -> str:
    return f"optimizer-{role}-{run_id}"


# ---------------------------------------------------------------------------
# JSON calls through the gateway
# ---------------------------------------------------------------------------
def _parse_json(text: str) -> dict | None:
    """First JSON object in a model reply (tolerates ```json fences and prose around it)."""
    if not text:
        return None
    text = re.sub(r"^```(?:json)?|```$", "", text.strip(), flags=re.MULTILINE).strip()
    try:
        obj = json.loads(text)
        return obj if isinstance(obj, dict) else None
    except json.JSONDecodeError:
        pass
    start = text.find("{")
    while start != -1:
        depth = 0
        for i in range(start, len(text)):
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            if depth == 0:
                try:
                    obj = json.loads(text[start:i + 1])
                    return obj if isinstance(obj, dict) else None
                except json.JSONDecodeError:
                    break
        start = text.find("{", start + 1)
    return None


def chat_json(prompt: str, required: list[str], *, role: str, run_id: str,
              model: str = OPTIMIZER_MODEL, system: str | None = None,
              max_tokens: int = 1500) -> tuple[dict | None, list[GatewayResult]]:
    """Ask for a JSON object with the `required` keys. One traced repair retry on bad JSON.

    Returns (object or None, every GatewayResult made) so callers can log all attempts.
    """
    conv = conversation_id(role, run_id)
    instruction = (f"\n\nReturn ONLY a JSON object with the keys {', '.join(required)}. "
                   "No markdown, no prose outside the JSON.")
    attempts: list[GatewayResult] = []
    traceparent, _ = new_traceparent()
    res = chat(prompt + instruction, model, system=system, max_tokens=max_tokens,
               traceparent=traceparent, conversation_id=conv, json_mode=True)
    attempts.append(res)
    obj = _parse_json(res.content) if res.ok else None
    if res.ok and (obj is None or not all(k in obj for k in required)):
        traceparent, _ = new_traceparent()
        repair = chat(f"Your previous reply was not the required JSON.\n\nPrevious reply:\n{res.content[:4000]}"
                      f"{instruction}", model, system=system, max_tokens=max_tokens,
                      traceparent=traceparent, conversation_id=conv)
        attempts.append(repair)
        obj = _parse_json(repair.content) if repair.ok else None
    if obj is not None and not all(k in obj for k in required):
        obj = None
    return obj, attempts


def log_calls(session, role: str, run_id: str, model: str, attempts: list[GatewayResult]) -> None:
    """Record optimizer calls in OPTIMIZER_CALLS (one multi-row insert)."""
    if not attempts:
        return
    rows, params = [], []
    for r in attempts:
        rows.append("(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
        params += [uuid.uuid4().hex[:12], role, run_id, model, r.trace_id, conversation_id(role, run_id),
                   r.input_tokens, r.output_tokens, round(r.latency_ms), "OK" if r.ok else f"HTTP {r.status_code}"]
    session.sql(
        "INSERT INTO OPTIMIZER_CALLS (CALL_ID, ROLE, RUN_ID, MODEL, TRACE_ID, CONVERSATION_ID, "
        "INPUT_TOKENS, OUTPUT_TOKENS, LATENCY_MS, STATUS) VALUES " + ", ".join(rows), params=params,
    ).collect()


# ---------------------------------------------------------------------------
# Rubric judge
# ---------------------------------------------------------------------------
JUDGE_SYSTEM = ("You are a strict evaluator of answers from a medical device field sales assistant. "
                "Score fairly and briefly explain the main deduction.")


def _judge_prompt(question: str, expected: str, response: str, category: str) -> str:
    return f"""Score the RESPONSE against the EXPECTED answer for the QUESTION.

Criteria, each scored from 0 to 1:
- correctness: the facts and numbers match EXPECTED (allow rounding and formatting differences).
- completeness: every part of the question is answered.
- conciseness: no padding; length fits the question.
- compliance: {COMPLIANCE_RULES} Score 1 when nothing is violated.

QUESTION ({category}): {question}
EXPECTED: {expected}
RESPONSE: {response[:6000]}

Keys: correctness, completeness, conciseness, compliance (numbers 0-1) and rationale (one sentence)."""


def _weighted(detail: dict) -> float | None:
    try:
        return round(sum(float(detail[k]) * w for k, w in RUBRIC_WEIGHTS.items()), 4)
    except (KeyError, TypeError, ValueError):
        return None


def judge_run(session, run_id: str, rows: pd.DataFrame, judge_models: list[str],
              workers: int = 4) -> pd.DataFrame:
    """Score each OK row of a run with the rubric judge(s) through the gateway.

    rows needs PROMPT_ID, PROMPT, EXPECTED, CATEGORY, RESPONSE. Writes JUDGE_SCORE,
    JUDGE_DETAIL, JUDGE_MODEL and JUDGE_TRACE_ID to OPTIMIZATION_RESULTS and logs every
    call to OPTIMIZER_CALLS. Returns one row per prompt with the scores.
    """
    keys = list(RUBRIC_WEIGHTS) + ["rationale"]

    def one(job):
        row, model = job
        obj, attempts = chat_json(_judge_prompt(row.PROMPT, row.EXPECTED, row.RESPONSE, row.CATEGORY),
                                  keys, role="judge", run_id=run_id, model=model,
                                  system=JUDGE_SYSTEM, max_tokens=400)
        return row.PROMPT_ID, model, obj, attempts

    jobs = [(r, m) for r in rows.itertuples() for m in judge_models]
    with ThreadPoolExecutor(workers) as pool:
        results = list(pool.map(one, jobs))

    for model in judge_models:
        log_calls(session, "judge", run_id, model,
                  [a for _, m, _, att in results if m == model for a in att])

    out = []
    for pid in rows["PROMPT_ID"]:
        per = [(m, obj, att) for p, m, obj, att in results if p == pid]
        scores = {m: _weighted(obj) for m, obj, _ in per if obj}
        valid = [s for s in scores.values() if s is not None]
        primary = next((obj for m, obj, _ in per if m == judge_models[0] and obj), None) or \
            next((obj for _, obj, _ in per if obj), None)
        detail = dict(primary or {})
        if len(judge_models) > 1:
            detail["judges"] = scores
            if len(valid) > 1:
                detail["agreement"] = round(1 - (max(valid) - min(valid)), 4)
        trace = next((att[-1].trace_id for m, _, att in per if m == judge_models[0]), None)
        out.append({"PROMPT_ID": pid, "JUDGE_SCORE": float(np.mean(valid)) if valid else None,
                    "JUDGE_DETAIL": json.dumps(detail) if detail else None,
                    "JUDGE_MODEL": ",".join(judge_models), "JUDGE_TRACE_ID": trace})
    scored = pd.DataFrame(out)

    values, params = [], []
    for r in scored.itertuples():
        values.append("(?, ?, ?, ?, ?)")
        params += [r.PROMPT_ID, r.JUDGE_SCORE, r.JUDGE_DETAIL, r.JUDGE_MODEL, r.JUDGE_TRACE_ID]
    if values:
        session.sql(
            "UPDATE OPTIMIZATION_RESULTS r SET JUDGE_SCORE = v.column2, "
            "JUDGE_DETAIL = TRY_PARSE_JSON(v.column3), JUDGE_MODEL = v.column4, JUDGE_TRACE_ID = v.column5 "
            "FROM (SELECT * FROM VALUES " + ", ".join(values) + ") v "
            "WHERE r.RUN_ID = ? AND r.PROMPT_ID = v.column1",
            params=params + [run_id],
        ).collect()
    return scored


# ---------------------------------------------------------------------------
# Prompt optimizer (OPRO / APE style)
# ---------------------------------------------------------------------------
def propose_prompts(session, run_id: str, current_system: str, failures: pd.DataFrame,
                    n: int = 3) -> tuple[list[dict], str | None]:
    """Ask the optimizer model for n improved system prompts from the weakest answers.

    failures needs PROMPT, EXPECTED, RESPONSE, JUDGE_SCORE and JUDGE_DETAIL (rationale).
    Returns ([{system_prompt, rationale}], trace_id of the proposing call).
    """
    examples = []
    for r in failures.itertuples():
        detail = r.JUDGE_DETAIL if isinstance(r.JUDGE_DETAIL, dict) else _parse_json(str(r.JUDGE_DETAIL or "")) or {}
        examples.append(f"- QUESTION: {r.PROMPT}\n  EXPECTED: {r.EXPECTED}\n  RESPONSE: {str(r.RESPONSE)[:700]}\n"
                        f"  SCORE: {r.JUDGE_SCORE}  JUDGE: {detail.get('rationale', '')}")
    prompt = f"""You optimize system prompts for a medical device field sales assistant that answers
from facts supplied in the user message (sales, share, risk, labeling, evidence, policy).

CURRENT SYSTEM PROMPT:
{current_system}

LOWEST-SCORING ANSWERS UNDER THE CURRENT PROMPT:
{chr(10).join(examples)}

Write {n} different improved system prompts. Each must:
- fix the failure patterns above (accuracy against the supplied facts, answering every part, length)
- keep answers short: lead with the number or the direct answer
- keep this compliance rule verbatim in spirit: {COMPLIANCE_RULES}
- be under 120 words

Keys: candidates (a list of {n} objects, each with system_prompt and rationale)."""
    obj, attempts = chat_json(prompt, ["candidates"], role="propose_prompt", run_id=run_id,
                              max_tokens=2000)
    log_calls(session, "propose_prompt", run_id, OPTIMIZER_MODEL, attempts)
    cands = [c for c in (obj or {}).get("candidates", [])
             if isinstance(c, dict) and str(c.get("system_prompt", "")).strip()]
    return cands[:n], (attempts[-1].trace_id if attempts else None)


def split_dev_holdout(prompt_ids: list[str]) -> tuple[list[str], list[str]]:
    """Deterministic alternate split, so optimizing on dev is confirmed on unseen prompts."""
    ids = sorted(prompt_ids)
    return ids[0::2], ids[1::2]


# ---------------------------------------------------------------------------
# Statistics
# ---------------------------------------------------------------------------
def paired_bootstrap_ci(base: pd.Series, cand: pd.Series, n_boot: int = 2000,
                        seed: int = 7) -> tuple[float, float, float] | None:
    """Mean paired difference (cand - base) with a 95% bootstrap CI, matched on index."""
    both = pd.concat([base, cand], axis=1, keys=["b", "c"]).dropna()
    if len(both) < 3:
        return None
    diff = (both["c"] - both["b"]).to_numpy(dtype=float)
    rng = np.random.default_rng(seed)
    means = rng.choice(diff, size=(n_boot, len(diff)), replace=True).mean(axis=1)
    return float(diff.mean()), float(np.percentile(means, 2.5)), float(np.percentile(means, 97.5))
