#!/usr/bin/env bash
# Compatibility entrypoint: Linux bootstrap lives under rig/bootstrap/linux.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec "$ROOT/rig/bootstrap/linux.sh" "$@"
