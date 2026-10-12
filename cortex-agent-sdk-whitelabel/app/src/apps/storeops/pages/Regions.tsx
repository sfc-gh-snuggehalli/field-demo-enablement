import { useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { announce, shareContext } from "../agentBridge";
import { BUSINESS_DATE, dailySeries, inventory, money, productBySku, regionById, regions, risk, salesOn } from "../data";

export function RegionsPage() {
  const nav = useNavigate();
  useEffect(() => announce("Store Ops · Regions"), []);
  return (
    <>
      <h2>Regions</h2>
      <div className="so-cards" data-testid="region-list">
        {regions.map((r) => {
          const rk = risk.find((x) => x.region_id === r.id)!;
          return (
            <button key={r.id} className="so-card" data-testid={`region-card-${r.id}`} aria-label={`Open region ${r.name}`} onClick={() => { shareContext({ type: "region", id: r.id, summary: `${r.name} (${r.store_count} stores)` }); nav(`/${r.id}`); }}>
              <div className="muted small">{r.id}</div>
              <h3>{r.name}</h3>
              <div className="muted">{r.store_count} stores · {r.manager}</div>
              <div className="so-kpi">{money(salesOn(r.id, BUSINESS_DATE))}</div>
              <div className="muted small">today's sales</div>
              <div style={{ marginTop: 6 }}>
                Stockout risk <span className={`badge ${rk.stockout_breach ? "bad" : "ok"}`}>{rk.stockout_rate_pct}%</span>
              </div>
            </button>
          );
        })}
      </div>
    </>
  );
}

function Sparkline({ data }: { data: { date: string; revenue: number }[] }) {
  const w = 640, h = 160, pad = 24;
  const max = Math.max(...data.map((d) => d.revenue)), min = Math.min(...data.map((d) => d.revenue));
  const x = (i: number) => pad + (i / Math.max(1, data.length - 1)) * (w - pad * 2);
  const y = (v: number) => h - pad - ((v - min) / Math.max(1, max - min)) * (h - pad * 2);
  return (
    <svg viewBox={`0 0 ${w} ${h}`} width="100%" role="img" aria-label="30-day sales line chart" data-testid="sales-chart">
      <polyline fill="none" stroke="var(--accent)" strokeWidth={2.5} points={data.map((d, i) => `${x(i)},${y(d.revenue)}`).join(" ")} />
      {data.map((d, i) => <circle key={d.date} cx={x(i)} cy={y(d.revenue)} r={2.5} fill="var(--accent)"><title>{`${d.date}: ${money(d.revenue)}`}</title></circle>)}
      <text x={pad} y={h - 4} fontSize={11} fill="var(--text-muted)">{data[0]?.date}</text>
      <text x={w - pad} y={h - 4} fontSize={11} fill="var(--text-muted)" textAnchor="end">{data.at(-1)?.date}</text>
    </svg>
  );
}

export function RegionDetailPage() {
  const { regionId = "" } = useParams();
  const region = regionById.get(regionId);
  const [sel, setSel] = useState<string | null>(null);
  useEffect(() => announce(`Store Ops · ${region?.name ?? regionId} inventory`), [regionId]);
  if (!region) return <p>Unknown region {regionId}. <Link to="/">Back to regions</Link></p>;
  const rows = inventory.filter((i) => i.region_id === regionId);
  return (
    <>
      <div className="row">
        <h2>{region.name} · {region.id}</h2>
        <span className="spacer" />
        <Link className="btn" to={`/${regionId}/orders`} data-testid="open-orders">Order blotter</Link>
      </div>
      <div className="so-panel">
        <h3>30-day sales</h3>
        <Sparkline data={dailySeries(regionId)} />
      </div>
      <div className="so-panel">
        <h3>Store inventory</h3>
        <table className="so-table" data-testid="inventory-table">
          <thead><tr><th>SKU</th><th>Product</th><th>Category</th><th className="num">On hand</th><th className="num">On order</th><th className="num">Run rate/day</th><th className="num">Weeks of cover</th><th className="num">Value</th><th>Status</th></tr></thead>
          <tbody>
            {rows.map((i) => {
              const p = productBySku.get(i.sku)!;
              return (
                <tr key={i.sku} data-testid={`inventory-row-${i.sku}`} className={sel === i.sku ? "selected" : ""} onClick={() => { setSel(i.sku); shareContext({ type: "sku", id: i.sku, summary: `${p.name} in ${region.name}: on hand ${i.on_hand}, ${i.weeks_of_cover} wks cover` }); }} aria-label={`Inventory ${i.sku}`}>
                  <td>{i.sku}</td><td>{p.name}</td><td>{p.category}</td><td className="num">{i.on_hand}</td><td className="num">{i.on_order}</td><td className="num">{i.daily_run_rate}</td><td className="num">{i.weeks_of_cover}</td><td className="num">{money(i.inventory_value)}</td>
                  <td><span className={`badge ${i.stockout_flag ? "bad" : i.weeks_of_cover < 2 ? "warn" : "ok"}`}>{i.stockout_flag ? "Stockout" : i.weeks_of_cover < 2 ? "Low cover" : "Healthy"}</span></td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </>
  );
}
