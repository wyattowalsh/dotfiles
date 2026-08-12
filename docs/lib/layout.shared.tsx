import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";
import { BookOpen, Robot } from "@phosphor-icons/react/dist/ssr";
import { SiteWordmark } from "@/components/site-wordmark";

const duo = { weight: "duotone" as const };

/**
 * Nav only for unique destinations — not extra docs pages already in the sidebar.
 * - docs → this site’s runbooks
 * - agents → wyattowalsh/agents (AI/MCP SSOT, not this repo)
 * - GitHub → wyattowalsh/dotfiles (source)
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
        icon: <BookOpen className="size-4" aria-hidden {...duo} />
      },
      {
        type: "main",
        text: "agents",
        url: "https://github.com/wyattowalsh/agents",
        external: true,
        icon: <Robot className="size-4" aria-hidden {...duo} />
      }
    ]
  };
}
