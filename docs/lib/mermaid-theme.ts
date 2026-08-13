/**
 * Mermaid — Signal Graphite.
 * Card nodes, ink type, teal stroke. No mint blobs, no stock “default” look.
 */

export type MermaidThemeMode = "light" | "dark";

function cssVar(name: string, fallback: string): string {
  if (typeof window === "undefined") return fallback;
  const value = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  return value || fallback;
}

export function mermaidThemeVariables(mode: MermaidThemeMode) {
  const isDark = mode === "dark";
  const card = cssVar("--color-fd-card", isDark ? "#121a2b" : "#fafcfd");
  const ink = cssVar("--color-fd-foreground", isDark ? "#e8eef4" : "#0b1220");
  const muted = cssVar("--color-fd-muted", isDark ? "#151f30" : "#e6eef2");
  const mutedFg = cssVar("--color-fd-muted-foreground", isDark ? "#94a8b8" : "#4a5d6a");
  const border = cssVar("--color-fd-border", isDark ? "#243247" : "#c5d4de");
  const signal = cssVar("--color-fd-primary", isDark ? "#2dd4bf" : "#0f766e");
  const canvas = cssVar("--color-fd-background", isDark ? "#0b1220" : "#f3f6f8");

  return {
    darkMode: isDark,
    background: "transparent",
    fontFamily: "var(--font-sans), ui-sans-serif, system-ui, sans-serif",
    fontSize: "13px",

    /* Nodes = site cards, not pastel chips */
    primaryColor: card,
    primaryTextColor: ink,
    primaryBorderColor: signal,
    secondaryColor: muted,
    secondaryTextColor: ink,
    secondaryBorderColor: border,
    tertiaryColor: canvas,
    tertiaryTextColor: mutedFg,
    tertiaryBorderColor: border,

    lineColor: mutedFg,
    textColor: ink,
    mainBkg: card,
    nodeBorder: signal,
    clusterBkg: muted,
    clusterBorder: border,
    titleColor: mutedFg,
    edgeLabelBackground: canvas,
    nodeTextColor: ink,

    noteBkgColor: muted,
    noteTextColor: ink,
    noteBorderColor: border,

    actorBkg: card,
    actorBorder: signal,
    actorTextColor: ink,
    actorLineColor: mutedFg,

    labelBoxBkgColor: canvas,
    labelBoxBorderColor: border,
    labelTextColor: mutedFg,

    errorBkgColor: muted,
    errorTextColor: ink
  };
}

/** Injected into the SVG; keep selectors mermaid-11-safe. */
export const mermaidThemeCSS = `
  :root { --mermaid-font: var(--font-sans), ui-sans-serif, system-ui, sans-serif; }

  .node rect,
  .node polygon,
  .node circle,
  .node ellipse,
  .node path {
    stroke-width: 1.35px !important;
    filter: none !important;
  }

  .node .label,
  .nodeLabel,
  .label,
  .label text {
    font-family: var(--mermaid-font) !important;
    font-size: 13px !important;
    font-weight: 500 !important;
    letter-spacing: -0.01em;
  }

  .edgeLabel,
  .edgeLabel span,
  .edgeLabel p {
    font-family: var(--font-mono), ui-monospace, monospace !important;
    font-size: 11px !important;
    font-weight: 500 !important;
    background: transparent !important;
  }

  .edgeLabel rect {
    fill: transparent !important;
    stroke: none !important;
  }

  .cluster rect {
    rx: 12px !important;
    ry: 12px !important;
    stroke-width: 1px !important;
    stroke-dasharray: 0 !important;
  }

  .cluster-label,
  .cluster span,
  .cluster text {
    font-family: var(--font-mono), ui-monospace, monospace !important;
    font-size: 11px !important;
    font-weight: 600 !important;
    letter-spacing: 0.04em;
    text-transform: lowercase;
  }

  .flowchart-link,
  .edge-thickness-normal {
    stroke-width: 1.25px !important;
    fill: none !important;
  }

  marker path,
  .marker,
  .arrowheadPath {
    stroke-width: 0 !important;
  }
`;
