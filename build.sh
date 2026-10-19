#!/bin/zsh
# Builds Glimpse with SwiftPM and wraps it in a signed .app bundle.
# Usage: ./build.sh [--run] [--debug]
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=release
RUN=0
for arg in "$@"; do
  case "$arg" in
    --run) RUN=1 ;;
    --debug) CONFIG=debug ;;
  esac
done

swift build -c "$CONFIG"

APP="build/Glimpse.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Glimpse" "$APP/Contents/MacOS/Glimpse"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc signature so macOS remembers Screen Recording permission across rebuilds.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
if [[ $RUN -eq 1 ]]; then
  pkill -x Glimpse >/dev/null 2>&1 || true
  open "$APP"
fi
