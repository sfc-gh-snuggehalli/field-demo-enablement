#!/usr/bin/env bash
# {{DECK_TITLE}}: setup, run and teardown in one script.
#
#   ./demo.sh setup [-c <conn>] [--skip-data]
#                        Python env (uv), lab/setup.sql, lab/data_gen.py (if present), .env
#   ./demo.sh data       (re)load the synthetic data (lab/data_gen.py)
#   ./demo.sh notebook   open the lab notebook in JupyterLab
#   ./demo.sh sql <file> run another SQL file with the saved connection
#   ./demo.sh teardown [-c <conn>] [--yes]
#                        drop everything (lab/cleanup.sql)
#
# Under an agent (Cortex Code), in CI, or without a terminal, nothing prompts:
# pass -c for setup, and --yes for teardown. A missing answer stops with a
# message saying which flag to add.
#
# Requires uv (https://docs.astral.sh/uv/). uv installs Python, the lab
# dependencies and the Snowflake CLI into .venv.
#
# Optional blocks (build, app, PATs, key pairs): see the create-demo skill's
# reference/demo-sh-patterns.md. Keep usage() in step with this header.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$HERE/.env"
NOTEBOOK="lab/{{SLUG}}-lab.ipynb"
cd "$HERE"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,17p' "$HERE/demo.sh"; }

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

load_data() {
  [[ -f lab/data_gen.py ]] || return 0
  step "Loading synthetic data (lab/data_gen.py)"
  run python lab/data_gen.py --connection "$CONN"
}

cmd_setup() {
  local skip_data=0
  CONN=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--connection) CONN="$2"; shift 2 ;;
      --skip-data)     skip_data=1; shift ;;
      *) die "Unknown option for setup: $1" ;;
    esac
  done

  step "Installing the Python environment (uv sync)"
  uv sync --project "$HERE" --frozen
  pick_connection

  step "Checking the account behind '$CONN'"
  local sf_user sf_account acct_name
  IFS=, read -r sf_user sf_account acct_name < <(sf --format csv -q \
    "SELECT CURRENT_USER(), CURRENT_ORGANIZATION_NAME()||'-'||CURRENT_ACCOUNT_NAME(), CURRENT_ACCOUNT_NAME()" | tail -n 1)
  [[ -n "${sf_user:-}" ]] || die "Could not read the current user from connection '$CONN'."
  echo "  $sf_user on $sf_account"

  step "Creating Snowflake objects (lab/setup.sql)"
  sql_file lab/setup.sql
  [[ $skip_data -eq 1 ]] || load_data

  step "Writing .env"
  ( umask 077
    printf '# Written by ./demo.sh setup. demo.sh loads this before every command.\nSNOWFLAKE_DEFAULT_CONNECTION_NAME=%s\nSNOWFLAKE_ACCOUNT=%s\nDEMO_EXPECTED_ACCOUNT=%s\n' \
      "$CONN" "$sf_account" "$acct_name" > "$ENV_FILE" )

  step "Done"
  cat <<EOF
Next:
  ./demo.sh notebook    # the hands-on lab
Teardown: ./demo.sh teardown
EOF
}

cmd_teardown() {
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
  pick_connection
  if [[ $yes -eq 0 ]]; then
    ask ok "Drop {{DB_NAME}} and the lab's account-level objects on '$CONN'? [y/N] " \
      "Teardown drops {{DB_NAME}} and the lab's account-level objects on '$CONN'. Pass --yes to confirm."
    [[ "$ok" =~ ^[Yy]$ ]] || exit 0
  fi
  step "Running lab/cleanup.sql"; sql_file lab/cleanup.sql
  rm -f "$ENV_FILE"
  echo "Teardown complete."
}

[[ $# -gt 0 ]] || { usage; exit 1; }
sub="$1"; shift
case "$sub" in
  -h|--help|help) usage ;;
  setup)    need_uv; cmd_setup "$@" ;;
  data)     need_uv; load_env; load_data ;;
  notebook) need_uv; load_env; run jupyter lab "$NOTEBOOK" "$@" ;;
  sql)      need_uv; load_env; [[ -n "${1:-}" ]] || die "Usage: ./demo.sh sql <file>"; sf -f "$@" ;;
  teardown) need_uv; cmd_teardown "$@" ;;
  *) usage; die "Unknown command: $sub" ;;
esac
