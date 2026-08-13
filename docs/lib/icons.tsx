import type { Icon } from "@phosphor-icons/react";
import {
  ArrowRight,
  BookOpen,
  House,
  MapTrifold,
  Robot,
  RocketLaunch,
  ShieldCheck,
  Stack,
  Wrench
} from "@phosphor-icons/react/dist/ssr";
import {
  siApple,
  siGit,
  siGithub,
  siGithubactions,
  siGhostty,
  siGnuprivacyguard,
  siHomebrew,
  siLinux,
  siMarkdown,
  siNextdotjs,
  siNixos,
  siZsh
} from "simple-icons";
import type { DocSectionGroup } from "@/lib/sections";

/**
 * Hub marks: official Simple Icons (CC0) in brand color when a tech exists.
 * Phosphor duotone (MIT) only as fallback for non-brand concepts.
 * @see https://simpleicons.org
 */

type BrandMark = {
  title: string;
  hex: string;
  path: string;
  /** Near-black brands (Apple, etc.) invert in dark mode. */
  invertDark?: boolean;
};

function brand(icon: { title: string; hex: string; path: string }, invertDark = false): BrandMark {
  return { title: icon.title, hex: icon.hex, path: icon.path, invertDark };
}

const sectionBrands: Record<string, BrandMark> = {
  index: brand(siMarkdown),
  "fresh-mac": brand(siApple, true),
  "linux-setup": brand(siLinux),
  "ssot-workflow": brand(siGit),
  shell: brand(siZsh),
  freshen: brand(siHomebrew),
  terminal: brand(siGhostty),
  git: brand(siGit),
  validation: brand(siGithubactions),
  packages: brand(siHomebrew),
  nix: brand(siNixos),
  "ai-harness": brand(siGithub, true),
  security: brand(siGnuprivacyguard),
  "docs-maintenance": brand(siNextdotjs, true)
};

const sectionFallback: Record<string, Icon> = {
  "home-config": House,
  "ai-harness": Robot,
  security: ShieldCheck,
  "domain-map": MapTrifold,
  "docs-maintenance": BookOpen
};

export const groupIcons: Record<DocSectionGroup, Icon> = {
  start: RocketLaunch,
  operate: Wrench,
  reference: Stack
};

const duo = { weight: "duotone" as const };

export function SectionIcon({
  slug,
  className = "size-4 shrink-0"
}: {
  slug: string;
  className?: string;
}) {
  const mark = sectionBrands[slug];
  if (mark) {
    return (
      <svg
        viewBox="0 0 24 24"
        className={`brand-icon ${mark.invertDark ? "brand-icon--ink" : ""} ${className}`}
        role="img"
        aria-hidden
      >
        <title>{mark.title}</title>
        <path d={mark.path} fill={`#${mark.hex}`} />
      </svg>
    );
  }

  const Glyph = sectionFallback[slug];
  if (!Glyph) return null;
  return <Glyph className={className} aria-hidden {...duo} />;
}

export function GroupIcon({
  group,
  className = "size-3.5 shrink-0"
}: {
  group: DocSectionGroup;
  className?: string;
}) {
  const Glyph = groupIcons[group];
  return <Glyph className={className} aria-hidden {...duo} />;
}

export function BrandMark({ className = "size-3.5" }: { className?: string }) {
  return <Stack className={className} aria-hidden {...duo} />;
}

export function RunbooksMark({ className = "size-4" }: { className?: string }) {
  return <BookOpen className={className} aria-hidden weight="regular" />;
}

export function CtaArrow({ className = "size-4" }: { className?: string }) {
  return <ArrowRight className={className} aria-hidden weight="bold" />;
}

export function HeroMark({ className = "size-3.5" }: { className?: string }) {
  return <BookOpen className={className} aria-hidden {...duo} />;
}
