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
check: check-shell check-zsh check-freshen check-json secrets-scan

# Run the validation suite used by CI.
ci: check smoke docs-ci

# Validate shell scripts with bash -n and shellcheck when available.
check-shell:
    bash -n {{shell_files}}
    command -v shellcheck >/dev/null 2>&1 && shellcheck {{shell_files}} || echo "shellcheck not installed; skipping"

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
    command -v brew >/dev/null 2>&1 && brew bundle check --file brew/Brewfile || echo "brew not installed; skipping"

# Check Nix flakes and nix-darwin when available.
darwin-check:
    command -v nix >/dev/null 2>&1 && nix flake check ./darwin || echo "nix not installed; skipping"
    command -v darwin-rebuild >/dev/null 2>&1 && darwin-rebuild check --flake ./darwin#w4w-mbp || echo "darwin-rebuild not installed; skipping"

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

# Generate local redacted inventory artifacts under ignored local/.
inventory-redacted:
    mkdir -p local
    command -v brew >/dev/null 2>&1 && brew bundle dump --file=local/Brewfile.raw --describe --force || printf '%s\n' 'brew not installed; skipping Brewfile inventory' > local/Brewfile.raw
    ./checks/config-dirs-inventory.sh
    ./checks/zsh-inventory.sh