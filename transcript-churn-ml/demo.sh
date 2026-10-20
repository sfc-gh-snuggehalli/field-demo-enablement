#!/usr/bin/env bash
# Call-transcript topics to churn: setup, run and teardown in one script.
#
#   ./demo.sh setup [-c <conn>]
#                        Python env (uv), lab/setup.sql (database, warehouse, synthetic data), .env
#   ./demo.sh build [--yes] [--from <1-5>]
#                        run the five lab notebooks headless, in order, and print their CHECK lines
#   ./demo.sh ledger [--yes]
#                        re-run notebook 05 (data-gravity ledger and AI cost) only
#   ./demo.sh notebook [<1-5>]
#                        open a lab notebook in JupyterLab (default 01)
#   ./demo.sh sql <file> run another SQL file with the saved connection
#   ./demo.sh app [--yes] [--app-only]
#                        presenter path: lab/app_setup.sql (live step, risk tables, semantic view,
#                        search service, agent), then deploy the Streamlit story app (app/)
#   ./demo.sh app-reset  remove January again, so the app's live step can be shown again
#   ./demo.sh app-load   run the live step from the command line (rehearsal or recovery; resumes a partial run)
#   ./demo.sh teardown [-c <conn>] [--yes]
#                        drop everything (lab/cleanup.sql)
#
# Under an agent (Cortex Code), in CI, or without a terminal, nothing prompts:
# pass -c for setup, and --yes for build, ledger, app and teardown. A missing answer stops with
# a message saying which flag to add.
#
# Requires uv (https://docs.astral.sh/uv/). uv installs Python, the lab dependencies and
# the Snowflake CLI into .venv.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$HERE/.env"
NOTEBOOKS=(
  "lab/transcript-churn-01-segments-governance.ipynb"
  "lab/transcript-churn-02-topics-registry.ipynb"
  "lab/transcript-churn-03-insights-semantic-view.ipynb"
  "lab/transcript-churn-04-churn-feature-store.ipynb"
  "lab/transcript-churn-05-ledger-cost.ipynb"
)
cd "$HERE"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
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

cmd_setup() {
  CONN=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--connection) CONN="$2"; shift 2 ;;
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

  step "Creating the database, warehouse and synthetic data (lab/setup.sql)"
  sql_file lab/setup.sql

  step "Writing .env"
  ( umask 077
    printf '# Written by ./demo.sh setup. demo.sh loads this before every command.\nSNOWFLAKE_DEFAULT_CONNECTION_NAME=%s\nSNOWFLAKE_ACCOUNT=%s\nDEMO_EXPECTED_ACCOUNT=%s\n' \
      "$CONN" "$sf_account" "$acct_name" > "$ENV_FILE" )

  step "Done"
  cat <<EOF
Next:
  ./demo.sh build --yes   # run the five notebooks headless and print every CHECK line
  ./demo.sh notebook 1    # or walk them yourself, 01 to 05
Teardown: ./demo.sh teardown
EOF
}

# Run one notebook with nbconvert (outputs saved into it) and print its CHECK lines.
run_notebook() {
  local nb="$1" log
  mkdir -p "$HERE/.logs"; log="$HERE/.logs/$(basename "$nb" .ipynb).log"
  step "Running $nb (log in ${log#"$HERE/"})"
  if run jupyter nbconvert --to notebook --execute --inplace \
       --ExecutePreprocessor.timeout=3000 --ExecutePreprocessor.kernel_name=python3 \
       "$nb" > "$log" 2>&1; then
    run python - "$nb" <<'PY'
import json, sys
nb = json.load(open(sys.argv[1]))
for c in nb["cells"]:
    for o in c.get("outputs", []):
        text = "".join(o.get("text", "")) if o.get("output_type") == "stream" else ""
        for line in text.splitlines():
            if line.startswith("CHECK "):
                print("  " + line[:240])
PY
  else
    grep -E '^CHECK ' "$log" | sed 's/^/  /' || true
    tail -n 30 "$log" >&2
    die "$nb failed; see $log. Fix the cause, then re-run with --from <n>."
  fi
}

cmd_build() {
  local yes=0 ok="" from=1 i
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes) yes=1; shift ;;
      --from)   from="$2"; shift 2 ;;
      *) die "Unknown option for build: $1" ;;
    esac
  done
  [[ "$from" =~ ^[1-5]$ ]] || die "--from takes 1 to 5."
  if [[ $yes -eq 0 ]]; then
    ask ok "Run notebooks 0$from-05 on '$CONN' (AI functions, models, a model monitor; spends credits)? [y/N] " \
      "Build runs notebooks 0$from-05 on '$CONN': it calls AI functions, trains and registers models and creates a model monitor. Pass --yes to confirm."
    [[ "$ok" =~ ^[Yy]$ ]] || exit 0
  fi
  for (( i = from - 1; i < ${#NOTEBOOKS[@]}; i++ )); do run_notebook "${NOTEBOOKS[$i]}"; done
  step "Build complete: every CHECK passed"
  echo "Next: ./demo.sh app --yes   # the presenter path (story app + agent)"
}

cmd_ledger() {
  local yes=0 ok=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes) yes=1; shift ;;
      *) die "Unknown option for ledger: $1" ;;
    esac
  done
  if [[ $yes -eq 0 ]]; then
    ask ok "Re-run notebook 05 (ledger and AI cost) on '$CONN'? [y/N] " \
      "Ledger re-runs notebook 05 on '$CONN' (moves 4,000 rows out and back on purpose). Pass --yes to confirm."
    [[ "$ok" =~ ^[Yy]$ ]] || exit 0
  fi
  run_notebook "${NOTEBOOKS[4]}"
}

