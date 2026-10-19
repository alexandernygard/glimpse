#!/bin/zsh
# Builds Glimpse with SwiftPM and wraps it in a signed .app bundle.
# Usage: ./build.sh [--run] [--debug]
# VERSION=1.2.0 stamps the version (defaults to Info.plist's). UNIVERSAL=1 builds for Apple Silicon and Intel.
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

if [[ "${UNIVERSAL:-0}" == 1 ]]; then
  # Built per architecture and merged, since `--arch a --arch b` needs full Xcode.
  # Each binary is copied out right away: newer SwiftPM builds every triple into the same bin path.
  mkdir -p build
  BINS=()
  for ARCH in arm64 x86_64; do
    swift build -c "$CONFIG" --triple "$ARCH-apple-macosx14.0"
    cp "$(swift build -c "$CONFIG" --triple "$ARCH-apple-macosx14.0" --show-bin-path)/Glimpse" "build/Glimpse-$ARCH"
    BINS+=("build/Glimpse-$ARCH")
  done
  BIN="build/Glimpse-universal"
  lipo -create "${BINS[@]}" -output "$BIN"
else
  swift build -c "$CONFIG"
  BIN=".build/$CONFIG/Glimpse"
fi

APP="build/Glimpse.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Glimpse"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION#v}" -c "Set :CFBundleVersion ${VERSION#v}" "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc signature so macOS remembers Screen Recording permission across rebuilds.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
if [[ $RUN -eq 1 ]]; then
  pkill -x Glimpse >/dev/null 2>&1 || true
  open "$APP"
fi
