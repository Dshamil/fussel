#!/bin/bash
# Wraps a compiled Fussel binary into Fussel.app and zips it.
# Usage: scripts/bundle.sh <path-to-binary> [version]
set -euo pipefail

BIN="$1"
VERSION="${2:-0.0.0}"
VERSION="${VERSION#v}"
case "$VERSION" in
  [0-9]*) ;;
  *) VERSION="0.0.0" ;;
esac
BUILD="${GITHUB_RUN_NUMBER:-1}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Fussel.app"

rm -rf "$APP" "$DIST/Fussel.zip"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Fussel"
chmod +x "$APP/Contents/MacOS/Fussel"
# The Liquid Glass icon, compiled from design/AppIcon.icon by scripts/icon.sh.
cp "$ROOT/Resources/AppIcon/Assets.car" "$ROOT/Resources/AppIcon/AppIcon.icns" "$APP/Contents/Resources/"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD/g" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"

# Ad-hoc signature: required for Apple Silicon, no Apple Developer account needed.
codesign --force --deep --sign - "$APP"

(cd "$DIST" && ditto -c -k --keepParent Fussel.app Fussel.zip)
echo "Built $DIST/Fussel.zip (version $VERSION, build $BUILD)"
