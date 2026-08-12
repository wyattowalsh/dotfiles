import Link from "next/link";
import { HomeLayout } from "fumadocs-ui/layouts/home";
import { baseOptions } from "@/lib/layout.shared";
import { docSections, groupLabels, groupOrder } from "@/lib/sections";
import { CtaArrow, GroupIcon, SectionIcon } from "@/lib/icons";

const paths = [
  { href: "/docs/fresh-mac", slug: "fresh-mac", label: "mac", cmd: "just bootstrap --dry-run" },
  { href: "/docs/linux-setup", slug: "linux-setup", label: "linux", cmd: "./setup.sh --dry-run" },
  { href: "/docs/ssot-workflow", slug: "ssot-workflow", label: "promote", cmd: "just inventory-redacted" },
  { href: "/docs/validation", slug: "validation", label: "check", cmd: "just check" }
] as const;

export default function HomePage() {
  return (
    <HomeLayout {...baseOptions()} className="relative">
      <div className="home-shell mx-auto w-full max-w-3xl px-4 py-10 sm:px-6 sm:py-14">
        <header className="mb-10">
          <h1 className="home-kicker mb-2 text-fd-primary">dotfiles</h1>
          <p className="text-lg font-medium tracking-tight text-fd-foreground sm:text-xl">
            bootstrap · promote · validate
          </p>
        </header>

        <nav className="path-strip mb-12" aria-label="Primary paths">
          {paths.map((p) => (
            <Link key={p.href} href={p.href} className="path-chip group">
              <span className="path-chip__top">
                <SectionIcon slug={p.slug} className="size-3.5 text-fd-primary" />
                <span className="path-chip__label">{p.label}</span>
              </span>
              <code className="path-chip__cmd">{p.cmd}</code>
              <CtaArrow className="path-chip__arrow size-3.5 opacity-0 transition-opacity group-hover:opacity-100" />
            </Link>
          ))}
        </nav>

        <div className="space-y-8">
          {groupOrder.map((group) => {
            const sections = docSections.filter((s) => s.group === group);
            if (sections.length === 0) return null;
            return (
              <section key={group}>
                <h2 className="group-label">
                  <GroupIcon group={group} className="size-3.5 text-fd-primary" />
                  {groupLabels[group]}
                </h2>
                <ul className="page-list">
                  {sections.map((section) => (
                    <li key={section.slug}>
                      <Link href={section.href} className="page-row group">
                        <span className="page-row__main">
                          <SectionIcon
                            slug={section.slug}
                            className="size-3.5 shrink-0 text-fd-primary/85"
                          />
                          <span className="page-row__title">{section.title}</span>
                          <span className="page-row__desc">{section.description}</span>
                        </span>
                        {section.firstCommand ? (
                          <code className="page-row__cmd">{section.firstCommand}</code>
                        ) : null}
                      </Link>
                    </li>
                  ))}
                </ul>
              </section>
            );
          })}
        </div>
      </div>
    </HomeLayout>
  );
}
