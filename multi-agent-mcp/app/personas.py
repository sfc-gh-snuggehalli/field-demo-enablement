"""Demo configuration: the demo's fixed object names and its three persona users.

Object names are created by lab/setup.sql and the lab notebook and must not
change. What varies per machine (account, key file paths) is read from the
environment, which ./demo.sh loads from the .env that ./demo.sh setup writes.
"""

import os

# Org-account identifier, e.g. MYORG-MYACCOUNT. ./demo.sh setup derives it from
# the connection; underscores are fine (snowflake_mcp converts the hostname).
ACCOUNT = os.environ.get("SNOWFLAKE_ACCOUNT", "")
DATABASE = "MULTI_AGENT_MCP_DEMO"
SCHEMA = "APP"
SERVER = "ORCHESTRATOR_MCP"


def require_account() -> str:
    if not ACCOUNT:
        raise RuntimeError("SNOWFLAKE_ACCOUNT is not set. Run ./demo.sh setup, then start this through ./demo.sh.")
    return ACCOUNT


# Two architectures, one MCP server each, both exposing one tool named northwind_assistant.
SERVERS = {
    "hub": {
        "server": "ORCHESTRATOR_MCP",
        "agent": "ORCHESTRATOR_AGENT",
        "label": "Hub and spoke",
        "summary": "Orchestrator delegates to specialist agents through caller's-rights bridges",
    },
    "toolset": {
        "server": "TOOLSET_MCP",
        "agent": "TOOLSET_AGENT",
        "label": "Agent toolset",
        "summary": "One agent inherits the specialists' tools at run time (agent_toolset)",
    },
}

PERSONAS = {
    "sales_global": {
        "label": "Global sales exec",
        "user": "MULTI_AGENT_MCP_DEMO_SALES_GLOBAL_USER",
        "role": "MULTI_AGENT_MCP_DEMO_SALES_GLOBAL",
        "key_env": "PERSONA_KEY_SALES_GLOBAL",
        "expect": "Sales specialist, all theaters",
    },
    "sales_emea": {
        "label": "EMEA seller",
        "user": "MULTI_AGENT_MCP_DEMO_SALES_EMEA_USER",
        "role": "MULTI_AGENT_MCP_DEMO_SALES_EMEA",
        "key_env": "PERSONA_KEY_SALES_EMEA",
        "expect": "Sales specialist, EMEA rows only",
    },
    "support": {
        "label": "Support rep",
        "user": "MULTI_AGENT_MCP_DEMO_SUPPORT_USER",
        "role": "MULTI_AGENT_MCP_DEMO_SUPPORT",
        "key_env": "PERSONA_KEY_SUPPORT",
        "expect": "Support specialist only",
    },
}
