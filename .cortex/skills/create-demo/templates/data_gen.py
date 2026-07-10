"""
{{DECK_TITLE}} — Synthetic data generator (hybrid pattern)

Loads the UNSTRUCTURED tables for this demo into Snowflake. Structured tables
(customers, billing, engagement, etc.) are created with SQL GENERATOR in
lab/setup.sql; this script produces the free-text tables (chat threads, call
transcripts, support tickets, reviews, ...) that AI Functions run against.

Run order:
  1. lab/setup.sql            (database, schema, warehouse, structured tables)
  2. python lab/data_gen.py   (this script — loads unstructured text tables)
  3. lab/<slug>-lab.ipynb     (the hands-on lab)

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

DB_NAME = "{{DB_NAME}}"
SCHEMA_NAME = "{{SCHEMA_NAME}}"
WH_NAME = "{{WH_NAME}}"
DEFAULT_CONNECTION = "{{CONNECTION_NAME}}"  # a name in ~/.snowflake/connections.toml

RANDOM_SEED = 42


def get_session(connection_name: str):
    """Return an active Snowpark session (notebook first, else named connection)."""
    try:
        from snowflake.snowpark.context import get_active_session

        return get_active_session()
    except Exception:
        from snowflake.snowpark import Session

        return Session.builder.config("connection_name", connection_name).create()


# ─────────────────────────────────────────────────────────────────────────────
# BUILD DATAFRAMES
# ─────────────────────────────────────────────────────────────────────────────
# Replace the body of build_frames() with the demo's unstructured tables.
# Author the text with real variety (positive / negative / mixed, multiple
# topics) so AI Functions produce interesting, non-uniform results.
# Return a dict of {TABLE_NAME: pandas.DataFrame}.
def build_frames() -> dict[str, pd.DataFrame]:
    random.seed(RANDOM_SEED)

    # {{DATA_GEN_STUB}}
    # Example shape:
    #   rows = [{"ID": 1, "CUSTOMER_ID": 100, "TEXT": "..."}, ...]
    #   return {"MY_TEXT_TABLE": pd.DataFrame(rows)}
    return {}


def main() -> None:
    parser = argparse.ArgumentParser(description="Load synthetic data for {{DECK_TITLE}}")
    parser.add_argument("--connection", default=DEFAULT_CONNECTION,
                        help="Named connection in ~/.snowflake/connections.toml")
    args = parser.parse_args()

    session = get_session(args.connection)
    session.sql(f"USE DATABASE {DB_NAME}").collect()
    session.sql(f"USE SCHEMA {SCHEMA_NAME}").collect()
    session.sql(f"USE WAREHOUSE {WH_NAME}").collect()

    frames = build_frames()
    if not frames:
        print("build_frames() returned nothing — fill in the {{DATA_GEN_STUB}} section.")
        return

    for table_name, df in frames.items():
        session.write_pandas(
            df, table_name, auto_create_table=True, overwrite=True, quote_identifiers=False,
        )
        print(f"Loaded {len(df):>6} rows -> {DB_NAME}.{SCHEMA_NAME}.{table_name}")

    print("Done. Open the lab notebook next.")


if __name__ == "__main__":
    main()
