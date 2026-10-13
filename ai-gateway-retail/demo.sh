#!/usr/bin/env bash
# Cortex AI Gateway retail lab: setup, run and teardown in one script.
#
#   ./demo.sh setup [-c <conn>] [-p <pat-file> | --create-pat] [--skip-smoke]
#                        Python env (uv), Snowflake objects, demo PATs, .env,
#                        then one live prompt as a smoke test
#   ./demo.sh traffic    background gateway traffic for the Trace Analyzer
#   ./demo.sh burst      drive the cost demo user over its daily quota (HTTP 403)
#   ./demo.sh notebook   open the lab notebook in JupyterLab
#   ./demo.sh app        run the Trace Analyzer locally (http://localhost:8501)
#   ./demo.sh ask "..."  send one prompt through the agent and print its trace_id
#   ./demo.sh deploy     deploy the Trace Analyzer to Streamlit in Snowflake
#   ./demo.sh teardown [-c <conn>] [--yes]
#                        drop everything (lab/cleanup.sql)
#
# Under an agent (Cortex Code), in CI, or without a terminal, nothing prompts:
# pass -c, plus -p or --create-pat if there is no PAT file yet, and --yes for
# teardown. A missing answer stops with a message saying which flag to add.
#
# Requires uv (https://docs.astral.sh/uv/). uv installs Python, the lab
# dependencies and the Snowflake CLI into .venv. The connection's user needs
# the SYSADMIN and ACCOUNTADMIN roles.
set -euo pipefail

# --- Module config -------------------------------------------------------
DATABASE="CORTEX_GATEWAY_RETAIL_LAB"
COST_USER="GATEWAY_RETAIL_COST_DEMO"
COST_ROLE="GATEWAY_RETAIL_COST_RL"
DEFAULT_PAT_FILE="$HOME/.snowflake/ai_gateway_retail.pat"
PAT_NAME="ai_gateway_retail"
DEFAULT_BURST_PAT_FILE="$HOME/.snowflake/gateway_retail_cost.pat"
NOTEBOOK="lab/ai-gateway-lab.ipynb"
NEEDS_LIBOMP=1
# -------------------------------------------------------------------------

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$HERE/.env"
cd "$HERE"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,22p' "$HERE/demo.sh"; }

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

# One query, CSV output, last row only.
sf_value() { sf --format csv -q "$1" | tail -n 1; }

# Create (or rotate, if it exists) a PAT and save its secret to a file.
#   issue_pat <user> <token-name> <role-restriction> <file>
issue_pat() {
  local user="$1" name="$2" role="$3" file="$4" stmt
  if sf --format csv -q "SHOW USER PROGRAMMATIC ACCESS TOKENS FOR USER \"$user\"" \
       | cut -d, -f1 | grep -qix "$name"; then
    stmt="ALTER USER \"$user\" ROTATE PROGRAMMATIC ACCESS TOKEN $name EXPIRE_ROTATED_TOKEN_AFTER_HOURS = 0"
  else
    stmt="ALTER USER \"$user\" ADD PROGRAMMATIC ACCESS TOKEN $name ROLE_RESTRICTION = '$role' DAYS_TO_EXPIRY = 7"
  fi
  mkdir -p "$(dirname "$file")"
  ( umask 077
    sf --format json -q "USE ROLE ACCOUNTADMIN; $stmt" | run python -c '
import json, sys
def rows(x):
    if isinstance(x, dict): yield x
    elif isinstance(x, list):
        for y in x: yield from rows(y)
secret = next((r["token_secret"] for r in rows(json.load(sys.stdin)) if r.get("token_secret")), "")
if not secret: sys.exit("no token_secret in the output")
print(secret)' > "$file" ) || die "Could not create a PAT for $user."
  chmod 600 "$file"
}

write_env() {
  ( umask 077
    cat > "$ENV_FILE" <<EOF
# Written by ./demo.sh setup. demo.sh loads this before every command.
SNOWFLAKE_DEFAULT_CONNECTION_NAME=$CONN
SNOWFLAKE_ACCOUNT=$SF_ACCOUNT
SNOWFLAKE_USER=$SF_USER
SNOWFLAKE_PAT_FILE=$PAT_FILE
GATEWAY_HOST=$GATEWAY_HOST
BURST_PAT_FILE=$DEFAULT_BURST_PAT_FILE
EOF
  )
}

cmd_setup() {
  local pat_arg="" skip_smoke=0 create_pat=0
  CONN=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--connection) CONN="$2"; shift 2 ;;
      -p|--pat-file)   pat_arg="$2"; shift 2 ;;
      --create-pat)    create_pat=1; shift ;;
      --skip-smoke)    skip_smoke=1; shift ;;
      *) die "Unknown option for setup: $1" ;;
    esac
  done

  step "Installing the Python environment (uv sync)"
  uv sync --project "$HERE" --frozen
  if [[ $NEEDS_LIBOMP -eq 1 && "$(uname)" == "Darwin" ]]; then
    [[ -e /opt/homebrew/opt/libomp/lib/libomp.dylib || -e /usr/local/opt/libomp/lib/libomp.dylib ]] \
      || warn "libomp not found; XGBoost in the notebook needs it on macOS: brew install libomp"
  fi

  if [[ -z "$CONN" ]]; then
    echo "Snowflake CLI connections:"; run snow connection list 2>/dev/null || true
    ask CONN "Connection name to use: " "Pass -c <connection>, one of the connections listed above."
  fi
  [[ -n "$CONN" ]] || die "A Snowflake CLI connection name is required."
  run snow connection test -c "$CONN" >/dev/null || die "Connection '$CONN' failed 'snow connection test'."

  IFS=, read -r SF_USER SF_ACCOUNT GATEWAY_HOST < <(sf_value \
    "SELECT CURRENT_USER(), CURRENT_ORGANIZATION_NAME()||'-'||CURRENT_ACCOUNT_NAME(),
            LOWER(REPLACE(CURRENT_ORGANIZATION_NAME()||'-'||CURRENT_ACCOUNT_NAME(), '_', '-'))||'.snowflakecomputing.com'")
  [[ -n "${SF_USER:-}" ]] || die "Could not read the current user from connection '$CONN'."
  echo "Connected as $SF_USER on $SF_ACCOUNT (gateway host $GATEWAY_HOST)"

  step "Creating Snowflake objects (lab/setup.sql)"
  sql_file lab/setup.sql -D "gateway_host=$GATEWAY_HOST"

  step "Programmatic access tokens"
  PAT_FILE="${pat_arg:-${SNOWFLAKE_PAT_FILE:-$DEFAULT_PAT_FILE}}"
  PAT_FILE="${PAT_FILE/#\~/$HOME}"
  if [[ -s "$PAT_FILE" ]]; then
    echo "Using your PAT at $PAT_FILE"
  else
    if [[ $create_pat -eq 0 ]]; then
      ask ok "No PAT at $PAT_FILE. Create one for $SF_USER (SYSADMIN, 7 days)? [Y/n] " \
        "No PAT at $PAT_FILE. Pass -p <pat-file>, or --create-pat to create one for $SF_USER (SYSADMIN, 7 days)."
      [[ "$ok" =~ ^[Nn]$ ]] && die "The lab needs a PAT. Save one to $PAT_FILE or pass -p <file>."
    fi
    issue_pat "$SF_USER" "$PAT_NAME" SYSADMIN "$PAT_FILE"
    echo "Saved your PAT to $PAT_FILE"
  fi
  issue_pat "$COST_USER" cost_demo "$COST_ROLE" "$DEFAULT_BURST_PAT_FILE"
  echo "Saved the $COST_USER PAT (for ./demo.sh burst) to $DEFAULT_BURST_PAT_FILE"

  step "Writing .env"
  write_env
  echo "Wrote $ENV_FILE"

  if [[ $skip_smoke -eq 0 ]]; then
    step "Smoke test: one live prompt through the gateway"
    load_env
    run python lab/live_agent.py || die "Smoke test failed. Check the PAT and network policy, then: ./demo.sh ask"
  fi

  step "Done"
  cat <<EOF
Next:
  ./demo.sh traffic     # background traces for the Trace Analyzer
  ./demo.sh notebook    # the hands-on lab
  ./demo.sh app         # Trace Analyzer at http://localhost:8501
  ./demo.sh burst       # before a demo: block the cost demo user
Teardown: ./demo.sh teardown
EOF
}

