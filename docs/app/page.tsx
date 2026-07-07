import Link from "next/link";

const sections = [
  {
    href: "/docs/fresh-mac",
    title: "Fresh Mac",
    description: "Bootstrap a new Apple Silicon Mac with dry-run first apply."
  },
  {
    href: "/docs/ssot-workflow",
    title: "SSOT workflow",
    description: "Inventory the live rig, curate, and promote into tracked manifests."
  },
  {
    href: "/docs/validation",
    title: "Validation",
    description: "just check, just ci, and focused namespace checks."
  },
  {
    href: "/docs/packages",
    title: "Packages",
    description: "Curated Brewfile groups and promotion policy."
  },
  {
    href: "/docs/ai-harness",
    title: "AI harness",
    description: "Configs live in wyattowalsh/agents; env vars documented here."
  }
] as const;

export default function HomePage() {
  return (
    <main
      style={{
        maxWidth: 960,
        margin: "0 auto",
        padding: "4rem 1.5rem 5rem",
        fontFamily: "system-ui, sans-serif",
        lineHeight: 1.6
      }}
    >
      <p
        style={{
          fontSize: "0.875rem",
          fontWeight: 600,
          letterSpacing: "0.04em",
          textTransform: "uppercase",
          color: "#64748b",
          marginBottom: "0.75rem"
        }}
      >
        Internal · w4w-mbp SSOT
      </p>
      <h1 style={{ fontSize: "2.25rem", fontWeight: 700, margin: "0 0 1rem", letterSpacing: "-0.02em" }}>
        Dotfiles operator docs
      </h1>
      <p style={{ fontSize: "1.125rem", color: "#475569", maxWidth: 640, margin: "0 0 2.5rem" }}>
        Runbooks, validation commands, and manifest policy for the full-rig macOS bootstrap. Tracked
        desired state only — not live secrets or inventory dumps.
      </p>
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fill, minmax(260px, 1fr))",
          gap: "1rem",
          marginBottom: "2.5rem"
        }}
      >
        {sections.map((section) => (
          <Link
            key={section.href}
            href={section.href}
            style={{
              display: "block",
              padding: "1.25rem",
              borderRadius: "0.75rem",
              border: "1px solid #e2e8f0",
              textDecoration: "none",
              color: "inherit",
              background: "#fafafa",
              transition: "border-color 0.15s ease"
            }}
          >
            <strong style={{ display: "block", marginBottom: "0.35rem", fontSize: "1rem" }}>
              {section.title}
            </strong>
            <span style={{ fontSize: "0.9rem", color: "#64748b" }}>{section.description}</span>
          </Link>
        ))}
      </div>
      <Link
        href="/docs"
        style={{
          display: "inline-block",
          padding: "0.65rem 1.25rem",
          borderRadius: "0.5rem",
          background: "#0f172a",
          color: "#f8fafc",
          textDecoration: "none",
          fontWeight: 600,
          fontSize: "0.95rem"
        }}
      >
        Open full documentation →
      </Link>
    </main>
  );
}
