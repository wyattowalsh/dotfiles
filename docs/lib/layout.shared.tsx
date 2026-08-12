import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";
import { BookOpen } from "@phosphor-icons/react/dist/ssr";
import { SiteWordmark } from "@/components/site-wordmark";

/**
 * Minimal chrome: wordmark · docs · GitHub.
 */
export function baseOptions(): BaseLayoutProps {
  return {
    githubUrl: "https://github.com/wyattowalsh/dotfiles",
    nav: {
      title: <SiteWordmark />,
      url: "/",
      transparentMode: "top"
    },
    links: [
      {
        type: "main",
        text: "docs",
        url: "/docs",
        active: "nested-url",
        icon: <BookOpen className="size-4" aria-hidden weight="duotone" />
      }
    ]
  };
}
