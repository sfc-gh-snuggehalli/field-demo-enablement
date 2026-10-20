#!/usr/bin/env bash
# Multi-Agent Orchestration over MCP: setup, run and teardown in one script.
#
#   ./demo.sh setup [-c <conn>] [-p <pat-file> | --create-pat]
#                        Python env (uv), account check, lab/setup.sql, persona
#                        key pairs, host-model PAT, .env
#   ./demo.sh build [--yes] [--skip-evals]
#                        run the lab notebook headless: MCP servers, toolset
#                        agent, persona checks over MCP, evaluations
#   ./demo.sh notebook   open the lab notebook in JupyterLab
#   ./demo.sh app        the Claude-style MCP client (http://localhost:8501)
#   ./demo.sh smoke [--server hub|toolset] [--persona <p>] [--list-only]
#                        tools/list + tools/call as each persona, no model
#   ./demo.sh pat        reissue the host-model PAT (it lasts 7 days)
#   ./demo.sh sql <file> run another SQL file with the saved connection
#   ./demo.sh teardown [-c <conn>] [--yes]
#                        drop everything (lab/cleanup.sql), the PAT and the keys
#
# Under an agent (Cortex Code), in CI, or without a terminal, nothing prompts:
# pass -c (and -p or --create-pat) for setup, and --yes for build and teardown.
# A missing answer stops with a message saying which flag to add.
#
# Requires uv (https://docs.astral.sh/uv/) and openssl. uv installs Python, the
# lab dependencies and the Snowflake CLI into .venv. The connection's user needs
# the ACCOUNTADMIN role (setup.sql creates users and roles; PATs and keys are
# registered as ACCOUNTADMIN). Secrets never reach stdout.
set -euo pipefail

# --- Module config -------------------------------------------------------
DB_NAME="MULTI_AGENT_MCP_DEMO"
ADMIN_ROLE="MULTI_AGENT_MCP_DEMO_ADMIN"
NOTEBOOK="lab/multi-agent-mcp-lab.ipynb"
PAT_NAME="multi_agent_mcp_demo"
DEFAULT_PAT_FILE="$HOME/.snowflake/multi_agent_mcp_demo.pat"
KEY_DIR="$HOME/.snowflake/keys"
PERSONAS=(sales_global sales_emea support)
# -------------------------------------------------------------------------

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$HERE/.env"
cd "$HERE"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,26p' "$HERE/demo.sh"; }

# Prompt a person at a terminal; otherwise stop and name the flag that answers it.
# Agent shells (Cortex Code sets COCO_AGENT) and CI can have a TTY nobody types in.
#   ask <var> <prompt> <flag-hint>
ask() {
  [[ -t 0 && -z "${COCO_AGENT:-}" && -z "${CI:-}" ]] || die "$3"
  read -rp "$2" "$1"
}

run() { uv run --project "$HERE" --frozen "$@"; }
sf()  { run snow sql -c "$CONN" "$@"; }

# Run a SQL file quietly: its statement echo goes to .logs/<file>.log, and the
# tail is shown only if it fails. DEMO_VERBOSE=1 streams it instead.
#   sql_file <file> [snow sql args]
sql_file() {
  local file="$1" log; shift
  if [[ -n "${DEMO_VERBOSE:-}" ]]; then sf -f "$file" "$@"; return; fi
  mkdir -p "$HERE/.logs"; log="$HERE/.logs/$(basename "$file" .sql).log"
  if sf -f "$file" "$@" > "$log" 2>&1; then
    echo "  ok (output in ${log#"$HERE/"})"
  else
    tail -n 40 "$log" >&2
    die "$(basename "$file") failed; full output in $log"
  fi
}

need_uv() {
  command -v uv >/dev/null || die "uv not found. Install: brew install uv (or curl -LsSf https://astral.sh/uv/install.sh | sh)"
}

load_env() {
  [[ -f "$ENV_FILE" ]] || die "No .env yet. Run ./demo.sh setup first."
  set -a; source "$ENV_FILE"; set +a
  CONN="${SNOWFLAKE_DEFAULT_CONNECTION_NAME:-}"
}

