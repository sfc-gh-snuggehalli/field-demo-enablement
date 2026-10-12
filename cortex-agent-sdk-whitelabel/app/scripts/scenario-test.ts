// Headless acceptance scenarios (section 5b) against the REAL agent through the proxy's
// dispatch(), with a fake sidebar executor backed by the same seed JSON as the simulator.
// Usage: npm run test:scenarios [-- 1|2|3]
import { readFileSync } from "node:fs";
import { loadEnv } from "../server/env";

loadEnv();
const { dispatch } = await import("../server/handlers");
const data = (f: string) => JSON.parse(readFileSync(new URL(`../src/apps/storeops/data/${f}.json`, import.meta.url), "utf8"));
const orders = data("orders");
const exceptions = data("exceptions");
const risk = data("risk");
const regions = data("regions");
const TODAY = orders.map((o: any) => o.order_date).sort().at(-1);

/** Minimal model of the Store Ops pages, answering browser_* tools like the bridge does. */
class FakeSidebar {
  url = "/apps/storeops";
  filters: Record<string, string> = {};
  sort = "id";
  assigned: Record<string, string> = {};
  highlighted: string[] = [];
  confirmations: string[] = [];
  page() {
    const u = this.url;
    if (/\/orders/.test(u)) {
      return [
        { role: "heading", text: "Order blotter" }, { role: "text", testid: "business-date", text: `Business date (today): ${TODAY}` },
        { role: "combobox", testid: "order-filter-status", label: "Status filter", value: this.filters.status ?? "", options: ["", "NEW", "PICKED", "SHIPPED", "FAILED", "BACKORDERED"] },
        { role: "combobox", testid: "order-filter-channel", label: "Channel filter", value: this.filters.channel ?? "", options: ["", "STORE", "ONLINE", "BOPIS"] },
        { role: "combobox", testid: "order-filter-date", label: "Date range filter", value: this.filters.range ?? "", options: ["", "today", "7d"] },
        { role: "table", testid: "orders-table" },
      ];
    }
    if (/exceptions/.test(u)) return [{ role: "combobox", testid: "exception-sort", label: "Sort exceptions", value: this.sort, options: ["id", "age_desc", "age_asc"] }, { role: "button", testid: "exceptions-sort-age", label: "Sort by age" }, { role: "table", testid: "exceptions-table" }, ...this.exRows().map((e: any) => ({ role: "button", testid: `exception-assign-${e.exception_id}`, label: `Assign exception ${e.exception_id}`, confirm: true }))];
    if (/risk/.test(u)) return [{ role: "table", testid: "risk-table" }, ...risk.map((r: any) => ({ role: "row", testid: `risk-row-${r.region_id}`, text: `${r.region_id} ${r.stockout_rate_pct}% ${r.stockout_breach ? "BREACH" : "OK"}` }))];
    if (/RG-\d+$/.test(u)) return [{ role: "link", testid: "open-orders", text: "Order blotter" }, { role: "table", testid: "inventory-table" }];
    return regions.map((r: any) => ({ role: "button", testid: `region-card-${r.id}`, label: `Open region ${r.name}` })).concat([{ role: "link", testid: "nav-exceptions" }, { role: "link", testid: "nav-risk" }] as any);
  }
  exRows() {
    const r = exceptions.map((e: any) => ({ ...e, assignee: this.assigned[e.exception_id] ?? e.assignee }));
    return this.sort === "age_desc" ? r.sort((a: any, b: any) => b.age_hours - a.age_hours) : this.sort === "age_asc" ? r.sort((a: any, b: any) => a.age_hours - b.age_hours) : r;
  }
  exec(name: string, input: any): unknown {
    switch (name) {
      case "browser_open_app": this.url = "/apps/storeops"; return { url: this.url, title: "Store Ops · Regions" };
      case "browser_navigate": {
        const p = new URL(input.url, "http://x");
        if (!p.pathname.startsWith("/apps/storeops")) return { ok: false, error: "URL not allowed" };
        this.url = p.pathname;
        p.searchParams.forEach((v, k) => (this.filters[k] = v));
        return { url: this.url, title: "Store Ops" };
      }
      case "browser_get_page": return { url: this.url, title: "Store Ops", tree: this.page() };
      case "browser_select": {
        const key = String(input.testid).replace(/^order-filter-/, "");
        if (input.testid === "exception-sort") this.sort = input.value;
        else this.filters[key === "date" ? "range" : key] = input.value;
        return { ok: true, url: this.url };
      }
      case "browser_click": {
        if (input.testid === "exceptions-sort-age") this.sort = this.sort === "age_desc" ? "age_asc" : "age_desc";
        else if (String(input.testid).startsWith("exception-assign-")) {
          this.confirmations.push(input.testid); // the real client shows an approval card here
          this.assigned[input.testid.replace("exception-assign-", "")] = "Sam Rivera";
        } else if (String(input.testid).startsWith("region-card-")) this.url = `/apps/storeops/${input.testid.replace("region-card-", "")}`;
        else if (input.testid === "open-orders") this.url += "/orders";
        else if (input.testid === "nav-exceptions") this.url = "/apps/storeops/exceptions";
        else if (input.testid === "nav-risk") this.url = "/apps/storeops/risk";
        return { ok: true, url: this.url };
      }
      case "browser_get_table": {
        if (input.testid === "orders-table") {
          const region = this.url.match(/RG-\d+/)?.[0];
          const f = this.filters;
          const rows = orders.filter((o: any) => o.region_id === region && (!f.status || o.status === f.status) && (!f.channel || o.channel === f.channel) && (f.range !== "today" || o.order_date === TODAY));
          return { rowCount: rows.length, rows: rows.map((o: any) => ({ testid: `order-row-${o.order_id}`, Order: o.order_id, Date: o.order_date, SKU: o.sku, Channel: o.channel, Qty: o.qty, Carrier: o.carrier, Status: o.status })) };
        }
        if (input.testid === "exceptions-table") return { rows: this.exRows().map((e: any) => ({ testid: `exception-row-${e.exception_id}`, Exception: e.exception_id, Order: e.order_id, Reason: e.reason, "Age (h)": e.age_hours, Assignee: e.assignee ?? "Unassigned", Status: e.status })) };
        if (input.testid === "risk-table") return { rows: risk.map((r: any) => ({ testid: `risk-row-${r.region_id}`, Region: r.region_id, "Stockout rate %": r.stockout_rate_pct, "Threshold %": r.stockout_threshold_pct, Breach: r.stockout_breach ? "BREACH" : "OK" })) };
        return { ok: false, error: "no such table" };
      }
      case "browser_highlight": this.highlighted.push(input.testid); return { ok: true };
      case "browser_get_text": return { text: JSON.stringify(this.page()) };
      default: return { url: this.url };
    }
  }
}

