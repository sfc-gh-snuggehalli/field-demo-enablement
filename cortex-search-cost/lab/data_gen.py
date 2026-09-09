"""
Cortex Search: BYO Embeddings & Cost Optimization — Synthetic data generator

Loads the DOCUMENT_CHUNKS table (~5,000 rows) with paragraph-length text and
pre-computed 768-dim embeddings (via EMBED_TEXT_768 inside Snowflake, simulating
an external embedding pipeline).

Run order:
  1. lab/setup.sql            (database, schema, warehouse, DOCUMENTS + DOCUMENT_CHUNKS)
  2. lab/cortex-search-cost-lab.ipynb  (the hands-on lab)

NOTE: setup.sql already generates DOCUMENT_CHUNKS with embeddings entirely in SQL.
This script is an optional Python equivalent if you prefer the pandas +
write_pandas path. Run it in a Snowflake notebook cell (where
get_active_session() works) -- the local Python connector cannot drive
oauth_authorization_code without a client_id.

Read/write to Snowflake — two supported modes:
  * Inside a Snowflake Notebook / Worksheet: get_active_session() returns the
    live session. No credentials needed.
  * Locally (CLI): a named connection from ~/.snowflake/connections.toml is used
    via Session.builder.config("connection_name", ...). Set the name below or
    pass --connection.

Writing DataFrames: session.write_pandas(df, table, auto_create_table=True,
overwrite=True) creates/replaces the table and bulk-loads the rows. This is the
recommended path for pandas -> Snowflake.
"""

import argparse
import random

import pandas as pd

DB_NAME = "CORTEX_SEARCH_COST_DEMO"
SCHEMA_NAME = "DEMO"
WH_NAME = "CORTEX_SEARCH_COST_WH"
DEFAULT_CONNECTION = "default"  # a name in ~/.snowflake/connections.toml

RANDOM_SEED = 42
NUM_DOCS = 500
CHUNKS_PER_DOC = 10  # ~5,000 total chunks


def get_session(connection_name: str):
    """Return an active Snowpark session (notebook first, else named connection)."""
    try:
        from snowflake.snowpark.context import get_active_session

        return get_active_session()
    except Exception:
        from snowflake.snowpark import Session

        return Session.builder.config("connection_name", connection_name).create()


# ---------------------------------------------------------------------------
# CHUNK TEXT TEMPLATES
# ---------------------------------------------------------------------------
# Diverse topics so keyword and semantic search return interesting results.

DOC_TYPES = [
    "policy_guide", "faq", "procedure", "product_spec",
    "compliance", "onboarding", "release_notes", "architecture",
]

CATEGORIES = [
    "Engineering", "Legal", "HR", "Product",
    "Security", "Finance", "Operations", "Support",
]

CHUNK_TEMPLATES = [
    "This section covers the {topic} requirements for the {dept} team. All employees must complete the mandatory training within 30 days of enrollment. Failure to comply may result in restricted system access until the requirement is fulfilled.",
    "The {dept} department has updated its {topic} guidelines effective this quarter. Key changes include enhanced approval workflows, revised escalation paths, and new documentation standards for audit readiness.",
    "When handling {topic} requests, follow the standard operating procedure: verify the requester's identity, check authorization level, log the request in the tracking system, and route to the appropriate reviewer.",
    "Frequently asked question: How do I request access to {topic} resources? Submit a request through the internal portal, select the {dept} category, and provide your manager's approval code. Typical turnaround is 2-3 business days.",
    "The latest release introduces improvements to {topic} functionality. Performance benchmarks show a 40% reduction in processing time for batch operations. See the migration guide for breaking changes.",
    "Architecture overview: the {topic} subsystem uses a three-tier design pattern. The presentation layer communicates with the {dept} API gateway, which routes to backend microservices. All inter-service communication is encrypted.",
    "Compliance requirement: all {topic} data must be encrypted at rest and in transit. The {dept} team is responsible for rotating encryption keys quarterly and maintaining an audit trail of all key management operations.",
    "Onboarding checklist for {topic} access: (1) Complete security awareness training, (2) Set up multi-factor authentication, (3) Request role-based access from {dept} admin, (4) Review the acceptable use policy.",
    "Troubleshooting guide for {topic} integration issues: check the service health dashboard, verify API credentials have not expired, confirm the endpoint URL matches the environment, and review recent deployment logs.",
    "Best practices for {topic} data management in the {dept} domain: partition large datasets by date, implement retention policies aligned with regulatory requirements, and schedule regular data quality checks.",
    "The {topic} incident response playbook outlines steps for the {dept} team: identify the scope of impact, activate the response team, contain the issue, communicate status updates, and conduct a post-incident review.",
    "Product specification for the {topic} module: supports up to 10,000 concurrent users, provides sub-second query latency for indexed data, and integrates natively with the {dept} workflow automation platform.",
    "Security advisory: a vulnerability was identified in the {topic} authentication component. The {dept} security team has deployed a patch. All users should update to the latest version and reset their session tokens.",
    "The {dept} team's quarterly review of {topic} performance metrics shows steady improvement: error rates decreased by 15%, average response time improved by 22%, and customer satisfaction scores increased by 8 points.",
    "Data governance policy for {topic}: all personally identifiable information must be masked in non-production environments. The {dept} data steward is responsible for classifying columns and applying masking policies.",
]

