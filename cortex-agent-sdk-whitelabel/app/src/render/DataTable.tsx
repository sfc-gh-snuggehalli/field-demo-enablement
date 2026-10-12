import type { ReactNode } from "react";

export function toCsv(columns: string[], rows: unknown[][]): string {
  const esc = (v: unknown) => {
    const s = v === null || v === undefined ? "" : String(v);
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return [columns.map(esc).join(","), ...rows.map((r) => r.map(esc).join(","))].join("\n");
}

export function download(name: string, data: string | Blob, type = "text/csv") {
  const blob = typeof data === "string" ? new Blob([data], { type }) : data;
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

const isNum = (v: unknown, type?: string) => (type ? /fixed|real|number|float|int|decimal/i.test(type) : false) || (typeof v === "number" || (typeof v === "string" && v.trim() !== "" && !isNaN(Number(v))));

/** Scrollable result table: sticky header, all rows, row count, right-aligned numbers, CSV. */
export function DataTable({ columns, rows, title, testid }: { columns: { name: string; type?: string }[]; rows: unknown[][]; title?: string; testid?: string }) {
  const numeric = columns.map((c, i) => rows.length > 0 && rows.slice(0, 20).every((r) => r[i] === null || isNum(r[i], c.type)));
  return (
    <TableFrame title={title} count={rows.length} onCsv={() => download(`${(title || "acme-table").replace(/\W+/g, "-")}.csv`, toCsv(columns.map((c) => c.name), rows))} testid={testid}>
      <table>
        <thead>
          <tr>{columns.map((c, i) => <th key={i} className={numeric[i] ? "num" : ""}>{c.name}</th>)}</tr>
        </thead>
        <tbody>
          {rows.map((r, ri) => (
            <tr key={ri}>{r.map((v, ci) => <td key={ci} className={numeric[ci] ? "num" : ""}>{v === null ? "—" : String(v)}</td>)}</tr>
          ))}
        </tbody>
      </table>
    </TableFrame>
  );
}

export function TableFrame({ title, count, onCsv, children, testid }: { title?: string; count: number; onCsv: () => void; children: ReactNode; testid?: string }) {
  return (
    <div className="table-card" data-testid={testid}>
      <div className="table-head">
        <span className="table-title">{title ?? "Result"}</span>
        <span className="muted">{count} row{count === 1 ? "" : "s"}</span>
        <button className="link-btn" onClick={onCsv} aria-label="Download CSV">Download CSV</button>
      </div>
      <div className="table-scroll">{children}</div>
    </div>
  );
}
