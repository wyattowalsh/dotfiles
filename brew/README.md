# Brew Inventory

`Brewfile` is curated desired state. Do not replace it with a raw `brew bundle dump`.

Use:

```bash
task inventory:redacted
task brew:check
```

Promote packages only after classifying them into a group and deciding whether a service should be started, stopped, or left unmanaged.

