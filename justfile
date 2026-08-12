# Dotfiles workflow runner. List recipes: just --list

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

shell_files := "setup.sh rig/bootstrap/macos.sh rig/bootstrap/linux.sh checks/apps-manual-inventory.sh checks/brew-exclude-check.sh checks/config-dirs-inventory.sh checks/docs-css-health.sh checks/docs-hub-parity.sh checks/docs-sensitive.sh checks/freshen-smoke.sh checks/freshen-version.sh checks/freshen-privacy.sh checks/secrets-scan.sh checks/smoke.sh checks/stale-path-freeze.sh checks/validate-json.sh checks/zsh-inventory.sh checks/zsh-structure.sh checks/zsh-structure-test.sh checks/zsh-smoke-interactive.sh checks/zsh-rollback-live.sh"

# List available recipes (default).
default:
    @just --list

# Dispatch to the platform bootstrapper. Example: just bootstrap --dry-run
bootstrap *ARGS:
    ./rig/bootstrap/macos.sh {{ARGS}}

# Run static validation.
check: check-hooks check-shell check-zsh check-freshen check-json secrets-scan brew-exclude check-stale-paths

# Run the validation suite used by CI.
ci: check smoke docs-ci

# Validate shell scripts with bash -n and shellcheck when available.
check-shell:
    #!/usr/bin/env bash
    set -euo pipefail
    bash -n {{shell_files}}
    if command -v shellcheck >/dev/null 2>&1; then
      shellcheck {{shell_files}}
    else
      echo "shellcheck not installed; skipping"
    fi

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
      zsh -n rig/dots/zshrc rig/home/dot_zshrc.tmpl rig/dots/p10k.zsh rig/home/dot_p10k.zsh
    else
      echo "zsh not installed; skipping syntax"
    fi
    cmp -s rig/dots/zshrc rig/home/dot_zshrc.tmpl
    cmp -s rig/dots/p10k.zsh rig/home/dot_p10k.zsh
    ./checks/zsh-structure-test.sh
    ./checks/zsh-structure.sh rig/dots/zshrc all

# Local-only interactive zsh smoke (uv/pnpm/pipx/mise/zoxide).
check-zsh-smoke:
    ./checks/zsh-smoke-interactive.sh

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

# Fail on stale top-level machine path contracts in live surfaces.
check-stale-paths:
    ./checks/stale-path-freeze.sh

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
[working-directory: 'docs']
docs-install:
    pnpm install

# Typecheck the Fumadocs site when dependencies are installed.
[working-directory: 'docs']
docs-check:
    test -d node_modules && pnpm typecheck || echo "docs/node_modules missing; run just docs-install first"

# Build the internal Fumadocs site when dependencies are installed.
[working-directory: 'docs']
docs-build:
    test -d node_modules && pnpm build || echo "docs/node_modules missing; run just docs-install first"

# Scan docs content for sensitive/PII patterns (paths, token literals).
docs-sensitive:
    ./checks/docs-sensitive.sh

# Ensure hub-manifest.json slugs match docs sidebar meta.json.
docs-hub-parity:
    ./checks/docs-hub-parity.sh

# Install docs dependencies, typecheck, and build the Fumadocs site.
[working-directory: 'docs']
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
    pre-commit run --all-files {{ARGS}}

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
