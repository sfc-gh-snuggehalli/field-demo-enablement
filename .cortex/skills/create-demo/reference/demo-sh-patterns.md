# demo.sh patterns

Vetted blocks for `<slug>/demo.sh`, lifted from modules that run them (likely-to-sell-ml,
ai-gateway, multi-agent-mcp). `templates/demo.sh` already carries the agent-safe core
(`step`, `die`, `ask`, `run`, `sf`, `sql_file`, `need_uv`, `load_env`, `pick_connection`) and
pattern A. Add the others only when the lab needs them, and list every subcommand you add in
the header comment and in the `usage()` line range.

| Pattern | Use when |
|---|---|
| A. Account check | Always (already in the template) |
| B. `build [--yes]` | The notebook creates the objects, or is the verification run |
| C. `app` / `smoke` | The lab has a local app or a headless check script |
| D. PAT issue / rotate / expiry + `pat` | A lab script or app calls a Snowflake REST API with a PAT |
| E. Service-user key pairs | The lab signs in as persona/service users (key-pair JWT) |
| F. Teardown of PATs and local secrets | D or E is used |

General rules, whichever blocks you add:
- Secrets never reach stdout. A PAT secret goes from `--format json` straight into a mode-600
  file; a private key is generated into a mode-600 file and only its public half is read.
  Under Cortex Code the agent therefore never sees a secret, so these steps are safe to run there.
- Everything `demo.sh` learns at setup (account, user, file paths, expiries) goes into `.env`,
  and every subcommand reads it through `load_env`. Nobody exports variables by hand.
- Account identifiers are derived from the connection, never hard-coded in the module.

## A. Account check (template)

Record the account behind the connection, and let the notebook refuse to build anywhere else.

```bash
step "Checking the account behind '$CONN'"
IFS=, read -r SF_USER SF_ACCOUNT ACCT_NAME < <(sf --format csv -q \
  "SELECT CURRENT_USER(), CURRENT_ORGANIZATION_NAME()||'-'||CURRENT_ACCOUNT_NAME(), CURRENT_ACCOUNT_NAME()" | tail -n 1)
[[ -n "${SF_USER:-}" ]] || die "Could not read the current user from connection '$CONN'."
echo "  $SF_USER on $SF_ACCOUNT"
# .env: SNOWFLAKE_ACCOUNT=$SF_ACCOUNT (org-account, for REST hosts) and DEMO_EXPECTED_ACCOUNT=$ACCT_NAME
```

The notebook's connect cell reads `DEMO_ACCOUNT = os.environ.get("DEMO_EXPECTED_ACCOUNT", "<YOUR_DEMO_ACCOUNT>")`
and a guard cell stops when `CURRENT_ACCOUNT_NAME()` differs (see `templates/lab.ipynb.tmpl`).
REST hosts use hyphens where account names have underscores:
`lower(SNOWFLAKE_ACCOUNT).replace('_', '-') + '.snowflakecomputing.com'`.

## B. `build [--yes]`: run the notebook headless

Every notebook section ends in `check(<section>, ok, evidence)`, which prints
`CHECK <section>: PASS | <evidence>` and raises on FAIL. `build` runs the whole notebook with
nbconvert (outputs saved in place, so a reviewer can open it afterwards) and echoes only the
CHECK lines. Needs `nbconvert>=7.16` in `pyproject.toml`.

```bash
cmd_build() {
  local yes=0 ok=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes) yes=1; shift ;;
      *) die "Unknown option for build: $1" ;;
    esac
  done
  if [[ $yes -eq 0 ]]; then
    ask ok "Run $NOTEBOOK on '$CONN' (creates <what it creates>)? [y/N] " \
      "Build runs $NOTEBOOK on '$CONN' and creates <what it creates>. Pass --yes to confirm."
    [[ "$ok" =~ ^[Yy]$ ]] || exit 0
  fi
  mkdir -p "$HERE/.logs"
  step "Running $NOTEBOOK (outputs saved into the notebook; log in .logs/build.log)"
  if run jupyter nbconvert --to notebook --execute --inplace \
       --ExecutePreprocessor.timeout=1800 --ExecutePreprocessor.kernel_name=python3 \
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
```

