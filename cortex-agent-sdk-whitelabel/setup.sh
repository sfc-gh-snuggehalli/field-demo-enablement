#!/usr/bin/env bash
# ACME Assist: one-step setup for the Cortex Agent SDK demo.
#
#   ./setup.sh                      interactive setup
#   ./setup.sh -c <conn> -p <pat>   non-interactive (Snowflake CLI connection, PAT file)
#   ./setup.sh --history            also create the Snowflake conversation-history table
#   ./setup.sh --skip-npm           Snowflake objects and .env only
#   ./setup.sh --force-env          overwrite an existing app/.env
#   ./setup.sh --teardown -c <conn> drop everything (lab/cleanup.sql)
#
# The connection's user needs the SYSADMIN and ACCOUNTADMIN roles.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB="$HERE/lab"
APP="$HERE/app"

CONN="" PAT_FILE="" HISTORY=0 SKIP_NPM=0 FORCE_ENV=0 TEARDOWN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--connection) CONN="$2"; shift 2 ;;
    -p|--pat-file)   PAT_FILE="$2"; shift 2 ;;
    --history)       HISTORY=1; shift ;;
    --skip-npm)      SKIP_NPM=1; shift ;;
    --force-env)     FORCE_ENV=1; shift ;;
    --teardown)      TEARDOWN=1; shift ;;
    -h|--help)       sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- Prerequisites -------------------------------------------------------
step "Checking prerequisites"
command -v snow >/dev/null || die "Snowflake CLI ('snow') not found. Install: https://docs.snowflake.com/en/developer-guide/snowflake-cli/installation/installation"
if [[ $SKIP_NPM -eq 0 && $TEARDOWN -eq 0 ]]; then
  command -v node >/dev/null || die "Node.js not found (22.22 or later required)."
  node -e 'const [a,b]=process.versions.node.split(".").map(Number); process.exit(a>22||(a===22&&b>=22)?0:1)' \
    || die "Node.js $(node -v) is too old; 22.22 or later required."
fi

if [[ -z "$CONN" ]]; then
  echo "Snowflake CLI connections:"; snow connection list 2>/dev/null || true
  read -rp "Connection name to use: " CONN
fi
[[ -n "$CONN" ]] || die "A Snowflake CLI connection name is required."
snow connection test -c "$CONN" >/dev/null || die "Connection '$CONN' failed 'snow connection test'."

sf() { snow sql -c "$CONN" "$@"; }

if [[ $TEARDOWN -eq 1 ]]; then
  read -rp "Drop ACME_ASSIST_DEMO, its warehouse and roles on '$CONN'? [y/N] " ok
  [[ "$ok" =~ ^[Yy]$ ]] || exit 0
  step "Running lab/cleanup.sql"; sf -f "$LAB/cleanup.sql"
  echo "Teardown complete."; exit 0
fi

# Identity of the connection (user + org-account locator for .env).
read -r SF_USER SF_ACCOUNT < <(
  sf --format csv -q "SELECT CURRENT_USER(), LOWER(CURRENT_ORGANIZATION_NAME()||'-'||CURRENT_ACCOUNT_NAME())" | tail -n 1 | tr ',' ' '
)
[[ -n "${SF_USER:-}" ]] || die "Could not read the current user from connection '$CONN'."
echo "Connected as $SF_USER on $SF_ACCOUNT"

# --- Snowflake objects ---------------------------------------------------
step "Creating objects (lab/setup.sql, pass 1)";   sf -f "$LAB/setup.sql"
step "Loading seed data (lab/seed_data.sql)";      sf -f "$LAB/seed_data.sql"
step "Building semantic view + agents (lab/setup.sql, pass 2)"; sf -f "$LAB/setup.sql"
if [[ $HISTORY -eq 1 ]]; then
  step "Creating history store (lab/history.sql)"; sf -f "$LAB/history.sql"
fi

step "Granting demo roles to $SF_USER"
sf -q "USE ROLE ACCOUNTADMIN; GRANT ROLE ACME_DEMO_ROLE TO USER IDENTIFIER('\"$SF_USER\"');" >/dev/null
[[ $HISTORY -eq 1 ]] && sf -q "USE ROLE ACCOUNTADMIN; GRANT ROLE ACME_HISTORY_ROLE TO USER IDENTIFIER('\"$SF_USER\"');" >/dev/null

# --- app/.env ------------------------------------------------------------
step "Writing app/.env"
if [[ -f "$APP/.env" && $FORCE_ENV -eq 0 ]]; then
  echo "app/.env already exists; leaving it unchanged (use --force-env to overwrite)."
else
  if [[ -z "$PAT_FILE" ]]; then
    echo "The app authenticates with a programmatic access token (PAT) for $SF_USER."
    echo "Create one in Snowsight (User menu > Settings > Authentication) and save it to a file."
    read -rp "Path to the PAT file: " PAT_FILE
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
  cd "$APP" && npm run dev        # http://localhost:5173
Optional: set POWER_MODE_ENABLED=true in app/.env for Power Mode.
Teardown:  ./setup.sh --teardown -c $CONN
EOF
