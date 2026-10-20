"""Northwind Assistant: a Claude-style MCP client for the governed multi-agent stack.

The app plays the part of Claude Desktop with a Snowflake connector:
  * a Claude model on Cortex's Anthropic-compatible Messages endpoint decides
    when to use the connector's tools (it sees only what tools/list returns);
  * the app sends each tool call to a Snowflake-managed MCP server, signed in as
    the selected persona.

Two architectures sit behind identical connectors (one tool, northwind_assistant):
  * Hub and spoke  ORCHESTRATOR_MCP -> ORCHESTRATOR_AGENT -> caller's-rights
                   bridges -> SALES_AGENT / SUPPORT_AGENT (separate agent runs)
  * Agent toolset  TOOLSET_MCP -> TOOLSET_AGENT, which inherits sales_analyst and
                   support_kb from the specialists at run time (one agent run)

Snowflake decides what each persona gets in both: runs execute as the persona's
DEFAULT_ROLE, and the specialist grants and row access policy apply on every call.
Native chart blocks in the agent's response are rendered with st.vega_lite_chart.

Run locally (.env holds the account, key paths and the PAT file; nothing is entered in the UI):
    ./demo.sh app
"""

from __future__ import annotations

import os
import time
from concurrent.futures import ThreadPoolExecutor

import streamlit as st

from host_llm import HOST_MODEL, compact_json, host_client, host_pat, run_turn
from personas import DATABASE, PERSONAS, SCHEMA, SERVERS, require_account
from snowflake_mcp import KeyPairAuth, McpError, SnowflakeMcpClient, mcp_server_url

ACCOUNT = require_account()

st.set_page_config(page_title="Northwind Assistant (MCP demo)", layout="wide")

REFUSAL = "This type of question is not available at your access level"
DOMAIN_TOOLS = {"ask_sales", "ask_support", "sales_analyst", "support_kb"}
SAMPLES = [
    "What were total new bookings in FY25-Q4 by theater?",
    "Show new bookings by fiscal quarter and theater as a chart",
    "How do I set up single sign-on?",
    "What was total new bookings in FY25-Q4, and how do I fix a 401 error from the API?",
    "Break that down by territory.",
]


# ── Connections ───────────────────────────────────────────────────────────────
@st.cache_resource(show_spinner=False)
def mcp_client(persona_key: str, arch: str) -> SnowflakeMcpClient:
    persona = PERSONAS[persona_key]
    path = os.path.expanduser(os.environ.get(persona["key_env"], ""))
    if not path or not os.path.exists(path):
        raise RuntimeError(f"Set {persona['key_env']} to the .p8 file for {persona['user']}.")
    url = mcp_server_url(ACCOUNT, DATABASE, SCHEMA, SERVERS[arch]["server"])
    return SnowflakeMcpClient(url, KeyPairAuth(ACCOUNT, persona["user"], path))


@st.cache_resource(show_spinner=False)
def llm():
    return host_client(ACCOUNT)


@st.cache_data(ttl=300, show_spinner=False)
def list_tools(persona_key: str, arch: str) -> list[dict]:
    tools, _ = mcp_client(persona_key, arch).list_tools()
    return tools


def prepare(persona_key: str, arch: str):
    """Resolve cached clients on the script thread (worker threads have no script context)."""
    return llm(), mcp_client(persona_key, arch), list_tools(persona_key, arch)


def ask(prepared, history: list, question: str):
    llm_client, client, tools = prepared
    started = time.monotonic()
    turn = run_turn(llm_client, client, tools, history, question)
    turn.seconds = time.monotonic() - started
    return turn


def tool_steps(steps):
    return [s for s in steps if s.kind == "tool" and s.parsed]


# ── Rendering helpers ─────────────────────────────────────────────────────────
def md_text(text: str) -> None:
    """Markdown for model and agent text. Escape '$' so two dollar amounts in one
    line ("$59.6M ... $22.1M") are not rendered as LaTeX math."""
    st.markdown(text.replace("$", r"\$"))


def render_answer(answer: str, steps) -> None:
    """The answer plus the agent's native charts. Chart specs are parsed JSON
    (Vega-Lite) from the agent's chart blocks, never HTML."""
    md_text(answer or "_(no answer)_")
    for s in tool_steps(steps):
        for spec in s.parsed.get("charts", []):
            try:
                st.vega_lite_chart(spec=spec, width="stretch")
            except Exception as exc:  # noqa: BLE001 - a bad spec should not break the turn
                st.caption(f"Chart could not be rendered: {str(exc)[:200]}")


