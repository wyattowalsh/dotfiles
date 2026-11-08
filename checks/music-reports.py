#!/usr/bin/env -S uv run python
"""Read-only music inventory and conservative same-folder duplicate proposals."""

import argparse
import csv
import os
import re
import shutil
import sqlite3
import tempfile
from collections import Counter, defaultdict
from pathlib import Path

AUDIO = {".flac", ".mp3", ".m4a", ".aac", ".wav", ".aiff", ".aif", ".ogg", ".opus"}
COPY_SUFFIX = re.compile(r"^(.*?)(?:\s*\((\d+)\)|\.(\d+))$", re.IGNORECASE)


def audio_inventory(root: Path):
    if not root.is_dir():
        raise SystemExit(f"library missing: {root}")
    for directory, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = [name for name in dirs if name != "Incoming" and not (Path(directory) / name).is_symlink()]
        for name in files:
            path = Path(directory) / name
            if path.suffix.lower() not in AUDIO or path.is_symlink():
                continue
            try:
                yield path, path.stat().st_size
            except OSError:
                continue


def duplicates(items):
    groups = defaultdict(list)
    for path, size in items:
        match = COPY_SUFFIX.match(path.stem)
        canonical = match.group(1) if match else path.stem
        key = (str(path.parent), canonical.casefold(), path.suffix.casefold())
        groups[key].append((path, size, bool(match)))
    for key, candidates in sorted(groups.items()):
        if len(candidates) < 2 or not any(is_copy for _, _, is_copy in candidates):
            continue
        for path, size, _ in sorted(candidates):
            yield (*key, str(path), size, "review-only; content not verified")


def metadata_gaps(db: Path):
    if not db.is_file():
        return "not assessed (beets DB missing)"
    try:
        connection = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        try:
            result = connection.execute(
                "SELECT COUNT(*), SUM(CASE WHEN title IS NULL OR trim(title) = '' THEN 1 ELSE 0 END), "
                "SUM(CASE WHEN artist IS NULL OR trim(artist) = '' THEN 1 ELSE 0 END), "
                "SUM(CASE WHEN album IS NULL OR trim(album) = '' THEN 1 ELSE 0 END) FROM items"
            ).fetchone()
        finally:
            connection.close()
        return f"beets items={result[0] or 0}, missing title={result[1] or 0}, artist={result[2] or 0}, album={result[3] or 0}"
    except sqlite3.Error as exc:
        return f"not assessed (beets DB: {exc})"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("hygiene", "duplicates"))
    parser.add_argument("--library", type=Path, default=Path.home() / "Music/Library")
    parser.add_argument("--beets-db", type=Path, default=Path.home() / ".local/share/beets/library.db")
    args = parser.parse_args()
    library = args.library.expanduser()
    items = list(audio_inventory(library))
    if args.mode == "duplicates":
        output = library / "Incoming/review/same-format-duplicates.csv"
        output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            mode="w", newline="", encoding="utf-8", prefix=".same-format-", suffix=".csv",
            dir=output.parent, delete=False,
        ) as stream:
            staged = Path(stream.name)
            writer = csv.writer(stream)
            writer.writerow(("directory", "stem", "format", "path", "bytes", "assessment"))
            writer.writerows(duplicates(items))
        staged.replace(output)
        print(f"review CSV: {output} (no audio modified or deleted)")
        return
    counts = Counter()
    sizes = Counter()
    for path, size in items:
        counts[path.suffix.lower()] += 1
        sizes[path.suffix.lower()] += size
    print(f"audio files: {len(items)}")
    for suffix in sorted(counts):
        print(f"{suffix}: {counts[suffix]} files, {sizes[suffix]} bytes")
    print(f"metadata gaps: {metadata_gaps(args.beets_db.expanduser())}")
    top = Counter(row[0] for row in duplicates(items))
    print(f"same-folder numbered-copy candidate directories: {len(top)} (content not verified)")
    for directory, count in top.most_common(10):
        print(f"  {directory}: {count} candidate files")
    print(f"disk free bytes: {shutil.disk_usage(library).free}")
    for name in ("navidrome", "kopia"):
        print(f"{name} CLI: {'available' if shutil.which(name) else 'missing'} (service/repository status not probed)")


if __name__ == "__main__":
    main()
