import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";
import { BookOpen, ShieldCheck, RocketLaunch } from "@phosphor-icons/react/dist/ssr";
import { SiteWordmark } from "@/components/site-wordmark";

const duo = { weight: "duotone" as const };

/**
 * Shared nav for HomeLayout + DocsLayout.
 * githubUrl → native GitHub icon in fumadocs chrome.
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
        text: "Runbooks",
        url: "/docs",
        active: "nested-url",
        icon: <BookOpen className="size-4" aria-hidden {...duo} />
      },
      {
        type: "main",
        text: "Start",
        url: "/docs/fresh-mac",
        active: "url",
        icon: <RocketLaunch className="size-4" aria-hidden {...duo} />
      },
      {
        type: "main",
        text: "Validate",
        url: "/docs/validation",
        active: "url",
        icon: <ShieldCheck className="size-4" aria-hidden {...duo} />
      }
    ]
  };
}
