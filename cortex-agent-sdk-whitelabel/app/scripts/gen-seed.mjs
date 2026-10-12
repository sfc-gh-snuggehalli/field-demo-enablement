// Deterministic seed generator. Writes the Store Ops simulator JSON and the
// matching Snowflake INSERTs so UI and agent numbers always agree.
// Usage: node scripts/gen-seed.mjs   (from app/)
// Dates are relative to an anchor ("today" in the demo data): SEED_ANCHOR_DATE=YYYY-MM-DD, default
// = today's UTC date at generation time. The PRNG seed is fixed, so only the dates move: the
// scenario facts (West + Northeast breaches, West FAILED orders on the anchor day, Address
// mismatch exceptions) hold for any anchor.
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const DATA_DIR = resolve(here, "../src/apps/storeops/data");
const SQL_FILE = resolve(here, "../../lab/seed_data.sql");

let s = 20261011;
const rnd = () => ((s = (s * 1664525 + 1013904223) >>> 0) / 2 ** 32);
const pick = (a) => a[Math.floor(rnd() * a.length)];
const int = (lo, hi) => lo + Math.floor(rnd() * (hi - lo + 1));
const round = (n, d = 2) => Math.round(n * 10 ** d) / 10 ** d;

const anchorArg = process.env.SEED_ANCHOR_DATE || new Date().toISOString().slice(0, 10);
if (!/^\d{4}-\d{2}-\d{2}$/.test(anchorArg)) throw new Error(`SEED_ANCHOR_DATE must be YYYY-MM-DD, got ${anchorArg}`);
const ANCHOR = new Date(`${anchorArg}T00:00:00Z`); // "today" in the demo data
const day = (offset) => new Date(ANCHOR.getTime() + offset * 86400000).toISOString().slice(0, 10);

const regions = [
  { id: "RG-001", name: "West", manager: "Dana Ortiz", store_count: 42, currency: "USD", weekly_sales_target: 1450000, stockout_threshold_pct: 6 },
  { id: "RG-002", name: "Central", manager: "Marcus Lee", store_count: 35, currency: "USD", weekly_sales_target: 1120000, stockout_threshold_pct: 6 },
  { id: "RG-003", name: "South", manager: "Priya Nair", store_count: 38, currency: "USD", weekly_sales_target: 1230000, stockout_threshold_pct: 7 },
  { id: "RG-004", name: "Northeast", manager: "Tom Becker", store_count: 31, currency: "USD", weekly_sales_target: 1310000, stockout_threshold_pct: 5 },
];

const P = (sku, name, category, subcategory, brand, unit_cost, list_price) => ({ sku, name, category, subcategory, brand, unit_cost, list_price });
const products = [
  P("SKU-TRL-RUN-01", "Trail Runner Shoe", "Footwear", "Running", "ACME Trail", 42, 119),
  P("SKU-RD-RUN-02", "Road Runner Shoe", "Footwear", "Running", "ACME Trail", 38, 109),
  P("SKU-HK-BOT-03", "Summit Hiking Boot", "Footwear", "Hiking", "ACME Trail", 55, 159),
  P("SKU-SL-SND-04", "Everyday Slide Sandal", "Footwear", "Casual", "ACME Basics", 9, 29),
  P("SKU-AP-TEE-05", "Organic Cotton Tee", "Apparel", "Tops", "ACME Basics", 6, 24),
  P("SKU-AP-HOD-06", "Fleece Hoodie", "Apparel", "Tops", "ACME Basics", 18, 59),
  P("SKU-AP-JKT-07", "Packable Rain Jacket", "Apparel", "Outerwear", "ACME Trail", 34, 99),
  P("SKU-AP-LEG-08", "Performance Legging", "Apparel", "Bottoms", "ACME Active", 14, 54),
  P("SKU-AP-SHT-09", "Training Short", "Apparel", "Bottoms", "ACME Active", 9, 34),
  P("SKU-AP-SOK-10", "Merino Sock 3-Pack", "Apparel", "Accessories", "ACME Trail", 7, 26),
  P("SKU-HM-KTL-02", "Electric Kettle", "Home", "Kitchen", "ACME Home", 16, 49),
  P("SKU-HM-CFM-12", "Pour-Over Coffee Maker", "Home", "Kitchen", "ACME Home", 12, 39),
  P("SKU-HM-PAN-13", "Nonstick Skillet 10in", "Home", "Kitchen", "ACME Home", 14, 44),
  P("SKU-HM-TWL-14", "Bath Towel Set", "Home", "Bath", "ACME Home", 11, 39),
  P("SKU-HM-LMP-15", "LED Desk Lamp", "Home", "Lighting", "ACME Home", 13, 45),
  P("SKU-EL-EAR-16", "Wireless Earbuds", "Electronics", "Audio", "ACME Tech", 28, 89),
  P("SKU-EL-SPK-17", "Portable Speaker", "Electronics", "Audio", "ACME Tech", 24, 79),
  P("SKU-EL-WCH-18", "Fitness Watch", "Electronics", "Wearables", "ACME Tech", 52, 149),
  P("SKU-EL-CHG-19", "Fast Charger 65W", "Electronics", "Accessories", "ACME Tech", 11, 39),
  P("SKU-EL-PWR-20", "Power Bank 20k", "Electronics", "Accessories", "ACME Tech", 15, 49),
  P("SKU-OD-TNT-21", "2-Person Tent", "Outdoor", "Camping", "ACME Trail", 64, 189),
  P("SKU-OD-BAG-22", "Daypack 24L", "Outdoor", "Bags", "ACME Trail", 22, 69),
  P("SKU-OD-BTL-23", "Insulated Bottle 32oz", "Outdoor", "Hydration", "ACME Trail", 8, 32),
  P("SKU-OD-CHR-24", "Folding Camp Chair", "Outdoor", "Camping", "ACME Trail", 17, 54),
  P("SKU-OD-LTN-25", "Rechargeable Lantern", "Outdoor", "Camping", "ACME Trail", 12, 39),
];