TOPICS = [
    "data access", "API authentication", "infrastructure scaling",
    "audit logging", "vendor management", "cost allocation",
    "disaster recovery", "user provisioning", "network security",
    "CI/CD pipeline", "monitoring and alerting", "database migration",
    "document retention", "incident management", "performance tuning",
]


def build_frames() -> dict[str, pd.DataFrame]:
    random.seed(RANDOM_SEED)

    rows = []
    for doc_idx in range(NUM_DOCS):
        doc_id = f"DOC_{doc_idx:05d}"
        doc_type = DOC_TYPES[doc_idx % len(DOC_TYPES)]
        category = CATEGORIES[doc_idx % len(CATEGORIES)]
        file_name = f"docs/{category.lower()}/{doc_id}.pdf"

        for chunk_idx in range(CHUNKS_PER_DOC):
            chunk_id = f"{doc_id}_CHUNK_{chunk_idx:02d}"
            template = random.choice(CHUNK_TEMPLATES)
            topic = random.choice(TOPICS)
            dept = category

            chunk_text = template.format(topic=topic, dept=dept)
            page_number = chunk_idx + 1

            rows.append({
                "CHUNK_ID": chunk_id,
                "DOC_ID": doc_id,
                "CHUNK_TEXT": chunk_text,
                "DOC_TYPE": doc_type,
                "CATEGORY": category,
                "FILE_NAME": file_name,
                "PAGE_NUMBER": page_number,
            })

    return {"DOCUMENT_CHUNKS": pd.DataFrame(rows)}


def add_embeddings(session) -> None:
    """Add a 768-dim VECTOR column using EMBED_TEXT_768 (batch UPDATE)."""
    print("Adding EMBEDDING column via EMBED_TEXT_768 (this may take a few minutes)...")

    session.sql("""
        ALTER TABLE DOCUMENT_CHUNKS ADD COLUMN IF NOT EXISTS
            EMBEDDING VECTOR(FLOAT, 768)
    """).collect()

    session.sql("""
        UPDATE DOCUMENT_CHUNKS
        SET EMBEDDING = SNOWFLAKE.CORTEX.EMBED_TEXT_768(
            'snowflake-arctic-embed-m-v1.5', CHUNK_TEXT
        )
        WHERE EMBEDDING IS NULL
    """).collect()

    row_count = session.sql(
        "SELECT COUNT(*) AS CNT FROM DOCUMENT_CHUNKS WHERE EMBEDDING IS NOT NULL"
    ).collect()[0]["CNT"]
    print(f"Embeddings computed for {row_count} rows.")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Load synthetic data for Cortex Search Cost Demo"
    )
    parser.add_argument(
        "--connection", default=DEFAULT_CONNECTION,
        help="Named connection in ~/.snowflake/connections.toml",
    )
    args = parser.parse_args()

    session = get_session(args.connection)
    session.sql(f"USE DATABASE {DB_NAME}").collect()
    session.sql(f"USE SCHEMA {SCHEMA_NAME}").collect()
    session.sql(f"USE WAREHOUSE {WH_NAME}").collect()

    frames = build_frames()
    if not frames:
        print("build_frames() returned nothing.")
        return

    for table_name, df in frames.items():
        session.write_pandas(
            df, table_name, auto_create_table=True, overwrite=True,
            quote_identifiers=False,
        )
        print(f"Loaded {len(df):>6} rows -> {DB_NAME}.{SCHEMA_NAME}.{table_name}")

    add_embeddings(session)

    print("\nDone. Open the lab notebook next.")


if __name__ == "__main__":
    main()
