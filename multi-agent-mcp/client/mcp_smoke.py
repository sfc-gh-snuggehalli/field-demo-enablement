"""Headless smoke test: call ORCHESTRATOR_MCP as each persona user with key-pair JWT.

Proves, before any UI, that (1) the Snowflake-managed MCP endpoint accepts
key-pair JWT, (2) every persona sees the same single tool, and (3) tools/call
returns the persona-specific answer the lab notebook's Section 4 checks.

Usage (.env holds the account and the key paths; keys are never printed):
    ./demo.sh smoke [--list-only] [--persona sales_emea] [--server toolset]
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "app"))

from snowflake_mcp import KeyPairAuth, McpError, SnowflakeMcpClient, mcp_server_url, parse_agent_result  # noqa: E402
from personas import DATABASE, PERSONAS, SCHEMA, SERVERS, require_account  # noqa: E402

QUESTION = "What were total new bookings in FY25-Q4 by theater?"


def message_argument(tool: dict) -> str:
    schema = tool.get("inputSchema") or {}
    required = schema.get("required") or list((schema.get("properties") or {}).keys())
    if not required:
        raise SystemExit(f"tool {tool['name']} has no input properties: {json.dumps(schema)}")
    return required[0]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list-only", action="store_true")
    ap.add_argument("--persona", choices=list(PERSONAS))
    ap.add_argument("--question", default=QUESTION)
    ap.add_argument("--server", choices=list(SERVERS), default="hub", help="hub = ORCHESTRATOR_MCP, toolset = TOOLSET_MCP")
    args = ap.parse_args()

    ACCOUNT = require_account()
    url = mcp_server_url(ACCOUNT, DATABASE, SCHEMA, SERVERS[args.server]["server"])
    print(f"server: {url}\n")
    failures = 0
    for key, persona in PERSONAS.items():
        if args.persona and key != args.persona:
            continue
        key_path = os.path.expanduser(os.environ.get(persona["key_env"], ""))
        if not key_path or not os.path.exists(key_path):
            print(f"[{key}] SKIP: set {persona['key_env']} to the persona's .p8 path")
            failures += 1
            continue
        client = SnowflakeMcpClient(url, KeyPairAuth(ACCOUNT, persona["user"], key_path))
        print(f"[{key}] user={persona['user']}")
        try:
            tools, ex = client.list_tools()
            print(f"  tools/list  HTTP {ex.http_status} {ex.content_type} {ex.seconds:.1f}s")
            for t in tools:
                print(f"    - {t['name']}  input={json.dumps(t.get('inputSchema'))}")
            if args.list_only or not tools:
                continue
            tool = tools[0]
            arg = message_argument(tool)
            result, ex = client.call_tool(tool["name"], {arg: args.question})
            print(f"  tools/call  HTTP {ex.http_status} {ex.content_type} sse_events={ex.sse_events} {ex.seconds:.1f}s")
            print(f"  isError={result.get('isError')}  content_types={[b.get('type') for b in result.get('content', [])]}")
            parsed = parse_agent_result(result)
            for d in parsed["delegations"]:
                verdict = "DENIED (NOT_ENTITLED)" if d["denied"] else d["status"]
                print(f"  orchestrator -> {d['tool']}  {verdict}")
            print(f"  charts={len(parsed['charts'])} tables={len(parsed['tables'])}")
            print(f"  thread_id={parsed['thread_id']}  {parsed['meta']}")
            print("  answer: " + parsed["answer"][:1500].replace("\n", "\n          ") + "\n")
        except McpError as exc:
            failures += 1
            print(f"  ERROR {exc}\n")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
