#!/usr/bin/env bash
# Build the site locally and serve it at http://localhost:8000
# (open http://<this-mac's-IP>:8000 on a phone on the same Wi-Fi to test there).
set -euo pipefail
cd "$(dirname "$0")"
python3 scripts/build_index.py
python3 -m http.server 8000 --bind 0.0.0.0 -d _site
