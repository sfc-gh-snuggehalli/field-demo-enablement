# Speaker Notes: Multi-Agent Orchestration over MCP: One Governed Front Door for Any AI Client

## Account Context Summary

Scenario: Northwind, a B2B software company, wants every AI client its people use (Claude Desktop,
ChatGPT, Cursor, an in-house assistant) to answer from governed sales and support data. Sales and
support have different owners and different rules: a global sales exec sees every theater, an EMEA
seller sees EMEA only, and a support rep sees no sales numbers at all. The demo shows one
Snowflake-managed MCP server in front of a multi-agent stack where grants, not prompts, decide each
person's answer, and compares the hub-and-spoke design with an agent toolset.

Lab run order: `./demo.sh setup` (governed stack, persona keys, host-model PAT) then
`./demo.sh build --yes` (MCP servers, toolset agent, persona checks over MCP, evaluations), then
`./demo.sh app` for the live client.

---

## Slide 1: Hero

**Talking Points:**
- One MCP tool, one front door, for any AI client and any person.
- Three personas ask the same question and get three different answers, and none of the refusals come from a prompt.
- Two architectures sit behind the same tool name, so we can compare them like for like.

**Presenter Notes:**
- Open the app (`./demo.sh app`) before you start, so the sidebar already shows "Connected: 1 tool(s) via tools/list".
- The numbers on the stat cards are this demo's, not product limits.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp

---

## Slide 2: Every AI client wants your governed data

**Talking Points:**
- Each AI client wants its own connector, credentials and copy of the business rules.
- Rules written into a system prompt are suggestions; a different client or a clever question walks around them.
- Domains like sales and support have different owners, models and instructions; one giant agent flattens that.
- If the logic lives in every client, nobody has one audit trail of who asked what and what data answered it.

**Presenter Notes:**
- Ask the room which AI clients their people already use. The answer is usually "several", which is the point.
- Keep this slide short; the architecture slide is where the answer starts.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents

---

## Slide 3: Architecture

**Talking Points:**
- Any MCP client connects to one Snowflake-managed MCP server, `ORCHESTRATOR_MCP`, which exposes one tool of type `CORTEX_AGENT_RUN`.
- That tool runs `ORCHESTRATOR_AGENT`, which delegates to a sales or support specialist through caller's-rights bridge procedures.
- Each specialist answers from its own semantic view; the sales table carries a fail-closed row access policy.
- The MCP session runs as the signed-in user's default role, and every hop below it runs as that caller.

**Presenter Notes:**
- The persona users are service users whose `DEFAULT_ROLE` is the persona role. Agent runs authorize against the default role, so that setting is load-bearing.
- `DEFAULT_SECONDARY_ROLES = ()` keeps each session to one role, so the row access policy sees exactly one.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp
- https://docs.snowflake.com/en/sql-reference/sql/create-mcp-server

---

## Slide 4: Two identities, exactly as with Claude

**Talking Points:**
- The app plays Claude Desktop. A Claude model on Cortex's Anthropic-compatible Messages endpoint decides when to call a tool; it only sees what `tools/list` returns.
- That model call uses a PAT on the presenter's user. It plays the LLM vendor and never reads governed data.
- The tool call is a JSON-RPC `tools/call` signed in as the persona user with a key-pair JWT. That is the identity Snowflake governs.
- On the Snowflake side this is the same traffic Claude, ChatGPT or Cursor send; the server cannot tell them apart.

**Presenter Notes:**
- Claude Desktop would sign the person in with OAuth instead of a key pair; the server-side behavior is the same.
- Key-pair JWT on the MCP endpoint works with `X-Snowflake-Authorization-Token-Type: KEYPAIR_JWT`, though the MCP docs only name OAuth and PAT. It was tested while building this demo.
- A PAT on a person user only authenticates from a network the account's network policy allows. If the app's model call fails with 401, check the network first.
- `tools/call` returns `text/event-stream` (one `data:` event with the result); `tools/list` returns plain JSON.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp
- https://docs.snowflake.com/en/user-guide/programmatic-access-tokens
- https://docs.snowflake.com/en/user-guide/key-pair-auth

---

## Slide 5: The boundary is four layers of grants

**Talking Points:**
- Layer 1: everyone has USAGE on the orchestrator and both bridges, so everyone may ask. The bridges carry no authority of their own.
- Layer 2: the bridge's nested `DATA_AGENT_RUN` runs as the caller, so a persona without USAGE on a specialist gets error 399513, relayed as `NOT_ENTITLED`.
- Layer 3: the specialist's Cortex Analyst SQL runs as the caller, so SELECT on the semantic view and its base table must be granted too.
- Layer 4: the row access policy filters sales rows by the caller's role and returns nothing for a role with no entitlement.

**Presenter Notes:**
- `EXECUTE AS CALLER` on the bridges is the whole security property. Under `EXECUTE AS OWNER` every caller would get the owner's answer.
- The user's question goes to `DATA_AGENT_RUN` as a bind parameter inside a JSON body; nothing is concatenated into SQL.
- To audit who can reach which agent and tool, use the check-agent-access skill in Cortex Code.

**References:**
- https://docs.snowflake.com/en/user-guide/security-row-intro
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-manage

---

## Slide 6: One front door: a Snowflake-managed MCP server

**Talking Points:**
- The server has exactly one tool, `northwind_assistant`, on `ORCHESTRATOR_AGENT`. There is no `SYSTEM_EXECUTE_SQL` tool.
- Every persona's `tools/list` returns the same single tool; the client never learns there are specialists behind it.
- USAGE on the server allows `tools/list`; `tools/call` also needs USAGE on the agent and everything behind it.

