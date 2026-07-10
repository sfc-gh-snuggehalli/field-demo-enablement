"""
AI Functions: Customer Experience Telemetry — Synthetic data generator

Loads the UNSTRUCTURED text tables this demo runs AI Functions against:
  CHAT_THREADS      multi-turn customer <-> GPT-assistant conversations
  CALL_TRANSCRIPTS  text stand-ins for support call recordings
  SUPPORT_TICKETS   free-text tickets

Structured data (CUSTOMERS) is created by lab/setup.sql. Run order:
  1. lab/setup.sql
  2. python lab/data_gen.py          (this script)
  3. lab/cx-ai-functions-lab.ipynb

Read/write to Snowflake:
  * In a Snowflake Notebook/Worksheet, get_active_session() returns the live session.
  * Locally, a named connection from ~/.snowflake/connections.toml is used.
Text is authored with deliberate sentiment + topic variety so AI_SENTIMENT,
AI_CLASSIFY, AI_AGG, and AI_FILTER return interesting, non-uniform results.
"""

import argparse
import random

import pandas as pd

DB_NAME = "FIELD_CX_DEMO"
SCHEMA_NAME = "AI_FUNCTIONS"
WH_NAME = "CX_AI_FUNCTIONS_WH"
DEFAULT_CONNECTION = "sfsenorthamerica-snuggehalli_aws1"  # a name in ~/.snowflake/config.toml

RANDOM_SEED = 42
N_CUSTOMERS = 500

# Topic taxonomy for a home-valuation (proptech) product. Each entry carries
# templated snippets by sentiment so generated text is realistic and varied.
TOPICS = {
    "valuation_accuracy": {
        "positive": "The home value estimate was spot on — matched my recent appraisal within a couple percent.",
        "negative": "Your valuation is way off. It says my house is worth 80k less than three appraisers told me.",
        "neutral": "How often does the estimated home value get refreshed after I update the square footage?",
    },
    "pricing_billing": {
        "positive": "Upgrading to Pro was worth it, the comps report alone pays for the subscription.",
        "negative": "I was charged twice this month and the Pro plan price jumped without any notice.",
        "neutral": "Can you explain the difference between the Starter and Pro plans for billing?",
    },
    "onboarding": {
        "positive": "Setup was painless, I connected my listings and had a dashboard in ten minutes.",
        "negative": "I've been stuck on the onboarding step for an hour, the address import keeps failing.",
        "neutral": "Where do I find the guide for importing my B2B partner property portfolio?",
    },
    "bug_report": {
        "positive": "Thanks for the quick fix — the map view loads correctly now.",
        "negative": "The valuation chart is completely broken, it throws an error every time I open it.",
        "neutral": "Is the mobile app supposed to show the same comps as the web version?",
    },
    "cancellation": {
        "positive": "I was going to cancel but the new market-trends feature convinced me to stay.",
        "negative": "I want to cancel immediately and get a refund, this product is not working for me.",
        "neutral": "If I cancel mid-cycle, do I keep access until the end of the billing period?",
    },
    "feature_request": {
        "positive": "Love the product — it would be perfect if you added rental yield estimates too.",
        "negative": "Every competitor has API access and you still don't. This is a dealbreaker for our team.",
        "neutral": "Are there plans to support commercial property valuations for B2B accounts?",
    },
}
SENTIMENTS = ["positive", "negative", "neutral"]
# Weight toward more negatives/mixed so at-risk detection has signal.
SENTIMENT_WEIGHTS = [0.4, 0.4, 0.2]
CHANNELS = ["web_chat", "in_app", "mobile"]
AGENTS = [f"agent_{i:02d}" for i in range(1, 11)]


def _pick_topic_sentiment():
    topic = random.choice(list(TOPICS.keys()))
    sentiment = random.choices(SENTIMENTS, weights=SENTIMENT_WEIGHTS, k=1)[0]
    return topic, sentiment


