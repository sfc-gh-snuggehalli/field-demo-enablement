// Seed data shared with Snowflake (scripts/gen-seed.mjs writes both), plus derived views.
import dailySales from "./data/daily_sales.json";
import exceptions from "./data/exceptions.json";
import inventory from "./data/inventory.json";
import orders from "./data/orders.json";
import products from "./data/products.json";
import regions from "./data/regions.json";
import risk from "./data/risk.json";

export type Region = (typeof regions)[number];
export type Order = (typeof orders)[number];
export type Exception = (typeof exceptions)[number] & { assignee: string | null };
export type InventoryRow = (typeof inventory)[number];

export { dailySales, exceptions, inventory, orders, products, regions, risk };

export const BUSINESS_DATE = [...new Set(orders.map((o) => o.order_date))].sort().at(-1)!;
export const productBySku = new Map(products.map((p) => [p.sku, p]));
export const regionById = new Map(regions.map((r) => [r.id, r]));

export function salesOn(regionId: string, date: string): number {
  return dailySales.filter((d) => d.region_id === regionId && d.sales_date === date).reduce((s, d) => s + d.revenue, 0);
}

export function dailySeries(regionId: string): { date: string; revenue: number }[] {
  const m = new Map<string, number>();
  for (const d of dailySales) if (d.region_id === regionId) m.set(d.sales_date, (m.get(d.sales_date) ?? 0) + d.revenue);
  return [...m.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([date, revenue]) => ({ date, revenue }));
}

export function marginByCategory(): { region_id: string; category: string; margin_pct: number }[] {
  const acc = new Map<string, { rev: number; cost: number }>();
  for (const d of dailySales) {
    const p = productBySku.get(d.sku)!;
    const k = `${d.region_id}|${p.category}`;
    const a = acc.get(k) ?? { rev: 0, cost: 0 };
    a.rev += d.revenue;
    a.cost += d.units * p.unit_cost;
    acc.set(k, a);
  }
  return [...acc.entries()].map(([k, a]) => {
    const [region_id, category] = k.split("|");
    return { region_id, category, margin_pct: Math.round(((a.rev - a.cost) / a.rev) * 1000) / 10 };
  });
}

export function categoryExposure(regionId: string): { category: string; stockouts: number; skus: number }[] {
  const m = new Map<string, { stockouts: number; skus: number }>();
  for (const i of inventory) {
    if (i.region_id !== regionId) continue;
    const c = productBySku.get(i.sku)!.category;
    const a = m.get(c) ?? { stockouts: 0, skus: 0 };
    a.skus++;
    if (i.stockout_flag) a.stockouts++;
    m.set(c, a);
  }
  return [...m.entries()].map(([category, a]) => ({ category, ...a }));
}

export const money = (n: number) => n.toLocaleString("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });

/** Current user for "assign to me": the chat's Settings name (same origin), else "You". */
export function currentUser(): string {
  try {
    return JSON.parse(localStorage.getItem("acme.settings") || "{}").name || "You";
  } catch {
    return "You";
  }
}