// Inventory: 15 SKUs per region = 60 rows. West + Northeast get deliberate stockouts.
const inventory = [];
regions.forEach((r, ri) => {
  for (let k = 0; k < 15; k++) {
    const p = products[(ri * 5 + k) % products.length];
    const run = round(4 + rnd() * 26, 1);
    let on_hand = int(40, 900);
    const forcedOut = (r.id === "RG-001" && k < 2) || (r.id === "RG-004" && k === 0);
    if (forcedOut) on_hand = 0;
    const on_order = forcedOut ? int(200, 500) : int(0, 400);
    const woc = round(on_hand / (run * 7), 1);
    inventory.push({
      region_id: r.id, sku: p.sku, on_hand, on_order, daily_run_rate: run,
      weeks_of_cover: woc, inventory_value: round(on_hand * p.unit_cost),
      stockout_flag: on_hand === 0 || woc < 0.3,
    });
  }
});

// 30 days of daily sales per inventory row.
const daily_sales = [];
for (const inv of inventory) {
  const p = products.find((x) => x.sku === inv.sku);
  for (let d = -29; d <= 0; d++) {
    const units = Math.max(0, Math.round(inv.daily_run_rate * (0.6 + rnd() * 0.8)));
    daily_sales.push({ sales_date: day(d), region_id: inv.region_id, sku: inv.sku, units, revenue: round(units * p.list_price * (0.85 + rnd() * 0.15)) });
  }
}

// 150 orders over the last 10 days. West gets several FAILED orders "today".
const STATUSES = ["NEW", "PICKED", "SHIPPED", "SHIPPED", "SHIPPED", "FAILED", "BACKORDERED"];
const orders = [];
for (let i = 1; i <= 150; i++) {
  const r = regions[(i - 1) % 4];
  const p = pick(products);
  const d = -int(0, 9);
  let status = pick(STATUSES);
  if (r.id === "RG-001" && i % 12 === 1) status = "FAILED";
  const order_date = r.id === "RG-001" && i % 12 === 1 ? day(0) : day(d);
  orders.push({
    order_id: `ORD-${String(100000 + i)}`, region_id: r.id, sku: p.sku, channel: pick(["STORE", "ONLINE", "BOPIS"]),
    qty: int(1, 6), unit_price: p.list_price, order_date, promised_date: day(Math.min(d + int(1, 4), 3)),
    carrier: pick(["UPS", "FedEx", "USPS", "OnTrac"]), status,
  });
}

// 12 fulfillment exceptions attached to FAILED / BACKORDERED orders.
const REASONS = ["Address mismatch", "Qty short", "Late pick", "Carrier delay"];
const exOrders = orders.filter((o) => o.status === "FAILED" || o.status === "BACKORDERED").slice(0, 12);
const exceptions = exOrders.map((o, i) => ({
  exception_id: `EX-${String(5001 + i)}`, order_id: o.order_id, reason: REASONS[i % 4],
  age_hours: [6, 74, 31, 12, 49, 3, 96, 18, 27, 55, 8, 40][i], assignee: i % 3 === 0 ? null : pick(["J. Kim", "R. Silva", "A. Patel"]),
  status: "OPEN",
}));

