"""Minimal client for a Snowflake-managed MCP server, authenticated as a Snowflake
user with key-pair JWT.

This is the same traffic an MCP host such as Claude Desktop sends: JSON-RPC
`tools/list` and `tools/call` POSTed to the server URL with a bearer token. The
server cannot tell one client from another; what it acts on is the token's user,
whose DEFAULT_ROLE becomes the session role.

The private key is read from a path the caller supplies and is only used to sign
JWTs. It is never logged or returned.
"""

from __future__ import annotations

import base64
import hashlib
import itertools
import json
import time
from dataclasses import dataclass, field

import httpx
import jwt
from cryptography.hazmat.primitives import serialization

SSE_ACCEPT = "application/json, text/event-stream"
JWT_LIFETIME_SECONDS = 55 * 60  # Snowflake accepts at most 60 minutes


def account_host(account: str) -> str:
    """Account URL host. Hostnames take hyphens where account names have underscores."""
    return f"{account.lower().replace('_', '-')}.snowflakecomputing.com"


def mcp_server_url(account: str, database: str, schema: str, server: str) -> str:
    return f"https://{account_host(account)}/api/v2/databases/{database}/schemas/{schema}/mcp-servers/{server}"


class KeyPairAuth:
    """Signs short-lived Snowflake key-pair JWTs for one user, cached until near expiry."""

    def __init__(self, account: str, user: str, private_key_path: str):
        self.account = account.upper()  # JWT claims use the account identifier, underscores kept
        self.user = user.upper()
        with open(private_key_path, "rb") as fh:
            self._key = serialization.load_pem_private_key(fh.read(), password=None)
        der = self._key.public_key().public_bytes(
            serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo
        )
        self.fingerprint = "SHA256:" + base64.b64encode(hashlib.sha256(der).digest()).decode()
        self._token: str | None = None
        self._expires = 0.0

    def token(self) -> str:
        now = time.time()
        if self._token is None or now > self._expires - 60:
            qualified = f"{self.account}.{self.user}"
            self._expires = now + JWT_LIFETIME_SECONDS
            self._token = jwt.encode(
                {"iss": f"{qualified}.{self.fingerprint}", "sub": qualified, "iat": int(now), "exp": int(self._expires)},
                self._key,
                algorithm="RS256",
            )
        return self._token

    def headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.token()}",
            "X-Snowflake-Authorization-Token-Type": "KEYPAIR_JWT",
        }


class McpError(RuntimeError):
    pass


@dataclass
class Exchange:
    """One JSON-RPC round trip, kept for the app's inspector. Holds no credentials."""

    method: str
    request: dict
    response: dict | None = None
    http_status: int | None = None
    content_type: str = ""
    sse_events: int = 0
    seconds: float = 0.0
    notes: list[str] = field(default_factory=list)


class SnowflakeMcpClient:
    def __init__(self, url: str, auth: KeyPairAuth, timeout: float = 600.0):
        self.url = url
        self.auth = auth
        self.timeout = timeout
        self._ids = itertools.count(1)

    def _post(self, method: str, params: dict | None = None) -> Exchange:
        payload: dict = {"jsonrpc": "2.0", "id": next(self._ids), "method": method}
        if params is not None:
            payload["params"] = params
        ex = Exchange(method=method, request=payload)
        headers = {**self.auth.headers(), "Content-Type": "application/json", "Accept": SSE_ACCEPT}
        start = time.monotonic()
        with httpx.Client(timeout=httpx.Timeout(self.timeout, connect=30.0)) as http:
            with http.stream("POST", self.url, headers=headers, json=payload) as resp:
                ex.http_status = resp.status_code
                ex.content_type = resp.headers.get("content-type", "")
                if resp.status_code >= 400:
                    body = resp.read().decode(errors="replace")[:2000]
                    ex.seconds = time.monotonic() - start
                    raise McpError(f"HTTP {resp.status_code} from MCP server: {body}")
                if "text/event-stream" in ex.content_type:
                    ex.response = self._read_sse(resp, payload["id"], ex)
                else:
                    ex.response = json.loads(resp.read())
        ex.seconds = time.monotonic() - start
        if ex.response is None:
            raise McpError(f"{method}: stream closed without a result")
        if "error" in ex.response:
            raise McpError(f"{method}: {json.dumps(ex.response['error'])[:2000]}")
        return ex

    @staticmethod
    def _read_sse(resp: httpx.Response, request_id: int, ex: Exchange) -> dict | None:
        """Read data: events until the result for request_id. Keep-alive comments and
        progress notifications are skipped; the stream may close without [DONE]."""
        result = None
        data_lines: list[str] = []
        for line in itertools.chain(resp.iter_lines(), [""]):
            if line.startswith("data:"):
                data_lines.append(line[5:].strip())
                continue
            if line == "" and data_lines:
                data = "\n".join(data_lines)
                data_lines = []
                ex.sse_events += 1
                if data == "[DONE]":
                    break
                try:
                    msg = json.loads(data)
                except ValueError:
                    ex.notes.append("non-JSON SSE event skipped")
                    continue
                if msg.get("id") == request_id and ("result" in msg or "error" in msg):
                    result = msg
        return result

    def list_tools(self) -> tuple[list[dict], Exchange]:
        ex = self._post("tools/list")
        return ex.response["result"].get("tools", []), ex

    def call_tool(self, name: str, arguments: dict) -> tuple[dict, Exchange]:
        ex = self._post("tools/call", {"name": name, "arguments": arguments})
        return ex.response["result"], ex


