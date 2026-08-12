/**
 * Mermaid theme — aligned with DESIGN.md "Signal Graphite".
 */

export type MermaidThemeMode = "light" | "dark";

function cssVar(name: string, fallback: string): string {
  if (typeof window === "undefined") return fallback;
  const value = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  return value || fallback;
}

export function mermaidThemeVariables(mode: MermaidThemeMode) {
  const isDark = mode === "dark";
  return {
    darkMode: isDark,
    background: cssVar("--mermaid-bg", isDark ? "#0b1220" : "#f3f6f8"),
    primaryColor: cssVar("--mermaid-primary", isDark ? "#164e63" : "#ccfbf1"),
    primaryTextColor: cssVar("--mermaid-primary-text", isDark ? "#e8eef4" : "#0b1220"),
    primaryBorderColor: cssVar("--mermaid-primary-border", isDark ? "#2dd4bf" : "#0f766e"),
    secondaryColor: cssVar("--mermaid-secondary", isDark ? "#1a2740" : "#e0ebee"),
    tertiaryColor: cssVar("--mermaid-tertiary", isDark ? "#121a2b" : "#fafcfd"),
    lineColor: cssVar("--mermaid-line", isDark ? "#94a8b8" : "#4a5d6a"),
    textColor: cssVar("--mermaid-text", isDark ? "#e8eef4" : "#0b1220"),
    mainBkg: cssVar("--mermaid-primary", isDark ? "#164e63" : "#ccfbf1"),
    nodeBorder: cssVar("--mermaid-primary-border", isDark ? "#2dd4bf" : "#0f766e"),
    clusterBkg: cssVar("--mermaid-cluster", isDark ? "#151f30" : "#e6eef2"),
    clusterBorder: cssVar("--mermaid-primary-border", isDark ? "#2dd4bf" : "#0f766e"),
    titleColor: cssVar("--mermaid-text", isDark ? "#e8eef4" : "#0b1220"),
    edgeLabelBackground: cssVar("--mermaid-edge-label-bg", isDark ? "#121a2b" : "#fafcfd"),
    fontFamily: "ui-sans-serif, system-ui, sans-serif",
    fontSize: "14px",
    noteBkgColor: cssVar("--mermaid-secondary", isDark ? "#1a2740" : "#e0ebee"),
    noteTextColor: cssVar("--mermaid-text", isDark ? "#e8eef4" : "#0b1220"),
    noteBorderColor: cssVar("--mermaid-line", isDark ? "#94a8b8" : "#4a5d6a")
  };
}

export const mermaidThemeCSS = `
  .nodeLabel, .edgeLabel, .label { font-family: ui-sans-serif, system-ui, sans-serif; }
  .node rect, .node polygon, .node circle { stroke-width: 1.5px; }
  .edge-pattern-solid { stroke-width: 1.5px; }
  .cluster rect { rx: 10px; ry: 10px; stroke-width: 1.25px; }
  .flowchart-link { stroke-width: 1.5px; }
`;
