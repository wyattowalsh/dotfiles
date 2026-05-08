import Link from "next/link";

export default function HomePage() {
  return (
    <main style={{ maxWidth: 920, margin: "0 auto", padding: "4rem 1.5rem" }}>
      <h1>Dotfiles Internal Docs</h1>
      <p>
        Operational runbooks, package inventory, AI/MCP configuration, and
        validation guidance for the full-rig bootstrap.
      </p>
      <Link href="/docs">Open docs</Link>
    </main>
  );
}

