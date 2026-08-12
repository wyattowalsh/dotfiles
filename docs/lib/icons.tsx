import type { Icon } from "@phosphor-icons/react";
import {
  ArrowRight,
  BookOpen,
  Desktop,
  GitBranch,
  HardDrives,
  House,
  MapTrifold,
  Stack,
  Package,
  Robot,
  RocketLaunch,
  ShieldCheck,
  Snowflake,
  Sparkle,
  Terminal,
  TerminalWindow,
  Wrench
} from "@phosphor-icons/react/dist/ssr";
import type { DocSectionGroup } from "@/lib/sections";

/**
 * Phosphor Icons (MIT) — duotone for hub personality.
 * Dotfiles-relevant metaphors; keep body MDX free of icon spam.
 * @see https://github.com/phosphor-icons/react
 */
export const sectionIcons: Record<string, Icon> = {
  "fresh-mac": Desktop,
  "linux-setup": Terminal,
  "ssot-workflow": HardDrives,
  "home-config": House,
  shell: TerminalWindow,
  freshen: Sparkle,
  terminal: TerminalWindow,
  git: GitBranch,
  validation: ShieldCheck,
  packages: Package,
  nix: Snowflake,
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
  const Glyph = sectionIcons[slug];
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
