import Link from "next/link";
import { docSections, groupLabels, groupOrder } from "@/lib/sections";

/** Operator hub table driven by hub-manifest.json via sections.ts. */
export function DocsHub() {
  return (
    <div className="not-prose my-6 space-y-8">
      {groupOrder.map((group) => {
        const sections = docSections.filter((section) => section.group === group);
        if (sections.length === 0) return null;

        return (
          <section key={group}>
            <h3 className="mb-3 text-sm font-semibold tracking-wide text-fd-muted-foreground uppercase">
              {groupLabels[group]}
            </h3>
            <div className="overflow-x-auto rounded-xl border border-fd-border">
              <table className="w-full min-w-[36rem] border-collapse text-sm">
                <thead className="bg-fd-muted/40 text-left">
                  <tr>
                    <th className="px-3 py-2 font-semibold text-fd-foreground">Description</th>
                    <th className="px-3 py-2 font-semibold text-fd-foreground">Page</th>
                    <th className="px-3 py-2 font-semibold text-fd-foreground">First command</th>
                  </tr>
                </thead>
                <tbody>
                  {sections.map((section) => (
                    <tr key={section.slug} className="border-t border-fd-border">
                      <td className="px-3 py-2 text-fd-muted-foreground">{section.description}</td>
                      <td className="px-3 py-2">
                        <Link
                          href={section.href}
                          className="font-medium text-fd-primary no-underline hover:underline"
                        >
                          {section.title}
                        </Link>
                      </td>
                      <td className="px-3 py-2">
                        {section.firstCommand ? (
                          <code className="rounded-md bg-fd-muted/60 px-1.5 py-0.5 font-mono text-xs text-fd-muted-foreground">
                            {section.firstCommand}
                          </code>
                        ) : (
                          <span className="text-fd-muted-foreground">—</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        );
      })}
    </div>
  );
}
