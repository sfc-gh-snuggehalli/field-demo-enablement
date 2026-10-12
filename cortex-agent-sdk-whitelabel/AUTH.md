# Authentication, identity and custom domains

How ACME Assist authenticates users, which identity reaches Snowflake, and how to put the
app on your own domain (for example `assist.acme.com`) behind your own OAuth/SSO.

## 1. The three hops

```
User ──(1) sign-in──▶ App (UI + server) ──(2) token──▶ Snowflake REST
                                                       ├─ Cortex Agent API (agent:run)
                                                       └─ SQL API (history, run store)
                                         (3) Snowflake enforces RBAC for that identity
```

1. **User → app.** Who is this person? (Snowflake login, your IdP, or nothing locally.)
2. **App → Snowflake.** Which token the server sends on each Agent/SQL API call. All of it
   is in `app/server/auth.ts`; the browser never holds a Snowflake token.
3. **Snowflake.** Analyst SQL, the semantic view and warehouse usage run as the identity in
   hop 2, so RBAC, masking and row access policies apply to that user or role.

## 2. Modes supported today

| Mode | Hop 1 (user sign-in) | Hop 2 (token to Snowflake) | Runs as | Use for |
|---|---|---|---|---|
| Local dev (`npm run dev`, `npm start`) | none | PAT (`SNOWFLAKE_PAT` / `SNOWFLAKE_PAT_FILE`) or key-pair JWT (`SNOWFLAKE_PRIVATE_KEY_PATH`) | the PAT/key user | building and demos |
| App Runtime (deployed) | Snowflake login (your SSO if the account uses SAML/OAuth SSO) | `/snowflake/session/token` + `Sf-Context-Current-User-Token` (caller's rights) | the signed-in user, bounded by caller grants | production inside Snowflake |
| SPCS service | same as App Runtime | same as App Runtime | same | when you need SPCS controls |

### App Runtime details

- URL: `https://<id>-<org>-<account>.snowflakecomputing.app`. Snowflake hosts the login and
  only signed-in users with `USAGE` on the Application Service reach the app.
- Share the app: `GRANT USAGE ON APPLICATION SERVICE ACME_ASSIST_DEMO.APP.ACME_ASSIST TO ROLE <role>;`
  (users also need `USAGE` on the database and schema).
- **Caller's rights.** The server combines the service token and the user's token, so every
  query runs as the user. An operation succeeds only if both the user's privileges and the
  owner role's **caller grants** allow it. Those are in `lab/setup.sql` section 6b and
  `lab/history.sql`; without them you see the 503 "caller's rights" error. Audit them with
  `SHOW CALLER GRANTS TO ROLE SYSADMIN;`.
- The signed-in user's name appears in the sidebar and is passed to the agent as "me"
  (for example "assign ... to me"). See `server/identity.ts`.
- Hardening: deploy with a dedicated, narrowly scoped owner role rather than SYSADMIN, put
  caller grants in a caller role (`ACME_ASSIST_CALLER_RO`), and restrict
  `BIND SERVICE ENDPOINT` to approved roles. See
  [Securing App Runtime applications](https://docs.snowflake.com/en/developer-guide/snowflake-app-runtime/security).

## 3. Custom domain: what is and isn't possible

**App Runtime.** The Snowflake documentation for App Runtime (overview, deploy, `app.yml`,
access control, security, limitations) does not describe custom domains or vanity URLs,
and the ingress sets `X-Frame-Options: DENY` (so you also can't embed it in your portal in
an iframe). Treat the `*.snowflakecomputing.app` URL as fixed. A reverse proxy in front of
it isn't a supported pattern: Snowflake's login and cookies are bound to that host. Check
with your Snowflake account team before planning around anything else.

**If you need your own domain, self-host the app** (the Express build). The same code runs
anywhere Node 20+ runs: your Kubernetes cluster, ECS/Fargate, Azure Container Apps, Cloud
Run, or a VM. You own TLS, the hostname and the sign-in. You then pick how hop 2 works.

## 4. Self-hosted on a custom domain: three auth patterns

| Pattern | Runs as | Effort | Recommended when |
|---|---|---|---|
| A. Service user (key pair / PAT) | one service user | low | internal, everyone may see the same data |
| B. Snowflake OAuth (per user) | each signed-in user | medium | per-user RBAC, users already have Snowflake logins |
| C. External OAuth with your IdP (Okta, Entra ID, PingFederate) | each user, mapped from IdP | medium–high | SSO-first orgs, one sign-in for the portal and Snowflake |

### Pattern A: service user behind your SSO

1. Put the app behind your existing gateway/SSO (for example an OIDC proxy, Azure App
   Service authentication, or Cloudflare Access). That handles hop 1.
2. Create a service user with key-pair auth and a least-privilege role:
   ```sql
   CREATE USER ACME_ASSIST_SVC TYPE = SERVICE DEFAULT_ROLE = ACME_DEMO_ROLE
     RSA_PUBLIC_KEY = '<public key>';
   GRANT ROLE ACME_DEMO_ROLE TO USER ACME_ASSIST_SVC;
   ```
3. Set `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER=ACME_ASSIST_SVC` and
   `SNOWFLAKE_PRIVATE_KEY_PATH` (mount the key from your secret manager). No code changes.
4. Pass the gateway's user identity (email) to the app for the "me" display only. Data
   access is the service role for everybody. Don't use this pattern if users should
   see different rows.

### Pattern B: Snowflake OAuth (per user)

1. Create a custom OAuth client in Snowflake:
   ```sql
   CREATE SECURITY INTEGRATION ACME_ASSIST_OAUTH
     TYPE = OAUTH
     OAUTH_CLIENT = CUSTOM
     OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
     OAUTH_REDIRECT_URI = 'https://assist.acme.com/auth/callback'
     OAUTH_ISSUE_REFRESH_TOKENS = TRUE
     OAUTH_REFRESH_TOKEN_VALIDITY = 86400
     ENABLED = TRUE;
   SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('ACME_ASSIST_OAUTH');
   ```
2. In the app, add an authorization-code flow. Send users to
   `https://<account>.snowflakecomputing.com/oauth/authorize`, exchange the code at
   `/oauth/token-request`, and keep the access and refresh tokens **server-side** in an
   encrypted, HttpOnly session cookie or session store. Never put them in localStorage.
3. Per request, use the user's access token for hop 2. In `server/auth.ts` this is an
   `OAuthAuth` (or `CallableAuth` that refreshes) built from the session token instead of the
   PAT. The SDK already supports it: `new CortexAgentClient({ account, auth: new OAuthAuth(token) })`.
   SQL API calls send `Authorization: Bearer <token>` with
   `X-Snowflake-Authorization-Token-Type: OAUTH`.
4. Users sign in to Snowflake on the consent screen (or SSO if configured), and every
   query runs as them with their default or requested role (`scope=session:role:<ROLE>`).

### Pattern C: External OAuth with your IdP

1. Register the app in your IdP (Okta, Entra ID, ...) and configure an authorization
   server that issues access tokens with an audience for Snowflake.
2. Create the matching integration:
   ```sql
   CREATE SECURITY INTEGRATION ACME_ASSIST_EXT_OAUTH
     TYPE = EXTERNAL_OAUTH
     EXTERNAL_OAUTH_TYPE = OKTA            -- or AZURE, PING_FEDERATE, CUSTOM
     EXTERNAL_OAUTH_ISSUER = 'https://acme.okta.com/oauth2/<server-id>'
     EXTERNAL_OAUTH_JWS_KEYS_URL = 'https://acme.okta.com/oauth2/<server-id>/v1/keys'
     EXTERNAL_OAUTH_AUDIENCE_LIST = ('https://<account>.snowflakecomputing.com')
     EXTERNAL_OAUTH_TOKEN_USER_MAPPING_CLAIM = 'sub'
     EXTERNAL_OAUTH_SNOWFLAKE_USER_MAPPING_ATTRIBUTE = 'LOGIN_NAME'
     ENABLED = TRUE;
   ```
3. The app signs users in with the IdP (one sign-in for your portal), receives the IdP
   access token and passes it as the OAuth token for hop 2, exactly as in Pattern B.
4. Snowflake maps the token's claim to a Snowflake user, so RBAC is per user.
   Provision users with SCIM so the mapping stays in sync.

Validate the exact parameters for B and C against the Snowflake docs for
[Snowflake OAuth](https://docs.snowflake.com/en/user-guide/oauth-custom) and
[External OAuth](https://docs.snowflake.com/en/user-guide/oauth-ext-overview) before
rollout. The SQL here is a starting template, not run against this account.

## 5. Checklist for a self-hosted, custom-domain deployment

- [ ] DNS `assist.acme.com` → your load balancer; TLS certificate from your CA.
- [ ] Choose pattern A, B or C, then create the user or security integration.
- [ ] Store secrets (private key, OAuth client secret) in a secret manager, not in the image.
- [ ] Session cookie: `Secure`, `HttpOnly`, `SameSite=Lax`; refresh tokens server-side only.
- [ ] Network policy on the Snowflake user(s) allowing only your egress IPs.
- [ ] Keep the security headers from `server/security.ts` (CSP, frame-ancestors) and
      restrict `FRAME_ORIGINS` if you embed the app in your portal.
- [ ] Use a single instance, or set `RUN_STORE=snowflake` so background runs resume across
      instances.
- [ ] Grant the role(s) used by the app only what `lab/setup.sql` grants `ACME_DEMO_ROLE`.
- [ ] Test with a low-privilege user: they should only see what their role allows.

## 6. Which to choose

- Data stays in Snowflake, no infra, Snowflake URL is fine → **App Runtime** (as deployed).
- Must be on your domain, everyone sees the same data → **self-host + Pattern A**.
- Must be on your domain with per-user governance → **self-host + Pattern B**, or
  **Pattern C** if your IdP is the source of truth for sign-in.
