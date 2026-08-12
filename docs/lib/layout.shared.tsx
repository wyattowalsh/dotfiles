import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";
import { BrandMark, RunbooksMark } from "@/lib/icons";

export function baseOptions(): BaseLayoutProps {
  return {
    nav: {
      title: (
        <span className="inline-flex items-center gap-2 font-semibold tracking-tight">
          <span className="icon-badge size-7">
            <BrandMark className="size-3.5" />
          </span>
          Dotfiles
        </span>
      )
    },
    links: [
      {
        text: "Runbooks",
        url: "/docs",
        active: "nested-url",
        icon: <RunbooksMark className="size-4" />
      }
    ]
  };
}
