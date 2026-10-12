// "Data current as of <date>": MAX(order_date) from the orders table, read once through the SQL API
// and cached for the process. Falls back to today's UTC date if the query fails, so the agent
// context never carries a stale constant.
import { config } from "./config";
import { log } from "./log";
import { sql } from "./sqlapi";

const g = globalThis as unknown as { __acmeDataDate?: Promise<string> };
const today = () => new Date().toISOString().slice(0, 10);

export function dataDate(): Promise<string> {
  return (g.__acmeDataDate ??= (async () => {
    try {
      const table = process.env.DATA_DATE_TABLE || "ACME_ASSIST_DEMO.DATA.ORDERS";
      if (!/^[A-Za-z0-9_.$"]+$/.test(table)) throw new Error("invalid DATA_DATE_TABLE");
      const rows = await sql(`SELECT TO_VARCHAR(MAX(order_date), 'YYYY-MM-DD') AS d FROM ${table}`, [], { role: config().sqlReadonlyRole ?? config().role });
      const d = String(rows[0]?.d ?? "");
      if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) throw new Error("no order_date");
      log("info", "data date", { dataDate: d, source: "snowflake" });
      return d;
    } catch (e: any) {
      log("warn", "data date fallback to today", { error: e?.message });
      return today();
    }
  })());
}

/** Test hook. */
export function setDataDate(d: string | undefined): void {
  g.__acmeDataDate = d ? Promise.resolve(d) : undefined;
}
