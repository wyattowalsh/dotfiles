"use client";

import { Suspense, use, useEffect, useId, useState } from "react";
import { useTheme } from "next-themes";

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

function loadMermaid(theme: string): Promise<MermaidApi> {
  const cached = mermaidByTheme.get(theme);
  if (cached) return cached;

  const promise = import("mermaid")
    .then((mod) => {
      const mermaid = mod.default;
      mermaid.initialize({
        startOnLoad: false,
        securityLevel: "strict",
        fontFamily: "inherit",
        themeCSS: "margin: 1.5rem auto 0;",
        theme: theme === "dark" ? "dark" : "default"
      });
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
      className="my-6 min-h-32 rounded-lg border border-fd-border bg-fd-muted/30"
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
      return mermaid.render(id.replaceAll(":", ""), chart.replaceAll("\\n", "\n"));
    })
  );

  return (
    <div
      ref={(container) => {
        if (container) bindFunctions?.(container);
      }}
      dangerouslySetInnerHTML={{ __html: svg }}
    />
  );
}