cmd_app() {
  local yes=0 ok="" app_only=0 pool url
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes)   yes=1; shift ;;
      --app-only) app_only=1; shift ;;
      *) die "Unknown option for app: $1" ;;
    esac
  done
  if [[ $yes -eq 0 ]]; then
    ask ok "Create the presenter objects and deploy the story app on '$CONN'? [y/N] " \
      "App runs lab/app_setup.sql and deploys a Streamlit app on '$CONN'. Pass --yes to confirm."
    [[ "$ok" =~ ^[Yy]$ ]] || exit 0
  fi
  if [[ $app_only -eq 0 ]]; then
    step "Creating the live step, risk tables, semantic view, search service and agent (lab/app_setup.sql)"
    sql_file lab/app_setup.sql
  fi

  step "Resolving the Streamlit compute pool"
  pool="${DEMO_COMPUTE_POOL:-}"
  if [[ -z "$pool" ]]; then
    pool="$(sf --format json -q "SHOW PARAMETERS LIKE 'DEFAULT_STREAMLIT_COMPUTE_POOL' IN ACCOUNT" | run python -c '
import json, sys
rows = json.load(sys.stdin)
print((rows[0].get("value") or rows[0].get("default") or "") if rows else "")')" \
      || die "Could not read DEFAULT_STREAMLIT_COMPUTE_POOL. Set DEMO_COMPUTE_POOL=<pool from SHOW COMPUTE POOLS> and re-run."
  fi
  [[ -n "$pool" ]] || die "No DEFAULT_STREAMLIT_COMPUTE_POOL on this account. Set DEMO_COMPUTE_POOL=<pool from SHOW COMPUTE POOLS> and re-run."
  echo "  $pool"

  step "Deploying the story app (app/)"
  ( cd "$HERE/app" && DEMO_COMPUTE_POOL="$pool" run snow streamlit deploy churn_story_app -c "$CONN" --role SYSADMIN --replace --prune ) \
    || die "Deploy failed. Check the compute pool and that the role can use it."

  step "Checking the app exists"
  sf --format csv -q "SHOW STREAMLITS LIKE 'CHURN_STORY_APP' IN SCHEMA TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS" \
    | grep -qi CHURN_STORY_APP || die "Deploy reported success but CHURN_STORY_APP was not found."
  url="https://app.snowflake.com/${SNOWFLAKE_ACCOUNT//-//}/#/streamlit-apps/TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.CHURN_STORY_APP"
  cat <<EOF

App:   $url
Agent: TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.CHURN_INSIGHTS_AGENT, in Snowflake Intelligence (https://ai.snowflake.com)
       as "Call insights and churn risk".
Before each show: ./demo.sh app-reset   (the live step then has January to load)
EOF
}

cmd_app_reset() {
  step "Removing January (CALL ANALYTICS.DEMO_RESET_JANUARY())"
  sf -q "CALL TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.DEMO_RESET_JANUARY()" >/dev/null
  echo "  done: the app's page 3 can load January again."
}

cmd_app_load() {
  local run_id out
  run_id="CLI-$(date +%Y%m%d-%H%M%S)"
  step "Loading January from the command line (CALL ANALYTICS.LOAD_JANUARY('$run_id'), about 2 minutes)"
  out="$(sf --format json -q "CALL TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.LOAD_JANUARY('$run_id')" | run python -c '
import json, sys
res = json.loads(list(json.load(sys.stdin)[0].values())[0])
print(res.get("status", "") + "|" + res.get("message", "") + (" (step " + res["step"] + ")" if res.get("step") else ""))')" \
    || die "LOAD_JANUARY could not be called."
  [[ "${out%%|*}" == "ok" ]] || die "January load ${out%%|*}: ${out#*|}. Re-run ./demo.sh app-load to resume (finished steps are skipped), or ./demo.sh app-reset to start over."
  sf -q "SELECT STEP_NO, STEP, ROWS_OUT, AI_CALLS, ROUND(SECONDS, 1) AS SECONDS
         FROM TRANSCRIPT_CHURN_ML_DEMO.ANALYTICS.LIVE_RUN_LOG
         WHERE RUN_ID = '$run_id' AND STEP_NO BETWEEN 1 AND 6 ORDER BY STEP_NO"
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
    ask ok "Drop TRANSCRIPT_CHURN_ML_DEMO and warehouse TRANSCRIPT_CHURN_ML_WH on '$CONN'? [y/N] " \
      "Teardown drops TRANSCRIPT_CHURN_ML_DEMO and warehouse TRANSCRIPT_CHURN_ML_WH on '$CONN'. Pass --yes to confirm."
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
  build)    need_uv; load_env; cmd_build "$@" ;;
  ledger)   need_uv; load_env; cmd_ledger "$@" ;;
  notebook) need_uv; load_env; n="${1:-1}"; [[ "$n" =~ ^[1-5]$ ]] || die "notebook takes 1 to 5."
            run jupyter lab "${NOTEBOOKS[$((n - 1))]}" ;;
  sql)      need_uv; load_env; [[ -n "${1:-}" ]] || die "Usage: ./demo.sh sql <file>"; sf -f "$@" ;;
  app)       need_uv; load_env; cmd_app "$@" ;;
  app-reset) need_uv; load_env; cmd_app_reset ;;
  app-load)  need_uv; load_env; cmd_app_load ;;
  teardown) need_uv; cmd_teardown "$@" ;;
  *) usage; die "Unknown command: $sub" ;;
esac
