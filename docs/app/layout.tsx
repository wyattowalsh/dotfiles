import type { ReactNode } from "react";
import { Provider } from "@/components/provider";
import "./global.css";

export const metadata = {
  title: {
    default: "Dotfiles operator docs",
    template: "%s | Dotfiles"
  },
  description:
    "Operator runbooks for the full-rig macOS bootstrap, SSOT workflow, and validation."
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className="flex min-h-screen flex-col font-sans antialiased">
        <Provider>{children}</Provider>
      </body>
    </html>
  );
}
