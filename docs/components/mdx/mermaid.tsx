"use client";

import { Suspense, use, useEffect, useId, useState } from "react";
import { useTheme } from "next-themes";
import { mermaidThemeCSS, mermaidThemeVariables } from "@/lib/mermaid-theme";

type MermaidApi = typeof import("mermaid").default;

const cache = new Map<string, Promise<unknown>>();
const mermaidByTheme = new Map<string, Promise<MermaidApi>>();

function cachePromise<T>(key: string, setPromise: () => Promise<T>): Promise<T> {
  const cached = cache.get(key);
  if (cached) return cached as Promise<T>;

  const promise = setPromise().catch((error) => {
    cache.delete(key);
    throw error;
  });
  cache.set(key, promise);
  return promise;
}

function mermaidInitOptions(theme: "light" | "dark") {
  return {
    startOnLoad: false as const,
    securityLevel: "strict" as const,
    fontFamily: "var(--font-sans), ui-sans-serif, system-ui, sans-serif",
    theme: "base" as const,
    themeVariables: mermaidThemeVariables(theme),
    themeCSS: mermaidThemeCSS,
    flowchart: {
      curve: "linear" as const,
      padding: 14,
      htmlLabels: false,
      nodeSpacing: 44,
      rankSpacing: 52,
      wrappingWidth: 148
    }
  };
}

function loadMermaid(theme: string): Promise<MermaidApi> {
  const cached = mermaidByTheme.get(theme);
  if (cached) return cached;

  const mode = theme === "dark" ? "dark" : "light";
  const promise = import("mermaid")
    .then((mod) => {
      const mermaid = mod.default;
      mermaid.initialize(mermaidInitOptions(mode));
      return mermaid;
    })
    .catch((error) => {
      mermaidByTheme.delete(theme);
      throw error;
    });

  mermaidByTheme.set(theme, promise);
  return promise;
}

function DiagramPlaceholder() {
  return (
    <div
      role="img"
      aria-label="Diagram loading"
      aria-busy="true"
      className="mermaid-host min-h-36 animate-pulse bg-fd-muted/40"
    />
  );
}

export function Mermaid({ chart }: { chart: string }) {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  if (!mounted) return <DiagramPlaceholder />;
  return (
    <Suspense fallback={<DiagramPlaceholder />}>
      <MermaidContent chart={chart} />
    </Suspense>
  );
}

function MermaidContent({ chart }: { chart: string }) {
  const id = useId();
  const { resolvedTheme } = useTheme();
  const theme = resolvedTheme === "dark" ? "dark" : "light";
  const mermaid = use(loadMermaid(theme));

  const { svg, bindFunctions } = use(
    cachePromise(`${chart}-${theme}`, () => {
      mermaid.initialize(mermaidInitOptions(theme));
      return mermaid.render(id.replaceAll(":", ""), chart.replaceAll("\\n", "\n"));
    })
  );

  return (
    <div
      className="mermaid-host not-prose"
      role="img"
      aria-label="Flow diagram"
      ref={(container) => {
        if (container) bindFunctions?.(container);
      }}
      dangerouslySetInnerHTML={{ __html: svg }}
    />
  );
}