cmd_teardown() {
  need_uv
  local yes=0 ok=""
  CONN=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--connection) CONN="$2"; shift 2 ;;
      -y|--yes)        yes=1; shift ;;
      *) die "Unknown option for teardown: $1" ;;
    esac
  done
  if [[ -z "$CONN" && -f "$ENV_FILE" ]]; then load_env; fi
  [[ -n "$CONN" ]] || ask CONN "Connection name to use: " "Pass -c <connection>."
  if [[ $yes -eq 0 ]]; then
    ask ok "Drop $DATABASE, its warehouse, users and integrations on '$CONN'? [y/N] " \
      "Teardown drops $DATABASE and its account-level objects on '$CONN'. Pass --yes to confirm."
    [[ "$ok" =~ ^[Yy]$ ]] || exit 0
  fi
  # The notebook tags the lab user with COST_CENTER; the tag must be unset before
  # its database can be dropped. No-op if the notebook never ran.
  local user="${SNOWFLAKE_USER:-$(sf_value 'SELECT CURRENT_USER()')}"
  sf -q "USE ROLE ACCOUNTADMIN; ALTER USER \"$user\" UNSET TAG $DATABASE.PUBLIC.COST_CENTER" \
    >/dev/null 2>&1 || true
  step "Running lab/cleanup.sql"; sql_file lab/cleanup.sql
  rm -f "$ENV_FILE"
  echo "Teardown complete. PAT files under ~/.snowflake were left in place."
}

[[ $# -gt 0 ]] || { usage; exit 1; }
sub="$1"; shift
case "$sub" in
  -h|--help|help) usage ;;
  setup)    need_uv; cmd_setup "$@" ;;
  traffic)  need_uv; load_env; run python lab/generate_traffic.py "$@" ;;
  burst)    need_uv; load_env; run python lab/generate_traffic.py --burst --burst-pat-file "$BURST_PAT_FILE" "$@" ;;
  ask)      need_uv; load_env; run python lab/live_agent.py "$@" ;;
  notebook) need_uv; load_env; run jupyter lab "$NOTEBOOK" "$@" ;;
  app)      need_uv; load_env; cd app; run streamlit run streamlit_app.py "$@" ;;
  deploy)   need_uv; load_env; cd app; run snow streamlit deploy --replace -c "$CONN" "$@" ;;
  teardown) cmd_teardown "$@" ;;
  *) usage; die "Unknown command: $sub" ;;
esac
