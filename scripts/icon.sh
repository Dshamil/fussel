#!/bin/bash
# Compiles the Liquid Glass app icon (design/AppIcon.icon, made for Icon Composer) into
# Resources/AppIcon: Assets.car for macOS 26 and AppIcon.icns for older Macs.
# Also renders docs/logo.png and the installer pictures from it. Needs Xcode 26. Usage: scripts/icon.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Resources/AppIcon"
TMP="$(mktemp -d)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

rm -rf "$OUT" && mkdir -p "$OUT"
xcrun actool "$ROOT/design/AppIcon.icon" --compile "$OUT" --platform macosx \
  --minimum-deployment-target 14.0 --app-icon AppIcon \
  --output-partial-info-plist "$TMP/partial.plist" >/dev/null

# Let the Mac draw the glass icon once, from a throwaway app, for the README logo.
APP="$TMP/Logo.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT/Assets.car" "$OUT/AppIcon.icns" "$APP/Contents/Resources/"
cp /usr/bin/true "$APP/Contents/MacOS/Logo"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.fussel.logo-render</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleExecutable</key><string>Logo</string>
<key>CFBundleIconName</key><string>AppIcon</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
swift "$ROOT/design/snap-icon.swift" "$APP" "$ROOT/docs/logo.png"
rm -rf "$TMP"
(cd "$ROOT" && swift design/installer-background.swift)
echo "Icon compiled to $OUT, logo at docs/logo.png"
