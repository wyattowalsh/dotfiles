import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";
import {
  BookOpen,
  Desktop,
  MapTrifold,
  Robot,
  RocketLaunch,
  ShieldCheck,
  Terminal
} from "@phosphor-icons/react/dist/ssr";
import { SiteWordmark } from "@/components/site-wordmark";

const duo = { weight: "duotone" as const };

/**
 * Nav: docs · bootstrap (menu) · check · map · agents · GitHub.
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
        type: "menu",
        text: "bootstrap",
        icon: <RocketLaunch className="size-4" aria-hidden {...duo} />,
        items: [
          {
            text: "mac",
            url: "/docs/fresh-mac",
            description: "just bootstrap --dry-run",
            icon: <Desktop className="size-4" aria-hidden {...duo} />
          },
          {
            text: "linux",
            url: "/docs/linux-setup",
            description: "./setup.sh --dry-run",
            icon: <Terminal className="size-4" aria-hidden {...duo} />
          },
          {
            text: "promote",
            url: "/docs/ssot-workflow",
            description: "just inventory-redacted",
            icon: <RocketLaunch className="size-4" aria-hidden {...duo} />
          }
        ]
      },
      {
        type: "main",
        text: "check",
        url: "/docs/validation",
        active: "url",
        icon: <ShieldCheck className="size-4" aria-hidden {...duo} />
      },
      {
        type: "main",
        text: "map",
        url: "/docs/domain-map",
        active: "url",
        icon: <MapTrifold className="size-4" aria-hidden {...duo} />
      },
      {
        type: "icon",
        text: "agents",
        label: "wyattowalsh/agents",
        url: "https://github.com/wyattowalsh/agents",
        external: true,
        icon: <Robot className="size-4" aria-hidden {...duo} />
      }
    ]
  };
}
