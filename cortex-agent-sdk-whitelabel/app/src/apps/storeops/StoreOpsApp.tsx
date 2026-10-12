// Lazy chunk: ACME Store Ops simulator at /apps/storeops/*. react-router lives only here.
import { useEffect, useRef, type RefObject } from "react";
import { BrowserRouter, MemoryRouter, NavLink, Route, Routes, useLocation, useNavigate } from "react-router-dom";
import { getBrand } from "../../brand/brand.config";
import { ThinkingLogo } from "../../brand/Logo";
import { applyTheme } from "../../brand/theme";
import { getSettings } from "../../settings/settings";
import { startAgentBridge } from "./agentBridge";
import { BUSINESS_DATE } from "./data";
import { ExceptionsPage } from "./pages/Exceptions";
import { OrdersPage } from "./pages/Orders";
import { RegionDetailPage, RegionsPage } from "./pages/Regions";
import { RiskPage } from "./pages/Risk";

const BASE = "/apps/storeops";
const strip = (url: string) => url.replace(/^\/apps\/storeops/, "") || "/";

function Bridge({ rootRef }: { rootRef?: RefObject<HTMLDivElement | null> }) {
  const navigate = useNavigate();
  const loc = useLocation();
  const locRef = useRef(loc);
  locRef.current = loc;
  useEffect(
    () =>
      startAgentBridge({
        navigate: (url) => navigate(strip(url)),
        history: (dir) => (dir === "back" ? navigate(-1) : navigate(1)),
        inline: rootRef?.current ? { root: rootRef.current, url: () => BASE + (locRef.current.pathname === "/" ? "" : locRef.current.pathname) + locRef.current.search } : undefined,
      }),
    [navigate, rootRef],
  );
  return null;
}

function Shell({ inline }: { inline?: boolean }) {
  const loc = useLocation();
  useEffect(() => void (!inline && window.scrollTo(0, 0)), [loc.pathname, inline]);
  const brand = getBrand();
  return (
    <div className="so">
      <header className="so-head">
        <ThinkingLogo brand={brand} state="idle" size={24} />
        <span className="so-title">{brand.companyName.split(" ")[0]} Store Ops</span>
        <nav aria-label="Store Ops">
          <NavLink to="/" end data-testid="nav-regions">Regions</NavLink>
          <NavLink to="/exceptions" data-testid="nav-exceptions">Exceptions</NavLink>
          <NavLink to="/risk" data-testid="nav-risk">Risk</NavLink>
        </nav>
        <span className="spacer" />
        <span className="muted small" data-testid="business-date">Business date (today): {BUSINESS_DATE}</span>
      </header>
      <main className="so-main">
        <Routes>
          <Route path="/" element={<RegionsPage />} />
          <Route path="/exceptions" element={<ExceptionsPage />} />
          <Route path="/risk" element={<RiskPage />} />
          <Route path="/:regionId" element={<RegionDetailPage />} />
          <Route path="/:regionId/orders" element={<OrdersPage />} />
        </Routes>
      </main>
    </div>
  );
}

/** Rendered inside the chat's browser sidebar: same document, in-memory router, no iframe. */
export function InlineStoreOps({ initialUrl }: { initialUrl: string }) {
  const rootRef = useRef<HTMLDivElement>(null);
  return (
    <div ref={rootRef} className="so-inline" data-testid="browser-frame">
      <MemoryRouter initialEntries={[strip(new URL(initialUrl, location.origin).pathname) + new URL(initialUrl, location.origin).search]}>
        <Bridge rootRef={rootRef} />
        <Shell inline />
      </MemoryRouter>
    </div>
  );
}

export default function StoreOpsApp() {
  useEffect(() => void applyTheme(getBrand(), getSettings().theme), []);
  return (
    <BrowserRouter basename="/apps/storeops">
      <Bridge />
      <Shell />
    </BrowserRouter>
  );
}
