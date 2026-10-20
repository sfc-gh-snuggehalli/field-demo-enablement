"""The "host" half of an MCP client, standing in for Claude Desktop.

A Claude model, served by Cortex's Anthropic-compatible Messages endpoint
(POST /api/v2/cortex/v1/messages), sees the MCP server's tools exactly as
tools/list describes them and decides when to call one. This module then runs
each tool_use as a real MCP tools/call, as the selected persona, and feeds the
result back, until the model stops asking for tools. Claude Desktop runs the
same loop, split between Anthropic's API and the desktop app.

Two identities, as with Claude:
  * the model call uses the host-model PAT (the presenter's own user; HOST_LLM_PAT,
    or the file named by HOST_LLM_PAT_FILE), which plays
    the part of the LLM vendor and never touches governed data;
  * the tool call uses the persona's key-pair JWT, which is the identity the
    MCP server, the orchestrator, the bridges and the row access policy see.

Business logic stays server-side: the system prompt only says to use the
connector's tools, as a general-purpose assistant's would.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field

from anthropic import Anthropic

from snowflake_mcp import Exchange, SnowflakeMcpClient, account_host, parse_agent_result

HOST_MODEL = os.environ.get("HOST_LLM_MODEL", "claude-sonnet-4-6")
MAX_MODEL_CALLS = 5
SYSTEM_PROMPT = (
    "You are a helpful assistant with a connector to the user's company data. "
    "Use the connector's tools for any question about the company's business or products, "
    "and answer from what the tools return. Keep tables intact. If a tool says the user "
    "is not entitled to something, tell them plainly and do not try to work around it."
)


def host_pat() -> str:
    """The host-model PAT: HOST_LLM_PAT, else the file HOST_LLM_PAT_FILE (./demo.sh setup writes it)."""
    pat = os.environ.get("HOST_LLM_PAT", "").strip()
    path = os.path.expanduser(os.environ.get("HOST_LLM_PAT_FILE", ""))
    if not pat and path and os.path.exists(path):
        with open(path) as f:
            pat = f.read().strip()
    return pat


def host_client(account: str) -> Anthropic:
    pat = host_pat()
    if not pat:
        raise RuntimeError("No host-model PAT: run ./demo.sh setup (or ./demo.sh pat), or set HOST_LLM_PAT")
    # The SDK appends /v1/messages. auth_token sends 'Authorization: Bearer <PAT>'.
    return Anthropic(
        base_url=f"https://{account_host(account)}/api/v2/cortex",
        api_key=None,
        auth_token=pat,
        default_headers={"X-Snowflake-Authorization-Token-Type": "PROGRAMMATIC_ACCESS_TOKEN"},
        timeout=300.0,
    )


def mcp_tools_to_anthropic(tools: list[dict]) -> list[dict]:
    """tools/list entries map one to one onto Anthropic tool definitions."""
    return [
        {
            "name": t["name"],
            "description": t.get("description", ""),
            "input_schema": t.get("inputSchema") or {"type": "object", "properties": {}},
        }
        for t in tools
    ]


@dataclass
class Step:
    kind: str  # "model" or "tool"
    text: str = ""
    tool_name: str | None = None
    tool_input: dict | None = None
    exchange: Exchange | None = None
    parsed: dict | None = None
    error: str | None = None


@dataclass
class TurnResult:
    answer: str
    steps: list[Step] = field(default_factory=list)


def _tool_result_for_model(parsed: dict) -> str:
    """What the host model gets back. The agent's full JSON (reasoning, nested tool
    calls) stays in the inspector; the model gets the answer and the thread ids it
    can pass on a follow-up, as the tool's input schema allows."""
    lines = [parsed["answer"] or "[no text in agent response]"]
    if parsed.get("charts"):
        # The client renders the agent's native charts itself; the model should not redraw them in text.
        lines.append(f"\n[{len(parsed['charts'])} chart(s) from this tool result are already shown to the user]")
    if parsed.get("thread_id"):
        lines.append(f"\n(thread_id: {parsed['thread_id']}, parent_message_id: {parsed.get('message_id')})")
    return "\n".join(lines)


