# Dotfiles workflow runner. List recipes: just --list

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

shell_files := "setup.sh rig/bootstrap/macos.sh rig/bootstrap/linux.sh rig/bootstrap/dev-env.sh checks/apple-text-more-test.sh checks/apple-text-test.sh checks/apple-text.sh checks/apps-manual-inventory.sh checks/brew-exclude-check.sh checks/chezmoi-ignore.sh checks/config-dirs-inventory.sh checks/darwin-lock.sh checks/docs-css-health.sh checks/docs-hub-parity.sh checks/docs-sensitive.sh checks/freshen-smoke.sh checks/freshen-version.sh checks/freshen-privacy.sh checks/ghostty.sh checks/iina-config.sh checks/iina-native.sh checks/iina-plugins.sh checks/iina-qol.sh checks/iina-shaders.sh checks/music-ingest.sh checks/music-likes.sh checks/kopia-nightly.sh checks/linux-dev-env-rc.sh checks/mise-boundary.sh checks/remote-access.sh checks/spicetify.sh checks/rig-ecosystem-assurance.sh checks/secrets-scan.sh checks/shell-files-sync.sh checks/smoke.sh checks/stale-path-freeze.sh checks/validate-json.sh checks/yazi-config.sh checks/zsh-alias-docs.sh checks/zsh-alias-usage.sh checks/zsh-compaudit.sh checks/zsh-home-behavior-test.sh checks/zsh-startup-time.sh checks/zsh-inventory.sh checks/zsh-structure.sh checks/zsh-structure-test.sh checks/zsh-smoke-interactive.sh checks/zsh-rollback-live.sh rig/home/dot_local/bin/executable_kopia-nightly rig/home/dot_local/bin/executable_remote-access rig/home/dot_local/bin/executable_music-ingest rig/home/dot_local/bin/executable_music-likes rig/home/private_dot_config/direnv/lib/layout_uv.sh"

# List available recipes (default).
default:
    @just --list

# Dispatch to the platform bootstrapper. Example: just bootstrap --dry-run
bootstrap *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    case "$(uname -s)" in
      Darwin) exec ./rig/bootstrap/macos.sh {{ ARGS }} ;;
      Linux) exec ./rig/bootstrap/linux.sh {{ ARGS }} ;;
      *)
        printf 'just bootstrap is supported on Darwin and Linux only.\n' >&2
        exit 1
        ;;
    esac

# Portable agent-dev-env preview (wyattowalsh/agents). Defaults to dry-run.
bootstrap-dev *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    extra=( {{ ARGS }} )
    if [ "${#extra[@]}" -eq 0 ]; then
      extra=(--dry-run)
    fi
    exec ./rig/bootstrap/dev-env.sh "${extra[@]}"

# Run static validation.
check: check-hooks check-shell check-just-fmt check-mise-boundary check-zsh check-freshen check-json secrets-scan brew-exclude check-rig-ecosystem-assurance check-ghostty check-yazi-config check-stale-paths check-kopia-nightly check-apple-text check-iina-config check-mba-migration-policy check-music-ingest check-music-likes check-remote-access check-spicetify check-bats check-chezmoi-ignore check-darwin-lock check-linux-dev-env-rc check-shell-files

# Run the validation suite used by CI.
ci: check smoke docs-ci

# Validate shell scripts with bash -n, ShellCheck, and shfmt.
check-shell:
    #!/usr/bin/env bash
    set -euo pipefail
    bash -n {{ shell_files }}
    if command -v shellcheck >/dev/null 2>&1; then
      shellcheck {{ shell_files }}
    elif [ -n "${CI:-}" ]; then
      echo "shellcheck is required in CI" >&2
      exit 1
    else
      echo "shellcheck not installed; skipping"
    fi
    if command -v shfmt >/dev/null 2>&1; then
      shfmt -d -i 2 -ci -bn {{ shell_files }}
    elif [ -n "${CI:-}" ]; then
      echo "shfmt is required in CI" >&2
      exit 1
    else
      echo "shfmt not installed; skipping"
    fi

