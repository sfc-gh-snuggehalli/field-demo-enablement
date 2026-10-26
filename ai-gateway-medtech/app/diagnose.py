"""LLM diagnosis of gateway telemetry, sent through the gateway itself.

The rule engine on the Advisor page catches known patterns with fixed thresholds.
This module hands a compact telemetry profile plus a few captured payloads to a
strong model and asks for root causes and a concrete config change to test. Each
finding cites the span_ids it is based on, and its proposal uses the same shape as
the rule findings, so "Test this fix" seeds Experiments the same way.
"""

from __future__ import annotations

import json

import pandas as pd

from optimize_config import MODELS, config
from optimizer import OPTIMIZER_MODEL, chat_json, log_calls

MAX_GROUPS = 12
SAMPLES = 4


def telemetry_profile(df: pd.DataFrame) -> list[dict]:
    """One row per (user, model): volume, latency, errors and token distribution."""
    g = df.groupby(["USER_NAME", "REQUEST_MODEL"], dropna=False)
    prof = g.agg(
        requests=("SPAN_ID", "count"),
        p50_ms=("DURATION_MS", "median"),
        p95_ms=("DURATION_MS", lambda s: s.quantile(0.95)),
        errors=("STATUS_CODE", lambda s: int((s == "STATUS_CODE_ERROR").sum())),
        avg_in=("INPUT_TOKENS", "mean"),
        avg_out=("OUTPUT_TOKENS", "mean"),
        p95_out=("OUTPUT_TOKENS", lambda s: s.quantile(0.95)),
        traces=("TRACE_ID", "nunique"),
    ).reset_index().sort_values("requests", ascending=False).head(MAX_GROUPS)
    return json.loads(prof.round(1).to_json(orient="records"))


def sample_spans(session, df: pd.DataFrame) -> list[dict]:
    """A few captured payloads: the slowest, the most verbose and some errors."""
    pick = pd.concat([
        df.nlargest(2, "OUTPUT_TOKENS"), df.nlargest(1, "DURATION_MS"),
        df[df["STATUS_CODE"] == "STATUS_CODE_ERROR"].head(1),
    ]).drop_duplicates("SPAN_ID").head(SAMPLES)
    if pick.empty:
        return []
    ids = ", ".join(f"'{s}'" for s in pick["SPAN_ID"].astype(str) if s.isalnum())
    rows = session.sql(f"""
        SELECT TRACE:"span_id"::STRING AS SPAN_ID,
               LEFT(RECORD_ATTRIBUTES:"gen_ai.system_instructions"::STRING, 400) AS SYSTEM,
               LEFT(RECORD_ATTRIBUTES:"gen_ai.input.messages"::STRING, 600)      AS INPUT,
               LEFT(RECORD_ATTRIBUTES:"gen_ai.output.messages"::STRING, 600)     AS OUTPUT
        FROM TABLE(AGENT_TRACE_TABLE('SNOWFLAKE'))
        WHERE TIMESTAMP > DATEADD('day', -14, CURRENT_TIMESTAMP())
          AND TRACE:"span_id"::STRING IN ({ids})""").collect() if ids else []
    meta = pick.set_index("SPAN_ID")
    out = []
    for r in rows:
        d = r.as_dict()
        m = meta.loc[d["SPAN_ID"]] if d["SPAN_ID"] in meta.index else None
        if m is not None:
            d.update(model=m["REQUEST_MODEL"], user=m["USER_NAME"], duration_ms=m["DURATION_MS"],
                     output_tokens=m["OUTPUT_TOKENS"], status=m["STATUS_CODE"])
        out.append(d)
    return out


PROMPT = """You are an LLM platform engineer reviewing Cortex AI Gateway telemetry for a medical device
field sales assistant. Find the 2-4 problems most worth fixing for cost, latency, reliability or answer
quality, and propose ONE config change per problem that an experiment can test.

TELEMETRY PROFILE (per user and model):
{profile}

SAMPLE CAPTURED SPANS:
{samples}

A config is: model (one of {models}), max_tokens (16-4096) and system_prompt.
Keep any proposed system prompt under 80 words and include: stay within labeled indications and never
claim clinical superiority over a competitor.

Keys: findings, a list where each item has
  severity (HIGH, MEDIUM or LOW), title (under 90 characters), root_cause (one or two sentences),
  evidence_span_ids (list of span ids from the samples, may be empty), baseline_model (the model the
  flagged traffic uses), change (an object with any of model, max_tokens, system_prompt), expected_impact."""


def diagnose(session, df: pd.DataFrame, run_id: str) -> tuple[list[dict], str | None]:
    """Returns (advisor-style recommendations, trace_id of the diagnosis call)."""
    profile, samples = telemetry_profile(df), sample_spans(session, df)
    obj, attempts = chat_json(
        PROMPT.format(profile=json.dumps(profile, default=str), samples=json.dumps(samples, default=str),
                      models=", ".join(MODELS)),
        ["findings"], role="diagnose", run_id=run_id, max_tokens=2500)
    log_calls(session, "diagnose", run_id, OPTIMIZER_MODEL, attempts)
    trace_id = attempts[-1].trace_id if attempts else None

    recs = []
    for f in (obj or {}).get("findings", []):
        if not isinstance(f, dict):
            continue
        base_model = f.get("baseline_model") if f.get("baseline_model") in MODELS else MODELS[0]
        baseline = config(base_model)
        change = {k: v for k, v in (f.get("change") or {}).items() if k in baseline}
        if "model" in change and change["model"] not in MODELS:
            change.pop("model")
        if "max_tokens" in change:
            try:
                change["max_tokens"] = max(16, min(4096, int(change["max_tokens"])))
            except (TypeError, ValueError):
                change.pop("max_tokens")
        candidate = {**baseline, **change}
        recs.append({
            "severity": str(f.get("severity", "MEDIUM")).upper() if str(f.get("severity", "")).upper() in
                        ("HIGH", "MEDIUM", "LOW") else "MEDIUM",
            "title": str(f.get("title", "AI finding"))[:120],
            "detail": f"{f.get('root_cause', '')} Expected impact: {f.get('expected_impact', '-')}",
            "evidence": [str(s) for s in f.get("evidence_span_ids", []) or []],
            "proposal": ({"finding": f"AI: {str(f.get('title', ''))[:80]}", "baseline": baseline,
                          "candidate": candidate} if candidate != baseline else None),
        })
    return recs, trace_id
