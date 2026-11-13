#!/bin/bash
# Packages the Mac App Store edition (docs/app-store/README.md).
#
#   ADHOC=1 ./scripts/package-appstore.sh
#       Ad-hoc-signed, sandboxed build/appstore/Super Flow.app for local testing (no credentials needed).
#
#   APPSTORE_APP_IDENTITY="Apple Distribution: <Name> (<TEAMID>)" \
#   APPSTORE_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: <Name> (<TEAMID>)" \
#   APPSTORE_PROVISIONING_PROFILE=/path/to/SuperFlow_AppStore.provisionprofile \
#   ./scripts/package-appstore.sh
#       Signs inside-out with the Store identity and entitlements, embeds the profile and writes
#       dist/SuperFlow-AppStore-<version>.pkg for Transporter / `xcrun altool` / `notarytool`-free upload.
#
# UNIVERSAL=1 builds Apple silicon + Intel (the Store build should be universal unless the listing is Apple-silicon only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
APP="$ROOT/build/appstore/Super Flow.app"
ENT="$ROOT/Resources/SuperFlow-AppStore.entitlements"

if [ "${ADHOC:-0}" != 1 ]; then
  missing=()
  [ -n "${APPSTORE_APP_IDENTITY:-}" ] || missing+=(APPSTORE_APP_IDENTITY)
  [ -n "${APPSTORE_INSTALLER_IDENTITY:-}" ] || missing+=(APPSTORE_INSTALLER_IDENTITY)
  [ -n "${APPSTORE_PROVISIONING_PROFILE:-}" ] && [ -f "${APPSTORE_PROVISIONING_PROFILE:-}" ] || missing+=(APPSTORE_PROVISIONING_PROFILE)
  if [ ${#missing[@]} -gt 0 ]; then
    echo "error: missing ${missing[*]}." >&2
    echo "  Set APPSTORE_APP_IDENTITY (\"Apple Distribution: …\"), APPSTORE_INSTALLER_IDENTITY (\"3rd Party Mac Developer Installer: …\")" >&2
    echo "  and APPSTORE_PROVISIONING_PROFILE (a Mac App Store profile for the bundle id in scripts/build-app.sh), or run with ADHOC=1." >&2
    exit 2
  fi
  for id in "$APPSTORE_APP_IDENTITY" "$APPSTORE_INSTALLER_IDENTITY"; do
    security find-identity -v | grep -qF "$id" || { echo "error: identity \"$id\" is not in the keychain" >&2; exit 2; }
  done
fi

PROBE=0 DISTRIBUTION=appstore ./scripts/build-app.sh
[ "${ADHOC:-0}" = 1 ] && { echo "Ad-hoc sandboxed app: $APP"; exit 0; }

# Store signing. The profile supplies the application identifier and team; they join the sandbox entitlements.
cp "$APPSTORE_PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
security cms -D -i "$APPSTORE_PROVISIONING_PROFILE" > "$WORK/profile.plist"
APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$WORK/profile.plist")"
TEAM_ID="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$WORK/profile.plist")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")"
[ "$APP_ID" = "$TEAM_ID.$BUNDLE_ID" ] || { echo "error: the profile is for $APP_ID, the app is $TEAM_ID.$BUNDLE_ID" >&2; exit 2; }
cp "$ENT" "$WORK/entitlements.plist"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $APP_ID" "$WORK/entitlements.plist"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$WORK/entitlements.plist"

# Inside-out: frameworks (no entitlements), then the app. Same team identity everywhere, so library validation holds
# without com.apple.security.cs.disable-library-validation.
for fw in "$APP/Contents/Frameworks/"*.framework; do codesign -f -s "$APPSTORE_APP_IDENTITY" --timestamp=none "$fw"; done
codesign -f -s "$APPSTORE_APP_IDENTITY" --entitlements "$WORK/entitlements.plist" --timestamp=none "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
mkdir -p dist
PKG="dist/SuperFlow-AppStore-$VERSION.pkg"
productbuild --component "$APP" /Applications --sign "$APPSTORE_INSTALLER_IDENTITY" "$PKG"
pkgutil --check-signature "$PKG"
echo "Built $PKG. Upload with Transporter (or Xcode's altool when installed); validation happens there."