# Apply shfmt -w to tracked bash scripts (preview: just check-shell).
fmt-shell:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v shfmt >/dev/null 2>&1; then
      echo "shfmt not installed" >&2
      exit 1
    fi
    shfmt -w -i 2 -ci -bn {{ shell_files }}

# Fail if the justfile is not `just --unstable --fmt` clean.
check-just-fmt:
    just --unstable --fmt --check

# Refuse repo-root mise.toml and mise [tasks] that would rival just.
check-mise-boundary:
    ./checks/mise-boundary.sh

# Run Bats tests under checks/ when bats is available.
check-bats:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v bats >/dev/null 2>&1; then
      if [ -n "${CI:-}" ]; then
        echo "bats is required in CI" >&2
        exit 1
      fi
      echo "bats not installed; skipping"
      exit 0
    fi
    bats checks/*.bats

# Validate pre-commit hook configuration when pre-commit is available.
check-hooks:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v pre-commit >/dev/null 2>&1; then
      pre-commit validate-config
    else
      echo "pre-commit not installed; skipping"
    fi

# Validate zsh runtime configuration syntax when zsh is available.
check-zsh:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v zsh >/dev/null 2>&1; then
      zsh -n rig/dots/zshrc rig/home/dot_zshrc.tmpl rig/dots/p10k.zsh rig/home/dot_p10k.zsh rig/home/dot_zsh/aliases.zsh
    else
      echo "zsh not installed; skipping syntax"
    fi
    cmp -s rig/dots/zshrc rig/home/dot_zshrc.tmpl
    cmp -s rig/dots/p10k.zsh rig/home/dot_p10k.zsh
    grep -Fq '.zsh/aliases.zsh' rig/dots/zshrc
    grep -Fq 'atuin init zsh --disable-up-arrow --disable-ai' rig/dots/zshrc
    ./checks/zsh-alias-docs.sh
    ./checks/zsh-structure-test.sh
    ./checks/zsh-structure.sh rig/dots/zshrc all
    ./checks/zsh-home-behavior-test.sh
    ./checks/zsh-compaudit.sh

# Local-only interactive zsh smoke (uv/pnpm/pipx/mise/zoxide).
check-zsh-smoke:
    ./checks/zsh-smoke-interactive.sh

# Report-only interactive zsh startup time (min/median/max). Never a CI gate.
zsh-time *RUNS:
    ./checks/zsh-startup-time.sh {{ RUNS }}

# Local-only: alias names vs HISTFILE tokens → local/zsh-alias-usage.txt.
zsh-alias-usage:
    ./checks/zsh-alias-usage.sh

# Validate repository JSON files.
check-json:
    ./checks/validate-json.sh

# Run non-destructive smoke checks.
smoke:
    ./checks/smoke.sh

# Validate freshen function version SSOT and smoke tests.
check-freshen:
    ./checks/freshen-smoke.sh

# Scan tracked source for obvious secret-shaped values.
secrets-scan:
    ./checks/secrets-scan.sh

# Pure-file Brewfile exclude policy (no Homebrew required; always on just check).
brew-exclude:
    ./checks/brew-exclude-check.sh

# Pin the curated ecosystem-refresh package, Git, and macOS contracts.
check-rig-ecosystem-assurance:
    ./checks/rig-ecosystem-assurance.sh

# Static Ghostty source contract plus rendered validation when tools are available.
check-ghostty:
    ./checks/ghostty.sh

# Validate Yazi field names, locked packages/flavors, theme, and custom keys.
check-yazi-config:
    ./checks/yazi-config.sh

# Fail on stale top-level machine path contracts in live surfaces.
check-stale-paths:
    ./checks/stale-path-freeze.sh

# Static contract for the headless Kopia nightly runner (no live kopia/launchctl).
check-kopia-nightly:
    ./checks/kopia-nightly.sh

# Canonical Apple Text Replacement / Shortcuts registries plus offline merge.
check-apple-text:
    ./checks/apple-text.sh validate
    ./checks/apple-text-test.sh

# Preview or stage Apple Text Replacement imports. Default is dry-run.
[positional-arguments]
apple-text *ARGS:
    ./checks/apple-text.sh "$@"

# Static native IINA profile, shader, and plugin pin contracts (no live writes).
check-iina-config:
    ./checks/iina-config.sh

# Preview native IINA migration. Apply/restore require explicit --apply.
[positional-arguments]
iina-native *ARGS:
    ./checks/iina-native.sh "$@"

# Retired QoL runner: only preview/doctor; apply is disabled.
[positional-arguments]
iina-qol *ARGS:
    ./checks/iina-qol.sh "$@"

# Preview pinned GPL shaders; install/restore require explicit --apply.
[positional-arguments]
iina-shaders *ARGS:
    ./checks/iina-shaders.sh "$@"

# Preview pinned official plugins; install/restore require explicit --apply.
[positional-arguments]
iina-plugins *ARGS:
    ./checks/iina-plugins.sh "$@"

# Nine offline MBA policy suites, including review-only offload manifests; no live host proof.
check-mba-migration-policy:
    UV_NO_PROJECT=1 PYTHONDONTWRITEBYTECODE=1 uv run --offline python -I ./checks/mba-capacity-budget-test.py
    UV_NO_PROJECT=1 PYTHONDONTWRITEBYTECODE=1 uv run --offline python -I ./checks/mba-retained-inventory-test.py
    UV_NO_PROJECT=1 PYTHONDONTWRITEBYTECODE=1 uv run --offline python -I ./checks/mba-offload-manifest-test.py
    UV_NO_PROJECT=1 PYTHONDONTWRITEBYTECODE=1 uv run --offline python -I ./checks/mba-media-policy-test.py
    UV_NO_PROJECT=1 PYTHONDONTWRITEBYTECODE=1 uv run --offline python -I ./checks/mba-media-census-test.py
    UV_NO_PROJECT=1 PYTHONDONTWRITEBYTECODE=1 uv run --offline python -I ./checks/mba-media-stage-test.py
    UV_NO_PROJECT=1 PYTHONDONTWRITEBYTECODE=1 uv run --offline python -I ./checks/mba-navidrome-guard-test.py
    UV_NO_PROJECT=1 PYTHONDONTWRITEBYTECODE=1 uv run --offline python -I ./checks/mba-migration-receipts-test.py
    UV_NO_PROJECT=1 PYTHONDONTWRITEBYTECODE=1 uv run --offline python -I ./checks/mba-resource-leases-test.py

# Music ingest and likes contracts use only tracked source and sandbox fixtures.
check-music-ingest:
    ./checks/music-ingest.sh

check-music-likes:
    ./checks/music-likes.sh
    UV_NO_PROJECT=1 PYTHONDONTWRITEBYTECODE=1 uv run --offline python -I ./checks/music-likes-match-playlist.py

# Run the source ingest runner; default doctor is read-only.
[positional-arguments]
music-ingest *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    export MUSIC_INGEST_REPO="{{ justfile_directory() }}"
    exec "{{ justfile_directory() }}/rig/home/dot_local/bin/executable_music-ingest" "$@"

# Preview installation by default. Pass --apply to install only after review.
[positional-arguments]
music-ingest-install *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    export MUSIC_INGEST_REPO="{{ justfile_directory() }}"
    case "${1:---dry-run}" in
      --apply) [[ "$#" -eq 1 ]] || exit 2; exec "{{ justfile_directory() }}/rig/home/dot_local/bin/executable_music-ingest" install ;;
      --dry-run) [[ "$#" -le 1 ]] || exit 2; exec "{{ justfile_directory() }}/rig/home/dot_local/bin/executable_music-ingest" install --dry-run ;;
      *) printf 'music-ingest-install: use --dry-run or --apply\n' >&2; exit 2 ;;
    esac

# Run the source likes runner; default doctor is read-only.
[positional-arguments]
music-likes *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    export MUSIC_LIKES_REPO="{{ justfile_directory() }}"
    exec "{{ justfile_directory() }}/rig/home/dot_local/bin/executable_music-likes" "$@"

# Preview installation by default. Pass --apply to install only after review.
[positional-arguments]
music-likes-install *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    export MUSIC_LIKES_REPO="{{ justfile_directory() }}"
    case "${1:---dry-run}" in
      --apply) [[ "$#" -eq 1 ]] || exit 2; exec "{{ justfile_directory() }}/rig/home/dot_local/bin/executable_music-likes" install ;;
      --dry-run) [[ "$#" -le 1 ]] || exit 2; exec "{{ justfile_directory() }}/rig/home/dot_local/bin/executable_music-likes" install --dry-run ;;
      *) printf 'music-likes-install: use --dry-run or --apply\n' >&2; exit 2 ;;
    esac

# Read-only report over existing library files and the beets database.
music-hygiene:
    uv run python ./checks/music-reports.py hygiene

# Write only a candidate CSV under Incoming/review; never alter audio.
music-duplicates:
    uv run python ./checks/music-reports.py duplicates # Incoming/review

# Static contract for opt-in RustDesk-over-Tailscale (no live launchctl/TCC).
check-remote-access:
    ./checks/remote-access.sh

# Opt-in remote access runner. Always uses repo source. Default is plan.
remote-access *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    export REMOTE_ACCESS_REPO="{{ justfile_directory() }}"
    exec "{{ justfile_directory() }}/rig/home/dot_local/bin/executable_remote-access" {{ ARGS }}

# Static contract for Spotify pin + Spicetify apply (no live Spotify/launchctl).
check-spicetify:
    ./checks/spicetify.sh

# Spicetify runner. Always uses repo source. Default is dry-run preview.
spicetify *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    export SPICETIFY_REPO="{{ justfile_directory() }}"
    exec "{{ justfile_directory() }}/rig/home/dot_local/bin/executable_spicetify-apply" {{ ARGS }}

# Sync dest runner/pin/plist and bootstrap the WatchPaths agent. Default is dry-run.
spicetify-install *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    export SPICETIFY_REPO="{{ justfile_directory() }}"
    extra=( {{ ARGS }} )
    if [ "${#extra[@]}" -eq 0 ]; then
      extra=(--dry-run)
    fi
    exec "{{ justfile_directory() }}/rig/home/dot_local/bin/executable_spicetify-apply" install "${extra[@]}"

# Chezmoi ignore file must use destination/target path names.
check-chezmoi-ignore:
    ./checks/chezmoi-ignore.sh

# flake.lock JSON + recoverable nix-darwin pin (no nix apply).
check-darwin-lock:
    ./checks/darwin-lock.sh

# Linux run_dev_env exit-status capture (no $HOME mutation).
check-linux-dev-env-rc:
    ./checks/linux-dev-env-rc.sh

# justfile shell_files must match tracked *.sh plus explicitly managed home runners.
check-shell-files:
    ./checks/shell-files-sync.sh

# Nightly Kopia CLI runner (install/doctor/dry-run). Always uses repo source.
kopia-nightly *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    export KOPIA_NIGHTLY_REPO="{{ justfile_directory() }}"
    exec "{{ justfile_directory() }}/rig/home/dot_local/bin/executable_kopia-nightly" {{ ARGS }}

# Disable KopiaUI login agents, sync dest runner, bootstrap the 04:00 LaunchAgent.
kopia-nightly-install *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    export KOPIA_NIGHTLY_REPO="{{ justfile_directory() }}"
    exec "{{ justfile_directory() }}/rig/home/dot_local/bin/executable_kopia-nightly" install {{ ARGS }}

# Check the curated Brewfile when Homebrew is available.
brew-check:
    #!/usr/bin/env bash
    set -euo pipefail
    ./checks/brew-exclude-check.sh
    if ! command -v brew >/dev/null 2>&1; then
      echo "brew not installed; skipping brew bundle check"
      exit 0
    fi
    brew bundle check --file rig/brew/Brewfile

# Check Nix flakes and nix-darwin when available.
darwin-check:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v nix >/dev/null 2>&1; then
      nix flake check --no-write-lock-file ./rig/darwin
    else
      echo "nix not installed; skipping"
    fi
    if command -v darwin-rebuild >/dev/null 2>&1; then
      darwin-rebuild check --flake ./rig/darwin#w4w-mbp
    else
      echo "darwin-rebuild not installed; skipping"
    fi

# Preview Chezmoi-managed home config when Chezmoi is available.
home-diff:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v chezmoi >/dev/null 2>&1; then
      echo "chezmoi not installed; skipping"
      exit 0
    fi
    chezmoi --source rig/home data
    chezmoi --source rig/home diff

# Install docs dependencies.
[working-directory('docs')]
docs-install:
    pnpm install

# Typecheck the Fumadocs site when dependencies are installed.
[working-directory('docs')]
docs-check:
    test -d node_modules && pnpm typecheck || echo "docs/node_modules missing; run just docs-install first"

# Build the internal Fumadocs site when dependencies are installed.
[working-directory('docs')]
docs-build:
    test -d node_modules && pnpm build || echo "docs/node_modules missing; run just docs-install first"

# Scan docs content for sensitive/PII patterns (paths, token literals).
docs-sensitive:
    ./checks/docs-sensitive.sh

# Ensure hub-manifest.json slugs match docs sidebar meta.json.
docs-hub-parity:
    ./checks/docs-hub-parity.sh

# Install docs dependencies, typecheck, and build the Fumadocs site.
[working-directory('docs')]
docs-ci:
    pnpm install --frozen-lockfile
    pnpm typecheck
    pnpm build
    ../checks/docs-css-health.sh
    ../checks/docs-sensitive.sh
    ../checks/docs-hub-parity.sh

# Install repository pre-commit and pre-push hooks.
hooks-install:
    pre-commit install --install-hooks --hook-type pre-commit --hook-type pre-push

# Run pre-commit hooks across the repository. Extra args pass through.
hooks-run *ARGS:
    pre-commit run --all-files {{ ARGS }}

# Update pinned pre-commit hook revisions.
hooks-update:
    pre-commit autoupdate

# Generate local redacted inventory artifacts under ignored local/.

# Never commit local/ — package names / paths-only evidence for promotion.
inventory-redacted:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p local
    export HOMEBREW_NO_ENV_HINTS=1
    if command -v brew >/dev/null 2>&1; then
      # Full dump: formulae, casks, taps, mas, vscode (vscode stays local-only — do not promote wholesale).
      # Fail closed on dump errors (RV-008) so promote passes never treat a stub as inventory.
      if ! brew bundle dump --file=local/Brewfile.raw --force --brews --casks --taps --mas --vscode; then
        printf '%s\n' 'brew bundle dump failed; refusing to write stub inventory' >&2
        exit 1
      fi
    else
      printf '%s\n' 'brew not installed; skipping Brewfile inventory' > local/Brewfile.raw
    fi
    if command -v mas >/dev/null 2>&1; then
      mas list > local/mas.raw
    else
      printf '%s\n' 'mas not installed; skipping' > local/mas.raw
    fi
    ./checks/apps-manual-inventory.sh local/apps-all.txt
    ./checks/config-dirs-inventory.sh
    ./checks/zsh-inventory.sh
