#!/bin/bash
# Builds Easy Backgrounds, installs it to /Applications and (re)starts it.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
pkill -x EasyBackgrounds 2>/dev/null || true
while pgrep -x EasyBackgrounds >/dev/null; do sleep 0.2; done
rm -rf "/Applications/Easy Backgrounds.app"
cp -R "build/Easy Backgrounds.app" /Applications/
open "/Applications/Easy Backgrounds.app"
echo "Installed /Applications/Easy Backgrounds.app. Look for its icon in the menu bar."
