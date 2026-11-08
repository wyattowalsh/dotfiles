#!/usr/bin/env bash
# just check-chezmoi-ignore
# Chezmoi .chezmoiignore matches destination/target paths, not source names.
# Fail if source-style names are used, or required target ignores are missing.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IGNORE="${1:-$REPO_DIR/rig/home/.chezmoiignore}"

if [[ ! -f "$IGNORE" ]]; then
  printf 'Missing chezmoi ignore file: %s\n' "$IGNORE" >&2
  exit 1
fi

fail=0

if rg -q -- '^[[:space:]]*dot_zshrc(\.tmpl)?[[:space:]]*$' "$IGNORE" \
  || rg -q -- '^[[:space:]]*dot_p10k\.zsh[[:space:]]*$' "$IGNORE"; then
  printf 'chezmoi-ignore: source-style names (dot_zshrc / dot_p10k.zsh) match nothing; use target paths\n' >&2
  fail=1
fi

required_targets=(
  '.zshrc'
  '.p10k.zsh'
  'AGENTS.md'
  'Library/Application Support/com.colliderli.iina/plugins/.data'
  'Library/Application Support/com.colliderli.iina/plugins/.preferences'
  'Library/Application Support/com.colliderli.iina/history.plist'
  'Library/Application Support/com.colliderli.iina/watch_later'
  'Library/Application Support/com.colliderli.iina/screenshots'
)
for target in "${required_targets[@]}"; do
  if ! rg -qxF -- "$target" "$IGNORE"; then
    printf 'chezmoi-ignore: missing required target ignore: %s\n' "$target" >&2
    fail=1
  fi
done

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

if command -v chezmoi >/dev/null 2>&1; then
  template_root="$(mktemp -d "${TMPDIR:-/tmp}/chezmoi-host-role.XXXXXX")"
  trap 'rm -rf "$template_root"' EXIT
  mkdir -p "$template_root/source" "$template_root/home" "$template_root/cache"
  : >"$template_root/config.toml"
  music_targets=(
    'Library/LaunchAgents/com.wyattowalsh.music-ingest.plist'
    'Library/LaunchAgents/com.wyattowalsh.music-likes.plist'
    'Library/LaunchAgents/com.wyattowalsh.navidrome.plist'
    '.config/navidrome/navidrome.toml'
  )
  nightly_targets=(
    '.local/bin/kopia-nightly'
    'Library/LaunchAgents/com.wyattowalsh.kopia-nightly.plist'
  )
  check_rendered_targets() {
    local result="$1" identity="$2" expected="$3" target observed
    shift 3
    for target in "$@"; do
      observed=retained
      if rg -qxF -- "$target" <<<"$result"; then
        observed=ignored
      fi
      if [[ "$observed" != "$expected" ]]; then
        printf 'chezmoi-ignore: %s must render %s as %s (got %s)\n' "$identity" "$target" "$expected" "$observed" >&2
        exit 1
      fi
    done
  }
  while IFS='|' read -r role_os role_host role_user music_expected nightly_expected; do
    override="$(printf '{"chezmoi":{"os":"%s","hostname":"%s","username":"%s"}}' "$role_os" "$role_host" "$role_user")"
    rendered="$(chezmoi --config "$template_root/config.toml" --source "$template_root/source" \
      --destination "$template_root/home" --cache "$template_root/cache" \
      --persistent-state "$template_root/state.boltdb" --refresh-externals=never --no-tty --no-pager \
      --override-data "$override" execute-template --file "$IGNORE")"
    identity="$role_os/$role_host/$role_user"
    check_rendered_targets "$rendered" "$identity" "$music_expected" "${music_targets[@]}"
    check_rendered_targets "$rendered" "$identity" "$nightly_expected" "${nightly_targets[@]}"
  done <<'ROLES'
darwin|w4w-mbp|ww|ignored|retained
darwin|w4w-mbp.local|ww|ignored|retained
darwin|MacBookAir|wyattwalsh|ignored|ignored
darwin|MacBookAir.local|wyattwalsh|ignored|ignored
darwin|MacBookAir|ww|retained|retained
darwin|other-host|ww|retained|retained
darwin|other-host|wyattwalsh|retained|retained
linux|MacBookAir|wyattwalsh|retained|retained
ROLES
else
  printf 'chezmoi-ignore: native render cases skipped (chezmoi unavailable)\n'
fi

printf 'chezmoi-ignore: ok\n'
