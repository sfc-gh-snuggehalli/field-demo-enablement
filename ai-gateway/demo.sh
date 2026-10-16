#!/usr/bin/env bash
# Cortex AI Gateway lab: setup, run and teardown in one script.
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
#   ./demo.sh pat        reissue the demo PATs (they last 7 days) without rerunning setup
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
DATABASE="CORTEX_GATEWAY_LAB"
COST_USER="GATEWAY_COST_DEMO"
COST_ROLE="GATEWAY_COST_DEMO_RL"
DEFAULT_PAT_FILE="$HOME/.snowflake/ai_gateway_demo.pat"
PAT_NAME="ai_gateway_demo"
DEFAULT_BURST_PAT_FILE="$HOME/.snowflake/gateway_cost_demo.pat"
NOTEBOOK="lab/ai-gateway-lab.ipynb"
NEEDS_LIBOMP=0
# -------------------------------------------------------------------------

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$HERE/.env"
cd "$HERE"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,23p' "$HERE/demo.sh"; }

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

# "<status> <expiry>" of a user's PAT, as PAT_PY prints it.
#   pat_status <user> <token-name>
pat_status() {
  sf --format json -q "USE ROLE ACCOUNTADMIN; SHOW USER PROGRAMMATIC ACCESS TOKENS FOR USER \"$1\"" \
    | run python -c "$PAT_PY" "$2"
}

# Create a PAT, or rotate it if it is active, and save its secret to a file.
# An expired or disabled PAT is replaced instead: rotation is documented only
# for a live secret. Prints the new expiry (epoch seconds).
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

# Stop before a command that needs a PAT if .env says it has expired, and warn
# in its last day. Silent when the expiry is unknown (a PAT passed with -p).
#   check_pat <expiry> <description>
check_pat() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] || return 0
  local left=$(( $1 - $(date +%s) ))
  (( left > 0 )) || die "$2 expired on $(fmt_time "$1"). Run ./demo.sh pat to reissue it."
  (( left > 86400 )) || warn "$2 expires on $(fmt_time "$1"). Run ./demo.sh pat to reissue it."
}
need_pat() { check_pat "${PAT_EXPIRES_AT:-}" "Your PAT (${SNOWFLAKE_PAT_FILE:-})"; }

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
# PAT expiry in epoch seconds; empty when unknown (a PAT you passed with -p)
PAT_EXPIRES_AT=${PAT_EXPIRES_AT:-}
BURST_PAT_EXPIRES_AT=${BURST_PAT_EXPIRES_AT:-}
EOF
  )
}

cmd_setup() {
  local pat_arg="" skip_smoke=0 create_pat=0 status
  CONN="" PAT_EXPIRES_AT="" BURST_PAT_EXPIRES_AT=""
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
  # Only -p overrides the default: an exported SNOWFLAKE_PAT_FILE may belong to another lab.
  PAT_FILE="${pat_arg:-$DEFAULT_PAT_FILE}"
  PAT_FILE="${PAT_FILE/#\~/$HOME}"
  if [[ -s "$PAT_FILE" ]]; then
    echo "Using your PAT at $PAT_FILE"
    # Setup wrote the default file, so it holds $PAT_NAME: record when it expires.
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
      ask ok "No PAT at $PAT_FILE. Create one for $SF_USER (SYSADMIN, 7 days)? [Y/n] " \
        "No PAT at $PAT_FILE. Pass -p <pat-file>, or --create-pat to create one for $SF_USER (SYSADMIN, 7 days)."
      [[ "$ok" =~ ^[Nn]$ ]] && die "The lab needs a PAT. Save one to $PAT_FILE or pass -p <file>."
    fi
    PAT_EXPIRES_AT="$(issue_pat "$SF_USER" "$PAT_NAME" SYSADMIN "$PAT_FILE")" || exit 1
    echo "Saved your PAT to $PAT_FILE"
  fi
  BURST_PAT_EXPIRES_AT="$(issue_pat "$COST_USER" cost_demo "$COST_ROLE" "$DEFAULT_BURST_PAT_FILE")" || exit 1
  echo "Saved the $COST_USER PAT (for ./demo.sh burst) to $DEFAULT_BURST_PAT_FILE"

  step "Writing .env"
  write_env
  echo "Wrote $ENV_FILE"

  if [[ $skip_smoke -eq 0 ]]; then
    step "Smoke test: one live prompt through the gateway"
    load_env; need_pat
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

# Reissue the demo PATs and record their new expiry in .env. Yours is left alone
# when setup was given your own file with -p.
cmd_pat() {
  [[ $# -eq 0 ]] || die "pat takes no options; it uses the connection in .env."
  load_env
  [[ -n "$CONN" ]] || die "No connection in .env. Run ./demo.sh setup first."
  SF_USER="$SNOWFLAKE_USER" SF_ACCOUNT="$SNOWFLAKE_ACCOUNT" PAT_FILE="$SNOWFLAKE_PAT_FILE"
  if [[ "$PAT_FILE" == "$DEFAULT_PAT_FILE" ]]; then
    step "Reissuing your PAT ($PAT_NAME)"
    PAT_EXPIRES_AT="$(issue_pat "$SF_USER" "$PAT_NAME" SYSADMIN "$PAT_FILE")" || exit 1
    echo "Saved to $PAT_FILE; expires $(fmt_time "$PAT_EXPIRES_AT")"
  else
    warn "Your PAT at $PAT_FILE was passed with -p, so demo.sh leaves it alone. Replace it yourself."
  fi
  step "Reissuing the $COST_USER PAT"
  BURST_PAT_EXPIRES_AT="$(issue_pat "$COST_USER" cost_demo "$COST_ROLE" "$DEFAULT_BURST_PAT_FILE")" || exit 1
  echo "Saved to $DEFAULT_BURST_PAT_FILE; expires $(fmt_time "$BURST_PAT_EXPIRES_AT")"
  write_env
  echo "Updated $ENV_FILE"
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
  traffic)  need_uv; load_env; need_pat; run python lab/generate_traffic.py "$@" ;;
  burst)    need_uv; load_env
            check_pat "${BURST_PAT_EXPIRES_AT:-}" "The $COST_USER PAT ($BURST_PAT_FILE)"
            run python lab/generate_traffic.py --burst --burst-pat-file "$BURST_PAT_FILE" "$@" ;;
  ask)      need_uv; load_env; need_pat; run python lab/live_agent.py "$@" ;;
  notebook) need_uv; load_env; need_pat; run jupyter lab "$NOTEBOOK" "$@" ;;
  app)      need_uv; load_env; need_pat; cd app; run streamlit run streamlit_app.py "$@" ;;
  pat)      need_uv; cmd_pat "$@" ;;
  deploy)   need_uv; load_env; cd app; run snow streamlit deploy --replace -c "$CONN" "$@" ;;
  teardown) cmd_teardown "$@" ;;
  *) usage; die "Unknown command: $sub" ;;
esac
