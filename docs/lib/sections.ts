import hubManifest from "@/lib/hub-manifest.json";

export type DocSectionGroup = "start" | "operate" | "reference";

export type HubManifestSection = {
  slug: string;
  title: string;
  description: string;
  firstCommand?: string;
  group: DocSectionGroup;
};

export type DocSection = {
  slug: string;
  href: string;
  title: string;
  description: string;
  firstCommand?: string;
  group: DocSectionGroup;
};

const groups: readonly DocSectionGroup[] = ["start", "operate", "reference"];

function isGroup(value: string): value is DocSectionGroup {
  return (groups as readonly string[]).includes(value);
}

/** Shared SSOT for landing cards and docs hub paths. Never include secrets. */
export const docSections: readonly DocSection[] = hubManifest.sections.map((section) => {
  if (!isGroup(section.group)) {
    throw new Error(`Invalid hub-manifest group for slug ${section.slug}: ${section.group}`);
  }

  return {
    slug: section.slug,
    href: `/docs/${section.slug}`,
    title: section.title,
    description: section.description,
    firstCommand: section.firstCommand,
    group: section.group
  };
});

export const groupLabels: Record<DocSectionGroup, string> = {
  start: "Start here",
  operate: "Day-to-day",
  reference: "Reference"
};

export const groupOrder: readonly DocSectionGroup[] = groups;