pick_connection() {
  if [[ -z "$CONN" ]]; then
    echo "Snowflake CLI connections:"; run snow connection list 2>/dev/null || true
    ask CONN "Connection name to use: " "Pass -c <connection>, one of the connections listed above."
  fi
  [[ -n "$CONN" ]] || die "A Snowflake CLI connection name is required."
  run snow connection test -c "$CONN" >/dev/null || die "Connection '$CONN' failed 'snow connection test'."
}

persona_user() { printf 'MULTI_AGENT_MCP_DEMO_%s_USER' "$(tr '[:lower:]' '[:upper:]' <<<"$1")"; }
persona_key()  { printf '%s/multi_agent_mcp_%s.p8' "$KEY_DIR" "$1"; }

# --- Programmatic access token for the host model --------------------------
# Reads `snow sql --format json` output on stdin and prints "<status> <expiry>"
# for the named PAT (expiry in epoch seconds; "NONE -" if there is no such PAT).
# With a file argument it also writes the output's token_secret there (mode 600).
PAT_PY='
import json, os, sys
from datetime import datetime
def rows(x):
    if isinstance(x, dict): yield x
    elif isinstance(x, list):
        for y in x: yield from rows(y)
try: out = list(rows(json.load(sys.stdin)))
except ValueError: sys.exit("snow sql returned no JSON; see its error above")
if len(sys.argv) > 2:
    secret = next((r["token_secret"] for r in out if r.get("token_secret")), "")
    if not secret: sys.exit("no token_secret in the output")
    fd = os.open(sys.argv[2], os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f: f.write(secret + "\n")
pat = next((r for r in out if str(r.get("name", "")).upper() == sys.argv[1].upper()), None)
if pat is None: print("NONE -")
else: print(pat["status"], int(datetime.fromisoformat(pat["expires_at"]).timestamp()))'

#   pat_status <user> <token-name>
pat_status() {
  sf --format json -q "USE ROLE ACCOUNTADMIN; SHOW USER PROGRAMMATIC ACCESS TOKENS FOR USER \"$1\"" \
    | run python -c "$PAT_PY" "$2"
}

# Create the PAT, or rotate it if it is active (an expired or disabled one is
# replaced), and save its secret to a file. Prints the new expiry (epoch seconds).
#   issue_pat <user> <token-name> <role-restriction> <file>
issue_pat() {
  local user="$1" name="$2" role="$3" file="$4" status add stmt info
  status="$(pat_status "$user" "$name")" || die "Could not list the PATs of $user."
  add="ALTER USER \"$user\" ADD PROGRAMMATIC ACCESS TOKEN $name ROLE_RESTRICTION = '$role' DAYS_TO_EXPIRY = 7"
  case "${status%% *}" in
    NONE)   stmt="$add" ;;
    ACTIVE) stmt="ALTER USER \"$user\" ROTATE PROGRAMMATIC ACCESS TOKEN $name EXPIRE_ROTATED_TOKEN_AFTER_HOURS = 0" ;;
    *)      stmt="ALTER USER \"$user\" REMOVE PROGRAMMATIC ACCESS TOKEN $name; $add" ;;
  esac
  mkdir -p "$(dirname "$file")" || die "Could not create $(dirname "$file")."
  sf --format json -q "USE ROLE ACCOUNTADMIN; $stmt" | run python -c "$PAT_PY" "$name" "$file" >/dev/null \
    || die "Could not create a PAT for $user."
  chmod 600 "$file" || die "Could not restrict $file to mode 600."
  info="$(pat_status "$user" "$name")" || die "Saved the PAT to $file, but could not read its expiry."
  [[ "${info##* }" =~ ^[0-9]+$ ]] || die "Saved the PAT to $file, but SHOW lists no $name for $user."
  echo "${info##* }"
}

fmt_time() { date -r "$1" '+%Y-%m-%d %H:%M %Z' 2>/dev/null || date -d "@$1" '+%Y-%m-%d %H:%M %Z'; }

