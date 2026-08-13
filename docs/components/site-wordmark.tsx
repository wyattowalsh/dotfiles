import Link from "next/link";

/**
 * Brand: hex icon + lowercase mono wordmark.
 */
export function SiteWordmark({ href = "/" }: { href?: string }) {
  return (
    <Link href={href} className="site-wordmark group" aria-label="dotfiles home">
      <span className="site-wordmark__glyph" aria-hidden>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/icon.svg" alt="" width={22} height={22} className="site-wordmark__icon" />
      </span>
      <span className="site-wordmark__text">dotfiles</span>
    </Link>
  );
}
