import Link from "next/link";
import { docSections, groupLabels, groupOrder } from "@/lib/sections";
import { GroupIcon, SectionIcon } from "@/lib/icons";

/** Compact index — same SSOT as landing. */
export function DocsHub() {
  return (
    <div className="not-prose my-4 space-y-6">
      {groupOrder.map((group) => {
        const sections = docSections.filter((s) => s.group === group);
        if (sections.length === 0) return null;

        return (
          <section key={group}>
            <h3 className="group-label mb-2">
              <GroupIcon group={group} className="size-3.5 text-fd-primary" />
              {groupLabels[group]}
            </h3>
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
  );
}
