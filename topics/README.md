# Topics

Topic directories group related dotfile concerns in the style of mature topic-oriented repos. They are **scaffolding** today — canonical desired state still lives in `brew/`, `home/`, `darwin/`, root dotfiles, and `.env.example`. AI/MCP harness configs live in [wyattowalsh/agents](https://github.com/wyattowalsh/agents) (`topics/ai/` is the pointer).

## Topic map

| Topic | Owns | Canonical SSOT |
| --- | --- | --- |
| [shell](shell/) | Zsh, PATH, completions, prompt | `.zshrc`, `.p10k.zsh`, `home/dot_zsh/` |
| [git](git/) | Git defaults, delta, aliases | `.gitconfig` |
| [terminal](terminal/) | Ghostty, fonts, shell integration | `home/private_dot_config/ghostty/` |
| [editors](editors/) | IDE/editor portable config | Chezmoi templates (future) |
| [macos](macos/) | macOS defaults, services | `darwin/hosts/` |
| [packages](packages/) | Package curation policy | `brew/Brewfile`, `darwin/` |
| [ai](ai/) | AI client strategy | wyattowalsh/agents |
| [mcp](mcp/) | MCPHub + fallbacks | `wyattowalsh/agents` |
| [docs](docs/) | Internal docs workflow | `docs/` Fumadocs site |
| [security](security/) | No-secrets, scanning | `checks/secrets-scan.sh`, `AGENTS.md` |

## Conventions

Each topic README documents:

- **Ownership** — what config domain the topic covers
- **Validation** — relevant `just` recipes
- **Overrides** — local/private hook patterns
- **Links** — path to canonical manifest (never duplicate Brewfile contents)