def build_chat_threads(n: int) -> pd.DataFrame:
    rows = []
    for i in range(1, n + 1):
        topic, sentiment = _pick_topic_sentiment()
        snippet = TOPICS[topic][sentiment]
        transcript = (
            "Customer: Hi, I need help with my account.\n"
            f"Assistant: Happy to help — what's going on?\n"
            f"Customer: {snippet}\n"
            "Assistant: Thanks for the detail, let me look into that for you.\n"
            f"Customer: {'Appreciate it.' if sentiment == 'positive' else 'Please hurry, this is frustrating.' if sentiment == 'negative' else 'Okay, thanks.'}"
        )
        rows.append({
            "THREAD_ID": i,
            "CUSTOMER_ID": random.randint(1, N_CUSTOMERS),
            "CHANNEL": random.choice(CHANNELS),
            "CREATED_AT": pd.Timestamp("2026-01-01") + pd.Timedelta(minutes=random.randint(0, 180 * 24 * 60)),
            "TRANSCRIPT": transcript,
        })
    return pd.DataFrame(rows)


def build_call_transcripts(n: int) -> pd.DataFrame:
    rows = []
    for i in range(1, n + 1):
        topic, sentiment = _pick_topic_sentiment()
        snippet = TOPICS[topic][sentiment]
        transcript = (
            f"Agent: Thank you for calling home valuation support, this is {random.choice(AGENTS)}.\n"
            f"Caller: {snippet}\n"
            "Agent: I understand. Let me pull up your account and take a look.\n"
            f"Caller: {'Great, thank you so much.' if sentiment == 'positive' else 'I have called about this three times now.' if sentiment == 'negative' else 'Sure, take your time.'}"
        )
        rows.append({
            "CALL_ID": i,
            "CUSTOMER_ID": random.randint(1, N_CUSTOMERS),
            "AGENT_ID": random.choice(AGENTS),
            "CALL_DATE": (pd.Timestamp("2026-01-01") + pd.Timedelta(days=random.randint(0, 180))).date(),
            "TRANSCRIPT": transcript,
        })
    return pd.DataFrame(rows)


def build_support_tickets(n: int) -> pd.DataFrame:
    subjects = {
        "valuation_accuracy": "Estimated value looks wrong",
        "pricing_billing": "Billing question",
        "onboarding": "Trouble getting started",
        "bug_report": "Something is broken",
        "cancellation": "Cancellation request",
        "feature_request": "Feature suggestion",
    }
    rows = []
    for i in range(1, n + 1):
        topic, sentiment = _pick_topic_sentiment()
        rows.append({
            "TICKET_ID": i,
            "CUSTOMER_ID": random.randint(1, N_CUSTOMERS),
            "CREATED_AT": pd.Timestamp("2026-01-01") + pd.Timedelta(hours=random.randint(0, 180 * 24)),
            "SUBJECT": subjects[topic],
            "BODY": TOPICS[topic][sentiment],
        })
    return pd.DataFrame(rows)


def build_frames() -> dict[str, pd.DataFrame]:
    random.seed(RANDOM_SEED)
    return {
        "CHAT_THREADS": build_chat_threads(1200),
        "CALL_TRANSCRIPTS": build_call_transcripts(400),
        "SUPPORT_TICKETS": build_support_tickets(600),
    }


def get_session(connection_name: str):
    try:
        from snowflake.snowpark.context import get_active_session

        return get_active_session()
    except Exception:
        from snowflake.snowpark import Session

        return Session.builder.config("connection_name", connection_name).create()


def main() -> None:
    parser = argparse.ArgumentParser(description="Load synthetic CX text tables")
    parser.add_argument("--connection", default=DEFAULT_CONNECTION,
                        help="Named connection in ~/.snowflake/connections.toml")
    args = parser.parse_args()

    session = get_session(args.connection)
    session.sql(f"USE DATABASE {DB_NAME}").collect()
    session.sql(f"USE SCHEMA {SCHEMA_NAME}").collect()
    session.sql(f"USE WAREHOUSE {WH_NAME}").collect()

    for table_name, df in build_frames().items():
        session.write_pandas(
            df, table_name, auto_create_table=True, overwrite=True, quote_identifiers=False,
        )
        print(f"Loaded {len(df):>6} rows -> {DB_NAME}.{SCHEMA_NAME}.{table_name}")

    print("Done. Open cx-ai-functions-lab.ipynb next.")


if __name__ == "__main__":
    main()
