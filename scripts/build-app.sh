#!/bin/bash
# Builds build/Super Flow.app (release by default; `--debug` for a fast debug build; UNIVERSAL=1 for Apple silicon +
# Intel) and signs it with the project-local identity from scripts/signing-setup.sh (falls back to ad-hoc).
# The whisper.cpp and llama.cpp frameworks (SwiftPM binary targets) are embedded in Contents/Frameworks, the
# executable gets the matching rpath, and every nested piece is signed before the bundle that seals it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
CONFIG=release; [ "${1:-}" = "--debug" ] && CONFIG=debug
PRODUCTS=(SuperFlow)
if [ "${UNIVERSAL:-0}" = 1 ]; then
  # Build each architecture separately (the CLT toolchain has no multi-arch build) and merge with lipo.
  for arch in arm64 x86_64; do
    for product in "${PRODUCTS[@]}"; do swift build -c "$CONFIG" --product "$product" --triple "$arch-apple-macosx14.0"; done
  done
  ARM="$(swift build -c "$CONFIG" --triple arm64-apple-macosx14.0 --show-bin-path)"
  INTEL="$(swift build -c "$CONFIG" --triple x86_64-apple-macosx14.0 --show-bin-path)"
  BIN="$ROOT/build/universal"; mkdir -p "$BIN"; RES_BIN="$ARM"
  for product in "${PRODUCTS[@]}"; do lipo -create -output "$BIN/$product" "$ARM/$product" "$INTEL/$product"; done
else
  for product in "${PRODUCTS[@]}"; do swift build -c "$CONFIG" --product "$product"; done
  BIN="$(swift build -c "$CONFIG" --show-bin-path)"; RES_BIN="$BIN"
fi

APP="$ROOT/build/Super Flow.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
for product in "${PRODUCTS[@]}"; do cp "$BIN/$product" "$APP/Contents/MacOS/$product"; done
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# SwiftPM resource bundles of modules that declare resources (FluidAudio's, loaded through Bundle.module's
# Bundle.main.resourceURL lookup).
find "$RES_BIN" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;

# Native engines: the macOS slice of each xcframework SwiftPM downloaded (universal dynamic frameworks).
FRAMEWORKS=()
for name in whisper llama; do
  SLICE="$(find "$ROOT/.build/artifacts" -type d -path "*/$name.xcframework/macos-*" -name "$name.framework" | head -1)"
  [ -n "$SLICE" ] || { echo "Missing $name.framework in .build/artifacts; run swift build first" >&2; exit 1; }
  # cp -R keeps the Versions/Current symlink layout; dSYMs stay out of the bundle.
  cp -R "$SLICE" "$APP/Contents/Frameworks/$name.framework"
  FRAMEWORKS+=("$APP/Contents/Frameworks/$name.framework")
done
# The frameworks' install names are @rpath/<name>.framework/Versions/Current/<name>; SwiftPM linked the executable
# against the artifact folder, so replace that rpath with the bundle's.
for product in "${PRODUCTS[@]}"; do
  EXE="$APP/Contents/MacOS/$product"
  while IFS= read -r rpath; do
    [ -n "$rpath" ] && install_name_tool -delete_rpath "$rpath" "$EXE" 2>/dev/null || true
  done < <(otool -l "$EXE" | awk '/LC_RPATH/ {getline; getline; print $2}' | grep -F ".build/" || true)
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXE"
done

ICONSET="$ROOT/build/AppIcon.iconset"
if [ ! -f "$ROOT/build/AppIcon.icns" ]; then
  swift "$ROOT/scripts/make-icon.swift" "$ICONSET" && iconutil -c icns "$ICONSET" -o "$ROOT/build/AppIcon.icns"
fi
cp "$ROOT/build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

KC="$ROOT/.signing/super-flow.keychain-db"
ENT="$ROOT/Resources/SuperFlow.entitlements"
if [ -f "$KC" ]; then
  security unlock-keychain -p superflow "$KC"
  ORIG=()
  while IFS= read -r line; do line="${line#"${line%%[![:space:]]*}"}"; line="${line//\"/}"; [ -n "$line" ] && ORIG+=("$line"); done < <(security list-keychains -d user)
  restore() { security list-keychains -d user -s "${ORIG[@]}"; }
  trap restore EXIT
  security list-keychains -d user -s "${ORIG[@]}" "$KC"
  # Nested code first (the frameworks), then the bundle that seals it; resource bundles are data the seal covers.
  for fw in "${FRAMEWORKS[@]}"; do codesign -f -s "Super Flow Local Signing" --keychain "$KC" -o runtime "$fw"; done
  codesign -f -s "Super Flow Local Signing" --keychain "$KC" -o runtime --entitlements "$ENT" "$APP"
  restore; trap - EXIT
else
  for fw in "${FRAMEWORKS[@]}"; do codesign -f -s - "$fw"; done
  codesign -f -s - --entitlements "$ENT" "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "Built $APP"
