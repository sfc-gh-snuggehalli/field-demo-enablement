# Optimization Log

## Agent details
- Fully qualified agent name: DONOR_CHURN_ML_DEMO.MODELS.DONOR_RETENTION_AGENT
- Clone FQN (if production): N/A — demo agent, optimized in place
- Purpose / domain: Nonprofit donor retention — retrieve donor metrics via Cortex Analyst and
  score/explain at-risk donors with the deployed lapse model.
- Current status: demo

## Tools
- Donor_Metrics — cortex_analyst_text_to_sql over DONOR_CHURN_ML_DEMO.ANALYTICS.DONOR_CHURN_SV
  (metrics: donor_count, total_giving, avg_gift, gift_count, engagement_count, lapsed_donors,
  lapse_rate; dims: region, donor_segment, channel, appeal_type, event_type, month grains).
- Score_Donor_Churn — generic, backed by MODELS.TOP_CHURN_RISK(SEGMENT STRING, N NUMBER)
  RETURNS TABLE(donor_id, region, churn_probability, risk_drivers, recommended_action).
  Binding of the generic tool to the function is completed in Snowsight (AI & ML -> Agents ->
  Custom tools); grant USAGE on the function to the agent's role.

## Agent versions
- baseline: original spec captured from live agent (versions/baseline/agent_spec.json)
- optimized (2026-07-14): rewritten spec (versions/optimized/agent_spec.yaml) — deployed live.

## Optimization details
### Entry: 2026-07-14
- Version: optimized
- Goal: production-quality tool descriptions + instructions per agent best practices.
- Changes made:
  1. Donor_Metrics description: one-liner -> full spec (metrics, dimensions with valid values,
     when to use / when NOT to use, NL query tips + examples). Clarifies lapse_rate is a
     historical aggregate, not a model prediction.
  2. Score_Donor_Churn description: documented the previously-hidden parameters (segment enum
     Major/Mid/Grassroots, n = top-N), return columns, and the key constraint that it filters by
     SEGMENT ONLY (no region). Added when-to-use / when-NOT.
  3. Orchestration: added Role, Domain context (lapse def, segment/region enums, model drivers,
     lapse_rate vs churn_probability), Tool selection rules, the segment-vs-region constraint,
     an explicit flagship multi-step workflow, and Boundaries.
  4. Response: percentages for probabilities/rates, currency symbols, table format for ranked
     donors, distinguish predicted probability vs historical lapse rate.
  5. Sample questions: 2 -> 4, showcasing both tools and routing (region-filtered scoring,
     lapse_rate aggregate, top-N scoring, cross-segment giving comparison).
- Rationale: tool descriptions are the single most impactful factor for tool-selection accuracy;
  the biggest real risk here was the agent mis-driving Score_Donor_Churn (region param that does
  not exist) and conflating lapse_rate with model churn_probability.
- Deploy: CREATE OR REPLACE AGENT (verified: spec parses; DESCRIBE AGENT confirms new instructions
  and tool descriptions). Notebook cell (donor-churn-03-serve-agent.ipynb, Section 12) synced.
- Note: CREATE OR REPLACE re-owned the agent from ACCOUNTADMIN to SYSADMIN (this session's role).
- Not run: no automated eval harness — the generic Score_Donor_Churn tool binding is completed in
  Snowsight, so the scoring path isn't fully exercisable headless. Validate live in Snowsight chat.
- Next steps: (optional) build a 15-20 question eval set and run baseline vs optimized once the
  custom tool is bound; add region as a filter to TOP_CHURN_RISK if region-scoped scoring is common.
