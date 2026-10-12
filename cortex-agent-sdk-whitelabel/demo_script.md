# Demo Script — ACME Assist on the Cortex Agent SDK

**Length:** 25–35 minutes. **Prereqs:** `lab/setup.sql`, `lab/seed_data.sql` and `lab/history.sql` already run; `app/.env` configured; `cd app && npm install`.

## Beat 1 — The ask (2 min)
Deck slides 1–3. "You want an agent experience under your own brand, driving your own apps. Here's how to build it."

## Beat 2 — The meta-prompt (5 min)
1. Open `META_PROMPT.md`. Show the seed paragraph and the clarifying questions.
2. Open `PROMPT.md`. Scroll the sections: branding, browser tools, Power Mode, deploy, acceptance criteria.
3. Option A (live, about 45–60 min): start a fresh Cortex Code session on a high-reasoning model, attach `PROMPT.md`, and say "Build the application described in PROMPT.md…". Let it run during beats 3–6, then come back to it.
4. Option B (pre-built): continue with the reference build in `app/`.

## Beat 3 — Branded chat (4 min)
1. Run `npm run dev` and open http://localhost:5173.
2. Point out the ACME logo, palette, and empty-chat hero.
3. Ask **"Which region is breaching its stockout threshold?"**
   - Watch the spark-and-settle animation, the compact live line, and the streamed answer: West 13.3% vs 6%, Northeast 6.7% vs 5%.
   - Open the Activity accordion to show the generated SQL and the table.

## Beat 4 — The agent drives the app (8 min)
1. **"Show me today's failed orders for the West region"**
   - The sidebar opens Store Ops, navigates to RG-001 orders, filters FAILED, and reads 13 rows.
2. Ask the stockout question again and the agent opens Risk and highlights both breach rows.
3. **"Assign the oldest Address mismatch exception to me"**
   - An approval card appears. Click Allow; EX-5005 now shows your name.
   - Set your name in Settings first (gear icon).
4. Reload the page mid-answer. The "Reconnected" step appears and the run finishes.

## Beat 5 — Re-brand with config (2 min)
1. Stop the dev server and run `VITE_BRAND=northwind npm run dev`. The chat and the embedded app re-skin.
2. Toggle Light/Dark in Settings.

## Beat 6 — Power Mode (5 min)
1. Toggle **Power Mode** (Preview badge) and ask: **"Build me a CSV of all failed orders this week with carrier and age, and a chart by exception reason."**
2. Approve each sandbox step and download the files.

## Beat 7 — Ship it in Snowflake (4 min)
1. Show `app/app-runtime/app.yml` and run `npm run deploy:sar` (or open the already-deployed `*.snowflakecomputing.app` URL).
2. Sign in with Snowflake. Settings shows "Signed in as …" from the ingress header.
3. Mention the Docker and SPCS alternatives (deck slide 10).

### Hosting the App Runtime URL in your demo account
The URL (`https://<id>-<org>-<account>.snowflakecomputing.app`) is created by the
deploy. It is unique to each account, so every presenter deploys into their own demo
account; a URL from another account will not work. The full auth model is in `AUTH.md`.

**One-time setup in the demo account.** Run these in order:
1. `lab/setup.sql`: the database, warehouse, data, semantic view, both agents,
   `ACME_DEMO_ROLE`, and the caller grants in section 6b.
2. `lab/history.sql`: the `APP` schema, the `CONVERSATIONS` table, `ACME_HISTORY_ROLE`,
   and its caller grant.
3. `snow connection list`: confirm the default connection points at the demo account
   and uses the deploying role, then run `npm run deploy:sar` from `app/`. Copy the
   `App ready at …` URL into your notes.

**Permissions for the deploying role.** The scripts assume `SYSADMIN`; if you use a
different role, replace `SYSADMIN` in section 6b and `history.sql` with it. The role
needs:
- Ownership or `USAGE` on `ACME_ASSIST_DEMO`, the `DATA` and `APP` schemas, and
  `ACME_ASSIST_WH`.
- The privilege to create an Application Service in `ACME_ASSIST_DEMO.APP` (see the
  App Runtime docs for the exact grant in your account).
- The ability to issue `GRANT CALLER …`. This normally means `MANAGE CALLER GRANTS`
  on the account, so ask an `ACCOUNTADMIN` to run section 6b if the grants fail.
- Cortex access: the `SNOWFLAKE.CORTEX_USER` database role (or equivalent), and
  cross-region inference enabled if your region lacks a model. Anthropic, OpenAI,
  Google, xAI and Kimi models must be allowed for agents in the account.

**Permissions for each viewer.** The app runs with caller's rights. Each signed-in
user is limited by both the owner's caller grants and their own role's privileges, so
a viewer needs:
- `GRANT USAGE ON APPLICATION SERVICE ACME_ASSIST_DEMO.APP.ACME_ASSIST TO ROLE <viewer_role>;`
- A role that can use the warehouse, the agents and the semantic view or tables. The
  simplest option is `GRANT ROLE ACME_DEMO_ROLE TO ROLE <viewer_role>;`, plus
  `ACME_HISTORY_ROLE` if saved history should work.
- A Snowflake login in the same account; the URL redirects to Snowflake sign-in (SSO
  if configured).

**Check before you present:**
- `SHOW CALLER GRANTS TO ROLE SYSADMIN;` lists the grants from 6b and `history.sql`.
- Open the URL in a private window as a viewer. Ask a data question, then run an
  action in the Store Ops sidebar.
- If you see a 503 "caller's rights" error, a caller grant is missing. If you see
  "does not exist or not authorized", the viewer's role is missing a grant.
- `lab/cleanup.sql` drops everything, including the Application Service.
- Custom domains are not documented for App Runtime; see `AUTH.md` for self-hosting
  options.

## Beat 8 — Close (2 min)
Deck slides 11–12: the production checklist, then next steps. To tear down, run `lab/cleanup.sql`.

## Recovery tips
- **No browser actions:** confirm the sidebar is enabled, and check that the server logs show browser tools being merged into the request.
- **401 locally:** check that `SNOWFLAKE_PAT_FILE` points at a valid PAT and that the role has `ACME_DEMO_ROLE`.
- **Power Mode toggle hidden:** set `POWER_MODE_ENABLED=true`.
