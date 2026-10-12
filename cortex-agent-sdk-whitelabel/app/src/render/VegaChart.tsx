// Lazy chunk: vega + vega-lite + vega-embed. Full chat-column width (autosize fit-x,
// re-rendered by ResizeObserver), themed from the brand palette, no external data URLs.
import { useEffect, useRef, useState } from "react";
import embed, { type Result } from "vega-embed";
// AST interpreter instead of `new Function`: the app CSP has no 'unsafe-eval'.
import { expressionInterpreter } from "vega-interpreter";
import type { BrandConfig } from "../brand/brand.config";
import { currentPalette } from "../brand/theme";
import { download } from "./DataTable";

function hasExternalData(node: unknown): boolean {
  if (!node || typeof node !== "object") return false;
  if (Array.isArray(node)) return node.some(hasExternalData);
  for (const [k, v] of Object.entries(node)) {
    if (k === "url" && typeof v === "string") return true;
    if (hasExternalData(v)) return true;
  }
  return false;
}

export default function VegaChart({ spec, brand, dark }: { spec: string; brand: BrandConfig; dark: boolean }) {
  const host = useRef<HTMLDivElement>(null);
  const view = useRef<Result | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let parsed: any;
    try {
      parsed = typeof spec === "string" ? JSON.parse(spec) : spec;
      if (hasExternalData(parsed)) throw new Error("External data URLs are blocked");
    } catch (e: any) {
      setError(e.message);
      return;
    }
    const p = currentPalette(brand);
    const range = [p.accent, p.primary, p.accentLight, p.success, p.warning, p.accentLight2, p.textMuted];
    const el = host.current!;
    let disposed = false;
    const render = async () => {
      view.current?.finalize();
      const width = Math.max(240, el.clientWidth - 8);
      const full = { ...parsed, width, autosize: { type: "fit-x", contains: "padding" }, background: "transparent" };
      try {
        const r = await embed(el, full, {
          actions: false,
          renderer: "svg",
          ast: true,
          expr: expressionInterpreter as any,
          loader: { load: () => Promise.reject(new Error("External data is blocked")), sanitize: () => Promise.reject(new Error("External data is blocked")) } as any,
          config: {
            font: brand.font,
            range: { category: range },
            axis: { labelColor: p.textMuted, titleColor: p.text, gridColor: p.border, domainColor: p.border, tickColor: p.border },
            legend: { labelColor: p.textMuted, titleColor: p.text },
            title: { color: p.text, font: brand.font },
            view: { stroke: "transparent" },
            mark: { color: p.accent },
          },
        });
        if (disposed) r.finalize();
        else view.current = r;
        setError(null);
      } catch (e: any) {
        setError(e.message ?? "Invalid chart");
      }
    };
    render();
    let w = el.clientWidth;
    const ro = new ResizeObserver(() => {
      if (Math.abs(el.clientWidth - w) > 4) {
        w = el.clientWidth;
        render();
      }
    });
    ro.observe(el);
    return () => {
      disposed = true;
      ro.disconnect();
      view.current?.finalize();
    };
  }, [spec, brand, dark]);

  const save = async (type: "png" | "svg") => {
    if (!view.current) return;
    const url = await view.current.view.toImageURL(type, 2);
    const blob = await (await fetch(url)).blob();
    download(`acme-chart.${type}`, blob);
  };

  return (
    <div className="chart-card" data-testid="chart">
      <div className="table-head">
        <span className="table-title">Chart</span>
        <span />
        <button className="link-btn" onClick={() => save("png")}>Download PNG</button>
        <button className="link-btn" onClick={() => save("svg")}>Download SVG</button>
      </div>
      {error ? <div className="chart-error" role="alert">Chart could not be rendered: {error}</div> : null}
      <div ref={host} className="chart-host" />
    </div>
  );
}
