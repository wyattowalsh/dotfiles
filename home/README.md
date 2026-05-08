# Home Configuration

This directory is the intended Chezmoi source tree.

Rules:
- Portable config can be tracked here.
- Machine-specific values must be templated.
- Secrets, auth files, histories, telemetry, caches, app databases, and session state stay out of Git.

Preview:

```bash
task home:diff
```

