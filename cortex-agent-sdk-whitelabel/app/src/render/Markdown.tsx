// Lazy chunk: react-markdown + remark-gfm. Links to registered ACME apps open in the
// browser sidebar; markdown tables get the same scroll/CSV wrapper as result sets.
import { Children, isValidElement, type ReactNode } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { isAllowedAppUrl } from "../config/app.config";
import { browserHost } from "../browser/host";
import { TableFrame, download, toCsv } from "./DataTable";

function textOf(node: ReactNode): string {
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(textOf).join("");
  if (isValidElement(node)) return textOf((node.props as any).children);
  return "";
}

function rowsOf(children: ReactNode): string[][] {
  const rows: string[][] = [];
  const walk = (n: ReactNode) =>
    Children.forEach(n, (c) => {
      if (!isValidElement(c)) return;
      const props = c.props as any;
      if (c.type === "tr") rows.push(Children.toArray(props.children).filter(isValidElement).map((cell) => textOf((cell.props as any).children)));
      else walk(props.children);
    });
  walk(children);
  return rows;
}

export default function Markdown({ text }: { text: string }) {
  return (
    <div className="md">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          a({ href, children }) {
            const inApp = href && isAllowedAppUrl(href, location.origin);
            return (
              <a
                href={href}
                target={inApp ? undefined : "_blank"}
                rel="noreferrer"
                onClick={(e) => {
                  if (!inApp) return;
                  e.preventDefault();
                  browserHost.navigate(href!).catch(() => undefined);
                }}
              >
                {children}
              </a>
            );
          },
          table({ children }) {
            const rows = rowsOf(children);
            return (
              <TableFrame title="Table" count={Math.max(0, rows.length - 1)} onCsv={() => download("acme-table.csv", toCsv(rows[0] ?? [], rows.slice(1)))}>
                <table>{children}</table>
              </TableFrame>
            );
          },
        }}
      >
        {text}
      </ReactMarkdown>
    </div>
  );
}
