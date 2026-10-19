#!/bin/bash
# Builds Redpaper, installs it to /Applications and (re)starts it.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
pkill -x Redpaper 2>/dev/null || true
while pgrep -x Redpaper >/dev/null; do sleep 0.2; done
rm -rf /Applications/Redpaper.app
cp -R build/Redpaper.app /Applications/
open /Applications/Redpaper.app
echo "Installed /Applications/Redpaper.app. Look for its icon in the menu bar."
