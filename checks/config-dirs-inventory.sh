#!/usr/bin/env bash
set -euo pipefail

output="${1:-local/config-dirs.txt}"

if [[ -d "${HOME}/.config" ]]; then
  find "${HOME}/.config" -maxdepth 2 -type d 2>/dev/null \
    | sed "s#${HOME}#~#" \
    | sed -E 's#(^|/)([Tt][Oo][Kk][Ee][Nn]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Cc][Rr][Ee][Dd][Ee][Nn][Tt][Ii][Aa][Ll]|[Pp][Rr][Ii][Vv][Aa][Tt][Ee]-[Kk][Ee][Yy]|[Aa][Pp][Ii]-[Kk][Ee][Yy])[^/]*#\1[redacted]#g; s#(^|/)([A-Za-z0-9_-]{32,})#\1[redacted]#g' \
    | sort >"${output}"
else
  printf '%s\n' 'missing ~/.config' >"${output}"
fi
