import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";
import { BookOpen } from "@phosphor-icons/react/dist/ssr";
import { SiteWordmark } from "@/components/site-wordmark";
import { SectionIcon } from "@/lib/icons";

/**
 * Main operator pages + this repo on GitHub.
 * No external agents link — that lives in the AI runbook.
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
      },
      {
        type: "main",
        text: "mac",
        url: "/docs/fresh-mac",
        active: "url",
        icon: <SectionIcon slug="fresh-mac" className="size-4" />
      },
      {
        type: "main",
        text: "linux",
        url: "/docs/linux-setup",
        active: "url",
        icon: <SectionIcon slug="linux-setup" className="size-4" />
      },
      {
        type: "main",
        text: "promote",
        url: "/docs/ssot-workflow",
        active: "url",
        icon: <SectionIcon slug="ssot-workflow" className="size-4" />
      },
      {
        type: "main",
        text: "check",
        url: "/docs/validation",
        active: "url",
        icon: <SectionIcon slug="validation" className="size-4" />
      }
    ]
  };
}
