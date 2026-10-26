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

rm -rf "$WORK" "$DIST/Fussel-Installer.pkg" "$DIST/Fussel-Installer.zip" "$DIST/Fussel.dmg"
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

# The package wears the Fussel icon. Browsers drop custom icons on download, so it also ships
# zipped: unzipping brings the icon back. The icon lives beside the file's data, so the
# signature of the package stays valid.
ICON="$ROOT/Resources/AppIcon/AppIcon.icns"
swift "$ROOT/design/set-icon.swift" "$ICON" "$DIST/Fussel-Installer.pkg"
(cd "$DIST" && ditto -c -k --sequesterRsrc Fussel-Installer.pkg Fussel-Installer.zip)

# --- Disk image: drag Fussel onto Applications --------------------------------
mkdir -p "$WORK/dmg"
ditto "$APP" "$WORK/dmg/Fussel.app"
ln -s /Applications "$WORK/dmg/Applications"
# The mounted disk shows the Fussel icon too: the flag has to be set on the mounted volume itself.
cp "$ICON" "$WORK/dmg/.VolumeIcon.icns"
hdiutil create -volname "Fussel" -srcfolder "$WORK/dmg" -ov -format UDRW "$WORK/rw.dmg"
# Mounted at a place of our own choosing, so there's no output to parse (that once came back empty).
MOUNT="$WORK/mount"
mkdir -p "$MOUNT"
hdiutil attach -nobrowse -readwrite -mountpoint "$MOUNT" "$WORK/rw.dmg" > /dev/null
SetFile -a C "$MOUNT"
hdiutil detach "$MOUNT" -quiet
hdiutil convert "$WORK/rw.dmg" -format UDZO -o "$DIST/Fussel.dmg"

rm -rf "$WORK"
echo "Built $DIST/Fussel-Installer.pkg and $DIST/Fussel.dmg"
