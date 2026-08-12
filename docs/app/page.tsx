import Link from "next/link";
import { HomeLayout } from "fumadocs-ui/layouts/home";
import { baseOptions } from "@/lib/layout.shared";
import { docSections, groupLabels, groupOrder } from "@/lib/sections";

export default function HomePage() {
  return (
    <HomeLayout {...baseOptions()}>
      <div className="mx-auto w-full max-w-5xl px-6 py-16 md:py-20">
        <p className="mb-3 text-sm font-semibold tracking-wide text-fd-muted-foreground uppercase">
          Personal · operator SSOT
        </p>
        <h1 className="mb-4 text-3xl font-bold tracking-tight text-fd-foreground md:text-4xl">
          Dotfiles operator docs
        </h1>
        <p className="mb-10 max-w-2xl text-lg text-fd-muted-foreground">
          Runbooks, validation commands, and manifest policy for the full-rig macOS bootstrap.
          Tracked desired state only — not live secrets or inventory dumps.
        </p>

        {groupOrder.map((group) => {
          const sections = docSections.filter((section) => section.group === group);
          if (sections.length === 0) return null;
          return (
            <section key={group} className="mb-10">
              <h2 className="mb-4 text-sm font-semibold tracking-wide text-fd-muted-foreground uppercase">
                {groupLabels[group]}
              </h2>
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
                {sections.map((section) => (
                  <Link
                    key={section.href}
                    href={section.href}
                    className="group block rounded-xl border border-fd-border bg-fd-card p-5 text-fd-card-foreground no-underline transition-[border-color,box-shadow] duration-150 hover:border-fd-primary/40 hover:shadow-sm focus-visible:ring-2 focus-visible:ring-fd-primary focus-visible:outline-none motion-reduce:transition-none"
                  >
                    <strong className="mb-1.5 block text-base font-semibold text-fd-foreground group-hover:text-fd-primary">
                      {section.title}
                    </strong>
                    <span className="mb-2 block text-sm text-fd-muted-foreground">
                      {section.description}
                    </span>
                    {section.firstCommand ? (
                      <code className="mt-2 block truncate rounded-md bg-fd-muted/60 px-2 py-1 font-mono text-xs text-fd-muted-foreground">
                        {section.firstCommand}
                      </code>
                    ) : null}
                  </Link>
                ))}
              </div>
            </section>
          );
        })}

        <div className="mt-4">
          <Link
            href="/docs"
            className="inline-flex min-h-11 items-center justify-center rounded-lg bg-fd-primary px-5 py-2.5 text-sm font-semibold text-fd-primary-foreground no-underline transition-opacity hover:opacity-90 focus-visible:ring-2 focus-visible:ring-fd-primary focus-visible:ring-offset-2 focus-visible:outline-none motion-reduce:transition-none"
          >
            Open full documentation →
          </Link>
        </div>
      </div>
    </HomeLayout>
  );
}
