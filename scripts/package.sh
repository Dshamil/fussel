#!/bin/bash
# Builds the installer package and the disk image from dist/Fussel.app.
# Usage: scripts/package.sh <version>
set -euo pipefail

VERSION="${1:-0.0.0}"
VERSION="${VERSION#v}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Fussel.app"
WORK="$DIST/package-work"

rm -rf "$WORK" "$DIST/Fussel-Installer.pkg" "$DIST/Fussel.dmg"
mkdir -p "$WORK/root" "$WORK/scripts" "$WORK/resources"

# --- Installer package -------------------------------------------------------
ditto "$APP" "$WORK/root/Fussel.app"
cp "$ROOT/installer/scripts/preinstall" "$ROOT/installer/scripts/postinstall" "$WORK/scripts/"
chmod +x "$WORK/scripts/"*

# Always install into /Applications, never "relocate" to an older copy somewhere else.
pkgbuild --analyze --root "$WORK/root" "$WORK/components.plist"
plutil -replace 0.BundleIsRelocatable -bool NO "$WORK/components.plist"

pkgbuild \
  --root "$WORK/root" \
  --component-plist "$WORK/components.plist" \
  --identifier app.fussel.Fussel \
  --version "$VERSION" \
  --install-location /Applications \
  --scripts "$WORK/scripts" \
  "$WORK/Fussel-component.pkg"

cp "$ROOT/installer/resources/"* "$WORK/resources/"
sed "s/__VERSION__/$VERSION/g" "$ROOT/installer/distribution.xml" > "$WORK/distribution.xml"

productbuild \
  --distribution "$WORK/distribution.xml" \
  --resources "$WORK/resources" \
  --package-path "$WORK" \
  "$DIST/Fussel-Installer.pkg"

# --- Disk image: drag Fussel onto Applications --------------------------------
mkdir -p "$WORK/dmg"
ditto "$APP" "$WORK/dmg/Fussel.app"
ln -s /Applications "$WORK/dmg/Applications"
hdiutil create -volname "Fussel" -srcfolder "$WORK/dmg" -ov -format UDZO "$DIST/Fussel.dmg"

rm -rf "$WORK"
echo "Built $DIST/Fussel-Installer.pkg and $DIST/Fussel.dmg"
