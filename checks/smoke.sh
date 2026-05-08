#!/usr/bin/env bash
set -euo pipefail

bash -n setup.sh bootstrap/macos.sh checks/ai-check.sh checks/secrets-scan.sh checks/validate-json.sh

if [ "$(uname -s)" = "Darwin" ]; then
  ./bootstrap/macos.sh --dry-run >/dev/null
else
  ./setup.sh --dry-run --verbose >/dev/null
fi

echo "Smoke checks completed."

