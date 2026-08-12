import Link from "next/link";
import { HomeLayout } from "fumadocs-ui/layouts/home";
import { baseOptions } from "@/lib/layout.shared";
import { docSections, groupLabels, groupOrder } from "@/lib/sections";
import { CtaArrow, GroupIcon, SectionIcon } from "@/lib/icons";

export default function HomePage() {
  return (
    <HomeLayout {...baseOptions()} className="relative">
      <div className="home-shell mx-auto w-full max-w-5xl px-4 py-12 sm:px-6 sm:py-16 md:py-20">
        <header className="home-hero mb-12 max-w-2xl md:mb-14">
          <p className="home-kicker mb-3 text-sm font-medium tracking-wide text-fd-primary">
            personal operator ssot
          </p>
          <h1 className="home-title mb-4 text-balance text-3xl font-semibold tracking-tight text-fd-foreground sm:text-4xl md:text-[2.75rem] md:leading-[1.1]">
            rig docs, without the noise
          </h1>
          <p className="text-pretty text-base text-fd-muted-foreground sm:text-lg">
            Bootstrap, promote, and validate the Mac SSOT. Commands first — no inventory dumps, no
            secrets.
          </p>
          <div className="mt-8 flex flex-wrap items-center gap-3">
            <Link href="/docs/fresh-mac" className="home-cta">
              Start on a fresh Mac
              <CtaArrow />
            </Link>
            <Link href="/docs" className="home-cta home-cta--ghost">
              Browse runbooks
            </Link>
          </div>
        </header>

        {groupOrder.map((group) => {
          const sections = docSections.filter((section) => section.group === group);
          if (sections.length === 0) return null;
          return (
            <section key={group} className="mb-10 sm:mb-12">
              <h2 className="group-label">
                <GroupIcon group={group} className="size-3.5 text-fd-primary" />
                {groupLabels[group]}
              </h2>
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
                {sections.map((section) => (
                  <Link key={section.href} href={section.href} className="doc-card group">
                    <span className="mb-3 flex items-start gap-3">
                      <span className="icon-badge">
                        <SectionIcon slug={section.slug} className="size-4" />
                      </span>
                      <strong className="block text-base font-semibold tracking-tight text-fd-foreground transition-colors group-hover:text-fd-primary">
                        {section.title}
                      </strong>
                    </span>
                    <span className="mb-2 block text-sm leading-relaxed text-fd-muted-foreground">
                      {section.description}
                    </span>
                    {section.firstCommand ? (
                      <code className="mt-3 block truncate rounded-md border border-fd-border/60 bg-fd-muted/50 px-2 py-1 font-mono text-[0.7rem] text-fd-muted-foreground sm:text-xs">
                        {section.firstCommand}
                      </code>
                    ) : null}
                  </Link>
                ))}
              </div>
            </section>
          );
        })}
      </div>
    </HomeLayout>
  );
}