Dispatch: `build) need_uv; load_env; cmd_build "$@" ;;`. Notebook SQL cells use `%%sql -r <name>`
(Snowsight runs them natively; the template's connect cell registers a local `%%sql` magic so
nbconvert runs them through the Snowpark session). One statement per `%%sql` cell.

## C. `app` and `smoke`

```bash
  app)   need_uv; load_env; run streamlit run app/streamlit_app.py "$@" ;;
  smoke) need_uv; load_env; run python client/smoke.py "$@" ;;
```

If the app needs a PAT (pattern D), call `need_pat` first. If `app/` has its own
`pyproject.toml` (a Streamlit-in-Snowflake manifest), keep `--project "$HERE"` so uv uses the
module's file.

## D. PAT issue / rotate / expiry and `pat`

`setup` creates the PAT (or rotates it when it is active; an expired or disabled one is
replaced), saves the secret to a mode-600 file, and records the expiry in `.env`. Commands that
use it call `need_pat`, which stops after expiry and warns in the last day. `pat` reissues
without re-running setup. Requires ACCOUNTADMIN on the connection's user to SHOW/ALTER PATs, and
a PAT on a person user only authenticates from a network the account's network policy allows.

```bash
PAT_NAME="<slug_underscored>_demo"
DEFAULT_PAT_FILE="$HOME/.snowflake/<slug_underscored>_demo.pat"

warn() { printf '\033[33mWARNING:\033[0m %s\n' "$*" >&2; }

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

# Prints the new expiry (epoch seconds).
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
  chmod 600 "$file"
  info="$(pat_status "$user" "$name")" || die "Saved the PAT to $file, but could not read its expiry."
  [[ "${info##* }" =~ ^[0-9]+$ ]] || die "Saved the PAT to $file, but SHOW lists no $name for $user."
  echo "${info##* }"
}

fmt_time() { date -r "$1" '+%Y-%m-%d %H:%M %Z' 2>/dev/null || date -d "@$1" '+%Y-%m-%d %H:%M %Z'; }

#   check_pat <expiry> <description>
check_pat() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] || return 0
  local left=$(( $1 - $(date +%s) ))
  (( left > 0 )) || die "$2 expired on $(fmt_time "$1"). Run ./demo.sh pat to reissue it."
  (( left > 86400 )) || warn "$2 expires on $(fmt_time "$1"). Run ./demo.sh pat to reissue it."
}
need_pat() { check_pat "${PAT_EXPIRES_AT:-}" "Your PAT (${PAT_FILE:-})"; }
```

Setup flags: `-p <pat-file>` uses an existing PAT file (demo.sh then never rotates it), and
`--create-pat` answers the "create one?" prompt. With neither and no file, `ask` stops and names
both flags. The ROLE_RESTRICTION should be the narrowest role the lab script needs.
Never put `ALTER USER ... ADD PROGRAMMATIC ACCESS TOKEN` in setup.sql: it fails on a second run.

## E. Service-user key pairs

For labs that sign in as dedicated service users (e.g. persona users whose DEFAULT_ROLE the
governance depends on). Keys live under `~/.snowflake/keys/`, mode 600; an existing key is reused
and its public half re-registered, so setup stays re-runnable.

```bash
KEY_DIR="$HOME/.snowflake/keys"

#   ensure_key <user> <key-file>
ensure_key() {
  local user="$1" key="$2" pub
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
```

Record each key path in `.env`; the app and scripts read the path, never the key contents.

## F. Teardown of PATs and local secrets

`DROP DATABASE` does not remove a PAT on a person user or files on disk. After `cleanup.sql`:

```bash
  if [[ "$(pat_status "$SF_USER" "$PAT_NAME" | cut -d' ' -f1)" != "NONE" ]]; then
    sf -q "USE ROLE ACCOUNTADMIN; ALTER USER \"$SF_USER\" REMOVE PROGRAMMATIC ACCESS TOKEN $PAT_NAME" >/dev/null \
      && echo "  removed PAT $PAT_NAME from $SF_USER"
  fi
  rm -f "$DEFAULT_PAT_FILE" "$KEY_DIR"/<slug_underscored>_*.p8 "$ENV_FILE"
```

Only delete files demo.sh itself wrote (the default PAT file, the module's key files); leave a
PAT passed with `-p` alone.