def render_steps(steps, arch: str) -> None:
    """Inspector: Claude's decisions, the MCP traffic, and what the agent did inside
    Snowflake. Text from tools and models is untrusted and is rendered as Markdown
    (no raw HTML) or as code."""
    agent = SERVERS[arch]["agent"]
    for i, s in enumerate(steps):
        if s.kind == "model":
            if s.text:
                with st.expander(f"Claude ({HOST_MODEL}): model call {i + 1}", expanded=False):
                    md_text(s.text)
            continue
        label = f"Tool call: {s.tool_name}"
        if s.error:
            label += " (failed)"
        elif s.parsed and any(d["denied"] for d in s.parsed["delegations"]):
            label += " (a specialist denied access)"
        with st.expander(label, expanded=False):
            st.caption("Claude wrote these tool arguments")
            st.code(compact_json(s.tool_input, 1500), language="json")
            if s.error:
                st.error(s.error)
                continue
            ex = s.exchange
            st.caption(
                f"MCP JSON-RPC to {SERVERS[arch]['server']}: HTTP {ex.http_status}, "
                f"{ex.content_type or 'n/a'}, {ex.sse_events} SSE event(s), {ex.seconds:.1f}s"
            )
            st.code(compact_json(ex.request, 1500), language="json")
            render_inside_snowflake(s.parsed or {}, agent, arch)


def render_inside_snowflake(parsed: dict, agent: str, arch: str) -> None:
    st.markdown("**Inside Snowflake**")
    calls = parsed.get("delegations", [])
    if arch == "hub":
        if not calls:
            st.write("The orchestrator answered without delegating.")
        for d in calls:
            if d["denied"]:
                st.error(f"{agent} → {d['tool']} → specialist denied: NOT_ENTITLED (error 399513)")
            else:
                st.success(f"{agent} → {d['tool']} → specialist answered ({d['status']})")
            st.code(compact_json(d["input"], 800), language="json")
            if d["result"] and not d["denied"]:
                md_text(d["result"][:3000])
    else:
        used = [d["tool"] for d in calls]
        if used:
            st.success(f"{agent} called (one agent run): " + " → ".join(used))
        if not DOMAIN_TOOLS.intersection(used) and REFUSAL in (parsed.get("answer") or ""):
            st.warning(
                "No inherited domain tool was available for this persona. agent_toolset "
                "skips a referenced agent the caller has no USAGE on, silently: no error, "
                "no NOT_ENTITLED marker. The refusal comes from TOOLSET_AGENT's instructions."
            )
        for d in calls:
            if d["tool"] in DOMAIN_TOOLS:
                st.code(compact_json(d["input"], 800), language="json")
    for t in parsed.get("tables", []):
        st.caption(f"Table block: {t.get('title') or ''}")
        st.dataframe([dict(zip(t["columns"], r)) for r in t["rows"]], hide_index=True)
    if parsed.get("charts"):
        st.caption(f"{len(parsed['charts'])} native chart block(s), rendered under the answer")
    meta = parsed.get("meta") or {}
    st.caption(
        f"thread_id {parsed.get('thread_id')} · run_id {meta.get('run_id')} · "
        f"agent model {meta.get('orchestration_model')}"
    )
    if parsed.get("raw"):
        st.caption("Raw agent response (from the tools/call result)")
        st.code(compact_json(parsed["raw"], 6000), language="json")


def render_result(res, arch: str) -> None:
    if isinstance(res, Exception):
        st.error(str(res)[:1000])
        return
    render_answer(res.answer, res.steps)
    st.caption(f"{getattr(res, 'seconds', 0):.0f}s end to end")
    render_steps(res.steps, arch)


# ── Sidebar: the "connector" ──────────────────────────────────────────────────
st.sidebar.title("Connector")
arch = st.sidebar.radio(
    "Architecture behind the connector",
    list(SERVERS),
    format_func=lambda k: SERVERS[k]["label"],
    horizontal=True,
)
st.sidebar.caption(SERVERS[arch]["summary"])
st.sidebar.code(f"{DATABASE}.{SCHEMA}.{SERVERS[arch]['server']}", language=None)
persona_key = st.sidebar.radio(
    "Signed in as",
    list(PERSONAS),
    format_func=lambda k: PERSONAS[k]["label"],
)
persona = PERSONAS[persona_key]
st.sidebar.markdown(
    f"**Snowflake user** `{persona['user']}`  \n**Default role** `{persona['role']}`  \n"
    f"**Expected reach** {persona['expect']}"
)
try:
    tools = list_tools(persona_key, arch)
    st.sidebar.success(f"Connected: {len(tools)} tool(s) via tools/list")
    for t in tools:
        with st.sidebar.expander(f"Tool: {t['name']}"):
            st.markdown(t.get("description", ""))
            st.code(compact_json(t.get("inputSchema"), 2000), language="json")