// Risk: computed from inventory + sales so the breach is real, not hard-coded.
const risk = regions.map((r) => {
  const inv = inventory.filter((x) => x.region_id === r.id);
  const stockout_rate_pct = round((inv.filter((x) => x.stockout_flag).length / inv.length) * 100, 1);
  const last7 = daily_sales.filter((x) => x.region_id === r.id && x.sales_date > day(-7));
  const rev7 = last7.reduce((a, b) => a + b.revenue, 0);
  const cost7 = last7.reduce((a, b) => a + b.units * products.find((p) => p.sku === b.sku).unit_cost, 0);
  // Scale demo SKU sample (15 SKUs) up to the region's full assortment.
  const sales_7d = round(rev7 * r.store_count * 3.2);
  return {
    region_id: r.id, stockout_rate_pct, stockout_threshold_pct: r.stockout_threshold_pct,
    stockout_breach: stockout_rate_pct > r.stockout_threshold_pct,
    gross_margin_pct: round(((rev7 - cost7) / rev7) * 100, 1),
    sales_7d, sales_vs_target_pct: round((sales_7d / r.weekly_sales_target) * 100, 1),
    sales_breach: sales_7d < r.weekly_sales_target * 0.9,
  };
});

mkdirSync(DATA_DIR, { recursive: true });
const sets = { regions, products, inventory, daily_sales, orders, exceptions, risk };
for (const [k, v] of Object.entries(sets)) writeFileSync(resolve(DATA_DIR, `${k}.json`), JSON.stringify(v, null, 1) + "\n");

const lit = (v) => (v === null || v === undefined ? "NULL" : typeof v === "number" ? String(v) : typeof v === "boolean" ? (v ? "TRUE" : "FALSE") : `'${String(v).replace(/'/g, "''")}'`);
const insert = (table, rows, cols) => {
  const out = [];
  for (let i = 0; i < rows.length; i += 500) {
    out.push(`INSERT INTO ${table} (${cols.join(", ")}) VALUES\n` + rows.slice(i, i + 500).map((r) => `  (${cols.map((c) => lit(r[c])).join(", ")})`).join(",\n") + ";");
  }
  return out.join("\n");
};
const sql = [
  "-- GENERATED by app/scripts/gen-seed.mjs. Do not edit by hand; re-run the script.",
  `-- Anchor (\"today\" in the data): ${day(0)}. Regenerate with SEED_ANCHOR_DATE=YYYY-MM-DD npm run gen:seed.`,
  "USE SCHEMA ACME_ASSIST_DEMO.DATA;",
  "TRUNCATE TABLE IF EXISTS REGIONS; TRUNCATE TABLE IF EXISTS PRODUCTS; TRUNCATE TABLE IF EXISTS INVENTORY;",
  "TRUNCATE TABLE IF EXISTS DAILY_SALES; TRUNCATE TABLE IF EXISTS ORDERS; TRUNCATE TABLE IF EXISTS FULFILLMENT_EXCEPTIONS; TRUNCATE TABLE IF EXISTS REGION_RISK;",
  insert("REGIONS", regions.map((r) => ({ ...r, region_id: r.id, region_name: r.name })), ["region_id", "region_name", "manager", "store_count", "currency", "weekly_sales_target", "stockout_threshold_pct"]),
  insert("PRODUCTS", products, ["sku", "name", "category", "subcategory", "brand", "unit_cost", "list_price"]),
  insert("INVENTORY", inventory, ["region_id", "sku", "on_hand", "on_order", "daily_run_rate", "weeks_of_cover", "inventory_value", "stockout_flag"]),
  insert("DAILY_SALES", daily_sales, ["sales_date", "region_id", "sku", "units", "revenue"]),
  insert("ORDERS", orders, ["order_id", "region_id", "sku", "channel", "qty", "unit_price", "order_date", "promised_date", "carrier", "status"]),
  insert("FULFILLMENT_EXCEPTIONS", exceptions, ["exception_id", "order_id", "reason", "age_hours", "assignee", "status"]),
  insert("REGION_RISK", risk, ["region_id", "stockout_rate_pct", "stockout_threshold_pct", "stockout_breach", "gross_margin_pct", "sales_7d", "sales_vs_target_pct", "sales_breach"]),
].join("\n\n");
writeFileSync(SQL_FILE, sql + "\n");
console.log(`Wrote ${Object.keys(sets).length} JSON files to ${DATA_DIR} and ${SQL_FILE}`);
console.log("Risk:", risk.map((r) => `${r.region_id} stockout ${r.stockout_rate_pct}% (thr ${r.stockout_threshold_pct}) breach=${r.stockout_breach}`).join(" | "));

// Scenario invariants (fail loudly if a change to the generator breaks the demo story).
const breach = risk.filter((r) => r.stockout_breach).map((r) => r.region_id).sort().join(",");
const westFailedToday = orders.filter((o) => o.region_id === "RG-001" && o.status === "FAILED" && o.order_date === day(0)).length;
const addressMismatch = exceptions.filter((e) => e.reason === "Address mismatch").length;
console.log(`Anchor ${day(0)} | stockout breaches: ${breach} | West FAILED today: ${westFailedToday} | Address mismatch exceptions: ${addressMismatch}`);
if (breach !== "RG-001,RG-004" || westFailedToday < 1 || addressMismatch < 1) {
  console.error("Scenario invariants FAILED");
  process.exit(1);
}