# Stop before a command that needs the PAT if .env says it has expired, and warn
# in its last day. Silent when the expiry is unknown (a PAT passed with -p).
#   check_pat <expiry> <description>
check_pat() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] || return 0
  local left=$(( $1 - $(date +%s) ))
  (( left > 0 )) || die "$2 expired on $(fmt_time "$1"). Run ./demo.sh pat to reissue it."
  (( left > 86400 )) || warn "$2 expires on $(fmt_time "$1"). Run ./demo.sh pat to reissue it."
}
need_pat() { check_pat "${PAT_EXPIRES_AT:-}" "The host-model PAT (${HOST_LLM_PAT_FILE:-})"; }

# --- Persona key pairs ------------------------------------------------------
# Generate a key once (reused on re-runs), then (re)register its public half.
# The private key never leaves the mode-600 file.
#   ensure_key <user> <key-file>
ensure_key() {
  local user="$1" key="$2" pub
  command -v openssl >/dev/null || die "openssl not found; it generates the persona key pairs."
  mkdir -p "$KEY_DIR" && chmod 700 "$KEY_DIR"
  if [[ ! -s "$key" ]]; then
    ( umask 077; openssl genrsa 2048 2>/dev/null | openssl pkcs8 -topk8 -inform PEM -out "$key" -nocrypt ) \
      || die "Could not generate $key."
    chmod 600 "$key"
  fi
  pub="$(openssl rsa -in "$key" -pubout 2>/dev/null | grep -v '^-----' | tr -d '\n')"
  [[ -n "$pub" ]] || die "Could not read the public key of $key."
  sf -q "USE ROLE ACCOUNTADMIN; ALTER USER \"$user\" SET RSA_PUBLIC_KEY = '$pub'" >/dev/null \
    || die "Could not register the public key on $user."
  echo "  $user <- $(basename "$key")"
}

write_env() {
  ( umask 077
    cat > "$ENV_FILE" <<EOF
# Written by ./demo.sh setup. demo.sh loads this before every command.
SNOWFLAKE_DEFAULT_CONNECTION_NAME=$CONN
SNOWFLAKE_ACCOUNT=$SF_ACCOUNT
SNOWFLAKE_USER=$SF_USER
DEMO_EXPECTED_ACCOUNT=$ACCT_NAME
PERSONA_KEY_SALES_GLOBAL=$(persona_key sales_global)
PERSONA_KEY_SALES_EMEA=$(persona_key sales_emea)
PERSONA_KEY_SUPPORT=$(persona_key support)
HOST_LLM_PAT_FILE=$PAT_FILE
# Host-model PAT expiry in epoch seconds; empty when unknown (a PAT you passed with -p)
PAT_EXPIRES_AT=${PAT_EXPIRES_AT:-}
EOF
  )
}

