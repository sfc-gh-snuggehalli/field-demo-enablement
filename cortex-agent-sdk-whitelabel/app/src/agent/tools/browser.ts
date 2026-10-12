// Single registry for the client-side browser tools. It feeds both the agent request
// (tool_spec, sent as `generic` tools with no tool_resources => client_side_execute)
// and the UI (activity labels). Shared with the server: keep it free of DOM/Vite APIs.

export interface BrowserToolDef {
  name: string;
  description: string;
  input_schema: { type: "object"; properties: Record<string, unknown>; required?: string[] };
  /** Activity label shown in chat. */
  label: (input: Record<string, any>) => string;
  /** Write-style action subject to data-agent-confirm. */
  write?: boolean;
}

const none = { type: "object" as const, properties: {} };
const testid = { testid: { type: "string", description: "data-testid of the target element" } };

export const BROWSER_TOOLS: BrowserToolDef[] = [
  { name: "browser_open_app", description: "Open a registered ACME app in the user's browser sidebar. appId is one of the registered app ids (e.g. 'storeops').", input_schema: { type: "object", properties: { appId: { type: "string" } }, required: ["appId"] }, label: (i) => `Opening ${i.appId}…` },
  { name: "browser_navigate", description: "Navigate the sidebar to a URL. Must be within a registered app (e.g. /apps/storeops/RG-001/orders, /apps/storeops/risk, /apps/storeops/exceptions).", input_schema: { type: "object", properties: { url: { type: "string" } }, required: ["url"] }, label: (i) => `Navigating to ${i.url}` },
  { name: "browser_back", description: "Go back in the sidebar history.", input_schema: none, label: () => "Going back" },
  { name: "browser_forward", description: "Go forward in the sidebar history.", input_schema: none, label: () => "Going forward" },
  { name: "browser_refresh", description: "Reload the sidebar page.", input_schema: none, label: () => "Refreshing page" },
  { name: "browser_get_page", description: "Return url, title and a simplified accessibility tree (role, label, testid, text, value) of the sidebar page. Call this before click/fill/select.", input_schema: none, label: () => "Reading page" },
  { name: "browser_get_text", description: "Return the visible text of the page or of an element (testid or CSS selector).", input_schema: { type: "object", properties: { selector: { type: "string" } } }, label: (i) => `Reading text${i.selector ? ` of ${i.selector}` : ""}` },
  { name: "browser_click", description: "Click an element by data-testid.", input_schema: { type: "object", properties: testid, required: ["testid"] }, label: (i) => `Clicking ${i.testid}`, write: true },
  { name: "browser_fill", description: "Type a value into an input by data-testid.", input_schema: { type: "object", properties: { ...testid, value: { type: "string" } }, required: ["testid", "value"] }, label: (i) => `Filling ${i.testid} = ${i.value}`, write: true },
  { name: "browser_select", description: "Choose an option in a select by data-testid (value is the option value, e.g. FAILED).", input_schema: { type: "object", properties: { ...testid, value: { type: "string" } }, required: ["testid", "value"] }, label: (i) => `Filtering ${String(i.testid).replace(/^.*-filter-/, "")} = ${i.value}`, write: true },
  { name: "browser_get_table", description: "Return the rows of a table (by data-testid) as JSON objects keyed by column header.", input_schema: { type: "object", properties: testid, required: ["testid"] }, label: (i) => `Reading table ${i.testid}` },
  { name: "browser_highlight", description: "Visually outline an element (by data-testid) so the user sees it.", input_schema: { type: "object", properties: testid, required: ["testid"] }, label: (i) => `Highlighting ${i.testid}` },
  { name: "browser_screenshot", description: "Optional: return a PNG data URL of the sidebar app view.", input_schema: none, label: () => "Capturing screenshot" },
];

export const BROWSER_TOOL_NAMES = new Set(BROWSER_TOOLS.map((t) => t.name));

/** Agent API tool specs: `generic` tools with no tool_resources run client-side. */
export function browserToolSpecs() {
  return BROWSER_TOOLS.map((t) => ({ tool_spec: { type: "generic", name: t.name, description: t.description, input_schema: t.input_schema } }));
}

export function browserToolLabel(name: string, input: Record<string, any>): string {
  const t = BROWSER_TOOLS.find((x) => x.name === name);
  return t ? t.label(input ?? {}) : name;
}

/** Guidance appended to the orchestration instructions whenever the browser tools are sent. */
export function browserToolGuidance(businessDate: string): string {
  return `

## Browser sidebar (client-side tools)
The user has an ACME Store Ops sidebar you can drive with the browser_* tools. "Today" in the app is the data date ${businessDate} (the latest order date); use it for "today" in SQL and in the app.
When the user says show, open, display, filter, assign or act, do it in the app as well as answering:
- Regions /apps/storeops (region-card-<RG id>); region inventory /apps/storeops/<RG id> (inventory-table)
- Order blotter /apps/storeops/<RG id>/orders: selects order-filter-status (NEW|PICKED|SHIPPED|FAILED|BACKORDERED), order-filter-channel, order-filter-date ("today" | "7d"); table orders-table
- Exceptions /apps/storeops/exceptions: select exception-sort ("age_desc" = oldest first), exception-filter-reason; buttons exception-assign-<EX id> assign to the user; table exceptions-table
- Risk /apps/storeops/risk: rows risk-row-<RG id>
Region ids: RG-001 West, RG-002 Central, RG-003 South, RG-004 Northeast. Call browser_get_page before clicking, filling or selecting; read results with browser_get_table and summarize them.`;
}