async function run(prompt: string, sidebar: FakeSidebar) {
  const calls: string[] = [];
  let threadId: string | undefined;
  let parentMessageId: string | undefined;
  let content: any[] = [{ type: "text", text: prompt }];
  let answer = "";
  for (let hop = 0; hop < 14; hop++) {
    const res = await dispatch(new Request("http://local/api/chat", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ conversationId: "scenario", mode: "assist", threadId, parentMessageId, content, user: { name: "Sam Rivera", email: "sam.rivera@acme.example" } }) }));
    const text = await res.text();
    const pending: any[] = [];
    let turnText = "";
    for (const block of text.split("\n\n")) {
      const ev = block.match(/^event: (.*)$/m)?.[1];
      const d = block.match(/^data: (.*)$/m)?.[1];
      if (!ev || !d) continue;
      const data = JSON.parse(d);
      if (ev === "acme.run") threadId = data.threadId;
      if (ev === "metadata" && data.metadata?.role === "assistant") parentMessageId = String(data.metadata.message_id);
      if (ev === "response.tool_use") {
        calls.push(data.name + (data.client_side_execute ? "" : "(server)"));
        if (data.client_side_execute) pending.push(data);
      }
      if (ev === "response.text.delta") turnText += data.text ?? "";
      if (ev === "acme.error" || ev === "error") throw new Error(data.message);
    }
    answer += turnText;
    if (!pending.length) break;
    content = pending.map((p) => ({ type: "tool_result", tool_result: { tool_use_id: p.tool_use_id, name: p.name, content: [{ type: "json", json: sidebar.exec(p.name, p.input ?? {}) }] } }));
  }
  return { calls, answer };
}

const which = process.argv[2];
let failed = 0;
const report = (n: string, ok: boolean, info: string) => {
  console.log(`${ok ? "PASS" : "FAIL"}  ${n}\n      ${info}`);
  if (!ok) failed++;
};

if (!which || which === "1") {
  const s = new FakeSidebar();
  const r = await run("Show me today's failed orders for the West region", s);
  const browser = r.calls.filter((c) => c.startsWith("browser_"));
  const ok = browser.length > 0 && /RG-001\/orders|orders/.test(s.url) && s.filters.status === "FAILED" && r.calls.includes("browser_get_table");
  report("Scenario 1: today's failed West orders", ok, `tools: ${r.calls.join(" → ")}\n      sidebar: ${s.url} ${JSON.stringify(s.filters)}\n      answer: ${r.answer.trim().slice(0, 240).replace(/\n/g, " ")}`);
}
if (!which || which === "2") {
  const s = new FakeSidebar();
  const r = await run("Which region is breaching its stockout threshold?", s);
  const ok = r.calls.some((c) => /analyst|execute_sql/.test(c)) && s.url.endsWith("/risk") && s.highlighted.some((h) => /risk-row-RG-00(1|4)/.test(h)) && /13\.3/.test(r.answer);
  report("Scenario 2: stockout breach (Analyst + /risk highlight)", ok, `tools: ${r.calls.join(" → ")}\n      highlighted: ${s.highlighted.join(", ")}\n      answer: ${r.answer.trim().slice(0, 240).replace(/\n/g, " ")}`);
}
if (!which || which === "3") {
  const s = new FakeSidebar();
  const r = await run("Assign the oldest Address mismatch exception to me", s);
  const ok = s.assigned["EX-5005"] === "Sam Rivera" && s.confirmations.includes("exception-assign-EX-5005");
  report("Scenario 3: assign oldest Address mismatch (confirm-gated click)", ok, `tools: ${r.calls.join(" → ")}\n      assigned: ${JSON.stringify(s.assigned)}\n      answer: ${r.answer.trim().slice(0, 240).replace(/\n/g, " ")}`);
}
process.exit(failed ? 1 : 0);