**Presenter Notes:**
- There is no ALTER for an MCP server's specification, and `CREATE OR REPLACE` drops every grant on the server. The notebook re-applies the grants right after creating it.
- The tool's input schema is `text` (required) plus optional `thread_id` and `parent_message_id`. The result is one text block holding the agent's whole response as JSON.

**References:**
- https://docs.snowflake.com/en/sql-reference/sql/create-mcp-server
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp

---

## Slide 7: Same server, same tool, same question

**Talking Points:**
- Ask "What were total new bookings in FY25-Q4 by theater?" as each persona.
- The global sales exec gets Americas $59.6M, EMEA $38.4M, APAC $22.1M, total $120.0M.
- The EMEA seller gets EMEA $38.4M only, because the row access policy filtered the rows.
- The support rep gets "not available at your access level": the bridge returned `NOT_ENTITLED` because the support role has no USAGE on the sales specialist.

**Presenter Notes:**
- In the app, open the tool-call expander: it shows the arguments the model wrote, the JSON-RPC request, and under "Inside Snowflake" the orchestrator's delegation.
- The support persona sometimes calls `ask_sales` twice (both `NOT_ENTITLED`) before refusing, even though the instructions say not to retry. The boundary held both times.
- Lab notebook Section 4 runs exactly this comparison on both servers and prints a CHECK.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-monitor

---

## Slide 8: The alternative: agent toolsets

**Talking Points:**
- An agent toolset lets one agent reference others by name and inherit their tools at run time.
- `TOOLSET_AGENT` references the sales and support specialists, so its orchestrator sees `sales_analyst` and `support_kb` directly. One run, one context, one budget.
- `TOOLSET_MCP` exposes it under the same tool name, so a client switches architecture by changing the server URL.

**Presenter Notes:**
- USAGE on a referenced agent is checked as the caller. Without it, the reference is skipped silently: no error, no annotation. That is why the refusal wording lives in `TOOLSET_AGENT`'s instructions.
- No partial inheritance: if a referenced agent can't be resolved, all of its tools are dropped.
- The documented limits are 25 referenced agents per run and depth 5 (`CORTEX_AGENT_TOOLSET_MAX_AGENTS`, `CORTEX_AGENT_TOOLSET_MAX_DEPTH`). Cycles fail the run.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-toolsets

---

## Slide 9: Hub and spoke vs agent toolset, measured

**Talking Points:**
- The toolset runs one agent per question; the hub runs two, or three for cross-domain questions.
- For "as a chart", the toolset returned a native chart in about 22 seconds; the hub re-drew one from the relayed table in about 60.
- The hub's denial is explicit and visible in the trace; the toolset's is silent.
- On five questions, the toolset scored higher on answer correctness and logical consistency.

**Presenter Notes:**
- Say clearly that the scores come from one run of five questions over two tools. They are directional. A fair test grows the tool count until selection accuracy drops.
- Evaluations run as the admin role and don't impersonate personas, so they score routing and answers, not the access boundary. Evaluations also don't support MCP servers as tools or agents that depend on session attributes.
- Lab notebook Section 5 re-runs both evaluations on the audience's account (several minutes; `--skip-evals` skips them).

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations
- https://docs.snowflake.com/en/sql-reference/functions/execute_ai_evaluation

---

## Slide 10: Claims, checked

**Talking Points:**
- "A toolset is fine up to 20-30 tools" is a rule of thumb, not documentation. The documented limit counts agents, not tools; selection accuracy in one context is the real ceiling.
- Toolsets do give native charts, and faster.
- A toolset replaces hub-and-spoke orchestration but keeps the access boundary: USAGE on referenced agents and the row access policy still apply.
- Key-pair JWT works on the MCP endpoint.

**Presenter Notes:**
- As the EMEA seller, the toolset agent's chart covers EMEA only and may say the other theaters are "missing". An agent can't tell rows a policy hid from rows that don't exist; use this as a teaching moment about fail-closed policies.
- Whether Claude Desktop renders the Vega-Lite chart that arrives inside the tool's JSON was not verified. This app draws it with `st.vega_lite_chart`; Snowsight and CoWork render it natively.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-toolsets
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp

---

## Slide 11: When to use which

**Talking Points:**
- Choose hub and spoke when domains need their own instructions, model, budget or owning team, when the tool count would crowd one context, or when you need an explicit, auditable denial.
- Choose an agent toolset when one agent can hold all the tools and still pick well, and you want native charts, lower latency and one run per question.
- Either way the MCP front door and the grants underneath are identical.

**Presenter Notes:**
- Risks to name: the hub has bridge code to maintain and loses context between hops; the toolset hides a missing grant and puts every tool description in one context.
- Observability: the hub gives one trace per agent with the delegation visible; the toolset gives one trace, and a skipped toolset leaves none.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-toolsets
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-monitor

---

## Slide 12: Next Steps

**Talking Points:**
- Run the lab: `./demo.sh setup`, then `./demo.sh build --yes`, and read the CHECK lines.
- Drive it like Claude with `./demo.sh app`: switch personas, open the inspector, compare personas or architectures.
- Point Claude Desktop, ChatGPT or Cursor at the same MCP URL with OAuth: the governance does not move.
- Pick two of your own data domains with different owners and decide hub or toolset with an evaluation.

**Presenter Notes:**
- Where to look in Snowsight: **AI & ML > Agents > ORCHESTRATOR_AGENT > Monitoring** shows each run attributed to the persona user.
- Teardown with `./demo.sh teardown --yes`: it drops the database, warehouse, persona users and roles, removes the host-model PAT, and deletes the local key and PAT files.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations
