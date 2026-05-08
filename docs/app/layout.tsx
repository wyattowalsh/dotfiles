import type { ReactNode } from "react";
import { RootProvider } from "fumadocs-ui/provider/next";
import "fumadocs-ui/style.css";

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        <RootProvider>{children}</RootProvider>
      </body>
    </html>
  );
}
