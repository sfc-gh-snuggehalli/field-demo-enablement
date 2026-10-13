#!/usr/bin/env bash
# ACME Assist: one-step setup (and teardown) for the Cortex Agent SDK demo.
#
#   ./setup.sh                        interactive setup
#   ./setup.sh -c <conn> -p <pat>     non-interactive (Snowflake CLI connection, PAT file)
#   ./setup.sh -c <conn> --create-pat create a PAT for your user (ACME_DEMO_ROLE, 7 days)
#                                     instead of -p; rewrites app/.env
#   ./setup.sh --history              also create the Snowflake conversation-history table
#   ./setup.sh --skip-npm             Snowflake objects and app/.env only
#   ./setup.sh --force-env            overwrite an existing app/.env
#   ./setup.sh --teardown [-c <conn>] [--yes]   drop everything (lab/cleanup.sql)
#
# Everything after setup is an npm script in app/: npm run dev, npm run spike,
# npm run test:scenarios, npm run deploy:sar.
#
# Under an agent (Cortex Code), in CI, or without a terminal, nothing prompts:
# pass -c, -p or --create-pat, and --yes for teardown. A missing answer stops
# with a message saying which flag to add. SQL output goes to .logs/
# (DEMO_VERBOSE=1 shows it).
#
# Requires Node.js 22.22+ and either the Snowflake CLI ('snow') or uv; with uv,
# setup runs the CLI through uvx and needs no separate install. The
# connection's user needs the SYSADMIN and ACCOUNTADMIN roles.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB="$HERE/lab"
APP="$HERE/app"
DEFAULT_PAT_FILE="$HOME/.snowflake/acme_assist.pat"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,23p' "$HERE/setup.sh"; }

# Prompt a person at a terminal; otherwise stop and name the flag that answers it.
# Agent shells (Cortex Code sets COCO_AGENT) and CI can have a TTY nobody types in.
#   ask <var> <prompt> <flag-hint>
ask() {
  [[ -t 0 && -z "${COCO_AGENT:-}" && -z "${CI:-}" ]] || die "$3"
  read -rp "$2" "$1"
}

CONN="" PAT_FILE="" HISTORY=0 SKIP_NPM=0 FORCE_ENV=0 CREATE_PAT=0 TEARDOWN=0 YES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--connection) CONN="$2"; shift 2 ;;
    -p|--pat-file)   PAT_FILE="$2"; shift 2 ;;
    --create-pat)    CREATE_PAT=1; FORCE_ENV=1; shift ;;
    --history)       HISTORY=1; shift ;;
    --skip-npm)      SKIP_NPM=1; shift ;;
    --force-env)     FORCE_ENV=1; shift ;;
    --teardown)      TEARDOWN=1; shift ;;
    -y|--yes)        YES=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    *) die "Unknown option: $1 (see ./setup.sh --help)" ;;
  esac
done

# --- Prerequisites -------------------------------------------------------
step "Checking prerequisites"

# Use 'snow' from PATH, else run it through uvx for the rest of this script.
if ! command -v snow >/dev/null; then
  command -v uv >/dev/null || die "Neither the Snowflake CLI ('snow') nor uv found. Install uv: brew install uv (or https://docs.astral.sh/uv/)"
  # Pin Python and the CLI: on an old default Python, uvx resolves to CLI 2.x.
  snow() { uvx --python 3.11 --from "snowflake-cli>=3.29" snow "$@"; }
  echo "Using the Snowflake CLI through uvx ($(snow --version))"
fi

if [[ $TEARDOWN -eq 0 && ( $SKIP_NPM -eq 0 || $CREATE_PAT -eq 1 ) ]]; then
  command -v node >/dev/null || die "Node.js not found (22.22 or later required)."
  node -e 'const [a,b]=process.versions.node.split(".").map(Number); process.exit(a>22||(a===22&&b>=22)?0:1)' \
    || die "Node.js $(node -v) is too old; 22.22 or later required."
fi

if [[ -z "$CONN" ]]; then
  echo "Snowflake CLI connections:"; snow connection list 2>/dev/null || true
  ask CONN "Connection name to use: " "Pass -c <connection>, one of the connections listed above."
fi
[[ -n "$CONN" ]] || die "A Snowflake CLI connection name is required."
snow connection test -c "$CONN" >/dev/null || die "Connection '$CONN' failed 'snow connection test'."

sf() { snow sql -c "$CONN" "$@"; }

# Run a SQL file quietly: its statement echo goes to .logs/<file>.log, and the
# tail is shown only if it fails. DEMO_VERBOSE=1 streams it instead.
sql_file() {
  local file="$1" log
  if [[ -n "${DEMO_VERBOSE:-}" ]]; then sf -f "$file"; return; fi
  mkdir -p "$HERE/.logs"; log="$HERE/.logs/$(basename "$file" .sql).log"
  if sf -f "$file" > "$log" 2>&1; then
    echo "  ok (output in ${log#"$HERE/"})"
  else
    tail -n 40 "$log" >&2
    die "$(basename "$file") failed; full output in $log"
  fi
}

if [[ $TEARDOWN -eq 1 ]]; then
  if [[ $YES -eq 0 ]]; then
    ask ok "Drop ACME_ASSIST_DEMO, its warehouse and roles on '$CONN'? [y/N] " \
      "Teardown drops ACME_ASSIST_DEMO, its warehouse and roles on '$CONN'. Pass --yes to confirm."
    [[ "$ok" =~ ^[Yy]$ ]] || exit 0
  fi
  step "Running lab/cleanup.sql"; sql_file "$LAB/cleanup.sql"
  echo "Teardown complete."; exit 0
