# Dotfiles workflow runner. List recipes: just --list

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

shell_files := "setup.sh bootstrap/macos.sh checks/config-dirs-inventory.sh checks/freshen-smoke.sh checks/freshen-version.sh checks/secrets-scan.sh checks/smoke.sh checks/validate-json.sh checks/zsh-inventory.sh"

# List available recipes (default).
default:
    @just --list

# Dispatch to the platform bootstrapper. Example: just bootstrap --dry-run
bootstrap *ARGS:
    ./bootstrap/macos.sh {{ARGS}}

# Run static validation.
check: check-hooks check-shell check-zsh check-freshen check-json secrets-scan

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
    command -v zsh >/dev/null 2>&1 && zsh -n .zshrc home/dot_zshrc.tmpl .p10k.zsh home/dot_p10k.zsh || echo "zsh not installed; skipping"
    cmp -s .zshrc home/dot_zshrc.tmpl
    cmp -s .p10k.zsh home/dot_p10k.zsh

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

# Check the curated Brewfile when Homebrew is available.
brew-check:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v brew >/dev/null 2>&1; then
      echo "brew not installed; skipping"
      exit 0
    fi
    brew bundle check --file brew/Brewfile

# Check Nix flakes and nix-darwin when available.
darwin-check:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v nix >/dev/null 2>&1; then
      nix flake check --no-write-lock-file ./darwin
    else
      echo "nix not installed; skipping"
    fi
    if command -v darwin-rebuild >/dev/null 2>&1; then
      darwin-rebuild check --flake ./darwin#w4w-mbp
    else
      echo "darwin-rebuild not installed; skipping"
    fi

# Preview Chezmoi-managed home config when Chezmoi is available.
home-diff:
    command -v chezmoi >/dev/null 2>&1 && chezmoi --source home data && chezmoi --source home diff || echo "chezmoi not installed; skipping"

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

# Install docs dependencies, typecheck, and build the Fumadocs site.
[working-directory: 'docs']
docs-ci:
    pnpm install --frozen-lockfile
    pnpm typecheck
    pnpm build

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
inventory-redacted:
    mkdir -p local
    command -v brew >/dev/null 2>&1 && brew bundle dump --file=local/Brewfile.raw --describe --force || printf '%s\n' 'brew not installed; skipping Brewfile inventory' > local/Brewfile.raw
    ./checks/config-dirs-inventory.sh
    ./checks/zsh-inventory.sh
