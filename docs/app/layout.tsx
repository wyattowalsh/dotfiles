import type { ReactNode } from "react";
import { DM_Sans, JetBrains_Mono } from "next/font/google";
import { Provider } from "@/components/provider";
import "./global.css";

const sans = DM_Sans({
  subsets: ["latin"],
  variable: "--font-sans-loaded",
  display: "swap"
});

const mono = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-mono-loaded",
  display: "swap"
});

export const metadata = {
  title: {
    default: "dotfiles",
    template: "%s · dotfiles"
  },
  description:
    "Operator runbooks for the full-rig macOS bootstrap, SSOT workflow, and validation."
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning className={`${sans.variable} ${mono.variable}`}>
      <body className="flex min-h-screen flex-col font-sans antialiased">
        <div className="site-layer site-layer--grid" aria-hidden />
        <div className="site-layer site-layer--glow" aria-hidden />
        <Provider>{children}</Provider>
      </body>
    </html>
  );
}
