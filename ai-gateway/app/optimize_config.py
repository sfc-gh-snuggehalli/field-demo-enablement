"""Configs shared by the Advisor and Experiments pages.

An Advisor finding seeds Experiments with a full baseline (what traffic looks
like today) and a full candidate (baseline + the proposed fix), so the
experiment always isolates the change being tested.
"""

from __future__ import annotations

import pandas as pd

MODELS = ["openai-gpt-5.4", "openai-gpt-5.4-mini", "openai-gpt-5-mini", "openai-gpt-5-nano",
          "claude-haiku-4-5", "claude-sonnet-4-5"]
DEFAULT_MODEL = "openai-gpt-5.4"
# Traces do not record the client's max_tokens, so the baseline uses the
# unconstrained default the lab traffic was generated with.
DEFAULT_MAX_TOKENS = 2048
DEFAULT_SYSTEM = (
    "You are a detailed marketing analyst. Always give comprehensive, thorough "
    "responses with specific numbers and examples."
)
CONCISE_SYSTEM = (
    "You are a concise marketing analyst. Answer in at most 3 short sentences or "
    "3 bullets. Lead with the number or the direct answer."
)
CONCISE_MAX_TOKENS = 300
ALT_MODEL = "openai-gpt-5.4-mini"


def config(model: str = DEFAULT_MODEL, max_tokens: int = DEFAULT_MAX_TOKENS,
           system_prompt: str = DEFAULT_SYSTEM) -> dict:
    return {"model": model, "max_tokens": int(max_tokens), "system_prompt": system_prompt}


def dominant_model(df: pd.DataFrame) -> str:
    models = df["REQUEST_MODEL"].dropna()
    return models.value_counts().index[0] if not models.empty else DEFAULT_MODEL


def other_model(model: str, preferred: str = ALT_MODEL) -> str:
    """An alternative to `model`, so a model-swap candidate never equals its baseline."""
    if model != preferred:
        return preferred
    return "openai-gpt-5-nano" if preferred != "openai-gpt-5-nano" else DEFAULT_MODEL


def proposal(finding: str, baseline: dict, **changes) -> dict:
    return {"finding": finding, "baseline": baseline, "candidate": {**baseline, **changes}}
