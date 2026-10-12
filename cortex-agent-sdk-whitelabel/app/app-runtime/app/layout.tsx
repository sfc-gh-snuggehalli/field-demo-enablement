import type { Metadata } from "next";
import type React from "react";
import "../acme/src/styles.css";

export const metadata: Metadata = {
  title: "ACME Assist",
  description: "ACME Retail store-operations assistant on Snowflake Cortex Agents",
  icons: { icon: "/icon.svg" },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <head>
        <link rel="icon" type="image/svg+xml" href="/icon.svg" id="brand-favicon" />
      </head>
      <body>
        <div id="root">{children}</div>
      </body>
    </html>
  );
}
