import { createElement } from "react";
import { loader } from "fumadocs-core/source";
import { docs } from "@/.source/server";
import { SectionIcon } from "@/lib/icons";

export const source = loader({
  baseUrl: "/docs",
  source: docs.toFumadocsSource(),
  icon(name) {
    if (!name) return;
    return createElement(SectionIcon, { slug: name, className: "size-4 shrink-0" });
  }
});

export async function getLLMText(page: (typeof source)["$inferPage"]) {
  const processed = await page.data.getText("processed");
  return `# ${page.data.title} (${page.url})

${processed}`;
}
