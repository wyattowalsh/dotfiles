import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";

export function baseOptions(): BaseLayoutProps {
  return {
    nav: {
      title: "Dotfiles"
    },
    links: [
      {
        text: "Runbooks",
        url: "/docs",
        active: "nested-url"
      }
    ]
  };
}