except (McpError, RuntimeError, OSError) as exc:
    st.sidebar.error(f"Not connected: {exc}")
    tools = []
if not host_pat():
    st.sidebar.warning("No host-model PAT: run ./demo.sh setup or ./demo.sh pat, then restart the app.")
st.sidebar.caption(f"Host model: {HOST_MODEL} on Cortex /v1/messages")
chat_key = f"chat_{arch}_{persona_key}"
history_key = f"history_{arch}_{persona_key}"
if st.sidebar.button("New conversation"):
    st.session_state.pop(chat_key, None)
    st.session_state.pop(history_key, None)
    st.rerun()

st.title("Northwind Assistant")
st.caption(
    "A Claude-style MCP client. The model chooses the tool; Snowflake decides what "
    "the signed-in persona may see."
)
chat_tab, compare_tab = st.tabs(["Chat", "Compare"])

# ── Chat: one persona, one architecture, multi-turn ──────────────────────────
with chat_tab:
    chat = st.session_state.setdefault(chat_key, [])
    history = st.session_state.setdefault(history_key, [])
    st.caption(f"{SERVERS[arch]['label']} · {persona['label']}")
    clicked = None
    for c, q in zip(st.columns(len(SAMPLES)), SAMPLES):
        if c.button(q, key=f"sample_{chat_key}_{q}", width="stretch"):
            clicked = q
    for turn in chat:
        with st.chat_message("user"):
            md_text(turn["question"])
        with st.chat_message("assistant"):
            render_result(turn["result"], arch)

    typed = st.chat_input(f"Ask as {persona['label']}")
    question = typed or clicked
    if question and tools:
        with st.chat_message("user"):
            md_text(question)
        with st.chat_message("assistant"):
            with st.spinner("Claude is working with the Snowflake connector..."):
                try:
                    result = ask(prepare(persona_key, arch), history, question)
                except Exception as exc:  # noqa: BLE001
                    result = exc  # run_turn only writes history when a turn finishes, so nothing to undo
            render_result(result, arch)
        chat.append({"question": question, "result": result})
    elif question:
        st.error("The connector is not available for this persona; see the sidebar.")

# ── Compare: personas side by side, or architectures side by side ────────────
with compare_tab:
    mode = st.radio(
        "Compare",
        ["personas", "architectures"],
        format_func=lambda m: {
            "personas": f"Three personas on {SERVERS[arch]['label']}",
            "architectures": f"Both architectures as {persona['label']}",
        }[m],
        horizontal=True,
    )
    cq = st.selectbox("Question", SAMPLES[:4] + ["(type your own)"])
    if cq == "(type your own)":
        cq = st.text_input("Your question", max_chars=500)
    if mode == "personas":
        lanes = [(k, arch, PERSONAS[k]["label"], f"`{PERSONAS[k]['role']}`") for k in PERSONAS]
    else:
        lanes = [(persona_key, a, SERVERS[a]["label"], f"`{SERVERS[a]['agent']}`") for a in SERVERS]
    if st.button("Run side by side", type="primary") and cq:
        with st.spinner("Asking in parallel..."):
            results, prepared = {}, {}
            for p_key, a_key, _, _ in lanes:
                try:
                    prepared[(p_key, a_key)] = prepare(p_key, a_key)
                except Exception as exc:  # noqa: BLE001
                    results[(p_key, a_key)] = exc
            with ThreadPoolExecutor(max_workers=len(lanes)) as pool:
                futures = {k: pool.submit(ask, args, [], cq) for k, args in prepared.items()}
                for k, f in futures.items():
                    try:
                        results[k] = f.result()
                    except Exception as exc:  # noqa: BLE001
                        results[k] = exc
        st.session_state["compare"] = (cq, lanes, results)
    if "compare" in st.session_state:
        cq, saved_lanes, results = st.session_state["compare"]
        md_text(f"**Q:** {cq}")
        for col, (p_key, a_key, title, sub) in zip(st.columns(len(saved_lanes)), saved_lanes):
            with col:
                st.subheader(title)
                st.caption(sub)
                render_result(results.get((p_key, a_key), RuntimeError("no result")), a_key)
