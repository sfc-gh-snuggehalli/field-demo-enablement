import { useEffect, useMemo, useState } from "react";
import { announce, shareContext } from "../agentBridge";
import { currentUser, exceptions, orders, type Exception } from "../data";

const KEY = "so.exceptions";

export function ExceptionsPage() {
  const [items, setItems] = useState<Exception[]>(() => JSON.parse(sessionStorage.getItem(KEY) || "null") ?? (exceptions as Exception[]));
  const [sort, setSort] = useState<"age_desc" | "age_asc" | "id">("id");
  const [reason, setReason] = useState("");
  const [assignee, setAssignee] = useState(currentUser());
  const [sel, setSel] = useState<string | null>(null);
  useEffect(() => announce("Store Ops · Fulfillment exceptions"), []);

  const rows = useMemo(() => {
    const r = items.filter((e) => !reason || e.reason === reason);
    if (sort === "age_desc") return [...r].sort((a, b) => b.age_hours - a.age_hours);
    if (sort === "age_asc") return [...r].sort((a, b) => a.age_hours - b.age_hours);
    return r;
  }, [items, sort, reason]);

  const assign = (id: string) => {
    const next = items.map((e) => (e.exception_id === id ? { ...e, assignee: assignee || currentUser(), status: "ASSIGNED" } : e));
    setItems(next);
    sessionStorage.setItem(KEY, JSON.stringify(next));
  };

  return (
    <>
      <h2>Fulfillment exceptions</h2>
      <div className="so-panel so-filters">
        <label>Reason
          <select data-testid="exception-filter-reason" aria-label="Reason filter" value={reason} onChange={(e) => setReason(e.target.value)}>
            <option value="">All</option>
            {["Address mismatch", "Qty short", "Late pick", "Carrier delay"].map((r) => <option key={r} value={r}>{r}</option>)}
          </select>
        </label>
        <label>Sort
          <select data-testid="exception-sort" aria-label="Sort exceptions" value={sort} onChange={(e) => setSort(e.target.value as any)}>
            <option value="id">By ID</option>
            <option value="age_desc">Oldest first</option>
            <option value="age_asc">Newest first</option>
          </select>
        </label>
        <label>Assign to
          <input data-testid="exception-assignee-input" aria-label="Assignee for Assign buttons" value={assignee} onChange={(e) => setAssignee(e.target.value)} />
        </label>
        <button className="btn" data-testid="exceptions-reset" onClick={() => { sessionStorage.removeItem(KEY); setItems(exceptions as Exception[]); }}>Reset demo</button>
      </div>
      <div className="so-panel">
        <table className="so-table" data-testid="exceptions-table">
          <thead>
            <tr>
              <th>Exception</th><th>Order</th><th>Region</th><th>Reason</th>
              <th className="num"><button data-testid="exceptions-sort-age" aria-label="Sort by age" onClick={() => setSort(sort === "age_desc" ? "age_asc" : "age_desc")}>Age (h) {sort === "age_desc" ? "▼" : sort === "age_asc" ? "▲" : ""}</button></th>
              <th>Assignee</th><th>Status</th><th>Action</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((e) => (
              <tr key={e.exception_id} data-testid={`exception-row-${e.exception_id}`} className={sel === e.exception_id ? "selected" : ""} onClick={() => { setSel(e.exception_id); shareContext({ type: "exception", id: e.exception_id, summary: `${e.reason}, ${e.age_hours}h old, order ${e.order_id}` }); }}>
                <td>{e.exception_id}</td><td>{e.order_id}</td><td>{orders.find((o) => o.order_id === e.order_id)?.region_id}</td><td>{e.reason}</td><td className="num">{e.age_hours}</td>
                <td data-testid={`exception-assignee-${e.exception_id}`}>{e.assignee ?? "Unassigned"}</td>
                <td><span className={`badge ${e.status === "OPEN" ? "warn" : "ok"}`}>{e.status}</span></td>
                <td><button className="link-btn" data-testid={`exception-assign-${e.exception_id}`} data-agent-confirm="true" aria-label={`Assign exception ${e.exception_id}`} onClick={(ev) => { ev.stopPropagation(); assign(e.exception_id); }}>Assign exception</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
