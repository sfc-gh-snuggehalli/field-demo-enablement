"use client";
// One UI: the shared AppRoot (chat or Store Ops simulator by pathname), client-only.
import dynamic from "next/dynamic";
import { setDefaultBrand } from "../../acme/src/brand/brand.config";

setDefaultBrand(process.env.NEXT_PUBLIC_BRAND);

const AppRoot = dynamic(() => import("../../acme/src/AppRoot"), { ssr: false });

export default function Page() {
  return <AppRoot />;
}
