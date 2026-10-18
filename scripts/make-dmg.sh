#!/bin/bash
# Produces dist/SuperFlow-<version>.dmg: universal (Apple silicon + Intel) app, drag-to-Applications layout,
# and install notes for Gatekeeper (the app is self-signed, not notarized).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

UNIVERSAL=1 ./scripts/build-app.sh

STAGE="$ROOT/build/dmg"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "build/Super Flow.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Install Super Flow.txt" <<TXT
Installing Super Flow $VERSION
============================

1. Drag Super Flow into the Applications folder.
2. Open Super Flow from Applications. macOS will say it "cannot be opened" because the app
   is not notarized by Apple. Click Done.
3. Open System Settings → Privacy & Security, scroll down and click "Open Anyway" next to
   the Super Flow message, then confirm with your password.
   (Alternatively, in Terminal: xattr -dr com.apple.quarantine "/Applications/Super Flow.app")
4. Hold Fn and speak. Super Flow transcribes on your Mac; the speech models download in the
   background the first time it runs.

Requirements: macOS 14 Sonoma or later, Apple silicon or Intel.
TXT

mkdir -p dist
DMG="dist/SuperFlow-$VERSION.dmg"; rm -f "$DMG"
hdiutil create -volname "Super Flow $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null && echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
