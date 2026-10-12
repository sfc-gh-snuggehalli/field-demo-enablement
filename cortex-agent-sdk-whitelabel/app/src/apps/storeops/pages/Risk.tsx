import { useEffect } from "react";
import { announce, shareContext } from "../agentBridge";
import { categoryExposure, marginByCategory, money, regionById, risk } from "../data";

export function RiskPage() {
  useEffect(() => announce("Store Ops · Risk dashboard"), []);
  const margins = marginByCategory();
  const categories = [...new Set(margins.map((m) => m.category))].sort();
  const breaches = risk.filter((r) => r.stockout_breach || r.sales_breach);
  return (
    <>
      <h2>Risk dashboard</h2>
      <div className="so-panel" data-testid="threshold-breaches">
        <h3>Threshold breaches</h3>
        {breaches.length === 0 ? <p className="muted">No breaches.</p> : (
          <ul>
            {breaches.map((r) => (
              <li key={r.region_id} data-testid={`breach-${r.region_id}`}>
                <strong>{regionById.get(r.region_id)?.name}</strong>: stockout rate {r.stockout_rate_pct}% vs threshold {r.stockout_threshold_pct}%
              </li>
            ))}
          </ul>
        )}
      </div>
      <div className="so-panel">
        <h3>Stockout risk by region</h3>
        <table className="so-table" data-testid="risk-table">
          <thead><tr><th>Region</th><th className="num">Stockout rate %</th><th className="num">Threshold %</th><th>Breach</th><th className="num">Gross margin %</th><th className="num">Sales 7d</th><th className="num">Sales vs target %</th><th>Category exposure</th></tr></thead>
          <tbody>
            {risk.map((r) => {
              const name = regionById.get(r.region_id)?.name ?? r.region_id;
              const exp = categoryExposure(r.region_id).filter((c) => c.stockouts > 0);
              return (
                <tr key={r.region_id} data-testid={`risk-row-${r.region_id}`} onClick={() => shareContext({ type: "region", id: r.region_id, summary: `${name}: stockout ${r.stockout_rate_pct}% vs ${r.stockout_threshold_pct}%` })}>
                  <td>{name} ({r.region_id})</td><td className="num">{r.stockout_rate_pct}</td><td className="num">{r.stockout_threshold_pct}</td>
                  <td><span className={`badge ${r.stockout_breach ? "bad" : "ok"}`}>{r.stockout_breach ? "BREACH" : "OK"}</span></td>
                  <td className="num">{r.gross_margin_pct}</td><td className="num">{money(r.sales_7d)}</td><td className="num">{r.sales_vs_target_pct}</td>
                  <td>{exp.length ? exp.map((c) => `${c.category} ${c.stockouts}/${c.skus}`).join(", ") : "—"}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <div className="so-panel">
        <h3>Margin by category and region (30 days)</h3>
        <table className="so-table" data-testid="margin-table">
          <thead><tr><th>Region</th>{categories.map((c) => <th key={c} className="num">{c}</th>)}</tr></thead>
          <tbody>
            {risk.map((r) => (
              <tr key={r.region_id} data-testid={`margin-row-${r.region_id}`}>
                <td>{regionById.get(r.region_id)?.name}</td>
                {categories.map((c) => <td key={c} className="num">{margins.find((m) => m.region_id === r.region_id && m.category === c)?.margin_pct ?? "—"}%</td>)}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