cmd_setup() {
  local pat_arg="" create_pat=0 status ok="" p
  CONN="" PAT_EXPIRES_AT=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--connection) CONN="$2"; shift 2 ;;
      -p|--pat-file)   pat_arg="$2"; shift 2 ;;
      --create-pat)    create_pat=1; shift ;;
      *) die "Unknown option for setup: $1" ;;
    esac
  done

  step "Installing the Python environment (uv sync)"
  uv sync --project "$HERE" --frozen
  pick_connection

  step "Checking the account behind '$CONN'"
  IFS=, read -r SF_USER SF_ACCOUNT ACCT_NAME < <(sf --format csv -q \
    "SELECT CURRENT_USER(), CURRENT_ORGANIZATION_NAME()||'-'||CURRENT_ACCOUNT_NAME(), CURRENT_ACCOUNT_NAME()" | tail -n 1)
  [[ -n "${SF_USER:-}" ]] || die "Could not read the current user from connection '$CONN'."
  echo "  $SF_USER on $SF_ACCOUNT"

  step "Creating the governed stack (lab/setup.sql)"
  sql_file lab/setup.sql

  step "Persona key pairs"
  for p in "${PERSONAS[@]}"; do ensure_key "$(persona_user "$p")" "$(persona_key "$p")"; done

  step "Host-model PAT (the app's Claude model call)"
  # Only -p overrides the default file.
  PAT_FILE="${pat_arg:-$DEFAULT_PAT_FILE}"
  PAT_FILE="${PAT_FILE/#\~/$HOME}"
  if [[ -s "$PAT_FILE" ]]; then
    echo "  using the PAT at $PAT_FILE"
    if [[ "$PAT_FILE" == "$DEFAULT_PAT_FILE" ]]; then
      status="$(pat_status "$SF_USER" "$PAT_NAME")" || die "Could not list the PATs of $SF_USER."
      case "${status%% *}" in
        ACTIVE) PAT_EXPIRES_AT="${status##* }" ;;
        NONE)   warn "$SF_USER has no $PAT_NAME PAT, so $PAT_FILE is stale. Run ./demo.sh pat to reissue it." ;;
        *)      PAT_EXPIRES_AT="${status##* }"
                warn "The $PAT_NAME PAT in $PAT_FILE is ${status%% *}. Run ./demo.sh pat to reissue it." ;;
      esac
    fi
  else
    if [[ $create_pat -eq 0 ]]; then
      ask ok "No PAT at $PAT_FILE. Create one for $SF_USER ($ADMIN_ROLE, 7 days)? [Y/n] " \
        "No PAT at $PAT_FILE. Pass -p <pat-file>, or --create-pat to create one for $SF_USER ($ADMIN_ROLE, 7 days)."
      [[ "$ok" =~ ^[Nn]$ ]] && die "The app needs a PAT. Save one to $PAT_FILE or pass -p <file>."
    fi
    PAT_EXPIRES_AT="$(issue_pat "$SF_USER" "$PAT_NAME" "$ADMIN_ROLE" "$PAT_FILE")" || exit 1
    echo "  saved to $PAT_FILE (expires $(fmt_time "$PAT_EXPIRES_AT"))"
  fi

  step "Writing .env"
  write_env
  echo "  wrote ${ENV_FILE#"$HERE/"}"

  step "Done"
  cat <<EOF
Next:
  ./demo.sh build --yes   # MCP servers, toolset agent, persona checks, evaluations (CHECK lines)
  ./demo.sh notebook      # or step through it in JupyterLab
  ./demo.sh app           # then the Claude-style client at http://localhost:8501
Teardown: ./demo.sh teardown --yes
EOF
}

cmd_build() {
  local yes=0 ok=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes)     yes=1; shift ;;
      --skip-evals) export DEMO_SKIP_EVALS=1; shift ;;
      *) die "Unknown option for build: $1" ;;
    esac
  done
  if [[ $yes -eq 0 ]]; then
    ask ok "Run $NOTEBOOK on '$CONN' (creates two MCP servers and TOOLSET_AGENT, calls the agents, starts two evaluations)? [y/N] " \
      "Build runs $NOTEBOOK on '$CONN': it creates two MCP servers and TOOLSET_AGENT, calls the agents as each persona and starts two evaluations (credits). Pass --yes to confirm."
    [[ "$ok" =~ ^[Yy]$ ]] || exit 0
  fi
  mkdir -p "$HERE/.logs"
  step "Running $NOTEBOOK (outputs saved into the notebook; log in .logs/build.log)"
  if run jupyter nbconvert --to notebook --execute --inplace \
       --ExecutePreprocessor.timeout=2400 --ExecutePreprocessor.kernel_name=python3 \
       "$NOTEBOOK" > "$HERE/.logs/build.log" 2>&1; then
    run python - "$NOTEBOOK" <<'PY'
import json, sys
nb = json.load(open(sys.argv[1]))
for c in nb["cells"]:
    for o in c.get("outputs", []):
        text = "".join(o.get("text", "")) if o.get("output_type") == "stream" else ""
        for line in text.splitlines():
            if line.startswith("CHECK "):
                print("  " + line[:220])
PY
  else
    tail -n 40 "$HERE/.logs/build.log" >&2
    die "Notebook run failed; see .logs/build.log and the failing cell's output in $NOTEBOOK"
  fi
}

