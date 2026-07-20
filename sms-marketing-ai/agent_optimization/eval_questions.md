# Evaluation Questions — SMS_MARKETING_AGENT

16 questions for the /agent-optimization loop. ~25% test tool routing (analyst vs search). Load into
a Snowflake table with `question` and `expected_answer` columns, then run `run_evaluation.py` against
both `SMS_MARKETING_AGENT_BASELINE` and `SMS_MARKETING_AGENT` and compare.

| # | Category | Question | Expected answer / expected tool |
|---|----------|----------|----------------------------------|
| 1 | Core / analyst | What is attributed revenue by campaign type? | Analyst tool. Flow > broadcast; ~$1.25M flow vs ~$0.72M broadcast (values vary by seed). |
| 2 | Core / analyst | How does revenue per send compare for flows versus broadcasts? | Analyst. Flow RPS ~$59 vs broadcast ~$15; flows much higher. |
| 3 | Core / analyst | Which region has the fastest opt-in growth? | Analyst, opt_in_growth by region, sorted desc; names the top region. |
| 4 | Core / analyst | What is the consent rate and list churn rate by region? | Analyst, consent_rate + list_churn_rate by region (~0.81-0.84 consent, ~0.09-0.12 churn). |
| 5 | Core / analyst | What is the click-through rate by campaign theme? | Analyst, ctr by theme; flow themes (Welcome/Cart/Winback) higher than broadcast themes. |
| 6 | Core / analyst | What is subscriber LTV by region? | Analyst, subscriber_ltv by region (~$160-$167). |
| 7 | Routing / search | What does our playbook say about TCPA consent requirements? | Search tool. Cites "Tcpa Consent Compliance Guidelines": prior express written consent, opt-out, record retention. |
| 8 | Routing / search | What are the quiet hours for sending marketing messages? | Search. Cites "Tcpa Consent Compliance Guidelines": no sends before 8am / after 9pm local. |
| 9 | Routing / search | What should the welcome flow message copy say? | Search. Cites "Sms Mms Copy Library Approved Templates"; welcome copy, opt-out language, character limits. |
| 10 | Routing / search | How do we protect deliverability? | Search. Cites "Deliverability Carrier Best Practices": warm numbers, 10DLC, monitor delivered rate. |
| 11 | Blended | Compare revenue per send for flows vs broadcasts, and explain why flows perform that way. | Analyst for RPS + Search ("Quarterly Performance Review Q3 2025" / "Attribution Methodology Whitepaper") explaining high-intent triggering. |
| 12 | Blended | Attributed revenue for the Q3 flash sale came in below plan — what caused the PNW throughput issue, and which brief covered that send? | Analyst (attributed revenue) + Search ("Incident Postmortem Pnw Flash Sale Throughput" + "Campaign Brief Q3 Trailhead Flash Sale"). |
| 13 | Routing / search | A brand's opt-in rate is low — what does support recommend? | Search. Cites "Support Macros Help Center Common Questions": healthy embedded-form vs checkout opt-in benchmarks, compare like-for-like traffic. |
| 14 | Ambiguous | Show me our best campaigns. | Ask for clarification (best by what metric?) or default to revenue_per_send / attributed_revenue, stating the assumption. |
| 15 | Out-of-scope | Forecast next quarter's attributed revenue. | Decline forecasting; offer historical trend instead (business rule: no predictions). |
| 16 | Out-of-scope | What is a subscriber's phone number? | Decline — no PII / not in the semantic view; suggest available subscriber attributes. |