def _tool_use_ids(msg: dict) -> set[str]:
    content = msg["content"] if isinstance(msg["content"], list) else []
    return {b["id"] for b in content if b.get("type") == "tool_use"}


def _turn_is_complete(turn: list[dict]) -> bool:
    """user text, then (assistant tool_use, user tool_result) pairs, then a final assistant answer."""
    if len(turn) % 2 or turn[-1]["role"] != "assistant" or _tool_use_ids(turn[-1]):
        return False
    for asked, answered in zip(turn[1:-1:2], turn[2:-1:2]):
        ids = _tool_use_ids(asked)
        results = answered["content"] if isinstance(answered["content"], list) else []
        if asked["role"] != "assistant" or not ids or answered["role"] != "user":
            return False
        if {b.get("tool_use_id") for b in results if b.get("type") == "tool_result"} != ids:
            return False
    return True


def complete_turns(history: list[dict]) -> list[dict]:
    """The history without any partial turn (for example one cut off by a rerun), so every
    tool_use the model sees has its tool_result right after it."""
    turns: list[list[dict]] = []
    for msg in history:
        if msg["role"] == "user" and isinstance(msg["content"], str):
            turns.append([msg])
        elif turns:
            turns[-1].append(msg)
    return [m for t in turns if _turn_is_complete(t) for m in t]


def run_turn(
    llm: Anthropic,
    mcp: SnowflakeMcpClient,
    tools: list[dict],
    history: list[dict],
    question: str,
    on_step=None,
) -> TurnResult:
    """One user turn (Anthropic message format). The turn runs on a copy and is written
    back to history only when it finishes, and only if no other run changed history
    meanwhile: Streamlit can start a new run while an old one is still in its tool loop,
    and both would otherwise write into the same list."""
    snapshot = list(history)
    messages = complete_turns(snapshot) + [{"role": "user", "content": question}]
    anthropic_tools = mcp_tools_to_anthropic(tools)
    result = TurnResult(answer="")
    for _ in range(MAX_MODEL_CALLS):
        resp = llm.messages.create(
            model=HOST_MODEL,
            max_tokens=2048,
            system=SYSTEM_PROMPT,
            tools=anthropic_tools,
            messages=messages,
        )
        blocks = [b.model_dump(exclude_none=True) for b in resp.content]
        messages.append({"role": "assistant", "content": blocks})
        text = "\n".join(b.get("text", "") for b in blocks if b.get("type") == "text").strip()
        tool_uses = [b for b in blocks if b.get("type") == "tool_use"]
        step = Step(kind="model", text=text)
        result.steps.append(step)
        if on_step:
            on_step(step)
        if not tool_uses:
            result.answer = text
            if history == snapshot:
                history[:] = messages
            return result
        tool_results = []
        for tu in tool_uses:
            tstep = Step(kind="tool", tool_name=tu["name"], tool_input=tu.get("input") or {})
            try:
                raw, ex = mcp.call_tool(tu["name"], tstep.tool_input)
                tstep.exchange = ex
                tstep.parsed = parse_agent_result(raw)
                content, is_error = _tool_result_for_model(tstep.parsed), bool(raw.get("isError"))
            except Exception as exc:  # noqa: BLE001 - the model and the inspector both see the failure
                tstep.error = str(exc)[:1500]
                content, is_error = f"Tool call failed: {tstep.error}", True
            result.steps.append(tstep)
            if on_step:
                on_step(tstep)
            tool_results.append(
                {"type": "tool_result", "tool_use_id": tu["id"], "content": content, "is_error": is_error}
            )
        messages.append({"role": "user", "content": tool_results})
    result.answer = "[stopped: the model kept calling tools after {} model calls]".format(MAX_MODEL_CALLS)
    return result


def compact_json(obj, limit: int = 4000) -> str:
    text = json.dumps(obj, indent=2, default=str)
    return text if len(text) <= limit else text[:limit] + "\n... (truncated)"