fi

# Identity of the connection (user + org-account locator for .env).
read -r SF_USER SF_ACCOUNT < <(
  sf --format csv -q "SELECT CURRENT_USER(), LOWER(CURRENT_ORGANIZATION_NAME()||'-'||CURRENT_ACCOUNT_NAME())" | tail -n 1 | tr ',' ' '
)
[[ -n "${SF_USER:-}" ]] || die "Could not read the current user from connection '$CONN'."
echo "Connected as $SF_USER on $SF_ACCOUNT"

# --- Snowflake objects ---------------------------------------------------
step "Creating objects (lab/setup.sql, pass 1)";   sql_file "$LAB/setup.sql"
step "Loading seed data (lab/seed_data.sql)";      sql_file "$LAB/seed_data.sql"
step "Building semantic view + agents (lab/setup.sql, pass 2)"; sql_file "$LAB/setup.sql"
if [[ $HISTORY -eq 1 ]]; then
  step "Creating history store (lab/history.sql)"; sql_file "$LAB/history.sql"
fi

step "Granting demo roles to $SF_USER"
sf -q "USE ROLE ACCOUNTADMIN; GRANT ROLE ACME_DEMO_ROLE TO USER IDENTIFIER('\"$SF_USER\"');" >/dev/null
[[ $HISTORY -eq 1 ]] && sf -q "USE ROLE ACCOUNTADMIN; GRANT ROLE ACME_HISTORY_ROLE TO USER IDENTIFIER('\"$SF_USER\"');" >/dev/null

# --- app/.env ------------------------------------------------------------
step "Writing app/.env"
if [[ -f "$APP/.env" && $FORCE_ENV -eq 0 ]]; then
  echo "app/.env already exists; leaving it unchanged (use --force-env to overwrite)."
else
  if [[ $CREATE_PAT -eq 1 ]]; then
    # Create (or rotate, if it exists) the token, and save its secret.
    PAT_FILE="$DEFAULT_PAT_FILE"
    if sf --format csv -q "SHOW USER PROGRAMMATIC ACCESS TOKENS FOR USER \"$SF_USER\"" \
         | cut -d, -f1 | grep -qix acme_assist; then
      stmt="ALTER USER \"$SF_USER\" ROTATE PROGRAMMATIC ACCESS TOKEN acme_assist EXPIRE_ROTATED_TOKEN_AFTER_HOURS = 0"
    else
      stmt="ALTER USER \"$SF_USER\" ADD PROGRAMMATIC ACCESS TOKEN acme_assist ROLE_RESTRICTION = 'ACME_DEMO_ROLE' DAYS_TO_EXPIRY = 7"
    fi
    mkdir -p "$(dirname "$PAT_FILE")"
    ( umask 077
      sf --format json -q "USE ROLE ACCOUNTADMIN; $stmt" | node -e '
let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
  const find = x => Array.isArray(x) ? x.map(find).find(Boolean) : (x && x.token_secret);
  const secret = find(JSON.parse(s));
  if (!secret) { console.error("no token_secret in the output"); process.exit(1); }
  console.log(secret);
});' > "$PAT_FILE" ) || die "Could not create a PAT for $SF_USER."
    echo "Saved a PAT for $SF_USER (ACME_DEMO_ROLE, 7 days) to $PAT_FILE"
  elif [[ -z "$PAT_FILE" ]]; then
    echo "The app authenticates with a programmatic access token (PAT) for $SF_USER."
    echo "Create one in Snowsight (User menu > Settings > Authentication) and save it to a file."
    ask PAT_FILE "Path to the PAT file: " \
      "The app needs a PAT for $SF_USER. Pass -p <pat-file>, or --create-pat to create one (ACME_DEMO_ROLE, 7 days)."
  fi
  PAT_FILE="${PAT_FILE/#\~/$HOME}"
  [[ -s "$PAT_FILE" ]] || die "PAT file '$PAT_FILE' not found or empty."
  PAT_FILE="$(cd "$(dirname "$PAT_FILE")" && pwd)/$(basename "$PAT_FILE")"
  chmod 600 "$PAT_FILE" 2>/dev/null || true

  awk -v acct="$SF_ACCOUNT" -v user="$SF_USER" -v pat="$PAT_FILE" -v hist="$HISTORY" '
    /^SNOWFLAKE_ACCOUNT=/  { print "SNOWFLAKE_ACCOUNT=" acct; next }
    /^SNOWFLAKE_USER=/     { print "SNOWFLAKE_USER=" user; next }
    /^SNOWFLAKE_PAT_FILE=/ { print "SNOWFLAKE_PAT_FILE=" pat; next }
    /^HISTORY_STORE=/ && hist == 1 { print "HISTORY_STORE=snowflake"; next }
    { print }
  ' "$APP/.env.example" > "$APP/.env"
  chmod 600 "$APP/.env"
  echo "Wrote app/.env (account $SF_ACCOUNT, user $SF_USER)."
fi

# --- npm + smoke test ----------------------------------------------------
if [[ $SKIP_NPM -eq 0 ]]; then
  step "Installing npm dependencies"; (cd "$APP" && npm install)
  step "Smoke test: client-side tool round trip (npm run spike)"
  (cd "$APP" && npm run spike) || die "Spike failed. Check app/.env and the PAT, then re-run: cd app && npm run spike"
fi

step "Done"
cat <<EOF
Start the app:
  cd app && npm run dev           # http://localhost:5173
Optional: set POWER_MODE_ENABLED=true in app/.env for Power Mode.
Teardown:  ./setup.sh --teardown -c $CONN
EOF
