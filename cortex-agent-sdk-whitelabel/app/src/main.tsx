import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import AppRoot from "./AppRoot";
import { setDefaultBrand } from "./brand/brand.config";
import "./styles.css";

setDefaultBrand(import.meta.env.VITE_BRAND);

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <AppRoot />
  </StrictMode>,
);
