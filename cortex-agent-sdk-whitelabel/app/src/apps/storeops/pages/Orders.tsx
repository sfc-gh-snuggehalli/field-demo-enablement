import { useEffect, useMemo, useState } from "react";
import { Link, useParams, useSearchParams } from "react-router-dom";
import { announce, shareContext } from "../agentBridge";
import { BUSINESS_DATE, money, orders, productBySku, regionById } from "../data";

const STATUSES = ["NEW", "PICKED", "SHIPPED", "FAILED", "BACKORDERED"];
const CHANNELS = ["STORE", "ONLINE", "BOPIS"];
const shift = (d: string, days: number) => new Date(new Date(d + "T00:00:00Z").getTime() + days * 86400000).toISOString().slice(0, 10);

export function OrdersPage() {
  const { regionId = "" } = useParams();
  const region = regionById.get(regionId);
  const [q, setQ] = useSearchParams();
  const [cancelled, setCancelled] = useState<Set<string>>(() => new Set(JSON.parse(sessionStorage.getItem("so.cancelled") || "[]")));
  const [sel, setSel] = useState<string | null>(null);
  const status = q.get("status") ?? "";
  const channel = q.get("channel") ?? "";
  const range = q.get("range") ?? "";
  const from = q.get("from") ?? "";
  const to = q.get("to") ?? "";
  const set = (k: string, v: string) => {
    const n = new URLSearchParams(q);
    if (v) n.set(k, v);
    else n.delete(k);
    setQ(n, { replace: true });
  };
  useEffect(() => announce(`Store Ops · ${region?.name ?? regionId} order blotter`), [regionId, q.toString()]);

  const rows = useMemo(() => {
    const lo = range === "today" ? BUSINESS_DATE : range === "7d" ? shift(BUSINESS_DATE, -6) : from;
    const hi = range ? BUSINESS_DATE : to;
    return orders
      .filter((o) => o.region_id === regionId)
      .map((o) => (cancelled.has(o.order_id) ? { ...o, status: "CANCELLED" } : o))
      .filter((o) => (!status || o.status === status) && (!channel || o.channel === channel) && (!lo || o.order_date >= lo) && (!hi || o.order_date <= hi))
      .sort((a, b) => b.order_date.localeCompare(a.order_date) || a.order_id.localeCompare(b.order_id));
  }, [regionId, status, channel, range, from, to, cancelled]);

  const cancel = (id: string) => {
    const n = new Set(cancelled).add(id);
    setCancelled(n);
    sessionStorage.setItem("so.cancelled", JSON.stringify([...n]));
  };

  if (!region) return <p>Unknown region. <Link to="/">Back</Link></p>;
  return (
    <>
      <div className="row">
        <h2>{region.name} · Order blotter</h2>
        <span className="spacer" />
        <Link to={`/${regionId}`} className="btn" data-testid="back-to-inventory">Inventory</Link>
      </div>
      <div className="so-panel so-filters" role="search" aria-label="Order filters">
        <label>Status
          <select data-testid="order-filter-status" aria-label="Status filter" value={status} onChange={(e) => set("status", e.target.value)}>
            <option value="">All</option>
            {STATUSES.map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
        </label>
        <label>Channel
          <select data-testid="order-filter-channel" aria-label="Channel filter" value={channel} onChange={(e) => set("channel", e.target.value)}>
            <option value="">All</option>
            {CHANNELS.map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
        </label>
        <label>Date range
          <select data-testid="order-filter-date" aria-label="Date range filter" value={range} onChange={(e) => set("range", e.target.value)}>
            <option value="">All dates</option>
            <option value="today">Today ({BUSINESS_DATE})</option>
            <option value="7d">Last 7 days</option>
          </select>
        </label>
        <label>From<input type="date" data-testid="order-filter-date-from" aria-label="From date" value={from} onChange={(e) => set("from", e.target.value)} /></label>
        <label>To<input type="date" data-testid="order-filter-date-to" aria-label="To date" value={to} onChange={(e) => set("to", e.target.value)} /></label>
        <button className="btn" data-testid="order-filter-clear" onClick={() => setQ(new URLSearchParams(), { replace: true })}>Clear</button>
        <span className="muted" data-testid="order-count">{rows.length} orders</span>
      </div>
      <div className="so-panel" style={{ overflow: "auto" }}>
        <table className="so-table" data-testid="orders-table">
          <thead><tr><th>Order</th><th>Date</th><th>SKU</th><th>Product</th><th>Channel</th><th className="num">Qty</th><th className="num">Value</th><th>Promised</th><th>Carrier</th><th>Status</th><th>Action</th></tr></thead>
          <tbody>
            {rows.map((o) => (
              <tr key={o.order_id} data-testid={`order-row-${o.order_id}`} className={sel === o.order_id ? "selected" : ""} onClick={() => { setSel(o.order_id); shareContext({ type: "order", id: o.order_id, summary: `${o.status} ${o.channel} order, ${o.qty} x ${o.sku}, ${o.carrier}` }); }}>
                <td>{o.order_id}</td><td>{o.order_date}</td><td>{o.sku}</td><td>{productBySku.get(o.sku)?.name}</td><td>{o.channel}</td><td className="num">{o.qty}</td><td className="num">{money(o.qty * o.unit_price)}</td><td>{o.promised_date}</td><td>{o.carrier}</td>
                <td><span className={`badge ${o.status === "FAILED" || o.status === "CANCELLED" ? "bad" : o.status === "BACKORDERED" ? "warn" : "ok"}`}>{o.status}</span></td>
                <td>
                  {o.status !== "SHIPPED" && o.status !== "CANCELLED" && (
                    <button className="link-btn" data-testid={`order-cancel-${o.order_id}`} data-agent-confirm="true" aria-label={`Cancel order ${o.order_id}`} onClick={(e) => { e.stopPropagation(); cancel(o.order_id); }}>Cancel order</button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
