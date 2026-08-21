# XDG: ~/.config/visidata/config.py (VisiData ≥2.9).
# Interactive sheets; DuckDB remains SQL + yazi preview. Do not enable network MOTD.

import sys

options.motd_url = ""
options.header = 1
options.skip = 0
options.encoding = "utf-8"

if sys.platform == "darwin":
    options.clipboard_copy_cmd = "pbcopy"
    options.clipboard_paste_cmd = "pbpaste"
