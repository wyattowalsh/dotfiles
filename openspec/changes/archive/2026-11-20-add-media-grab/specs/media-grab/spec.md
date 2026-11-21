# MediaGrab capability

## Requirements

1. Normal video downloads delegate best-format ranking to installed `yt-dlp` and avoid intentional re-encoding.
2. Exact format selection exposes the real `yt-dlp -F` table.
3. Browser cookies are local, optional, and retried only for narrow authentication failures by default.
4. Safe archives use cleaned JSON; exhaustive archives never embed raw info JSON.
5. All-language subtitle retrieval is a separate, non-embedding pass.
6. Generated app bundles and mutable user state are not tracked.
7. Installation is idempotent, previewable, and refuses unknown Desktop targets.
8. The canonical app lives in `~/Applications`; the Desktop entry is a symlink.
