# Internal Docs

Fumadocs + Next.js site for operator runbooks. Content: `content/docs/`. App shell: `app/`.

## Commands

```bash
just docs-install
just docs-check
just docs-build
just docs-ci
```

Local preview: `cd docs && pnpm dev`.

Operator content SSOT is this tree — not nested subsystem README files. See [docs-maintenance](./content/docs/docs-maintenance.mdx) for the update matrix.
