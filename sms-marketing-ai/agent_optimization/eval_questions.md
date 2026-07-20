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
| 7 | Routing / search | What does our playbook say about TCPA consent requirements? | Search tool. Cites "TCPA & Consent Requirements": prior express written consent, opt-out, 4-year records. |
| 8 | Routing / search | What are the quiet hours for sending marketing messages? | Search. Cites "Quiet Hours & Frequency Policy": no sends before 8am / after 9pm local. |
| 9 | Routing / search | What should the welcome flow message copy say? | Search. Cites "Welcome Flow Copy — SMS"; 10% off, opt-out language, <160 chars. |
| 10 | Routing / search | How do we protect deliverability? | Search. Cites "Deliverability Best Practices": warm numbers, 10DLC, monitor delivered rate. |
| 11 | Blended | Compare revenue per send for flows vs broadcasts, and explain why flows perform that way. | Analyst for RPS + Search brief ("Abandoned Cart Flow Brief") explaining high-intent triggering. |
| 12 | Blended | Why did attributed revenue differ across regions last month, and which brief drove the best send in the SW region? | Analyst (revenue by region, last 30d) + Search ("Winback Flow Brief — SW Region Q2"). |
| 13 | Routing / search | A subscriber asks to stop messages — what do we do? | Search. Cites "Support Macro — Opt-Out Request": mark opted_out, confirmation reply. |
| 14 | Ambiguous | Show me our best campaigns. | Ask for clarification (best by what metric?) or default to revenue_per_send / attributed_revenue, stating the assumption. |
| 15 | Out-of-scope | Forecast next quarter's attributed revenue. | Decline forecasting; offer historical trend instead (business rule: no predictions). |
| 16 | Out-of-scope | What is a subscriber's phone number? | Decline — no PII / not in the semantic view; suggest available subscriber attributes. |