# Reissue the host-model PAT and record its new expiry in .env. A PAT you passed
# to setup with -p is left alone.
cmd_pat() {
  [[ $# -eq 0 ]] || die "pat takes no options; it uses the connection in .env."
  SF_USER="$SNOWFLAKE_USER" SF_ACCOUNT="$SNOWFLAKE_ACCOUNT" ACCT_NAME="$DEMO_EXPECTED_ACCOUNT"
  PAT_FILE="$HOST_LLM_PAT_FILE"
  [[ "$PAT_FILE" == "$DEFAULT_PAT_FILE" ]] \
    || die "Your PAT at $PAT_FILE was passed with -p, so demo.sh leaves it alone. Replace it yourself."
  step "Reissuing the host-model PAT ($PAT_NAME)"
  PAT_EXPIRES_AT="$(issue_pat "$SF_USER" "$PAT_NAME" "$ADMIN_ROLE" "$PAT_FILE")" || exit 1
  echo "  saved to $PAT_FILE (expires $(fmt_time "$PAT_EXPIRES_AT"))"
  write_env
  echo "  updated ${ENV_FILE#"$HERE/"}"
}

cmd_teardown() {
  local yes=0 ok="" user p
  CONN=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--connection) CONN="$2"; shift 2 ;;
      -y|--yes)        yes=1; shift ;;
      *) die "Unknown option for teardown: $1" ;;
    esac
  done
  if [[ -z "$CONN" && -f "$ENV_FILE" ]]; then load_env; fi
  pick_connection
  if [[ $yes -eq 0 ]]; then
    ask ok "Drop $DB_NAME, its warehouse, persona users and roles, and the $PAT_NAME PAT on '$CONN'? [y/N] " \
      "Teardown drops $DB_NAME, its warehouse, persona users and roles, and the $PAT_NAME PAT on '$CONN'. Pass --yes to confirm."
    [[ "$ok" =~ ^[Yy]$ ]] || exit 0
  fi
  step "Running lab/cleanup.sql"; sql_file lab/cleanup.sql

  step "Removing the host-model PAT and local secrets"
  user="${SNOWFLAKE_USER:-$(sf --format csv -q 'SELECT CURRENT_USER()' | tail -n 1)}"
  if [[ "$(pat_status "$user" "$PAT_NAME" | cut -d' ' -f1)" != "NONE" ]]; then
    sf -q "USE ROLE ACCOUNTADMIN; ALTER USER \"$user\" REMOVE PROGRAMMATIC ACCESS TOKEN $PAT_NAME" >/dev/null \
      && echo "  removed PAT $PAT_NAME from $user"
  fi
  rm -f "$DEFAULT_PAT_FILE"
  for p in "${PERSONAS[@]}"; do rm -f "$(persona_key "$p")"; done
  rm -f "$ENV_FILE"
  echo "  removed $DEFAULT_PAT_FILE, the persona keys in $KEY_DIR and .env"
  echo "Teardown complete. Delete the notebook from your Snowsight workspace if you imported it there."
}

[[ $# -gt 0 ]] || { usage; exit 1; }
sub="$1"; shift
case "$sub" in
  -h|--help|help) usage ;;
  setup)    need_uv; cmd_setup "$@" ;;
  build)    need_uv; load_env; cmd_build "$@" ;;
  notebook) need_uv; load_env; run jupyter lab "$NOTEBOOK" "$@" ;;
  app)      need_uv; load_env; need_pat; run streamlit run app/streamlit_app.py "$@" ;;
  smoke)    need_uv; load_env; run python client/mcp_smoke.py "$@" ;;
  pat)      need_uv; load_env; cmd_pat "$@" ;;
  sql)      need_uv; load_env; [[ -n "${1:-}" ]] || die "Usage: ./demo.sh sql <file>"; sf -f "$@" ;;
  teardown) need_uv; cmd_teardown "$@" ;;
  *) usage; die "Unknown command: $sub" ;;
esac
