import type { ReactNode } from "react";
import { Provider } from "@/components/provider";
import "fumadocs-ui/css/neutral.css";
import "fumadocs-ui/css/preset.css";

export const metadata = {
  title: {
    default: "Dotfiles operator docs",
    template: "%s | Dotfiles"
  },
  description:
    "Internal runbooks for the full-rig macOS bootstrap, SSOT workflow, and validation."
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className="flex min-h-screen flex-col">
        <Provider>{children}</Provider>
      </body>
    </html>
  );
}