def result_text(result: dict) -> str:
    """Concatenate the text content blocks of a tools/call result."""
    return "\n".join(b.get("text", "") for b in result.get("content", []) if b.get("type") == "text").strip()


NOT_ENTITLED_PREFIX = "NOT_ENTITLED:"


def _tool_result_text(tool_result: dict) -> str:
    parts = []
    for c in tool_result.get("content", []) or []:
        if isinstance(c.get("json"), dict) and "result" in c["json"]:
            parts.append(str(c["json"]["result"]))
        elif "text" in c:
            parts.append(str(c["text"]))
    return "\n".join(parts)


def _table_frame(table: dict) -> dict:
    """A 'table' content block as columns + rows (values stay strings, as returned)."""
    rs = table.get("result_set") or {}
    cols = [c.get("name", "") for c in (rs.get("resultSetMetaData") or {}).get("rowType", [])]
    return {"title": table.get("title"), "columns": cols, "rows": rs.get("data") or []}


def parse_agent_result(result: dict) -> dict:
    """Unpack a CORTEX_AGENT_RUN tools/call result.

    The tool returns the agent's whole response as JSON in one text block: the
    orchestrator's tool_use / tool_result pairs (its delegations to the
    specialists, through the caller's-rights bridges), the final text, and
    metadata including the server-side thread_id. Falls back to plain text when
    the body is not JSON.
    """
    raw = result_text(result)
    try:
        body = json.loads(raw)
    except ValueError:
        return {"answer": raw, "delegations": [], "charts": [], "tables": [], "thread_id": None, "message_id": None, "meta": {}, "raw": None}
    uses: dict[str, dict] = {}
    delegations: list[dict] = []
    answer_parts: list[str] = []
    charts: list[dict] = []
    tables: list[dict] = []
    for block in body.get("content", []):
        kind = block.get("type")
        if kind == "chart":
            spec = (block.get("chart") or {}).get("chart_spec")
            try:
                charts.append(json.loads(spec) if isinstance(spec, str) else spec)
            except (TypeError, ValueError):
                pass
            continue
        if kind == "table":
            tables.append(_table_frame(block.get("table") or {}))
            continue
        if kind == "tool_use":
            tu = block.get("tool_use", {})
            entry = {"tool": tu.get("name"), "input": tu.get("input"), "result": None, "status": None, "denied": False}
            uses[tu.get("tool_use_id")] = entry
            delegations.append(entry)
        elif kind == "tool_result":
            tr = block.get("tool_result", {})
            entry = uses.get(tr.get("tool_use_id"))
            if entry is None:
                entry = {"tool": tr.get("name"), "input": None, "result": None, "status": None, "denied": False}
                delegations.append(entry)
            text = _tool_result_text(tr)
            entry.update(result=text, status=tr.get("status"), denied=text.startswith(NOT_ENTITLED_PREFIX))
        elif kind == "text":
            answer_parts.append(block.get("text", ""))
    meta = body.get("metadata") or {}
    return {
        "answer": "\n".join(answer_parts).strip(),
        "delegations": delegations,
        "charts": [c for c in charts if isinstance(c, dict)],
        "tables": [t for t in tables if t["rows"]],
        "thread_id": str(body.get("thread_id") or meta.get("thread_id") or "") or None,
        "message_id": str(meta.get("assistant_message_id") or "") or None,
        "meta": {k: meta.get(k) for k in ("run_id", "orchestration_model") if k in meta},
        "raw": body,
    }
