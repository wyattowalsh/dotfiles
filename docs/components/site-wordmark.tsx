import Link from "next/link";

/**
 * Brand mark: lowercase "dotfiles" — mono, gradient, subtle motion.
 * Respects prefers-reduced-motion via CSS.
 */
export function SiteWordmark({ href = "/" }: { href?: string }) {
  return (
    <Link href={href} className="site-wordmark group" aria-label="dotfiles home">
      <span className="site-wordmark__glyph" aria-hidden>
        <span className="site-wordmark__pulse" />
      </span>
      <span className="site-wordmark__text">dotfiles</span>
    </Link>
  );
}
